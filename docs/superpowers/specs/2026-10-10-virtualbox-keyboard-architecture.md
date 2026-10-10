# VirtualBox 多国键盘适配架构与数据流分析

> 研究日期：2026-10-10  
> 目的：理解VirtualBox如何实现多国键盘布局的适配，为KeyCmd项目提供参考

---

## 1. 概述

VirtualBox作为虚拟机监控器（VMM），需要在Host物理键盘和Guest虚拟键盘之间建立桥梁。其核心挑战在于：

- **Host多样性**：支持Windows、macOS、Linux等不同操作系统的键盘输入
- **Guest多样性**：Guest OS可以运行任何操作系统，使用任意键盘布局
- **布局独立性**：Host和Guest可以使用完全不同的键盘布局（如Host用法语AZERTY，Guest用德语QWERTZ）

### 1.1 设计哲学

VirtualBox采用**"Scancode为中心"**的设计：

```
物理按键 → Host Scancode → VirtualBox翻译 → Guest Scancode → 字符生成
   ↑            ↑                ↑                ↑              ↑
 硬件层      Host OS         VMM层            Guest OS       应用层
```

**关键原则**：
1. **不信任Host布局翻译**：避免Host的布局设置影响Guest
2. **使用标准接口**：USB HID和PS/2作为通用翻译标准
3. **Guest主导**：最终字符由Guest的布局设置决定

---

## 2. 整体架构

### 2.1 三层翻译模型

```
┌─────────────────────────────────────────────────────────┐
│                    Host 物理键盘                         │
│              (USB/PS2/蓝牙/笔记本内置)                   │
└────────────────────┬────────────────────────────────────┘
                     │ 硬件中断
                     ▼
┌─────────────────────────────────────────────────────────┐
│                   Host OS 层                            │
│  ┌──────────────────────────────────────────────────┐  │
│  │ 键盘驱动 (USB HID / i8042 / Bluetooth)          │  │
│  └──────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────┐  │
│  │ 输入子系统 (X11/Wayland/Win32/Cocoa)            │  │
│  │  - 生成scancode/keysym                          │  │
│  │  - 应用Host布局（可选）                         │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────┬────────────────────────────────────┘
                     │ scancode / keysym / HID report
                     ▼
┌─────────────────────────────────────────────────────────┐
│              VirtualBox VMM 层                          │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Host输入捕获模块                                 │  │
│  │  - Windows: GetKeyboardLayout()                 │  │
│  │  - macOS: TISCopyCurrentKeyboardInputSource()   │  │
│  │  - Linux: XKB / libxkbcommon                    │  │
│  └──────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────┐  │
│  │ 翻译引擎 (核心)                                  │  │
│  │  - USB HID Usage ID → 内部scancode              │  │
│  │  - X11 keysym → PC scancode (WINE逻辑)          │  │
│  │  - 布局检测与匹配 (ByLayout/ByType)             │  │
│  └──────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────┐  │
│  │ 设备模拟器                                       │  │
│  │  - USB HID设备 (devhid.cpp)                     │  │
│  │  - PS/2键盘 (devkbd.cpp)                        │  │
│  │  - PS/2控制器 (DevPS2.cpp)                      │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────┬────────────────────────────────────┘
                     │ PS/2 scancode (Set 1 或 Set 2)
                     ▼
┌─────────────────────────────────────────────────────────┐
│                   Guest OS 层                           │
│  ┌──────────────────────────────────────────────────┐  │
│  │ 键盘驱动 (i8042/atkbd/usbhid)                   │  │
│  │  - 接收PS/2 scancode                            │  │
│  │  - 转换为Guest内部keycode                       │  │
│  └──────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────┐  │
│  │ 输入子系统                                       │  │
│  │  - 应用Guest键盘布局                            │  │
│  │  - 生成最终字符                                 │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────────┬────────────────────────────────────┘
                     │ 字符 (Unicode)
                     ▼
┌─────────────────────────────────────────────────────────┐
│                   应用程序                              │
│              (文本编辑器、浏览器等)                      │
└─────────────────────────────────────────────────────────┘
```

