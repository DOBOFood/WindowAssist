#Requires AutoHotkey v2.0
#SingleInstance Force

; Elevate process to administrator privileges if required
if !A_IsAdmin {
    try {
        if A_IsCompiled
            Run('*RunAs "' A_ScriptFullPath '"')
        else
            Run('*RunAs "' A_AhkPath '" /restart "' A_ScriptFullPath '"')
    }
    ExitApp()
}

A_MaxHotkeysPerInterval := 999999

; Directives for Ahk2Exe Compiler
;@Ahk2Exe-SetName WindowAssist
;@Ahk2Exe-SetMainIcon assets\app.ico
;@Ahk2Exe-UpdateManifest 1

; Set icon for uncompiled runtime / tray
if FileExist(A_ScriptDir "\assets\app.ico") {
    TraySetIcon(A_ScriptDir "\assets\app.ico")
}

ProcessSetPriority("High")
SetWinDelay(-1)
SetControlDelay(-1)
ListLines(false)

; 1. Global State Initializations
#Include core/Globals.ahk

; 2. Include Libraries
#Include <JSON>
#Include <WebView2\WebView2>

; 3. Include Core Modules
#Include core/Win32API.ahk
#Include core/ConfigManager.ahk
#Include core/WindowTracker.ahk
#Include core/CaptureEngine.ahk
#Include core/WebViewManager.ahk
#Include core/App.ahk

; 4. Include Functional Modules
#Include modules/Workspaces/WorkspaceManager.ahk
#Include modules/Workspaces/WindowMover.ahk
#Include modules/Workspaces/PocketManager.ahk
#Include modules/TitleBar/TitleBarEngine.ahk
#Include modules/Overview/OverviewController.ahk
#Include modules/AltTab/CrossWorkspaceAltTab.ahk
#Include modules/Peeker/LayerPeeker.ahk

; 5. Include Input & Hotkeys
#Include input/MouseHook.ahk
#Include input/HotkeyManager.ahk

; Initialize Application Lifecycle
App.Init()
