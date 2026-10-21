<div align="center">
  <img src="assets/icon.svg" alt="WindowAssist" width="96" height="96" />
  <h1>WindowAssist</h1>
  <p><strong>Fast virtual desktops, full-screen overview, quick-access window shelf, and effortless mouse controls for Windows</strong></p>

  <p>
    <img src="https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-0078D7?style=flat-square&logo=windows" alt="Platform" />
    <img src="https://img.shields.io/badge/AutoHotkey-v2.0+-334455?style=flat-square" alt="AutoHotkey v2" />
    <img src="https://img.shields.io/badge/UI-WebView2-28A745?style=flat-square" alt="WebView2" />
    <img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" alt="License" />
  </p>
</div>

---

Windows makes multitasking harder than it needs to be: built-in virtual desktops are slow, dragging windows requires grabbing thin titlebars, and finding an app buried under other windows takes too many clicks.

**WindowAssist** makes window management effortless. It gives you instant virtual desktops, a full visual bird's-eye overview of everything running, a quick-stash pocket for apps you need on hand, and mouse controls that let you grab and resize windows from anywhere on screen.

### Highlights

* **Zero-Lag Virtual Desktops:** Fast workspace transitions with per-monitor isolation, completely bypassing sluggish native Windows desktop animations.
* **Anywhere Window Drag & Resize:** Move (`LButton`) and resize (`RButton`) windows from anywhere inside their frame by holding a modifier key—no need to aim at thin borders or headers.
* **Global Scratchpad ("The Pocket"):** A dedicated floating window shelf with visual border accents to stash and summon terminals, messengers, or notes over any desktop.
* **Cross-Desktop Alt+Tab:** A clean, MRU-ordered switcher displaying exact workspace locations on each app card.
* **Fully Customizable Modifiers:** Uses <kbd>NumLock</kbd> by default to prevent hotkey collisions, but can be easily changed to any key (<kbd>CapsLock</kbd>, <kbd>Alt</kbd>, <kbd>Win</kbd>, etc.) in Settings.
* **Auto-Hiding Title Bars:** Reclaim vertical screen space by hiding window headers until your cursor hovers near the top edge.
* **Lightweight Architecture:** Powered by native Win32/DWM APIs and AutoHotkey v2 with WebView2 rendering—no Electron overhead or heavy background services.

---

## Visual Overview

Press a shortcut to bring up an interactive full-screen canvas displaying all your desktops, running windows, and pocketed apps. Drag windows between desktops, hover to see live previews, or right-click to center and close apps.

<img width="1700" height="1007" alt="Image" src="https://github.com/user-attachments/assets/1074fe74-d956-4b4a-b7c0-3d99047c2a17" />

* **Drag-and-Drop:** Move single or multiple windows between desktops with ease.
* **Live Hover Previews:** Instant visual previews of open apps without switching to them.
* **Quick Window Menu:** Right-click any app card to center, maximize, minimize, or close it.
* **Resizable Canvas:** Adjust the grid width to fit your screen and preferences.

---

## Key Features

### 1. Instant Virtual Desktops & Window Carry
Switch between desktops with zero transition lag or animations getting in your way. When switching, hold the move key to take your active window with you and place it on your target desktop.

https://github.com/user-attachments/assets/601da3e5-6836-4cf4-9c65-10cbf5643756

* **Zero-Delay Switching:** Fast desktop transitions without Windows animations.
* **Independent Monitors:** Each display has its own independent set of desktops.
* **Clean Indicator:** A subtle on-screen badge shows your current desktop number.
* **State Recovery:** Window positions, sizes, and maximized states are preserved across restarts.

---

### 2. The Pocket (Quick-Access App Shelf)
Put any window into the "Pocket" to take it off your regular desktops. Pocketed windows stay ready in the background and can be summoned on top of any active desktop with a single click or shortcut.

https://github.com/user-attachments/assets/3eecfb7c-4652-4fcd-834e-d22022699759

https://github.com/user-attachments/assets/569d3225-c94b-45f9-965f-92c563c4b42f

* **Always One Key Away:** Great for calculators, messengers, note-taking apps, or command lines.
* **Distinct Highlight:** Pocketed apps feature a subtle colored outline so you know they are in the shelf.
* **Cycle Through Items:** Quickly step through all your pocketed tools in sequence.

---

### 3. Anywhere Mouse Move & Resize
Stop trying to aim your cursor at tiny window headers or 1-pixel borders just to move or resize an application.

https://github.com/user-attachments/assets/d25daead-d1e1-4dec-b453-c7d0096dc5f1

* **Drag Anywhere:** Hold your modifier key and drag <kbd>Left Mouse Button</kbd> anywhere inside a window to move it.
* **Resize Anywhere:** Hold your modifier key and drag <kbd>Right Mouse Button</kbd> anywhere inside a window to resize from the closest edge or corner.

---

### 4. Layer Peeker
Bring obscured windows forward without clicking around or disrupting your desktop layout.

https://github.com/user-attachments/assets/f53fac08-63af-4b73-bda2-6bedc51e1047

* **Peek Underneath:** Hold your modifier key and click <kbd>Left Mouse Button</kbd> without dragging to bring forward the window lying directly beneath your cursor.
* **Z-Order Cycling:** Keep clicking to cycle through all overlapping background windows on the current desktop.

---

### 5. Pin Windows on Top
Keep floating utility windows above all maximized applications with a single shortcut or click.

https://github.com/user-attachments/assets/cf4046b8-79ba-4554-8bcb-a9261a513b13