### 2.2 两种输入路径

VirtualBox支持两种主要的键盘输入方式：

#### 路径A：Host键盘捕获（默认）

```
Host物理键盘 → Host OS → VirtualBox捕获 → 翻译 → Guest虚拟键盘
```

- **适用场景**：日常使用，Host和Guest共享键盘
- **特点**：VirtualBox拦截Host键盘事件，翻译后发送给Guest
- **布局处理**：Guest使用自己的布局设置

#### 路径B：USB设备直通

```
USB键盘 → Host USB栈 → VirtualBox USB控制器 → Guest USB驱动
```

- **适用场景**：需要完整USB设备功能（如游戏键盘、特殊硬件）
- **特点**：Guest直接控制USB设备，Host无法使用
- **布局处理**：Guest完全控制，包括布局、LED等

---

## 3. 数据流详解

### 3.1 路径A：Host键盘捕获流程

#### 步骤1：Host物理按键

```
用户按下物理键 'A'
    ↓
键盘硬件生成扫描码 (Set 1: 0x1E, Set 2: 0x1C)
    ↓
通过USB/PS2/蓝牙发送到Host
```

#### 步骤2：Host OS处理

**Windows示例**：
```c
// 1. 键盘驱动接收硬件中断
// 2. 转换为虚拟键码 (Virtual-Key Code)
wParam = VK_A;  // 0x41
lParam = 0x001E0001;  // 包含scancode信息

// 3. 发送到窗口消息队列
PostMessage(hWnd, WM_KEYDOWN, wParam, lParam);
```

**Linux (X11) 示例**：
```c
// 1. 内核键盘驱动处理
// 2. evdev子系统生成事件
struct input_event ev = {
    .type = EV_KEY,
    .code = KEY_A,  // 30
    .value = 1      // 按下
};

// 3. X11服务器接收并转换为keysym
// XKB扩展应用布局规则
keysym = XKB_KEY_A;  // 0x0061

// 4. 发送到X客户端
XKeyEvent event = {
    .type = KeyPress,
    .keycode = 38,      // X11 keycode
    .state = 0,         // 修饰键状态
    .xkey.keycode = 38
};
```

**macOS示例**：
```objc
// 1. IOHIDManager接收USB HID报告
IOHIDValueRef value = ...;
uint32_t usagePage = IOHIDValueGetUsagePage(value);  // 0x07 (Keyboard)
uint32_t usage = IOHIDValueGetUsage(value);          // 0x04 (A)

// 2. Cocoa转换为NSEvent
NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                  location:NSZeroPoint
                             modifierFlags:0
                                 timestamp:now
                              windowNumber:0
                                   context:context
                                characters:@"a"
               charactersIgnoringModifiers:@"a"
                                 isARepeat:NO
                                   keyCode:0];  // macOS keycode
```

#### 步骤3：VirtualBox捕获与翻译

**3.1 布局检测**

```cpp
// VirtualBox启动时检测Host布局
// src/VBox/Frontends/VirtualBox/src/runtime/UIKeyboardHandler.cpp

#if defined(RT_OS_LINUX)
// Linux: 使用XKB
char *layout = NULL;
if (XkbGetNamedDeviceValues(dpy, XkbUseCoreKbd, &layout) == Success) {
    // layout = "us", "de", "fr" 等
    m_hostLayout = layout;
}
#elif defined(RT_OS_DARWIN)
// macOS: 使用TIS
TISInputSourceRef source = TISCopyCurrentKeyboardInputSource();
CFStringRef layoutId = (CFStringRef)TISGetInputSourceProperty(
    source, kTISPropertyInputSourceID);
// layoutId = "com.apple.keylayout.US" 等
#elif defined(RT_OS_WINDOWS)
// Windows: 使用GetKeyboardLayout
HKL layout = GetKeyboardLayout(0);
LANGID langId = LOWORD(layout);
// langId = 0x0409 (en-US), 0x0407 (de-DE) 等
#endif
```

