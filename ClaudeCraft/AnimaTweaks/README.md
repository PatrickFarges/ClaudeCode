# 🎮 AnimaTweaks Ultimate Edition v4.0

**Enhanced Player Animation Pack for Minecraft Bedrock Edition**

---

## 🔧 Latest Fixes (v4.0.1)

### **Critical Bug Fixes**
- ✅ **Fixed Missing Animation Error**: Resolved `stationary2` animation not found
- ✅ **Fixed Swimming Detection**: Replaced deprecated `variable.swim_amount` with `query.is_in_water`
- ✅ **Updated Molang Queries**: Fixed deprecated `query.get_equipped_item_name` usage
- ✅ **Enhanced Compatibility**: Improved animation controller stability
- ✅ **Fixed Crouch Animation**: Eliminated "floating" effect, now properly grounded

### **🎭 NEW: Emote System**
- ✨ **Wave Animation**: Friendly greeting gesture (2.0s)
- ✨ **Point Gesture**: Directional pointing animation (1.5s)
- ✨ **Thumbs Up**: Approval gesture (2.0s)
- ✨ **Clap Animation**: Applause with rhythmic clapping (3.0s loop)
- ✨ **Dance Moves**: Fun dance animation with body movement (4.0s loop)

### **🎨 NEW: Custom Title Screen**
- ✨ **Replace Minecraft Logo**: Custom AnimaTweaks branding on title screen
- ✨ **Professional Appearance**: Branded experience from startup
- ✨ **Easy Setup**: Simple PNG replacement system
- ✨ **HD Support**: High-resolution logo support
- ✨ **Cross-Platform**: Works on all Bedrock platforms

---

## ✨ What's New in v4.0

This is a **massive overhaul** of the original AnimaTweaks pack, featuring completely rewritten animations, improved mechanics, and enhanced visual fidelity.

### 🔥 Major Improvements

#### **🚶 Enhanced Movement System**
- **Realistic Walking**: Smooth arm swings, natural leg movement, subtle head bob, and shoulder sway
- **Dynamic Sprinting**: Energetic movements with forward lean, powerful arm swings, and realistic running mechanics
- **Stealthy Tiptoe**: Careful, weight-shifted movements for slow walking
- **Improved Sneaking**: Realistic crouching posture with subtle breathing movements

#### **🏃 Advanced Animation States**
- **Precise Speed Thresholds**: 
  - Idle: 0-0.8 speed
  - Tiptoe: 0.8-2.5 speed  
  - Walk: 2.5-4.0 speed
  - Sprint: 4.0+ speed
- **Smooth Transitions**: Enhanced blend times (0.15-0.4s) for fluid movement changes
- **Speed-Responsive Animations**: Animation intensity scales with movement speed

#### **🎯 Refined Idle Animations**
- **Natural Breathing**: Subtle chest movement and posture shifts
- **Micro-movements**: Realistic weight shifting and small adjustments
- **Extended Duration**: 4-second loops for more natural variation

#### **🏊 Enhanced Swimming**
- **Realistic Strokes**: Coordinated arm and leg movements
- **Body Undulation**: Natural swimming body motion
- **Improved First-Person**: Better underwater arm animations

#### **⚔️ Better Weapon Handling**
- **Realistic Grip**: Proper weapon holding positions
- **Subtle Movements**: Natural weapon sway and micro-adjustments
- **Enhanced Stability**: Improved weapon holding animations

#### **🎮 Technical Improvements**
- **Modern Format**: Updated to format version 2 with latest engine support
- **Optimized Controllers**: Better state management and transition logic
- **Enhanced Variables**: Speed-responsive animation scaling
- **Improved Lerping**: Catmullrom interpolation for smoother movements

---

## 📋 Animation Details

### **Movement Animations**

| Animation | Duration | Features |
|-----------|----------|----------|
| **Idle** | 4.0s | Breathing, weight shifts, micro-movements |
| **Walk** | 1.0s | Head bob, shoulder sway, natural coordination |
| **Tiptoe** | 1.6s | Careful steps, stealth positioning |
| **Sprint** | 0.8s | Forward lean, powerful movements, dynamic energy |
| **Jump** | 1.0s | Realistic takeoff, airborne, and landing phases |
| **Sneak** | 2.0s | Crouching posture, careful movements |
| **Swim** | 1.5s | Coordinated strokes, body undulation |

### **Enhanced Features**

