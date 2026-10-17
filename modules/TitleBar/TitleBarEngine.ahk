#Requires AutoHotkey v2.0

class TitleBarEngine {
    static RestoreAll() {
        RestoreAllTitleBars()
    }
}

EnsureTaskbarTopmost() {
    try {
        if trayHwnd := WinExist("ahk_class Shell_TrayWnd")
            DllCall("SetWindowPos", "ptr", trayHwnd, "ptr", -1, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0053)
        for sHwnd in WinGetList("ahk_class Shell_SecondaryTrayWnd")
            DllCall("SetWindowPos", "ptr", sHwnd, "ptr", -1, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0053)
    }
}

GetOrInitTitleBarInfo(hwnd) {
    global titleBarInfo, lastActiveHwnd
    if titleBarInfo.Has(hwnd)
        return titleBarInfo[hwnd]

    eligible := IsEligibleForTitleBarAutoHide(hwnd)
    origStyle := 0
    try origStyle := WinGetStyle("ahk_id " hwnd)

    info := {
        eligible: eligible,
        hidden: false,
        origStyle: origStyle,
        themedActive: -1,
        boundsValid: false,
        bLeft: 0, bTop: 0, bRight: 0, triggerH: 0
    }
    titleBarInfo[hwnd] := info

    if (eligible) {
        darkEnabled := ConfigManager.Get("general.titleBar.darkTheme", true)
        if (darkEnabled) {
            SetDwmAttribute(hwnd, 20, 1)
            SetDwmAttribute(hwnd, 19, 1)
            ApplyTitleBarTheme(hwnd, (hwnd == lastActiveHwnd))
        }
        DllCall("SetProp", "ptr", hwnd, "str", "NonRudeHWND", "ptr", 1)
    }
    return info
}

CheckTitleBarHover() {
    global titleBarVisibleHeight, currentlyShownHwnd, isMovingOrResizing, titleBarInfo, wsWindows
    if (isMovingOrResizing)
        return

    if (!ConfigManager.Get("general.titleBar.autoHide", true))
        return

    static lastMX := -1, lastMY := -1
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mX, &mY, &rawHwnd)
    
    if (mX == lastMX && mY == lastMY)
        return
    lastMX := mX, lastMY := mY

    hoverHwnd := 0
    if rawHwnd {
        root := DllCall("GetAncestor", "ptr", rawHwnd, "uint", 2, "ptr")
        hoverHwnd := root ? root : rawHwnd
    }

    if (currentlyShownHwnd && currentlyShownHwnd != hoverHwnd) {
        if WinExist("ahk_id " currentlyShownHwnd) && titleBarInfo.Has(currentlyShownHwnd) {
            HideTitleBar(currentlyShownHwnd, titleBarInfo[currentlyShownHwnd])
        }
        currentlyShownHwnd := 0
    }

    if (!hoverHwnd || !WinExist("ahk_id " hoverHwnd) || IsWindowCloaked(hoverHwnd))
        return

    if (wsWindows.Has(hoverHwnd) && wsWindows[hoverHwnd].isOffscreen)
        return

    info := GetOrInitTitleBarInfo(hoverHwnd)
    if (!info.eligible)
        return

    style := 0
    try style := WinGetStyle("ahk_id " hoverHwnd)
    catch {
        UnregisterWindow(hoverHwnd)
        return
    }

    if (style & 0x20000000) ; WS_MINIMIZE
        return

    isMax := (style & 0x01000000) ; WS_MAXIMIZE

    if (!info.boundsValid) {
        bLeft := 0, bTop := 0, bRight := 0, triggerH := 0
        try {
            GetWindowHoverBounds(hoverHwnd, isMax, &bLeft, &bTop, &bRight, &triggerH)
            info.bLeft := bLeft, info.bTop := bTop, info.bRight := bRight, info.triggerH := triggerH
            info.boundsValid := true
        } catch {
            return
        }
    }

    activeZoneH := info.hidden ? info.triggerH : Max(info.triggerH, titleBarVisibleHeight)
    isHovering := (mX >= info.bLeft && mX <= info.bRight && mY >= info.bTop && mY <= info.bTop + activeZoneH)

    if (isHovering) {
        if (info.hidden) {
            ShowTitleBar(hoverHwnd, info)
            currentlyShownHwnd := hoverHwnd
        }
    } else {
        if (!info.hidden) {
            HideTitleBar(hoverHwnd, info)
            if (currentlyShownHwnd == hoverHwnd)
                currentlyShownHwnd := 0
        }
    }
}