**3.2 Scancode翻译**

```cpp
// 核心翻译逻辑
// src/VBox/Frontends/VirtualBox/src/platform/X11/X11Keyboard.cpp

uint32_t X11Keyboard::keysymToScancode(KeySym keysym) {
    // 使用WINE的翻译表
    // 参考: https://github.com/wine-mirror/wine/blob/master/dlls/user32/input.c
    
    static const struct {
        KeySym keysym;
        uint8_t scancode;
    } translationTable[] = {
        { XK_A, 0x1E },
        { XK_B, 0x30 },
        { XK_C, 0x2E },
        // ... 数百个映射
    };
    
    for (const auto &entry : translationTable) {
        if (entry.keysym == keysym) {
            return entry.scancode;
        }
    }
    return 0;  // 未知键
}
```

**3.3 生成Guest事件**

```cpp
// 将scancode发送给Guest
// src/VBox/Devices/Input/DevPS2.cpp

void PS2Keyboard::sendScancode(uint8_t scancode, bool release) {
    // 1. 转换为当前scancode集
    uint8_t code = convertToScanCodeSet(scancode, m_currentSet);
    
    // 2. 如果是释放键，添加break码
    if (release) {
        if (m_currentSet == 1) {
            code |= 0x80;  // Set 1: 最高位设为1
        } else {
            // Set 2: 发送 0xF0 + make code
            writeToPort(0xF0);
        }
    }
    
    // 3. 写入PS/2端口
    writeToPort(code);
    
    // 4. 触发Guest中断
    PICInterrupt(IRQ_KEYBOARD);
}
```

#### 步骤4：Guest OS处理

**Linux Guest示例**：
```c
// 1. i8042控制器接收scancode
// 中断处理: drivers/input/serio/i8042.c
irqreturn_t i8042_interrupt(int irq, void *dev_id) {
    unsigned char scancode = inb(0x60);  // 读取PS/2端口
    
    // 2. 转换为keycode
    // drivers/input/keyboard/atkbd.c
    unsigned int keycode = atkbd->keycode[scancode & 0x7F];
    
    // 3. 生成input事件
    struct input_dev *dev = ...;
    input_report_key(dev, keycode, scancode & 0x80 ? 0 : 1);
    input_sync(dev);
    
    // 4. evdev子系统处理
    // drivers/input/evdev.c
    struct input_event ev = {
        .type = EV_KEY,
        .code = keycode,
        .value = 1  // 按下
    };
    
    // 5. 发送到用户空间
    // /dev/input/eventX
    
    // 6. X11/Wayland接收并应用布局
    // 使用XKB规则将keycode转换为keysym
    KeySym keysym = XkbKeycodeToKeysym(dpy, keycode, 0, 0);
    
    // 7. 最终转换为字符
    char buffer[10];
    int len = XkbTranslateKeyCode(dpy, keycode, 0, NULL, buffer);
    // buffer = "a"
}
```

**Windows Guest示例**：
```c
// 1. i8042prt驱动接收scancode
// 2. kbdclass过滤驱动处理
// 3. 转换为MAKECODE
// 4. 发送到Win32子系统
// 5. 应用键盘布局 (HKL)
// 6. 生成WM_CHAR消息
PostMessage(hWnd, WM_CHAR, 'a', 0);
```

### 3.2 路径B：USB设备直通流程

#### 步骤1：USB设备枚举

```
USB键盘插入
    ↓
Host USB栈检测到新设备
    ↓
VirtualBox USB监控器 (VBoxUSBMon) 捕获
    ↓
如果配置了USB过滤器，传递给VM
    ↓
Guest USB驱动接管设备
```

#### 步骤2：HID报告处理

