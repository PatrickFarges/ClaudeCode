"""Tests headless de la caméra (aucun Qt requis) : maths de projection / zoom / pan.

Lancement : .venv/bin/python tests/test_camera.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import numpy as np

from claudecad.camera import Camera, DEFAULT_SCALE, MARGIN_PX

W, H = 1280.0, 800.0


def approx(a, b, eps=1e-6):
    return abs(float(a) - float(b)) <= eps


def test_roundtrip():
    cam = Camera()
    cam.frame_new_document(W, H)
    for sx, sy in [(20, 780), (640, 400), (1000, 120), (333.3, 555.5)]:
        wpt = cam.screen_to_world(sx, sy, W, H)
        bx, by = cam.world_to_screen(wpt, W, H)
        assert approx(bx, sx, 1e-4) and approx(by, sy, 1e-4), (sx, sy, bx, by)
        assert approx(wpt[2], 0.0), "plan de travail z=0 attendu"


def test_frame_new_document():
    cam = Camera()
    cam.frame_new_document(W, H)
    sx, sy = cam.world_to_screen([0.0, 0.0, 0.0], W, H)
    # Origine en bas à gauche, décalée de 20 px du coin.
    assert approx(sx, MARGIN_PX, 1e-4), sx
    assert approx(sy, H - MARGIN_PX, 1e-4), sy
    assert cam.scale == DEFAULT_SCALE


def test_zoom_keeps_cursor_fixed():
    cam = Camera()
    cam.frame_new_document(W, H)
    cur = (920.0, 240.0)
    before = cam.screen_to_world(*cur, W, H).copy()
    cam.zoom_at(*cur, 1.2, W, H)
    after = cam.screen_to_world(*cur, W, H)
    assert np.allclose(before, after, atol=1e-6), (before, after)
    assert cam.scale > DEFAULT_SCALE  # molette avant = zoom avant


def test_pan_follows_pixels():
    cam = Camera()
    cam.frame_new_document(W, H)
    sx, sy = 500.0, 300.0
    wpt = cam.screen_to_world(sx, sy, W, H).copy()
    cam.pan_pixels(40.0, -25.0, W, H)
    nx, ny = cam.world_to_screen(wpt, W, H)
    assert approx(nx, sx + 40.0, 1e-4) and approx(ny, sy - 25.0, 1e-4), (nx, ny)


def test_serialization():
    cam = Camera()
    cam.frame_new_document(W, H)
    cam.zoom_at(640, 400, 1.5, W, H)
    d = cam.to_dict()
    cam2 = Camera.from_dict(d)
    assert np.allclose(cam.center, cam2.center)
    assert approx(cam.scale, cam2.scale)


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in fns:
        fn()
        print(f"  ok  {fn.__name__}")
    print(f"\n{len(fns)} tests caméra OK")