ApplyTitleBarTheme(hwnd, isActive := true) {
    global titleBarInfo, colorActiveCaption, colorActiveText, colorActiveBorder, colorInactiveCaption, colorInactiveText, colorInactiveBorder
    try {
        if !WinExist("ahk_id " hwnd) || IsWindowCloaked(hwnd)
            return

        darkEnabled := ConfigManager.Get("general.titleBar.darkTheme", true)
        if (!darkEnabled) {
            SetDwmAttribute(hwnd, 35, 0xFFFFFFFF)
            SetDwmAttribute(hwnd, 36, 0xFFFFFFFF)
            SetDwmAttribute(hwnd, 34, 0xFFFFFFFF)
            SetDwmAttribute(hwnd, 20, 0)
            return
        }

        if titleBarInfo.Has(hwnd) {
            if (titleBarInfo[hwnd].HasOwnProp("themedActive") && titleBarInfo[hwnd].themedActive == isActive)
                return
            titleBarInfo[hwnd].themedActive := isActive
        }

        if (isActive) {
            SetDwmAttribute(hwnd, 35, colorActiveCaption)
            SetDwmAttribute(hwnd, 36, colorActiveText)
            SetDwmAttribute(hwnd, 34, colorActiveBorder)
        } else {
            SetDwmAttribute(hwnd, 35, colorInactiveCaption)
            SetDwmAttribute(hwnd, 36, colorInactiveText)
            SetDwmAttribute(hwnd, 34, colorInactiveBorder)
        }
        
        if !GetKeyState("LButton", "P") && !GetKeyState("RButton", "P")
            DllCall("RedrawWindow", "ptr", hwnd, "ptr", 0, "ptr", 0, "uint", 0x0401)
    }
}

GetWindowHoverBounds(hwnd, isMax, &bLeft, &bTop, &bRight, &triggerHeight) {
    global triggerHeightMaximized, triggerHeightFloating
    
    if (isMax) {
        monIdx := GetWindowMonitor(hwnd)
        mLeft := 0, mTop := 0, mRight := 0, mBottom := 0
        if MonitorGetWorkArea(monIdx, &mLeft, &mTop, &mRight, &mBottom) {
            bLeft := mLeft
            bTop := mTop
            bRight := mRight
            triggerHeight := triggerHeightMaximized
            return
        }
    }
    
    WinGetPos(&wX, &wY, &wW, &wH, "ahk_id " hwnd)
    bLeft := wX
    bTop := wY
    bRight := wX + wW
    triggerHeight := triggerHeightFloating
}

IsEligibleForTitleBarAutoHide(hwnd) {
    global Rules
    static rectBuf := Buffer(16, 0), ptBuf := Buffer(8, 0)
    try {
        if !WinExist("ahk_id " hwnd) || !DllCall("IsWindowVisible", "ptr", hwnd) || IsWindowCloaked(hwnd)
            return false

        procName := StrLower(WinGetProcessName("ahk_id " hwnd))
        if Rules.titleBarIgnoreProcesses.Has(procName)
            return false

        winClass := StrLower(WinGetClass("ahk_id " hwnd))
        if Rules.systemClasses.Has(winClass) || Rules.titleBarIgnoreClasses.Has(winClass)
            return false

        if (winClass = "#32770" || winClass = "taskdialog" || InStr(winClass, "dialog"))
            return false

        if (procName != "prismlauncher.exe") {
            if (SubStr(winClass, 1, 2) = "qt" || winClass = "qwidget")
                return false
        }

        owner := DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")
        if (owner != 0)
            return false

        if !IsMainWindow(hwnd)
            return false

        style := WinGetStyle("ahk_id " hwnd)
        exStyle := WinGetExStyle("ahk_id " hwnd)

        if ((style & 0x00C00000) != 0x00C00000)
            return false

        if (exStyle & 0x00000080) || (exStyle & 0x00000001) || (style & 0x40000000)
            return false

        if !(style & 0x00010000) && !(style & 0x00040000)
            return false

        DllCall("GetWindowRect", "ptr", hwnd, "ptr", rectBuf)
        wTop := NumGet(rectBuf, 4, "int")
        
        NumPut("int", 0, ptBuf, 0), NumPut("int", 0, ptBuf, 4)
        DllCall("ClientToScreen", "ptr", hwnd, "ptr", ptBuf)
        cTop := NumGet(ptBuf, 4, "int")
        
        return ((cTop - wTop) >= 16)
    } catch {
        return false
    }
}