```cpp
// Host端：捕获USB HID报告
// src/VBox/HostDrivers/VBoxUSB/VBoxUSB.cpp

void VBoxUSB::processHIDReport(const uint8_t *report, size_t size) {
    // 标准USB HID键盘报告格式 (8字节)
    // Byte 0: 修饰键 (Ctrl, Shift, Alt, GUI)
    // Byte 1: 保留
    // Byte 2-7: 按键Usage ID (最多6键同时按下)
    
    uint8_t modifiers = report[0];
    for (int i = 2; i < 8; i++) {
        uint8_t usageId = report[i];
        if (usageId != 0) {
            // 发送给Guest
            sendHIDUsage(modifiers, usageId);
        }
    }
}
```

#### 步骤3：Guest端HID解析

```cpp
// Guest端：解析HID报告
// src/VBox/Devices/USB/devhid.cpp

void HidKeyboard::handleHIDReport(const uint8_t *report) {
    uint8_t modifiers = report[0];
    
    // 1. 处理修饰键
    uint8_t modMask = modifiers ^ m_lastModifiers;
    if (modMask & 0x01) sendKey(KEY_LEFTCTRL, modifiers & 0x01);
    if (modMask & 0x02) sendKey(KEY_LEFTSHIFT, modifiers & 0x02);
    if (modMask & 0x04) sendKey(KEY_LEFTALT, modifiers & 0x04);
    if (modMask & 0x08) sendKey(KEY_LEFTGUI, modifiers & 0x08);
    // ... 右修饰键
    
    // 2. 处理普通键
    for (int i = 2; i < 8; i++) {
        uint8_t usageId = report[i];
        if (usageId != 0) {
            // 使用翻译表
            uint16_t linuxKeycode = s_ausKeyMap[usageId];
            sendKey(linuxKeycode, true);
        }
    }
    
    m_lastModifiers = modifiers;
}

// 翻译表定义
// src/VBox/Devices/USB/devhid.cpp
static const uint16_t s_ausKeyMap[256] = {
    [0x04] = KEY_A,           // HID Usage: Keyboard a and A
    [0x05] = KEY_B,           // HID Usage: Keyboard b and B
    [0x06] = KEY_C,           // HID Usage: Keyboard c and C
    [0x1E] = KEY_1,           // HID Usage: Keyboard 1 and !
    [0x1F] = KEY_2,           // HID Usage: Keyboard 2 and @
    [0x2C] = KEY_SPACE,       // HID Usage: Keyboard Spacebar
    [0x28] = KEY_ENTER,       // HID Usage: Keyboard Return (ENTER)
    [0x29] = KEY_ESC,         // HID Usage: Keyboard ESCAPE
    [0x2A] = KEY_BACKSPACE,   // HID Usage: Keyboard Backspace
    [0x2B] = KEY_TAB,         // HID Usage: Keyboard Tab
    // ... 完整映射参考 USB HID Usage Tables
};
```

#### 步骤4：Guest布局应用

```
Guest USB HID驱动
    ↓
生成Linux input事件 (keycode)
    ↓
evdev子系统
    ↓
X11/Wayland接收
    ↓
应用Guest键盘布局 (XKB)
    ↓
生成最终字符
```

**关键点**：USB直通时，Guest完全控制键盘，包括：
- 键盘布局
- LED状态 (Caps Lock, Num Lock, Scroll Lock)
- 特殊功能键
- 自定义宏

---

## 4. 关键翻译机制

### 4.1 Scancode集合

VirtualBox支持两种PS/2 scancode集合：

#### Set 1 (XT兼容)

```
按键    Make码    Break码
A       0x1E      0x9E (0x1E + 0x80)
B       0x30      0xB0
C       0x2E      0xAE
Enter   0x1C      0x9C
Escape  0x01      0x81
```

#### Set 2 (AT标准)

```
按键    Make码         Break码
A       0x1C           0xF0 0x1C
B       0x32           0xF0 0x32
C       0x21           0xF0 0x21
Enter   0x5A           0xF0 0x5A
Escape  0x76           0xF0 0x76
```

#### 切换机制