- ✅ **Smooth Transitions**: No jarring animation switches
- ✅ **Speed Scaling**: Animations adapt to movement speed
- ✅ **Realistic Physics**: Natural body mechanics and weight distribution
- ✅ **Enhanced First-Person**: Improved arm movements and weapon handling
- ✅ **Weapon Integration**: Proper animations for all weapon types
- ✅ **Swimming Overhaul**: Realistic aquatic movement
- ✅ **Jump Mechanics**: Proper takeoff and landing animations
- ✅ **Emote System**: Interactive gestures and expressions

---

## 🎭 **Emote System**

### **Available Emotes**

| Emote | Duration | Type | Description |
|-------|----------|------|-------------|
| **Wave** | 2.0s | Gesture | Friendly greeting with hand waving |
| **Point** | 1.5s | Gesture | Directional pointing animation |
| **Thumbs Up** | 2.0s | Gesture | Approval/positive gesture |
| **Clap** | 3.0s | Loop | Rhythmic applause animation |
| **Dance** | 4.0s | Loop | Fun dance with full body movement |

### **Emote Features**
- 🎯 **Realistic Movements**: Natural arm and body positioning
- 🔄 **Smooth Transitions**: Seamless start and end animations
- 🎪 **Expressive Gestures**: Clear, recognizable motions
- ⏱️ **Varied Durations**: Different timing for each emote type
- 🔁 **Loop Support**: Continuous animations for clap and dance

## 🎮 **How to Use Emotes**

### **Method 1: Function Commands (Recommended)**
Use these commands in chat or command blocks:

```
/function emotes/wave          # 👋 Wave hello
/function emotes/point         # 👉 Point ahead  
/function emotes/thumbs_up     # 👍 Thumbs up
/function emotes/clap          # 👏 Start clapping
/function emotes/dance         # 💃 Start dancing
```

### **Method 2: Direct Animation Commands**
For advanced users, use the `playanimation` command directly:

```
/playanimation @s animation.player.emote.wave
/playanimation @s animation.player.emote.point
/playanimation @s animation.player.emote.thumbs_up
/playanimation @s animation.player.emote.clap
/playanimation @s animation.player.emote.dance
```

### **Method 3: Command Block Setup**
1. Place a command block
2. Set it to "Impulse" and "Needs Redstone"
3. Enter one of the function commands above
4. Connect to a button or pressure plate
5. Step on/press to trigger emote!

### **🎯 Usage Tips**
- ✅ **Works in multiplayer** - Other players can see your emotes
- ✅ **No cooldown** - Use emotes as often as you want
- ✅ **Interrupt anytime** - Move or jump to stop an emote
- ✅ **Combine with chat** - Use emotes while talking for more expression
- ⚠️ **Requires cheats enabled** for function commands

---

## 🛠️ Technical Specifications

- **Format Version**: 2 (Latest)
- **Engine Requirement**: 1.19.0+
- **Pack Version**: 4.0.0
- **Animation Format**: 1.8.0
- **Controller Format**: 1.10.0

### **Performance Optimizations**
- Efficient state management
- Optimized transition logic
- Reduced animation conflicts
- Smooth blend transitions

---

## 📦 Installation

1. Download the pack
2. Import into Minecraft Bedrock Edition
3. Apply to your world in Resource Packs
4. Enjoy enhanced animations!

---

## 🎨 Animation Showcase

### **Movement States**
- **Idle**: Natural breathing and subtle movements
- **Tiptoe**: Careful, stealthy walking
- **Walk**: Realistic everyday movement
- **Sprint**: Dynamic, energetic running

### **Special Actions**
- **Jump**: Realistic takeoff and landing
- **Sneak**: Proper crouching mechanics
- **Swim**: Coordinated aquatic movement
- **Weapon Hold**: Natural grip and positioning

---

## 🔧 Compatibility

- ✅ **Minecraft Bedrock Edition 1.19+**
- ✅ **All platforms** (Mobile, Console, PC)
- ✅ **Multiplayer compatible**
- ✅ **Works with other resource packs**

---

## 📝 Credits

- **Original Pack**: ICEy
- **Ultimate Edition**: Enhanced by AI Assistant
- **Version**: 4.0.0 Ultimate Edition

---

## 🚀 Future Updates

- Additional weapon-specific animations
- Enhanced facial expressions
- More environmental interactions
- Improved particle effects integration

---

*Experience Minecraft like never before with realistic, smooth, and immersive player animations!* 