HideTitleBar(hwnd, info) {
    global padLeft, padRight, padTop, padBottom
    try {
        if !WinExist("ahk_id " hwnd) || IsWindowCloaked(hwnd)
            return

        style := WinGetStyle("ahk_id " hwnd)
        if (style & 0x00C00000) {
            newStyle := style & ~0x00C00000

            ; WM_SETREDRAW = 11, SMTO_ABORTIFHUNG = 0x0002, 10ms
            DllCall("SendMessageTimeout", "ptr", hwnd, "uint", 11, "ptr", 0, "ptr", 0, "uint", 0x0002, "uint", 10, "ptr*", 0)

            DllCall("SetWindowLongPtr", "ptr", hwnd, "int", -16, "ptr", newStyle)

            style := WinGetStyle("ahk_id " hwnd)
            if (style & 0x01000000) { ; WS_MAXIMIZE
                monIdx := GetWindowMonitor(hwnd)
                mLeft := 0, mTop := 0, mRight := 0, mBottom := 0
                if MonitorGetWorkArea(monIdx, &mLeft, &mTop, &mRight, &mBottom) {
                    DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0
                        , "int", mLeft - padLeft, "int", mTop - padTop
                        , "int", (mRight - mLeft) + padLeft + padRight, "int", (mBottom - mTop) + padTop + padBottom
                        , "uint", 0x0034)
                } else {
                    DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0037)
                }
            } else {
                DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0037)
            }

            DllCall("SendMessageTimeout", "ptr", hwnd, "uint", 11, "ptr", 1, "ptr", 0, "uint", 0x0002, "uint", 10, "ptr*", 0)
            DllCall("user32\RedrawWindow", "ptr", hwnd, "ptr", 0, "ptr", 0, "uint", 0x0485)

            info.hidden := true
            info.boundsValid := false
        }
    }
}

ShowTitleBar(hwnd, info) {
    global padLeft, padRight, padTop, padBottom
    try {
        if !WinExist("ahk_id " hwnd) || IsWindowCloaked(hwnd)
            return

        style := WinGetStyle("ahk_id " hwnd)
        if !(style & 0x00C00000) {
            newStyle := style | 0x00C00000

            DllCall("SendMessageTimeout", "ptr", hwnd, "uint", 11, "ptr", 0, "ptr", 0, "uint", 0x0002, "uint", 10, "ptr*", 0)

            DllCall("SetWindowLongPtr", "ptr", hwnd, "int", -16, "ptr", newStyle)

            style := WinGetStyle("ahk_id " hwnd)
            if (style & 0x01000000) { ; WS_MAXIMIZE
                monIdx := GetWindowMonitor(hwnd)
                mLeft := 0, mTop := 0, mRight := 0, mBottom := 0
                if MonitorGetWorkArea(monIdx, &mLeft, &mTop, &mRight, &mBottom) {
                    bx := 0, by := 0
                    GetWindowFramePadding(hwnd, &bx, &by)
                    DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0
                        , "int", mLeft - bx, "int", mTop - by
                        , "int", (mRight - mLeft) + 2 * bx, "int", (mBottom - mTop) + 2 * by
                        , "uint", 0x0034)
                } else {
                    DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0037)
                }
            } else {
                DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0037)
            }
            
            DllCall("SendMessageTimeout", "ptr", hwnd, "uint", 11, "ptr", 1, "ptr", 0, "uint", 0x0002, "uint", 10, "ptr*", 0)
            DllCall("user32\RedrawWindow", "ptr", hwnd, "ptr", 0, "ptr", 0, "uint", 0x0485)

            info.hidden := false
            info.boundsValid := false
            ApplyTitleBarTheme(hwnd, WinActive("ahk_id " hwnd))
        }
    }
}

RestoreAllTitleBars() {
    global titleBarInfo
    for hwnd, info in titleBarInfo {
        try {
            if WinExist("ahk_id " hwnd) {
                SetDwmAttribute(hwnd, 35, 0xFFFFFFFF)
                SetDwmAttribute(hwnd, 36, 0xFFFFFFFF)
                SetDwmAttribute(hwnd, 34, 0xFFFFFFFF)
                SetDwmAttribute(hwnd, 20, 0)
                
                if (info.hidden) {
                    style := WinGetStyle("ahk_id " hwnd)
                    DllCall("SetWindowLongPtr", "ptr", hwnd, "int", -16, "ptr", style | 0x00C00000)
                    
                    style := WinGetStyle("ahk_id " hwnd)
                    if (style & 0x01000000) { ; WS_MAXIMIZE
                        monIdx := GetWindowMonitor(hwnd)
                        mLeft := 0, mTop := 0, mRight := 0, mBottom := 0
                        if MonitorGetWorkArea(monIdx, &mLeft, &mTop, &mRight, &mBottom) {
                            bx := 0, by := 0
                            GetWindowFramePadding(hwnd, &bx, &by)
                            DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0
                                , "int", mLeft - bx, "int", mTop - by
                                , "int", (mRight - mLeft) + 2 * bx, "int", (mBottom - mTop) + 2 * by
                                , "uint", 0x0034)
                        }
                    }
                }
            }
        }
    }
}