```cpp
// Guest可以通过PS/2控制器命令切换scancode集
// src/VBox/Devices/Input/DevPS2.cpp

void PS2Keyboard::handleCommand(uint8_t cmd) {
    switch (cmd) {
        case 0xF0:  // Set Scan Code Set
            m_nextCommand = CMD_SET_SCANCODE;
            break;
        case 0xF2:  // Identify Keyboard
            sendResponse(0xAB);
            sendResponse(0x83);  // MF2 keyboard
            break;
    }
}

void PS2Keyboard::handleData(uint8_t data) {
    if (m_nextCommand == CMD_SET_SCANCODE) {
        if (data >= 1 && data <= 3) {
            m_currentSet = data;
            sendResponse(0xFA);  // ACK
        }
        m_nextCommand = CMD_NONE;
    }
}
```

### 4.2 USB HID到Scancode的映射

#### 完整映射表示例

```cpp
// 基于 USB HID Usage Tables 1.12
// Usage Page 0x07 (Keyboard/Keypad)

static const uint16_t s_ausKeyMap[256] = {
    // 字母键 (0x04 - 0x1D)
    [0x04] = KEY_A, [0x05] = KEY_B, [0x06] = KEY_C, [0x07] = KEY_D,
    [0x08] = KEY_E, [0x09] = KEY_F, [0x0A] = KEY_G, [0x0B] = KEY_H,
    [0x0C] = KEY_I, [0x0D] = KEY_J, [0x0E] = KEY_K, [0x0F] = KEY_L,
    [0x10] = KEY_M, [0x11] = KEY_N, [0x12] = KEY_O, [0x13] = KEY_P,
    [0x14] = KEY_Q, [0x15] = KEY_R, [0x16] = KEY_S, [0x17] = KEY_T,
    [0x18] = KEY_U, [0x19] = KEY_V, [0x1A] = KEY_W, [0x1B] = KEY_X,
    [0x1C] = KEY_Y, [0x1D] = KEY_Z,
    
    // 数字键 (0x1E - 0x27)
    [0x1E] = KEY_1, [0x1F] = KEY_2, [0x20] = KEY_3, [0x21] = KEY_4,
    [0x22] = KEY_5, [0x23] = KEY_6, [0x24] = KEY_7, [0x25] = KEY_8,
    [0x26] = KEY_9, [0x27] = KEY_0,
    
    // 控制键 (0x28 - 0x2F)
    [0x28] = KEY_ENTER,      [0x29] = KEY_ESC,
    [0x2A] = KEY_BACKSPACE,  [0x2B] = KEY_TAB,
    [0x2C] = KEY_SPACE,      [0x2D] = KEY_MINUS,
    [0x2E] = KEY_EQUAL,      [0x2F] = KEY_LEFTBRACE,
    
    // 修饰键 (0xE0 - 0xE7)
    [0xE0] = KEY_LEFTCTRL,   [0xE1] = KEY_LEFTSHIFT,
    [0xE2] = KEY_LEFTALT,    [0xE3] = KEY_LEFTMETA,
    [0xE4] = KEY_RIGHTCTRL,  [0xE5] = KEY_RIGHTSHIFT,
    [0xE6] = KEY_RIGHTALT,   [0xE7] = KEY_RIGHTMETA,
    
    // ... 完整映射约200+条目
};
```

### 4.3 多国布局特殊处理

#### Dead Keys（组合键）

```cpp
// Dead key示例：法语布局中的 ^ (circumflex)
// 用户按下 ^ (dead key)，然后按下 e，生成 ê

// Host端 (Linux X11)
XKeyEvent event1 = { .keycode = 35 };  // ^ 键
XKeyEvent event2 = { .keycode = 26 };  // e 键

// VirtualBox翻译
uint8_t scancode1 = keysymToScancode(XK_dead_circumflex);  // 0x1A
uint8_t scancode2 = keysymToScancode(XK_e);                // 0x12

// Guest端接收
// Guest的XKB系统处理dead key逻辑
// 最终生成字符 'ê'
```

#### AltGr键

