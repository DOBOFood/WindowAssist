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
        "progman", true, "workerw", true
    ),
    ignoreProcesses: Map(),
    titleBarIgnoreProcesses: Map(),
    titleBarIgnoreClasses: Map(),
    pinningIgnoreProcesses: Map(),
    gameClasses: Map()
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
