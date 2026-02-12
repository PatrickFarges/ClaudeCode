"""Native Windows drag-and-drop for Tkinter — GIL-safe.

The window proc is pure x64 machine code (no Python at all), so it
cannot corrupt Tkinter's GIL state.  On WM_DROPFILES it stores the
HDROP handle in a shared memory cell; a Tkinter after() timer polls
that cell and processes the drop from safe Python context.
"""

import sys

if sys.platform != 'win32':
    def hook_dropfiles(tk_root, callback):
        pass
else:
    import ctypes
    import ctypes.wintypes as wt
    import struct

    _kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
    _shell32 = ctypes.WinDLL('shell32', use_last_error=True)
    _user32 = ctypes.WinDLL('user32', use_last_error=True)

    # VirtualAlloc / VirtualFree for executable memory
    MEM_COMMIT = 0x1000
    MEM_RESERVE = 0x2000
    MEM_RELEASE = 0x8000
    PAGE_EXECUTE_READWRITE = 0x40

    _kernel32.VirtualAlloc.argtypes = [ctypes.c_void_p, ctypes.c_size_t,
                                       wt.DWORD, wt.DWORD]
    _kernel32.VirtualAlloc.restype = ctypes.c_void_p
    _kernel32.VirtualFree.argtypes = [ctypes.c_void_p, ctypes.c_size_t,
                                      wt.DWORD]
    _kernel32.VirtualFree.restype = wt.BOOL

    # Shell32 DragQueryFileW / DragFinish
    _shell32.DragQueryFileW.argtypes = [ctypes.c_void_p, wt.UINT,
                                        ctypes.c_wchar_p, wt.UINT]
    _shell32.DragQueryFileW.restype = wt.UINT
    _shell32.DragFinish.argtypes = [ctypes.c_void_p]
    _shell32.DragFinish.restype = None
    _shell32.DragAcceptFiles.argtypes = [wt.HWND, wt.BOOL]
    _shell32.DragAcceptFiles.restype = None

    # User32 — use c_void_p for all pointer-sized values
    _user32.SetWindowLongPtrW.argtypes = [wt.HWND, ctypes.c_int,
                                          ctypes.c_void_p]
    _user32.SetWindowLongPtrW.restype = ctypes.c_void_p
    _user32.GetWindowLongPtrW.argtypes = [wt.HWND, ctypes.c_int]
    _user32.GetWindowLongPtrW.restype = ctypes.c_void_p

    # GetProcAddress / GetModuleHandle for raw function addresses
    _kernel32.GetModuleHandleW.argtypes = [ctypes.c_wchar_p]
    _kernel32.GetModuleHandleW.restype = ctypes.c_void_p
    _kernel32.GetProcAddress.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    _kernel32.GetProcAddress.restype = ctypes.c_void_p

    WM_DROPFILES = 0x0233
    GWLP_WNDPROC = -4

    # prevent GC of allocated memory
    _stored = {}

    def _build_trampoline(old_proc, callwindowproc_addr):
        """Build x64 machine code for a WNDPROC that intercepts
        WM_DROPFILES and stores the HDROP handle, forwarding all
        other messages to old_proc via CallWindowProcW.

        Returns (code_addr, hdrop_cell_addr).
        The hdrop_cell is an 8-byte slot: 0 means no pending drop,
        non-zero is the HDROP handle to process.
        """
        code = bytearray()

        # ---- prologue ----
        # sub rsp, 0x28   (shadow space 0x20 + 5th-param slot 0x08)
        code += b'\x48\x83\xEC\x28'                        # offset 0

        # ---- check WM_DROPFILES ----
        # cmp edx, 0x233
        code += b'\x81\xFA\x33\x02\x00\x00'                # offset 4

        # jne .forward  (skip the WM_DROPFILES handler)
        # handler length: lea(7) + cmpxchg-block(see below)
        # Actually, let's use a simpler store with xchg:
        #   lea rax, [rip + hdrop_offset]  7 bytes
        #   mov [rax], r8                  3 bytes
        #   xor eax, eax                   2 bytes
        #   add rsp, 0x28                  4 bytes
        #   ret                            1 byte
        # Total handler = 17 bytes
        code += b'\x75\x11'                                 # offset 10

        # ---- WM_DROPFILES handler (offset 12) ----
        # lea rax, [rip + disp32]  → points to hdrop_cell
        code += b'\x48\x8D\x05'                             # offset 12
        hdrop_lea_pos = len(code)
        code += b'\x00\x00\x00\x00'  # fixup later          # offset 15

        # mov [rax], r8   (store HDROP)
        code += b'\x4C\x89\x00'                             # offset 19

        # xor eax, eax    (return 0)
        code += b'\x31\xC0'                                 # offset 22

        # add rsp, 0x28
        code += b'\x48\x83\xC4\x28'                         # offset 24

        # ret
        code += b'\xC3'                                     # offset 28

        # ---- .forward: pass to old wndproc (offset 29) ----
        # Rearrange params for CallWindowProcW(old, hwnd, msg, wp, lp):
        #   rcx → rdx (hwnd)
        #   rdx → r8  (msg)
        #   r8  → r9  (wparam)
        #   r9  → [rsp+0x20] (lparam, 5th param on stack)
        #   old_proc → rcx

        # mov [rsp+0x20], r9          ; lparam → 5th stack param
        code += b'\x4C\x89\x4C\x24\x20'                    # offset 29

        # mov r9, r8                  ; wparam
        code += b'\x4D\x89\xC1'                             # offset 34

        # mov r8, rdx                 ; msg
        code += b'\x49\x89\xD0'                             # offset 37

        # mov rdx, rcx                ; hwnd
        code += b'\x48\x89\xCA'                             # offset 40

        # mov rcx, [rip + old_proc_disp]  ; old_proc → rcx
        code += b'\x48\x8B\x0D'                             # offset 43
        old_proc_lea_pos = len(code)
        code += b'\x00\x00\x00\x00'                         # offset 46

        # mov rax, [rip + cwp_disp]       ; CallWindowProcW addr
        code += b'\x48\x8B\x05'                             # offset 50
        cwp_lea_pos = len(code)
        code += b'\x00\x00\x00\x00'                         # offset 53

        # call rax
        code += b'\xFF\xD0'                                 # offset 57

        # add rsp, 0x28
        code += b'\x48\x83\xC4\x28'                         # offset 59

        # ret
        code += b'\xC3'                                     # offset 63

        # ---- align data to 8 bytes ----
        while len(code) % 8 != 0:
            code += b'\xCC'  # int3 padding

        # ---- data section ----
        hdrop_cell_off = len(code)
        code += b'\x00' * 8      # hdrop_cell  (8 bytes)

        old_proc_off = len(code)
        code += struct.pack('<Q', old_proc)       # old wndproc pointer

        cwp_off = len(code)
        code += struct.pack('<Q', callwindowproc_addr)  # CallWindowProcW

        # ---- fixup RIP-relative displacements ----
        # lea rax, [rip + X]  →  disp = target - (lea_pos + 4)
        struct.pack_into('<i', code, hdrop_lea_pos,
                         hdrop_cell_off - (hdrop_lea_pos + 4))
        struct.pack_into('<i', code, old_proc_lea_pos,
                         old_proc_off - (old_proc_lea_pos + 4))
        struct.pack_into('<i', code, cwp_lea_pos,
                         cwp_off - (cwp_lea_pos + 4))

        # ---- allocate executable memory and copy ----
        size = len(code)
        addr = _kernel32.VirtualAlloc(None, size,
                                      MEM_COMMIT | MEM_RESERVE,
                                      PAGE_EXECUTE_READWRITE)
        if not addr:
            raise OSError('VirtualAlloc failed')

        ctypes.memmove(addr, bytes(code), size)

        hdrop_cell_addr = addr + hdrop_cell_off
        return addr, hdrop_cell_addr

    def _get_dropped_files(hdrop):
        count = _shell32.DragQueryFileW(hdrop, 0xFFFFFFFF, None, 0)
        files = []
        for i in range(count):
            length = _shell32.DragQueryFileW(hdrop, i, None, 0) + 1
            buf = ctypes.create_unicode_buffer(length)
            _shell32.DragQueryFileW(hdrop, i, buf, length)
            files.append(buf.value)
        _shell32.DragFinish(hdrop)
        return files

    def hook_dropfiles(tk_root, callback):
        """Register *tk_root* (a Tk or Toplevel) to accept file drops.
        *callback(files)* receives a list of absolute path strings.
        """
        tk_root.update_idletasks()
        hwnd = tk_root.winfo_id()

        _shell32.DragAcceptFiles(hwnd, True)

        # Allow WM_DROPFILES through UIPI (in case of elevation)
        try:
            _user32.ChangeWindowMessageFilterEx(hwnd, WM_DROPFILES, 1, None)
            _user32.ChangeWindowMessageFilterEx(hwnd, 0x0049, 1, None)
        except Exception:
            pass

        old_proc = _user32.GetWindowLongPtrW(hwnd, GWLP_WNDPROC)

        # Get the raw address of CallWindowProcW via GetProcAddress
        _h_user32 = _kernel32.GetModuleHandleW('user32.dll')
        cwp_addr = _kernel32.GetProcAddress(_h_user32, b'CallWindowProcW')

        # Build and install machine code trampoline
        code_addr, hdrop_cell_addr = _build_trampoline(old_proc, cwp_addr)

        # Keep a reference so nothing gets freed
        _stored[hwnd] = (code_addr, hdrop_cell_addr)

        # Install the trampoline as the new wndproc
        _user32.SetWindowLongPtrW(hwnd, GWLP_WNDPROC, code_addr)

        # Poll timer: check hdrop_cell every 50 ms
        hdrop_cell = ctypes.c_uint64.from_address(hdrop_cell_addr)

        def _poll():
            val = hdrop_cell.value
            if val:
                hdrop_cell.value = 0
                try:
                    files = _get_dropped_files(val)
                    if files:
                        callback(files)
                except Exception:
                    pass
            tk_root.after(50, _poll)

        tk_root.after(50, _poll)