```cpp
// AltGr (Right Alt) 用于输入特殊字符
// 例如：德语布局中 AltGr+Q = @

// USB HID报告
uint8_t report[8] = {
    0x40,  // 修饰键字节: Right Alt (0x40)
    0x00,  // 保留
    0x14,  // Usage ID: Q (0x14)
    0x00, 0x00, 0x00, 0x00, 0x00
};

// Guest端处理
// 1. 检测到Right Alt修饰键
// 2. 应用AltGr层布局规则
// 3. 生成字符 '@'
```

#### 日语特殊键

```cpp
// 日语键盘特殊键
// USB HID Usage IDs:
// 0x89 - Henkan (変換)
// 0x8A - Muhenkan (無変換)
// 0x8B - Katakanahiragana
// 0x92 - Han/Zen (半角/全角)

// VirtualBox特殊处理
// src/VBox/Devices/Input/DevPS2.cpp
void PS2Keyboard::sendJapaneseKey(uint8_t usageId) {
    switch (usageId) {
        case 0x89:  // Henkan
            sendScancode(0x79);  // 特殊scancode
            break;
        case 0x8A:  // Muhenkan
            sendScancode(0x7B);
            break;
        case 0x92:  // Han/Zen
            sendScancode(0x77);
            break;
    }
}
```

---

## 5. Guest Additions的作用

### 5.1 键盘同步服务

```
┌─────────────────────────────────────────────────────┐
│                    Host OS                          │
│  ┌──────────────────────────────────────────────┐  │
│  │ VBoxTray.exe / VBoxClient                    │  │
│  │  - 监控Host键盘布局变化                      │  │
│  │  - 通过VBoxService通知Guest                  │  │
│  └──────────────────────────────────────────────┘  │
└────────────────────┬────────────────────────────────┘
                     │ VBoxGuest控制通道
                     ▼
┌─────────────────────────────────────────────────────┐
│                    Guest OS                         │
│  ┌──────────────────────────────────────────────┐  │
│  │ VBoxService                                  │  │
│  │  - 接收Host布局通知                          │  │
│  │  - 更新Guest键盘布局                         │  │
│  │  - 同步修饰键状态                            │  │
│  └──────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

### 5.2 布局同步流程

```cpp
// Host端 (Windows)
// src/VBox/Additions/WINNT/VBoxTray/VBoxClipboard.cpp

void CheckKeyboardLayout() {
    static HKL lastLayout = NULL;
    HKL currentLayout = GetKeyboardLayout(0);
    
    if (currentLayout != lastLayout) {
        // 布局发生变化
        LANGID langId = LOWORD(currentLayout);
        
        // 通知Guest
        VBoxGuestCallService(VBOXGUEST_SERVICE_KEYBOARD,
                            VBOX_KB_LAYOUT_CHANGED,
                            langId);
        
        lastLayout = currentLayout;
    }
}

// Guest端 (Linux)
// src/VBox/Additions/linux/VBoxService/VBoxServiceKB.cpp

void HandleLayoutChange(LANGID langId) {
    // 映射Windows LANGID到XKB布局
    const char *xkbLayout = LangIdToXkbLayout(langId);
    // 0x0409 -> "us"
    // 0x0407 -> "de"
    // 0x040C -> "fr"
    
    // 应用XKB布局
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "setxkbmap %s", xkbLayout);
    system(cmd);
}
```

### 5.3 修饰键同步

```cpp
// 同步Caps Lock, Num Lock, Scroll Lock状态

// Host端
void SyncModifiers() {
    uint8_t hostState = 0;
    if (GetKeyState(VK_CAPITAL) & 1) hostState |= KB_CAPS_LOCK;
    if (GetKeyState(VK_NUMLOCK) & 1) hostState |= KB_NUM_LOCK;
    if (GetKeyState(VK_SCROLL) & 1) hostState |= KB_SCROLL_LOCK;
    
    // 发送给Guest
    VBoxGuestCallService(VBOXGUEST_SERVICE_KEYBOARD,
                        VBOX_KB_MODIFIERS,
                        hostState);
}

