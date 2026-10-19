#Requires AutoHotkey v2.0

; ==============================================================================
; GLOBAL STATE INITIALIZATION
; ==============================================================================

global Rules := {
    groupedProcesses: Map(
        "prismlauncher.exe", true
    ),
    systemClasses: Map(
        "shell_traywnd", true, "shell_secondarytraywnd", true,
        "progman", true, "workerw", true,
        "windows.ui.core.corewindow", true, "xamlexplorerhostislandwindow", true,
        "toplevelwindowforoverflowxamlisland", true, "#32770", true,
        "taskmanagerwindow", true, "chrome_widgetwin_2", true,
        "combolbox", true, "dropdown", true
    ),
    ignoreProcesses: Map(
        "flow.launcher.exe", true, "powertoys.powerlauncher.exe", true,
        "powertoys.peek.ui.exe", true, "powertoys.alwaysontop.exe", true,
        "wox.exe", true, "ditto.exe", true, "listary.exe", true,
        "everything.exe", true, "quicklook.exe", true, "snipaste.exe", true,
        "screenclippinghost.exe", true, "snippingtool.exe", true,
        "snippingtoolapp.exe", true, "searchapp.exe", true, "searchhost.exe", true,
        "startmenuexperiencehost.exe", true, "shellexperiencehost.exe", true,
        "textinputhost.exe", true, "gamebar.exe", true
    ),
    titleBarIgnoreProcesses: Map(
        "taskmgr.exe", true, "powershell.exe", true, "pwsh.exe", true,
        "windowsterminal.exe", true, "snippingtool.exe", true,
        "screenclippinghost.exe", true, "snippingtoolapp.exe", true,
        "calculatorapp.exe", true, "calculator.exe", true, "regedit.exe", true,
        "mmc.exe", true, "resmon.exe", true, "perfmon.exe", true,
        "msconfig.exe", true, "dxdiag.exe", true, "cleanmgr.exe", true,
        "sechealthui.exe", true, "systemsettings.exe", true, "flow.launcher.exe", true,
        "powertoys.powerlauncher.exe", true, "brave.exe", true, "chrome.exe", true,
        "msedge.exe", true
    ),
    titleBarIgnoreClasses: Map(
        "chrome_widgetwin_1", true, "chrome_widgetwin_0", true, "chrome_widgetwin_2", true,
        "mozillawindowclass", true, "applicationframewindow", true, "telegramclient", true,
        "spotifymainwindow", true, "discord", true,
        "vguipopupwindow", true, "valve001", true, "fltk", true, "sdl_app", true,
        "unrealwindow", true, "unitywndclass", true, "cascadia_hosting_window_class", true,
        "screenclippinghost", true, "taskmanagerwindow", true, "mmcmainframe", true, "regedit", true
    ),
    pinningIgnoreProcesses: Map(
        "taskmgr.exe", true, "powershell.exe", true, "pwsh.exe", true,
        "windowsterminal.exe", true, "snippingtool.exe", true,
        "screenclippinghost.exe", true, "snippingtoolapp.exe", true,
        "calculatorapp.exe", true, "calculator.exe", true,
        "flow.launcher.exe", true, "powertoys.powerlauncher.exe", true
    ),
    gameClasses: Map(
        "unrealwindow", true, "unitywndclass", true, "valve001", true,
        "fltk", true, "sdl_app", true, "vguipopupwindow", true
    )
}

global maxWorkspacesPerMon  := [6, 3, 3, 3]
global currentWorkspaces    := [1, 1, 1, 1]
global wsWindows            := Map()
global desktopStates        := Map()
global isSwitchingWorkspace := false
global lastSwitchTime       := 0
global isPanicMode          := false
global isMovingOrResizing   := false
global lastTaskbarClickTime := 0
global hasHooksInitialized  := false
global osdGlobalGui         := 0

global triggerHeightMaximized := 10  
global triggerHeightFloating  := 10  
global titleBarVisibleHeight  := 40  

global padLeft   := 8
global padRight  := 8
global padTop    := 8
global padBottom := 8

global colorActiveCaption   := 0x000000  
global colorActiveText      := 0xFFFFFF  
global colorActiveBorder    := 0x000000  
global colorInactiveCaption := 0x141414  
global colorInactiveText    := 0x888888  
global colorInactiveBorder  := 0x141414  

global lastToggleTime     := 0
global titleBarInfo       := Map()
global lastActiveHwnd     := 0
global currentlyShownHwnd := 0

global hWinEventHook      := 0
global winEventCallback   := 0
global hMouseHook         := 0
global mouseEventCallback := 0
