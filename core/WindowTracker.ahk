#Requires AutoHotkey v2.0

class WindowTracker {
    static Init() {
        global MsgNum, hWinEventHook, winEventCallback

        MsgNum := DllCall("RegisterWindowMessage", "str", "SHELLHOOK")
        DllCall("RegisterShellHookWindow", "ptr", A_ScriptHwnd)
        OnMessage(MsgNum, ShellMessage)

        winEventCallback := CallbackCreate(OnWinEvent, "C", 7)
        hWinEventHook := DllCall("SetWinEventHook"
            , "uint", 0x0003, "uint", 0x000B
            , "ptr", 0
            , "ptr", winEventCallback
            , "uint", 0, "uint", 0
            , "uint", 0)

        SetTimer(CheckTitleBarHover, 30)
    }

    static UnHook() {
        global hWinEventHook, winEventCallback
        SetTimer(CheckTitleBarHover, 0)
        try DllCall("user32\DeregisterShellHookWindow", "ptr", A_ScriptHwnd)
        if hWinEventHook {
            DllCall("UnhookWinEvent", "ptr", hWinEventHook)
            hWinEventHook := 0
        }
        if winEventCallback {
            CallbackFree(winEventCallback)
            winEventCallback := 0
        }
    }
}

ShellMessage(wParam, lParam, *) {
    action := wParam & 0x7FFF
    hwndTarget := lParam
    if !hwndTarget
        return

    try {
        if (action == 1) {
            RegisterNewWindow(hwndTarget)
            if (OverviewController.isOpen)
                SetTimer(() => OverviewController.PushStateToWeb(OverviewController.currentMon), -50)
        } else if (action == 2) {
            PocketManager.RemoveWindow(hwndTarget)
            UnregisterWindow(hwndTarget)
            if (OverviewController.isOpen)
                SetTimer(() => OverviewController.PushStateToWeb(OverviewController.currentMon), -50)
        } else if (action == 4) {
            rootHwnd := GetRootManagedWindow(hwndTarget)
            if (rootHwnd)
                HandleWindowActivation(rootHwnd, false, hwndTarget)
        }
    }
}

OnWinEvent(hHook, event, hwnd, idObject, idChild, dwEventThread, dwmsEventTime) {
    if (!hwnd || idObject != 0 || idChild != 0)
        return

    try {
        if (event == 0x0003) { ; EVENT_SYSTEM_FOREGROUND
            rootHwnd := GetRootManagedWindow(hwnd)
            if (rootHwnd) {
                HandleWindowActivation(rootHwnd, false, hwnd)
            }
        } else if (event == 0x000B) { ; EVENT_SYSTEM_MOVESIZEEND
            OnWindowMoveSizeEnd(hwnd)
            if PocketManager.IsInPocket(hwnd) {
                PocketManager.UpdateBorder(hwnd)
            }
        }
    }
}