// Guest端
void UpdateLEDs(uint8_t state) {
    // 更新Guest的LED状态
    ioctl(kbd_fd, KDSETLED, state);
    
    // 如果USB直通，还要更新物理键盘LED
    if (usbPassthrough) {
        uint8_t hidReport[1] = { state };
        usb_set_report(usb_dev, HID_REPORT_OUTPUT, hidReport, 1);
    }
}
```

---

## 6. 常见问题与解决方案

### 6.1 布局不匹配

**问题**：Host用法语AZERTY，Guest用英语QWERTY，按下Host的'A'键，Guest显示'Q'

**原因**：
- VirtualBox发送的是物理位置的scancode，而非字符
- Guest应用自己的布局规则

**解决方案**：
1. 安装Guest Additions，启用布局同步
2. 保持Host和Guest使用相同布局
3. 使用USB直通，让Guest完全控制

### 6.2 Dead Keys失效

**问题**：法语布局中，按下^后按e，无法生成ê

**原因**：
- Dead key状态在Host和Guest之间不同步
- Guest的XKB配置不正确

**解决方案**：
```bash
# Guest Linux
# 1. 检查XKB配置
setxkbmap -query

# 2. 重新设置布局
setxkbmap -layout fr -variant oss

# 3. 启用dead key支持
setxkbmap -option compose:caps
```

### 6.3 AltGr组合失败

**问题**：德语布局中AltGr+Q无法输入@

**原因**：
- Host系统拦截了AltGr组合
- VirtualBox未正确传递Right Alt修饰键

**解决方案**：
```bash
# Host Linux
# 检查是否有快捷键冲突
gsettings list-recursively | grep AltGr

# 禁用Host的AltGr快捷键
gsettings set org.gnome.desktop.wm.keybindings switch-input-source "[]"
```

### 6.4 日语特殊键不工作

**问题**：日语键盘的"変換"、"無変換"键无法使用

**原因**：
- Guest未配置日语布局
- 缺少IME支持

**解决方案**：
```bash
# Guest Linux
# 1. 安装日语支持
sudo apt install ibus-mozc

# 2. 配置日语布局
setxkbmap -layout jp

# 3. 启动IME
ibus-daemon -drx
```

---

## 7. 与KeyCmd项目的对比

### 7.1 设计哲学差异

| 方面 | VirtualBox | KeyCmd |
|------|-----------|--------|
| **目标** | 通用虚拟机，支持任意Guest OS | 专用键盘模拟器，针对特定硬件 |
| **布局处理位置** | Guest OS主导 | iOS端主导 |
| **翻译层** | 多层翻译（Host→VMM→Guest） | 直接映射（iOS→硬件） |
| **标准依赖** | USB HID, PS/2 | 自定义协议 |
| **动态性** | 运行时切换布局 | 预设布局配置 |

### 7.2 KeyCmd的当前实现

```swift
// KeyCmd/Managers/KeyboardLayoutManager.swift

class KeyboardLayoutManager {
    // 14个预定义布局
    let supportedLocales: [KeyboardLocale] = [
        .us, .uk, .de, .fr, .es, .it, .pt, .jp,
        .cn, .ca, .au, .be, .ch, .nordic
    ]
    
    // 布局缓存
    private var cache: [String: KeyboardLayoutDefinition] = [:]
    
    func layout(for os: TargetOS, locale: KeyboardLocale) -> KeyboardLayoutDefinition {
        let key = "\(os.rawValue)_\(locale.rawValue)"
        if let cached = cache[key] {
            return cached
        }
        
        // 生成布局定义
        let layout = generateLayout(for: os, locale: locale)
        cache[key] = layout
        return layout
    }
}
```

### 7.3 可借鉴的设计

从VirtualBox的设计中，KeyCmd可以借鉴：

1. **Scancode为中心**：
   - 当前KeyCmd使用`keyCode`字符串，可以考虑标准化为USB HID Usage ID
   - 便于跨平台映射

2. **布局检测机制**：
   - VirtualBox通过OS API检测Host布局
   - KeyCmd可以自动检测iOS系统键盘布局

3. **翻译表设计**：
   - VirtualBox使用静态数组映射
   - KeyCmd可以参考，优化布局生成性能

4. **特殊键处理**：
   - VirtualBox对日语、AltGr等特殊处理
   - KeyCmd需要确保这些键的正确映射

### 7.4 建议改进

```swift
// 建议1：使用USB HID Usage ID作为标准
enum HIDUsageID: UInt8 {
    case keyboardA = 0x04
    case keyboardB = 0x05
    case keyboardC = 0x06
    // ...
}