* **Elevated Priority:** Pinned floating windows stay visible over full-screen maximized windows without leaving the workspace.
* **Quick Toggle:** Toggle pinned states on the fly using <kbd>NumLock</kbd> + click <kbd>RButton</kbd> or a dedicated hotkey.

---

### 6. Auto-Hiding Window Title Bars
Maximize your usable screen real estate by removing top caption bars from windows while keeping them easy to access.

https://github.com/user-attachments/assets/992d6043-235f-47ca-8bac-839e2aec54f7

* **Top-Edge Reveal:** Title bars smoothly reveal when you hover your cursor near the top edge of the window or screen.
* **Dark Caption Support:** Automatically applies dark styling to native Windows caption bars.
* **Smart Filtering:** Automatically preserves title bars on games, browsers, and custom client frames.

---

### 7. Smart Cross-Desktop Alt+Tab
Replaces standard task switching with a clean overlay that shows which desktop each application lives on.

https://github.com/user-attachments/assets/833b1a83-c318-4e42-bd64-e2b934eb158d

* **Desktop Badges:** Clearly labels every card with its workspace (`WS 1`, `WS 2`, etc.).
* **MRU Order:** Keeps your most recently used windows prioritized at the front of the list.

---

### 8. Settings & Interactive Key Recorder
A modern, built-in settings interface that lets you customize every key, color, and behavior in real time.

https://github.com/user-attachments/assets/b7900ba6-071c-42e5-b26e-1cdd2f580ce2

https://github.com/user-attachments/assets/762e965c-3af6-4151-8522-dfd69f56cb17

* **Interactive Key Recorder:** Click `+ Add`, press any key, modifier, mouse button, or scroll wheel to bind it immediately.
* **Custom Modifiers:** Easily switch the default <kbd>NumLock</kbd> modifier to <kbd>CapsLock</kbd>, <kbd>Alt</kbd>, or any other key.
* **Multiple Profiles:** Create, duplicate, rename, or restore different shortcut setups.
* **Bilingual UI:** Native support for both English and Russian.

---

## Default Shortcuts

*All shortcuts can be remapped in Settings (<kbd>NumLock</kbd> + <kbd>I</kbd>).*

| Action | Shortcut |
| :--- | :--- |
| **Overview Canvas** | <kbd>NumLock</kbd> + <kbd>Tab</kbd> *or* <kbd>NumLock</kbd> + <kbd>Space</kbd> |
| **Switch Desktop (1–9)** | <kbd>NumLock</kbd> + <kbd>1</kbd>…<kbd>9</kbd> |
| **Move Window to Desktop (1–9)** | <kbd>NumLock</kbd> + <kbd>Shift</kbd> + <kbd>1</kbd>…<kbd>9</kbd> |
| **Previous / Next Desktop** | <kbd>NumLock</kbd> + <kbd>Z</kbd> / <kbd>X</kbd> *(or <kbd>WheelUp</kbd> / <kbd>WheelDown</kbd>)* |
| **Move Window Anywhere** | Hold <kbd>NumLock</kbd> + Drag <kbd>LButton</kbd> |
| **Resize Window Anywhere** | Hold <kbd>NumLock</kbd> + Drag <kbd>RButton</kbd> |
| **Layer Peeker (Cycle overlapping)** | <kbd>NumLock</kbd> + Click <kbd>LButton</kbd> |
| **Pin Window on Top** | <kbd>NumLock</kbd> + Click <kbd>RButton</kbd> |
| **Add / Remove Window to Pocket** | <kbd>NumLock</kbd> + <kbd>C</kbd> |
| **Cycle Pocket Windows** | <kbd>NumLock</kbd> + <kbd>F</kbd> |
| **Summon / Dismiss Pocket** | <kbd>NumLock</kbd> + <kbd>MButton</kbd> |
| **Cross-Workspace Alt+Tab** | <kbd>Alt</kbd> + <kbd>Tab</kbd> |
| **Close Active Window** | <kbd>NumLock</kbd> + <kbd>Q</kbd> |
| **Minimize Active Window** | <kbd>NumLock</kbd> + <kbd>A</kbd> |
| **Open Settings** | <kbd>NumLock</kbd> + <kbd>I</kbd> |
| **Quick Reload** | <kbd>NumLock</kbd> + <kbd>Ctrl</kbd> + <kbd>R</kbd> |
| **Panic Exit** | <kbd>NumLock</kbd> + <kbd>Insert</kbd> |

---

## Requirements

* **Operating System:** Windows 10 (version 1809+) or Windows 11 (64-bit).
* **WebView2 Runtime:** Included by default in Windows 11 and modern Windows 10 installations.
* **AutoHotkey:** [AutoHotkey v2.0+](https://www.autohotkey.com/) *(only required if running directly from source)*.
* **Permissions:** Administrator privileges are recommended so global window actions work reliably over elevated programs (Task Manager, Terminal, etc.).

---

## Installation & Running

### Run from Source
1. Clone the repository:
   ```bash
   git clone https://github.com/DOBOFood/WindowAssist.git
   cd WindowAssist
   ```
2. Launch `WindowAssist.ahk` with AutoHotkey v2.

### Build Portable Executable
Run `build.bat` in the repository root. It will compile a standalone binary into the `dist/` directory:
```cmd
build.bat
```

---

## Configuration

Settings are saved in `config.json` in the root folder. All adjustments made inside the Settings UI apply immediately in real time. If the file is missing or reset, default values are restored automatically.

---

## License

This project is open-source software licensed under the [MIT License](LICENSE).