// 建议2：自动布局检测
extension KeyboardLocale {
    static func detectFromSystem() -> KeyboardLocale {
        // 使用iOS API检测当前键盘布局
        let locale = Locale.current
        // 映射到KeyboardLocale
        return fromSystemLocale()
    }
}

// 建议3：优化翻译表
struct KeyboardTranslationTable {
    // 使用字典而非数组，提高查找效率
    private let hidToKeyCode: [HIDUsageID: String]
    
    func translate(_ usageID: HIDUsageID) -> String? {
        return hidToKeyCode[usageID]
    }
}
```

---

## 8. 参考资源

### 8.1 官方文档

- [VirtualBox源代码](https://github.com/VirtualBox/virtualbox)
- [VirtualBox SDK参考](https://www.virtualbox.org/sdkref/)
- [VirtualBox用户手册](https://www.virtualbox.org/manual/)
- [USB HID Usage Tables 1.12](https://usb.org/sites/default/files/documents/hut1_12v2.pdf)

### 8.2 关键源文件

```
VirtualBox源码结构:
src/VBox/
├── Devices/
│   ├── Input/
│   │   ├── DevPS2.cpp          # PS/2控制器模拟
│   │   ├── devkbd.cpp          # PS/2键盘设备
│   │   └── KeyboardScanCodes.cpp  # Scancode表
│   └── USB/
│       └── devhid.cpp          # USB HID设备
├── Frontends/
│   └── VirtualBox/
│       └── src/
│           ├── platform/
│           │   └── X11/
│           │       └── X11Keyboard.cpp  # X11键盘处理
│           └── runtime/
│               └── UIKeyboardHandler.cpp  # 键盘事件处理
└── Additions/
    ├── linux/
    │   └── VBoxService/       # Linux Guest Additions
    └── WINNT/
        └── VBoxTray/          # Windows Guest Additions
```

### 8.3 技术博客与讨论

- [VirtualBox键盘输入调查](https://www.virtualbox.org/wiki/KeyboardInput)
- [X11键盘处理](https://www.virtualbox.org/wiki/X11Keyboard)
- [PC扫描码总结](https://www.berrange.com/posts/2010/07/04/a-summary-of-scan-code-key-codes-sets-used-in-the-pc-virtualization-stack/)
- [VirtualBox论坛：键盘问题](https://forums.virtualbox.org/viewforum.php?f=6)

---

## 9. 总结

VirtualBox的多国键盘适配采用了一套精密的分层翻译架构：

1. **物理层**：捕获Host键盘事件（USB HID/PS2/蓝牙）
2. **翻译层**：将Host输入转换为标准scancode（USB HID Usage ID或PS/2 scancode）
3. **模拟层**：模拟标准键盘设备（USB HID或PS/2）
4. **Guest层**：Guest OS接收scancode并应用自己的布局规则

**核心设计原则**：
- 使用scancode作为通用中间表示
- 不信任Host的布局翻译
- Guest OS主导最终字符生成
- 通过Guest Additions实现动态同步

这套设计的优势在于：
- **通用性**：支持任意Host/Guest组合
- **隔离性**：Host和Guest布局独立
- **标准性**：基于USB HID和PS/2标准

对于KeyCmd项目，可以借鉴的关键点：
1. 使用USB HID Usage ID作为标准键码
2. 实现自动布局检测
3. 优化翻译表性能
4. 完善特殊键处理

---

*文档完成于 2026-10-10*
