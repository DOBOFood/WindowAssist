#Requires AutoHotkey v2.0

class WorkspaceManager {
    static dummy() => true
}

InitExistingWindows() {
    global wsWindows
    for hwnd in WinGetList() {
        if IsManagedWindow(hwnd)
            RegisterNewWindow(hwnd)
    }
}

RegisterNewWindow(hwnd) {
    global wsWindows, currentWorkspaces, desktopStates, hasHooksInitialized
    if (!hwnd || !WinExist("ahk_id " hwnd) || wsWindows.Has(hwnd) || !IsManagedWindow(hwnd))
        return

    wx := 0, wy := 0, ww := 0, wh := 0
    try WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
    
    isOff := IsPosOffscreen(wx, wy, ww, wh)

    propWs  := DllCall("GetProp", "ptr", hwnd, "str", "AHK_WS_NUM", "ptr")
    propMon := DllCall("GetProp", "ptr", hwnd, "str", "AHK_WS_MON", "ptr")

    if (isOff) {
        wMon := (propMon > 0) ? propMon : GetWindowMonitor(hwnd)
        assignedWs := (propWs > 0) ? propWs : 2
        
        savedX := DllCall("GetProp", "ptr", hwnd, "str", "AHK_WS_X", "int")
        savedY := DllCall("GetProp", "ptr", hwnd, "str", "AHK_WS_Y", "int")
        savedW := DllCall("GetProp", "ptr", hwnd, "str", "AHK_WS_W", "int")
        savedH := DllCall("GetProp", "ptr", hwnd, "str", "AHK_WS_H", "int")
        savedMax := DllCall("GetProp", "ptr", hwnd, "str", "AHK_WS_MAX", "int")

        curWs := currentWorkspaces[wMon]
        shouldBeOff := (assignedWs != curWs)

        info := {
            mon: wMon,
            ws: assignedWs,
            isOffscreen: shouldBeOff,
            x: (savedW > 0 ? savedX : 100),
            y: (savedH > 0 ? savedY : 100),
            w: (savedW > 0 ? savedW : 800),
            h: (savedH > 0 ? savedH : 600),
            isMax: (savedMax == 1)
        }
        wsWindows[hwnd] := info
        SaveWindowProps(hwnd, info)
        GetOrInitTitleBarInfo(hwnd)

        if (!shouldBeOff)
            SetWindowVisibility(hwnd, true)
        return
    }

    wMon := (propMon > 0) ? propMon : GetWindowMonitor(hwnd)
    assignedWs := (propWs > 0) ? propWs : currentWorkspaces[wMon]

    if IsAppGrouped(hwnd) {
        targetPid := 0
        try targetPid := WinGetPID("ahk_id " hwnd)
        if (targetPid) {
            for existHwnd, existInfo in wsWindows {
                if (existHwnd != hwnd && WinExist("ahk_id " existHwnd)) {
                    try {
                        if (WinGetPID("ahk_id " existHwnd) == targetPid) {
                            wMon := existInfo.mon
                            assignedWs := existInfo.ws
                            break
                        }
                    }
                }
            }
        }
    }

    ; Restore workspace binding from state.json if launching without cached window properties
    if (propWs <= 0 && !hasHooksInitialized && FileExist(A_ScriptDir "\state.json")) {
        try {
            rawState := FileRead(A_ScriptDir "\state.json", "UTF-8")
            sObj := JSON.Load(rawState)
            if (sObj is Map && sObj.Has("windows") && sObj["windows"] is Array) {
                curProc := StrLower(WinGetProcessName("ahk_id " hwnd))
                curClass := StrLower(WinGetClass("ahk_id " hwnd))
                for sItem in sObj["windows"] {
                    if !(sItem is Map)
                        continue
                    if (sItem.Has("process") && StrLower(sItem["process"]) == curProc) {
                        if (!sItem.Has("class") || sItem["class"] == "" || StrLower(sItem["class"]) == curClass) {
                            if sItem.Has("mon")
                                wMon := Integer(sItem["mon"])
                            if sItem.Has("ws")
                                assignedWs := Integer(sItem["ws"])
                            break
                        }
                    }
                }
            }
        }
    }

    curWs := currentWorkspaces[wMon]
    shouldBeOff := (assignedWs != curWs)
    isMax := false
    try {
        style := WinGetStyle("ahk_id " hwnd)
        isMax := (style & 0x01000000) ; WS_MAXIMIZE
    }

    info := {
        mon: wMon,
        ws: assignedWs,
        isOffscreen: shouldBeOff,
        x: wx, y: wy, w: ww, h: wh,
        isMax: isMax
    }
    wsWindows[hwnd] := info
    SaveWindowProps(hwnd, info)
    GetOrInitTitleBarInfo(hwnd)

    if (shouldBeOff) {
        SetWindowVisibility(hwnd, false)
    } else {
        stateKey := wMon "_" curWs
        if (desktopStates.Has(stateKey) && desktopStates[stateKey])
            AlignWindowToDesktopState(hwnd, false)
    }
}

UnregisterWindow(hwnd) {
    global wsWindows, titleBarInfo, currentlyShownHwnd, lastActiveHwnd, currentWorkspaces
    
    closingMon := 0
    closingWs := 0
    if wsWindows.Has(hwnd) {
        closingMon := wsWindows[hwnd].mon
        closingWs := wsWindows[hwnd].ws
    }

    CrossWorkspaceAltTab.RemoveWindow(hwnd)
    
    RemoveWindowProps(hwnd)
    if wsWindows.Has(hwnd)
        wsWindows.Delete(hwnd)
    if titleBarInfo.Has(hwnd)
        titleBarInfo.Delete(hwnd)
    if (currentlyShownHwnd == hwnd)
        currentlyShownHwnd := 0
    if (lastActiveHwnd == hwnd)
        lastActiveHwnd := 0

    ; Keep focus confined to the active workspace on this monitor instead of leaking to background desktops
    if (closingMon && currentWorkspaces.Has(closingMon) && currentWorkspaces[closingMon] == closingWs) {
        SetTimer(() => ActivateTopWindowOnWorkspace(closingMon, closingWs), -20)
    }
}

OnWindowMoveSizeEnd(hwnd) {
    global wsWindows, currentWorkspaces, titleBarInfo, isMovingOrResizing
    if (isMovingOrResizing || !hwnd || !WinExist("ahk_id " hwnd))
        return

    rootHwnd := GetRootManagedWindow(hwnd)
    if (!rootHwnd || !wsWindows.Has(rootHwnd))
        return

    info := wsWindows[rootHwnd]
    if (info.isOffscreen)
        return

    wx := 0, wy := 0, ww := 0, wh := 0
    try WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " rootHwnd)
    if IsPosOffscreen(wx, wy, ww, wh)
        return

    wMon := GetWindowMonitor(rootHwnd)
    if (info.mon != wMon) {
        info.mon := wMon
        info.ws := currentWorkspaces[wMon]
        if IsAppGrouped(rootHwnd)
            SyncAppWindowsLocation(rootHwnd, wMon, info.ws)
        CrossWorkspaceAltTab.RecordActiveWindow(rootHwnd)
        if (OverviewController.isOpen)
            SetTimer(() => OverviewController.PushStateToWeb(OverviewController.currentMon), -50)
    }

    try {
        style := WinGetStyle("ahk_id " rootHwnd)
        info.isMax := (style & 0x01000000) ; WS_MAXIMIZE
    }
    info.x := wx
    info.y := wy
    if (!info.isMax && !IsGameOrExclusiveWindow(rootHwnd)) {
        info.w := ww
        info.h := wh
    }

    SaveWindowProps(rootHwnd, info)
    SetTimer(() => SaveState(), -300)

    if titleBarInfo.Has(rootHwnd)
        titleBarInfo[rootHwnd].boundsValid := false
}

GetRootManagedWindow(hwnd) {
    global wsWindows
    if (!hwnd || !WinExist("ahk_id " hwnd))
        return 0
    if wsWindows.Has(hwnd)
        return hwnd

    try {
        rootOwner := DllCall("GetAncestor", "ptr", hwnd, "uint", 3, "ptr")
        if (rootOwner && (wsWindows.Has(rootOwner) || IsManagedWindow(rootOwner)))
            return rootOwner

        root := DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr")
        if (root && (wsWindows.Has(root) || IsManagedWindow(root)))
            return root

        cur := hwnd
        Loop 8 {
            owner := DllCall("GetWindow", "ptr", cur, "uint", 4, "ptr")
            if (!owner)
                break
            if wsWindows.Has(owner) || IsManagedWindow(owner)
                return owner
            cur := owner
        }
    }

    return IsManagedWindow(hwnd) ? hwnd : 0
}

IsWindowOrChildOf(childHwnd, rootHwnd) {
    global wsWindows
    if (!childHwnd || !rootHwnd)
        return false
    if (childHwnd == rootHwnd)
        return true

    try {
        if (DllCall("GetAncestor", "ptr", childHwnd, "uint", 3, "ptr") == rootHwnd)
            return true
        if (DllCall("GetAncestor", "ptr", childHwnd, "uint", 2, "ptr") == rootHwnd)
            return true

        childPid := WinGetPID("ahk_id " childHwnd)
        rootPid  := WinGetPID("ahk_id " rootHwnd)
        if (childPid != rootPid)
            return false

        cur := childHwnd
        Loop 8 {
            owner := DllCall("GetWindow", "ptr", cur, "uint", 4, "ptr")
            if (!owner)
                break
            if (owner == rootHwnd)
                return true
            cur := owner
        }
    }
    return false
}

GetTopActiveWindow(rootHwnd) {
    global wsWindows
    if (!rootHwnd || !WinExist("ahk_id " rootHwnd))
        return 0
    try {
        popup := DllCall("GetLastActivePopup", "ptr", rootHwnd, "ptr")
        if (popup && popup != rootHwnd && WinExist("ahk_id " popup) && DllCall("IsWindowVisible", "ptr", popup) && !IsWindowCloaked(popup))
            return popup
    }
    return rootHwnd
}

IsTaskbarActivation() {
    global lastTaskbarClickTime
    if (lastTaskbarClickTime > 0 && (A_TickCount - lastTaskbarClickTime < 750))
        return true

    CoordMode("Mouse", "Screen")
    MouseGetPos(&mX, &mY, &mHwnd)
    if (mHwnd && IsTaskbarOrPreviewHwnd(mHwnd, mX, mY)) {
        if GetKeyState("LButton", "P")
            return true
    }

    return false
}

IsTaskbarOrPreviewHwnd(hwnd, mX := 0, mY := 0) {
    global wsWindows
    if !hwnd || !WinExist("ahk_id " hwnd)
        return false

    rootHwnd := DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr")
    rootHwnd := rootHwnd ? rootHwnd : hwnd

    rootClass := ""
    try rootClass := StrLower(WinGetClass("ahk_id " rootHwnd))
    childClass := ""
    try childClass := StrLower(WinGetClass("ahk_id " hwnd))

    if (rootClass = "shell_traywnd" || rootClass = "shell_secondarytraywnd")
        return true

    if InStr(",shell_traywnd,shell_secondarytraywnd,mstasklistwclass,tasklistuiwnd,tasklistthumbnailwnd,traynotifywnd,windows.ui.composition.desktopwindowtarget,xamlexplorerhostislandwindow,toplevelwindowforoverflowxamlisland,multitaskingviewframe,taskswitcherwnd,", "," childClass ",")
        return true

    if InStr(",tasklistthumbnailwnd,mstasklistwclass,multitaskingviewframe,taskswitcherwnd,", "," rootClass ",")
        return true

    procName := ""
    try procName := StrLower(WinGetProcessName("ahk_id " hwnd))
    if (procName = "explorer.exe") {
        if (rootClass != "progman" && rootClass != "workerw" && rootClass != "cabinetwclass")
            return true
    }

    if (mX || mY) {
        if IsPointInTaskbar(mX, mY)
            return true
    }

    return false
}

IsPointInTaskbar(x, y) {
    try {
        tHwnds := [WinExist("ahk_class Shell_TrayWnd")]
        for sHwnd in WinGetList("ahk_class Shell_SecondaryTrayWnd")
            tHwnds.Push(sHwnd)

        for h in tHwnds {
            if (!h)
                continue
            wx := 0, wy := 0, ww := 0, wh := 0
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " h)
            if (x >= wx && x <= wx + ww && y >= wy && y <= wy + wh)
                return true
        }
    }
    return false
}

HandleWindowActivation(rootHwnd, isCreated := false, originalHwnd := 0) {
    global isSwitchingWorkspace, wsWindows, currentWorkspaces, lastTaskbarClickTime, lastActiveHwnd, titleBarInfo
    if (isSwitchingWorkspace || !rootHwnd || !WinExist("ahk_id " rootHwnd))
        return

    if !wsWindows.Has(rootHwnd) {
        RegisterNewWindow(rootHwnd)
        return
    }

    if (isCreated)
        return

    ; Pocket scratchpad windows belong to ws=0 and must never trigger desktop switches
    if (PocketManager.IsInPocket(rootHwnd)) {
        PocketManager.ApplyLayerHierarchy()
        return
    }

    info := wsWindows[rootHwnd]

    actualMon := GetWindowMonitor(rootHwnd)
    if (info.mon != actualMon && !info.isOffscreen) {
        info.mon := actualMon
        info.ws := currentWorkspaces[actualMon]
        SaveWindowProps(rootHwnd, info)
        if IsAppGrouped(rootHwnd)
            SyncAppWindowsLocation(rootHwnd, actualMon, info.ws)
        CrossWorkspaceAltTab.RecordActiveWindow(rootHwnd)
        if (OverviewController.isOpen)
            SetTimer(() => OverviewController.PushStateToWeb(OverviewController.currentMon), -50)
    }

    targetMon := info.mon
    targetWs  := info.ws
    curWs     := currentWorkspaces[targetMon]

    isTaskbarClick := IsTaskbarActivation()

    if (curWs != targetWs) {
        if (!isTaskbarClick) {
            if !ActivateTopWindowOnWorkspace(targetMon, curWs)
                SafeDesktopFocus()
            return
        }
        lastTaskbarClickTime := 0
        targetToActivate := (originalHwnd && WinExist("ahk_id " originalHwnd)) ? originalHwnd : rootHwnd
        CrossWorkspaceAltTab.RecordActiveWindow(targetToActivate)
        SwitchWorkspace(targetMon, targetWs, targetToActivate)
        return
    }

    lastTaskbarClickTime := 0

    if (isTaskbarClick) {
        try {
            style := WinGetStyle("ahk_id " rootHwnd)
            if (style & 0x20000000) { ; WS_MINIMIZE
                if (info.isMax)
                    DllCall("ShowWindowAsync", "ptr", rootHwnd, "int", 3) ; SW_MAXIMIZE
                else
                    DllCall("ShowWindowAsync", "ptr", rootHwnd, "int", 9) ; SW_RESTORE
            }
        }
        if (info.isOffscreen) {
            SetWindowVisibility(rootHwnd, true)
            info.isOffscreen := false
        }
        ShowOSD(targetWs)
    } else {
        style := WinGetStyle("ahk_id " rootHwnd)
        if (style & 0x20000000) ; WS_MINIMIZE
            return
    }

    if IsAppGrouped(rootHwnd)
        SyncAppWindowsLocation(rootHwnd, targetMon, targetWs)

    if (rootHwnd != lastActiveHwnd) {
        if (lastActiveHwnd && WinExist("ahk_id " lastActiveHwnd) && !IsWindowCloaked(lastActiveHwnd)) {
            if titleBarInfo.Has(lastActiveHwnd) && titleBarInfo[lastActiveHwnd].eligible
                ApplyTitleBarTheme(lastActiveHwnd, false)
        }
        tbInfo := GetOrInitTitleBarInfo(rootHwnd)
        if (tbInfo.eligible)
            ApplyTitleBarTheme(rootHwnd, true)
        lastActiveHwnd := rootHwnd
    }

    fg := DllCall("GetForegroundWindow", "ptr")
    if (fg && IsWindowOrChildOf(fg, rootHwnd)) {
        if (isTaskbarClick && DllCall("GetForegroundWindow", "ptr") != fg)
            ForceActivateWindow(fg)
        if (PocketManager.GetVisiblePocketWindow())
            PocketManager.ApplyLayerHierarchy()
        return
    }

    targetToActivate := 0
    if (originalHwnd && WinExist("ahk_id " originalHwnd) && IsWindowOrChildOf(originalHwnd, rootHwnd)) {
        targetToActivate := originalHwnd
    } else {
        targetToActivate := GetTopActiveWindow(rootHwnd)
    }

    if (fg != targetToActivate) {
        ForceActivateWindow(targetToActivate)
    }

    if (PocketManager.GetVisiblePocketWindow())
        PocketManager.ApplyLayerHierarchy()
}

GetOffscreenCoords(hwnd, mon) {
    global wsWindows
    mL := 0, mT := 0, mR := 0, mB := 0
    if !MonitorGet(mon, &mL, &mT, &mR, &mB)
        MonitorGet(1, &mL, &mT, &mR, &mB)

    wx := 0, wy := 0, ww := 0, wh := 0
    try WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
    ww := (ww > 0) ? ww : 800
    
    safeY := (wy >= mT && wy < mB) ? wy : mT + 100

    if (mon == 1)
        offX := mL - ww - 300
    else
        offX := mR + 300

    return {x: offX, y: safeY}
}

IsPosOffscreen(x, y, w, h) {
    monCount := MonitorGetCount()
    Loop monCount {
        mL := 0, mT := 0, mR := 0, mB := 0
        MonitorGet(A_Index, &mL, &mT, &mR, &mB)
        if (x + w > mL + 10 && x < mR - 10 && y + h > mT + 10 && y < mB - 10)
            return false
    }
    return true
}

SetWindowVisibility(hwnd, isVisible) {
    global wsWindows
    try {
        if !hwnd || !WinExist("ahk_id " hwnd)
            return

        if (!isVisible) {
            if (!IsGameOrExclusiveWindow(hwnd))
                WinSetAlwaysOnTop(false, "ahk_id " hwnd)

            wMon := 1
            if wsWindows.Has(hwnd) {
                wx := 0, wy := 0, ww := 0, wh := 0
                WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
                if !IsPosOffscreen(wx, wy, ww, wh) {
                    style := WinGetStyle("ahk_id " hwnd)
                    isMax := (style & 0x01000000) ; WS_MAXIMIZE
                    wsWindows[hwnd].isMax := isMax
                    wsWindows[hwnd].x := wx
                    wsWindows[hwnd].y := wy
                    if (!isMax) {
                        wsWindows[hwnd].w := ww
                        wsWindows[hwnd].h := wh
                    }
                    SaveWindowProps(hwnd, wsWindows[hwnd])
                }
                wMon := wsWindows[hwnd].mon
            } else {
                wMon := GetWindowMonitor(hwnd)
            }

            off := GetOffscreenCoords(hwnd, wMon)
            DllCall("user32\SetWindowPos", "ptr", hwnd, "ptr", 0
                , "int", off.x, "int", off.y, "int", 0, "int", 0
                , "uint", 0x4015)
        } else {
            if !wsWindows.Has(hwnd)
                return

            info := wsWindows[hwnd]
            if (info.isMax || IsGameOrExclusiveWindow(hwnd)) {
                targetX := info.HasOwnProp("x") ? info.x : 0
                targetY := info.HasOwnProp("y") ? info.y : 0
                DllCall("user32\SetWindowPos", "ptr", hwnd, "ptr", 0
                    , "int", targetX, "int", targetY, "int", 0, "int", 0
                    , "uint", 0x4015)
            } else {
                targetX := info.HasOwnProp("x") ? info.x : 100
                targetY := info.HasOwnProp("y") ? info.y : 100
                targetW := info.HasOwnProp("w") ? info.w : 800
                targetH := info.HasOwnProp("h") ? info.h : 600
                DllCall("user32\SetWindowPos", "ptr", hwnd, "ptr", 0
                    , "int", targetX, "int", targetY, "int", targetW, "int", targetH
                    , "uint", 0x4014)
            }
        }
    }
}

GetCurrentTargetMonitor() {
    global wsWindows
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mX, &mY)
    
    monCount := MonitorGetCount()
    Loop monCount {
        mL := 0, mT := 0, mR := 0, mB := 0
        MonitorGet(A_Index, &mL, &mT, &mR, &mB)
        if (mX >= mL && mX < mR && mY >= mT && mY < mB)
            return A_Index
    }

    activeHwnd := 0
    try activeHwnd := WinGetID("A")
    if (activeHwnd && wsWindows.Has(activeHwnd) && !wsWindows[activeHwnd].isOffscreen)
        return GetWindowMonitor(activeHwnd)

    return 1
}

GetWindowMonitor(hwnd) {
    global wsWindows
    if !hwnd || !WinExist("ahk_id " hwnd)
        return 1
    
    if (wsWindows.Has(hwnd) && wsWindows[hwnd].isOffscreen)
        return wsWindows[hwnd].mon

    wx := 0, wy := 0, ww := 0, wh := 0
    try WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
    
    if IsPosOffscreen(wx, wy, ww, wh) {
        propMon := DllCall("GetProp", "ptr", hwnd, "str", "AHK_WS_MON", "ptr")
        if (propMon > 0)
            return propMon
        monCount := MonitorGetCount()
        Loop monCount {
            mL := 0, mT := 0, mR := 0, mB := 0
            MonitorGet(A_Index, &mL, &mT, &mR, &mB)
            if (wy >= mT && wy < mB)
                return A_Index
        }
        return wsWindows.Has(hwnd) ? wsWindows[hwnd].mon : 1
    }
    
    cx := wx + (ww > 0 ? ww / 2 : 10)
    cy := wy + (wh > 0 ? wh / 2 : 10)
    
    monCount := MonitorGetCount()
    Loop monCount {
        mL := 0, mT := 0, mR := 0, mB := 0
        MonitorGet(A_Index, &mL, &mT, &mR, &mB)
        if (cx >= mL && cx < mR && cy >= mT && cy < mB)
            return A_Index
    }

    propMon := DllCall("GetProp", "ptr", hwnd, "str", "AHK_WS_MON", "ptr")
    if (propMon > 0)
        return propMon

    return 1
}

SwitchWorkspace(targetMon, targetWs, preferredHwnd := 0) {
    global isSwitchingWorkspace, lastSwitchTime, maxWorkspacesPerMon, currentWorkspaces, wsWindows, desktopStates
    isSwitchingWorkspace := true
    lastSwitchTime := A_TickCount
    ReleaseCursorClip()

    maxWs := maxWorkspacesPerMon.Has(targetMon) ? maxWorkspacesPerMon[targetMon] : 6
    if (targetWs < 1 || targetWs > maxWs) {
        isSwitchingWorkspace := false
        return
    }

    if (OverviewController.isOpen && OverviewController.currentMon != targetMon)
        OverviewController.MoveToMonitor(targetMon)

    oldWs := currentWorkspaces[targetMon]
    if (oldWs == targetWs) {
        if (preferredHwnd && WinExist("ahk_id " preferredHwnd)) {
            if (wsWindows.Has(preferredHwnd) && wsWindows[preferredHwnd].isOffscreen) {
                SetWindowVisibility(preferredHwnd, true)
                wsWindows[preferredHwnd].isOffscreen := false
            }
            target := GetTopActiveWindow(preferredHwnd)
            ForceActivateWindow(target)
        }
        ShowOSD(targetWs)
        PocketManager.ApplyLayerHierarchy()
        isSwitchingWorkspace := false
        return
    }

    currentWorkspaces[targetMon] := targetWs

    activeHwnd := 0
    try activeHwnd := WinGetID("A")
    if (activeHwnd && wsWindows.Has(activeHwnd)) {
        if (wsWindows[activeHwnd].mon == targetMon && wsWindows[activeHwnd].ws == oldWs)
            SafeDesktopFocus()
    }
    
    try {
        for hwnd, info in wsWindows {
            if (PocketManager.IsInPocket(hwnd))
                continue

            if (info.mon == targetMon && info.ws == oldWs && !info.isOffscreen && WinExist("ahk_id " hwnd)) {
                SetWindowVisibility(hwnd, false)
                info.isOffscreen := true
            }
        }

        for hwnd, info in wsWindows {
            if (PocketManager.IsInPocket(hwnd))
                continue

            if (info.mon == targetMon && info.ws == targetWs && info.isOffscreen && WinExist("ahk_id " hwnd)) {
                SetWindowVisibility(hwnd, true)
                info.isOffscreen := false
            }
        }

        PocketManager.OnWorkspaceSwitched(targetMon, targetWs)

        stateKey := targetMon "_" targetWs
        if (desktopStates.Has(stateKey) && desktopStates[stateKey]) {
            for hwnd in WinGetList()
                AlignWindowToDesktopState(hwnd, false)
        }

        if (preferredHwnd && WinExist("ahk_id " preferredHwnd)) {
            try {
                style := WinGetStyle("ahk_id " preferredHwnd)
                if (style & 0x20000000) { ; WS_MINIMIZE
                    rootH := GetRootManagedWindow(preferredHwnd)
                    isMax := (rootH && wsWindows.Has(rootH)) ? wsWindows[rootH].isMax : false
                    if (isMax)
                        DllCall("ShowWindowAsync", "ptr", preferredHwnd, "int", 3) ; SW_MAXIMIZE
                    else
                        DllCall("ShowWindowAsync", "ptr", preferredHwnd, "int", 9) ; SW_RESTORE
                }
            }
            target := GetTopActiveWindow(preferredHwnd)
            if (!OverviewController.isOpen)
                ForceActivateWindow(target)
        } else if !OverviewController.isOpen && !ActivateTopWindowOnWorkspace(targetMon, targetWs) {
            SafeDesktopFocus()
        }

        PocketManager.ApplyLayerHierarchy()
    }

    ShowOSD(targetWs)
    PocketManager.ApplyLayerHierarchy()

    lastSwitchTime := A_TickCount
    isSwitchingWorkspace := false
    if (OverviewController.isOpen) {
        OverviewController.EnsureTopmost()
        OverviewController.PushStateToWeb(targetMon)
    }

    SetTimer(() => SaveState(), -200)
}

SwitchWorkspaceDelta(delta) {
    global maxWorkspacesPerMon, currentWorkspaces
    monIdx := GetCurrentTargetMonitor()
    curWs  := currentWorkspaces[monIdx]
    maxWs  := maxWorkspacesPerMon.Has(monIdx) ? maxWorkspacesPerMon[monIdx] : 6
    newWs  := curWs + delta
    
    if (newWs >= 1 && newWs <= maxWs)
        SwitchWorkspace(monIdx, newWs)
}

IsAppGrouped(hwnd) {
    global Rules
    try {
        if !hwnd || !WinExist("ahk_id " hwnd)
            return false
        pName := StrLower(WinGetProcessName("ahk_id " hwnd))
        return Rules.groupedProcesses.Has(pName)
    }
    return false
}

GetAppWindows(hwnd) {
    global Rules
    appWindows := []
    try {
        targetPid := WinGetPID("ahk_id " hwnd)
        if !targetPid
            return [hwnd]

        for h in WinGetList() {
            try {
                if (WinGetPID("ahk_id " h) != targetPid)
                    continue
                if !DllCall("IsWindowVisible", "ptr", h)
                    continue
                winClass := StrLower(WinGetClass("ahk_id " h))
                if Rules.systemClasses.Has(winClass)
                    continue
                if (WinGetTitle("ahk_id " h) == "")
                    continue

                appWindows.Push(h)
            }
        }
    } catch {
        return [hwnd]
    }
    return appWindows.Length ? appWindows : [hwnd]
}

SyncAppWindowsLocation(masterHwnd, targetMon, targetWs) {
    global wsWindows, currentWorkspaces
    try {
        targetPid := WinGetPID("ahk_id " masterHwnd)
        if !targetPid
            return

        curWs := currentWorkspaces[targetMon]

        for h in GetAppWindows(masterHwnd) {
            if (h == masterHwnd)
                continue

            if !wsWindows.Has(h) {
                wx := 0, wy := 0, ww := 0, wh := 0
                try WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " h)
                isMax := false
                try {
                    style := WinGetStyle("ahk_id " h)
                    isMax := (style & 0x01000000) ; WS_MAXIMIZE
                }
                info := {
                    mon: targetMon,
                    ws: targetWs,
                    isOffscreen: (targetWs != curWs),
                    x: wx, y: wy, w: ww, h: wh,
                    isMax: isMax
                }
                wsWindows[h] := info
                SaveWindowProps(h, info)
                if (targetWs != curWs)
                    SetWindowVisibility(h, false)
            } else {
                info := wsWindows[h]
                info.mon := targetMon
                info.ws := targetWs
                SaveWindowProps(h, info)

                if (targetWs != curWs) {
                    if (!info.isOffscreen) {
                        SetWindowVisibility(h, false)
                        info.isOffscreen := true
                    }
                } else {
                    if (info.isOffscreen) {
                        SetWindowVisibility(h, true)
                        info.isOffscreen := false
                    }
                }
            }
        }
    }
}

global pendingMove := {
    hwnd: 0,
    targetWs: 0,
    monIdx: 0,
    borderGui: 0,
    animStep: 0,
    timerFn: 0
}

StartPendingMove() {
    global pendingMove
    if (pendingMove.hwnd && WinExist("ahk_id " pendingMove.hwnd)) {
        if (!pendingMove.borderGui)
            StartWindowSelectionAnimation(pendingMove.hwnd)
        return
    }

    activeHwnd := WinExist("A")
    if (!activeHwnd || !IsManagedWindow(activeHwnd))
        return

    pendingMove.hwnd := activeHwnd
    pendingMove.monIdx := GetWindowMonitor(activeHwnd)
    StartWindowSelectionAnimation(activeHwnd)
}

MoveActiveWindowAndFollow(targetWs) {
    global pendingMove, maxWorkspacesPerMon, currentWorkspaces, wsWindows
    ReleaseCursorClip()

    if (!pendingMove.hwnd || !WinExist("ahk_id " pendingMove.hwnd)) {
        activeHwnd := WinExist("A")
        if (!activeHwnd || !IsManagedWindow(activeHwnd))
            return
        pendingMove.hwnd := activeHwnd
        pendingMove.monIdx := GetWindowMonitor(activeHwnd)
    }

    targetHwnd := pendingMove.hwnd
    monIdx     := pendingMove.monIdx ? pendingMove.monIdx : GetWindowMonitor(targetHwnd)
    maxWs      := maxWorkspacesPerMon.Has(monIdx) ? maxWorkspacesPerMon[monIdx] : 6
    if (targetWs < 1 || targetWs > maxWs)
        return

    curWs := currentWorkspaces[monIdx]

    windowsToMove := IsAppGrouped(targetHwnd) ? GetAppWindows(targetHwnd) : [targetHwnd]
    for h in windowsToMove {
        if !wsWindows.Has(h) {
            RegisterNewWindow(h)
        }
        if wsWindows.Has(h) {
            wsWindows[h].mon := monIdx
            wsWindows[h].ws := targetWs
            wsWindows[h].isOffscreen := false
            SaveWindowProps(h, wsWindows[h])
        }
    }

    SwitchWorkspace(monIdx, targetWs, targetHwnd)

    if (HotkeyManager.AreMovePrefixKeysPressed()) {
        StartWindowSelectionAnimation(targetHwnd)
    } else {
        EndPendingMove()
    }
}

MoveActiveWindowDeltaAndFollow(delta) {
    global currentWorkspaces, maxWorkspacesPerMon, pendingMove
    monIdx := pendingMove.monIdx ? pendingMove.monIdx : GetCurrentTargetMonitor()
    curWs  := currentWorkspaces[monIdx]
    maxWs  := maxWorkspacesPerMon.Has(monIdx) ? maxWorkspacesPerMon[monIdx] : 6
    newWs  := curWs + delta
    if (newWs >= 1 && newWs <= maxWs)
        MoveActiveWindowAndFollow(newWs)
}

EndPendingMove() {
    global pendingMove
    StopWindowSelectionAnimation()
    pendingMove.hwnd := 0
    pendingMove.targetWs := 0
    pendingMove.monIdx := 0
}

CancelPendingMove() {
    EndPendingMove()
}

MoveWindowToWorkspace(activeHwnd, targetWs) {
    global wsWindows, currentWorkspaces, isSwitchingWorkspace, maxWorkspacesPerMon
    ReleaseCursorClip()
    
    if !activeHwnd || !WinExist("ahk_id " activeHwnd) || !IsManagedWindow(activeHwnd)
        return

    monIdx := GetWindowMonitor(activeHwnd)
    maxWs  := maxWorkspacesPerMon.Has(monIdx) ? maxWorkspacesPerMon[monIdx] : 6
    if (targetWs < 1 || targetWs > maxWs)
        return

    curWs := currentWorkspaces[monIdx]
    if (targetWs == curWs)
        return

    isSwitchingWorkspace := true
    try {
        windowsToMove := IsAppGrouped(activeHwnd) ? GetAppWindows(activeHwnd) : [activeHwnd]

        for h in windowsToMove {
            if !wsWindows.Has(h) {
                wx := 0, wy := 0, ww := 0, wh := 0
                try WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " h)
                isMax := false
                try {
                    style := WinGetStyle("ahk_id " h)
                    isMax := (style & 0x01000000) ; WS_MAXIMIZE
                }
                wsWindows[h] := {
                    mon: monIdx,
                    ws: targetWs,
                    isOffscreen: false,
                    x: wx, y: wy, w: ww, h: wh,
                    isMax: isMax
                }
            }

            info := wsWindows[h]
            info.mon := monIdx
            info.ws := targetWs
            SaveWindowProps(h, info)
            
            SetWindowVisibility(h, false)
            info.isOffscreen := true
        }

        SafeDesktopFocus()
        if !ActivateTopWindowOnWorkspace(monIdx, curWs)
            SafeDesktopFocus()
    } finally {
        isSwitchingWorkspace := false
    }
}

MoveActiveWindowTo(targetWs) {
    activeHwnd := WinExist("A")
    if (activeHwnd)
        MoveWindowToWorkspace(activeHwnd, targetWs)
}

StartWindowSelectionAnimation(hwnd) {
    global pendingMove
    try {
        if (!hwnd || !WinExist("ahk_id " hwnd)) {
            StopWindowSelectionAnimation()
            return
        }

        rectBuf := Buffer(16, 0)
        ; DWMWA_EXTENDED_FRAME_BOUNDS = 9
        hr := DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 9, "ptr", rectBuf, "uint", 16)
        if (hr == 0) {
            wx := NumGet(rectBuf, 0, "int")
            wy := NumGet(rectBuf, 4, "int")
            ww := NumGet(rectBuf, 8, "int") - wx
            wh := NumGet(rectBuf, 12, "int") - wy
        } else {
            wx := 0, wy := 0, ww := 0, wh := 0
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
        }

        if (ww <= 0 || wh <= 0) {
            StopWindowSelectionAnimation()
            return
        }

        bw := Integer(ConfigManager.Get("appearance.colors.windowDragPulseWidth", 3))
        pulseColor := StrReplace(ConfigManager.Get("appearance.colors.windowDragPulse", "0078D7"), "#", "")
        if (pulseColor == "")
            pulseColor := "0078D7"

        g := pendingMove.borderGui
        if (!g || !WinExist("ahk_id " g.Hwnd)) {
            StopWindowSelectionAnimation()
            g := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20 +E0x08000000")
            g.BackColor := pulseColor
            pendingMove.borderGui := g
        } else {
            g.BackColor := pulseColor
        }
        
        hRgnOuter := DllCall("gdi32\CreateRectRgn", "int", 0, "int", 0, "int", ww, "int", wh, "ptr")
        hRgnInner := DllCall("gdi32\CreateRectRgn", "int", bw, "int", bw, "int", ww - bw, "int", wh - bw, "ptr")
        hRgnDiff  := DllCall("gdi32\CreateRectRgn", "int", 0, "int", 0, "int", 0, "int", 0, "ptr")
        DllCall("gdi32\CombineRgn", "ptr", hRgnDiff, "ptr", hRgnOuter, "ptr", hRgnInner, "int", 4)
        DllCall("user32\SetWindowRgn", "ptr", g.Hwnd, "ptr", hRgnDiff, "int", 1)
        DllCall("gdi32\DeleteObject", "ptr", hRgnOuter)
        DllCall("gdi32\DeleteObject", "ptr", hRgnInner)

        g.Show("x" wx " y" wy " w" ww " h" wh " NoActivate")

        if (!pendingMove.timerFn) {
            pendingMove.animStep := 0
            pulseFn := () => AnimateBorderPulse()
            pendingMove.timerFn := pulseFn
            SetTimer(pulseFn, 40)
        }
    }
}

AnimateBorderPulse() {
    global pendingMove
    if (!pendingMove.borderGui)
        return

    if (!HotkeyManager.AreMovePrefixKeysPressed() || !pendingMove.hwnd || !WinExist("ahk_id " pendingMove.hwnd)) {
        EndPendingMove()
        return
    }

    pendingMove.animStep += 1
    alpha := Round(175 + 75 * Sin(pendingMove.animStep * 0.25))
    try WinSetTransparent(alpha, "ahk_id " pendingMove.borderGui.Hwnd)
}

StopWindowSelectionAnimation() {
    global pendingMove
    if (pendingMove.timerFn) {
        SetTimer(pendingMove.timerFn, 0)
        pendingMove.timerFn := 0
    }
    if (pendingMove.borderGui) {
        try {
            pendingMove.borderGui.Destroy()
        }
        pendingMove.borderGui := 0
    }
}

MoveActiveWindowDelta(delta) {
    global wsWindows, currentWorkspaces, maxWorkspacesPerMon
    activeHwnd := WinExist("A")
    if !activeHwnd || !IsManagedWindow(activeHwnd)
        return

    monIdx := GetWindowMonitor(activeHwnd)
    curWs  := wsWindows.Has(activeHwnd) ? wsWindows[activeHwnd].ws : currentWorkspaces[monIdx]
    maxWs  := maxWorkspacesPerMon.Has(monIdx) ? maxWorkspacesPerMon[monIdx] : 6
    newWs  := curWs + delta
    
    if (newWs >= 1 && newWs <= maxWs)
        MoveActiveWindowTo(newWs)
}

ActivateTopWindowOnWorkspace(monIdx, wsIdx) {
    global wsWindows
    for hwnd in WinGetList() {
        if wsWindows.Has(hwnd) {
            info := wsWindows[hwnd]
            if (info.mon == monIdx && info.ws == wsIdx && !info.isOffscreen) {
                target := GetTopActiveWindow(hwnd)
                ForceActivateWindow(target)
                return true
            }
        }
    }
    return false
}

IsManagedWindow(hwnd) {
    global Rules
    try {
        if !hwnd || !WinExist("ahk_id " hwnd)
            return false

        procName := StrLower(WinGetProcessName("ahk_id " hwnd))
        if Rules.ignoreProcesses.Has(procName)
            return false

        winClass := StrLower(WinGetClass("ahk_id " hwnd))
        if Rules.systemClasses.Has(winClass)
            return false

        if (WinGetTitle("ahk_id " hwnd) == "")
            return false

        return IsMainWindow(hwnd)
    } catch {
        return false
    }
}

IsMainWindow(hwnd) {
    try {
        style := WinGetStyle("ahk_id " hwnd)
        exStyle := WinGetExStyle("ahk_id " hwnd)
        
        if (style & 0x40000000) || (exStyle & 0x00000080)
            return false
            
        if (style & 0x80000000) {
            if !(style & 0x00C00000) && !(style & 0x00040000) && !(exStyle & 0x00040000)
                return false
        }

        owner := DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")
        return (owner == 0 || (exStyle & 0x00040000))
    } catch {
        return false
    }
}

ToggleFloatingWindows() {
    global lastToggleTime, lastSwitchTime, isSwitchingWorkspace, currentWorkspaces, desktopStates, wsWindows
    if (isSwitchingWorkspace || (A_TickCount - lastSwitchTime < 300) || (A_TickCount - lastToggleTime < 200))
        return
    lastToggleTime := A_TickCount

    monIdx := GetCurrentTargetMonitor()
    curWs  := currentWorkspaces[monIdx]
    stateKey := monIdx "_" curWs

    if !desktopStates.Has(stateKey)
        desktopStates[stateKey] := false

    newState := !desktopStates[stateKey]
    desktopStates[stateKey] := newState

    try {
        for hwnd in WinGetList() {
            if !wsWindows.Has(hwnd)
                continue
            info := wsWindows[hwnd]
            if (info.mon == monIdx && info.ws == curWs)
                AlignWindowToDesktopState(hwnd, !newState)
        }
    }

    if (!newState) {
        for h in WinGetList() {
            if wsWindows.Has(h) {
                info := wsWindows[h]
                if (info.mon == monIdx && info.ws == curWs && !info.isOffscreen && !IsEligibleFloatingWindow(h)) {
                    ForceActivateWindow(h)
                    break
                }
            }
        }
    }

    EnsureTaskbarTopmost()
    PocketManager.ApplyLayerHierarchy()
    if (newState)
        ShowOSD(Chr(0x1F4CC))
}

AlignWindowToDesktopState(hwnd, pushToBottom := false) {
    global wsWindows, desktopStates
    try {
        if !IsEligibleFloatingWindow(hwnd) || !wsWindows.Has(hwnd)
            return false

        info := wsWindows[hwnd]
        stateKey := info.mon "_" info.ws

        StopWindowFlash(hwnd)
        DllCall("SetProp", "ptr", hwnd, "str", "NonRudeHWND", "ptr", 1)

        isTop := (WinGetExStyle("ahk_id " hwnd) & 0x8)
        shouldPin := desktopStates.Has(stateKey) ? desktopStates[stateKey] : false

        if (shouldPin) {
            if (!isTop)
                WinSetAlwaysOnTop(true, "ahk_id " hwnd)
            return false
        } else {
            if (isTop)
                WinSetAlwaysOnTop(false, "ahk_id " hwnd)
            isActive := WinActive("ahk_id " hwnd)
            owner := DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")
            if (pushToBottom && owner == 0)
                DllCall("SetWindowPos", "ptr", hwnd, "ptr", 1, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0013)
            return isActive
        }
    }
    return false
}

IsEligibleFloatingWindow(hwnd) {
    global wsWindows, Rules
    try {
        if !WinExist("ahk_id " hwnd) || !DllCall("IsWindowVisible", "ptr", hwnd) || IsWindowCloaked(hwnd)
            return false

        if (wsWindows.Has(hwnd) && wsWindows[hwnd].isOffscreen)
            return false

        ; Pocket scratchpad windows are excluded from desktop floating pin state
        if PocketManager.IsInPocket(hwnd) || PocketManager.IsBorderHwnd(hwnd)
            return false

        if IsGameOrExclusiveWindow(hwnd) || IsExcludedFromPinning(hwnd)
            return false

        winClass := StrLower(WinGetClass("ahk_id " hwnd))
        if Rules.systemClasses.Has(winClass)
            return false

        if (WinGetTitle("ahk_id " hwnd) == "")
            return false

        owner := DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")
        if (owner != 0)
            return false

        style := WinGetStyle("ahk_id " hwnd)
        if !IsMainWindow(hwnd) || (style & 0x20000000) ; WS_MINIMIZE
            return false

        return !IsSnappedOrMaximized(hwnd)
    } catch {
        return false
    }
}

IsExcludedFromPinning(hwnd) {
    global Rules
    try {
        procName := StrLower(WinGetProcessName("ahk_id " hwnd))
        if Rules.pinningIgnoreProcesses.Has(procName)
            return true

        winClass := StrLower(WinGetClass("ahk_id " hwnd))
        return (winClass = "taskmanagerwindow" || winClass = "cascadia_hosting_window_class" || winClass = "screenclippinghost")
    }
    return false
}

IsSnappedOrMaximized(hwnd) {
    try {
        style := WinGetStyle("ahk_id " hwnd)
        if (style & 0x01000000) ; WS_MAXIMIZE
            return true
        if DllCall("user32\IsWindowArranged", "ptr", hwnd, "int")
            return true
    } catch {
        return IsSnappedByCoordinates(hwnd)
    }
    return false
}

IsSnappedByCoordinates(hwnd) {
    monIdx := GetWindowMonitor(hwnd)
    left := 0, top := 0, right := 0, bottom := 0
    if MonitorGetWorkArea(monIdx, &left, &top, &right, &bottom) {
        try {
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
            mW := right - left
            mH := bottom - top
            
            if (Abs(wh - mH) <= 25 && wy <= top + 15)
                return true
                
            for ratio in [0.5, 0.33, 0.66, 0.25, 0.75] {
                if (Abs(ww - (mW * ratio)) <= 35 && (Abs(wh - mH) <= 35 || Abs(wh - (mH / 2)) <= 35))
                    return true
            }
        }
    }
    return false
}

IsGameOrExclusiveWindow(hwnd) {
    global titleBarInfo, Rules
    try {
        if !hwnd || !WinExist("ahk_id " hwnd)
            return false

        if titleBarInfo.Has(hwnd) && titleBarInfo[hwnd].eligible
            return false

        winClass := StrLower(WinGetClass("ahk_id " hwnd))
        if Rules.gameClasses.Has(winClass) || Rules.systemClasses.Has(winClass)
            return true

        style := WinGetStyle("ahk_id " hwnd)
        if ((style & 0x80000000) && !(style & 0x00C00000)) {
            monIdx := GetWindowMonitor(hwnd)
            mL := 0, mT := 0, mR := 0, mB := 0
            if MonitorGetWorkArea(monIdx, &mL, &mT, &mR, &mB) {
                WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
                if (wx <= mL && wy <= mT && ww >= (mR - mL) && wh >= (mB - mT))
                    return true
            }
        }
    }
    return false
}

SaveState() {
    global currentWorkspaces, desktopStates, wsWindows

    statePath := A_ScriptDir "\state.json"
    
    cwList := []
    for mon, ws in currentWorkspaces
        cwList.Push(ws)

    dsMap := Map()
    for k, v in desktopStates
        dsMap[k] := (v ? 1 : 0)

    winList := []
    for hwnd, info in wsWindows {
        if !WinExist("ahk_id " hwnd)
            continue

        pName := ""
        try pName := WinGetProcessName("ahk_id " hwnd)
        pPath := ""
        try pPath := WinGetProcessPath("ahk_id " hwnd)
        wClass := ""
        try wClass := WinGetClass("ahk_id " hwnd)
        wTitle := ""
        try wTitle := WinGetTitle("ahk_id " hwnd)

        winList.Push(Map(
            "hwnd", hwnd,
            "mon", info.mon,
            "ws", info.ws,
            "isOffscreen", (info.isOffscreen ? 1 : 0),
            "x", Round(info.x),
            "y", Round(info.y),
            "w", Round(info.w),
            "h", Round(info.h),
            "isMax", (info.isMax ? 1 : 0),
            "process", pName,
            "path", pPath,
            "class", wClass,
            "title", wTitle
        ))
    }

    stateObj := Map(
        "currentWorkspaces", cwList,
        "desktopStates", dsMap,
        "windows", winList
    )

    try {
        jsonStr := JSON.Dump(stateObj, "  ")
        if FileExist(statePath)
            FileDelete(statePath)
        FileAppend(jsonStr, statePath, "UTF-8")
    }
}

LoadState() {
    global currentWorkspaces, desktopStates, wsWindows

    statePath := A_ScriptDir "\state.json"
    if !FileExist(statePath)
        return false

    raw := ""
    try raw := FileRead(statePath, "UTF-8")
    if (raw == "")
        return false

    stateObj := 0
    try stateObj := JSON.Load(raw)
    if !(stateObj is Map)
        return false

    if (stateObj.Has("currentWorkspaces") && stateObj["currentWorkspaces"] is Array) {
        for idx, wsNum in stateObj["currentWorkspaces"] {
            if (idx <= currentWorkspaces.Length)
                currentWorkspaces[idx] := Integer(wsNum)
        }
    }

    if (stateObj.Has("desktopStates") && stateObj["desktopStates"] is Map) {
        for k, v in stateObj["desktopStates"]
            desktopStates[k] := (v == 1 || v == true)
    }

    if (stateObj.Has("windows") && stateObj["windows"] is Array) {
        savedList := stateObj["windows"]
        
        usedHwnds := Map()
        unmatchedSaved := []

        for item in savedList {
            if !(item is Map)
                continue
            sHwnd := item.Has("hwnd") ? Integer(item["hwnd"]) : 0
            if (sHwnd && WinExist("ahk_id " sHwnd) && IsManagedWindow(sHwnd)) {
                usedHwnds[sHwnd] := true
                info := {
                    mon: Integer(item.Has("mon") ? item["mon"] : 1),
                    ws: Integer(item.Has("ws") ? item["ws"] : 1),
                    isOffscreen: (item.Has("isOffscreen") && item["isOffscreen"] == 1),
                    x: Integer(item.Has("x") ? item["x"] : 100),
                    y: Integer(item.Has("y") ? item["y"] : 100),
                    w: Integer(item.Has("w") ? item["w"] : 800),
                    h: Integer(item.Has("h") ? item["h"] : 600),
                    isMax: (item.Has("isMax") && item["isMax"] == 1)
                }
                wsWindows[sHwnd] := info
                SaveWindowProps(sHwnd, info)
                GetOrInitTitleBarInfo(sHwnd)
            } else {
                unmatchedSaved.Push(item)
            }
        }

        if (unmatchedSaved.Length > 0) {
            for curHwnd in WinGetList() {
                if (!IsManagedWindow(curHwnd) || usedHwnds.Has(curHwnd) || wsWindows.Has(curHwnd))
                    continue

                curProc := ""
                try curProc := StrLower(WinGetProcessName("ahk_id " curHwnd))
                curPath := ""
                try curPath := StrLower(WinGetProcessPath("ahk_id " curHwnd))
                curClass := ""
                try curClass := StrLower(WinGetClass("ahk_id " curHwnd))

                matchedIdx := 0
                for idx, sItem in unmatchedSaved {
                    sProc := StrLower(sItem.Has("process") ? sItem["process"] : "")
                    sPath := StrLower(sItem.Has("path") ? sItem["path"] : "")
                    sClass := StrLower(sItem.Has("class") ? sItem["class"] : "")

                    if (sProc != "" && sProc == curProc && (sClass == "" || sClass == curClass)) {
                        matchedIdx := idx
                        break
                    }
                }

                if (matchedIdx > 0) {
                    item := unmatchedSaved[matchedIdx]
                    unmatchedSaved.RemoveAt(matchedIdx)
                    usedHwnds[curHwnd] := true

                    info := {
                        mon: Integer(item.Has("mon") ? item["mon"] : 1),
                        ws: Integer(item.Has("ws") ? item["ws"] : 1),
                        isOffscreen: (item.Has("isOffscreen") && item["isOffscreen"] == 1),
                        x: Integer(item.Has("x") ? item["x"] : 100),
                        y: Integer(item.Has("y") ? item["y"] : 100),
                        w: Integer(item.Has("w") ? item["w"] : 800),
                        h: Integer(item.Has("h") ? item["h"] : 600),
                        isMax: (item.Has("isMax") && item["isMax"] == 1)
                    }
                    wsWindows[curHwnd] := info
                    SaveWindowProps(curHwnd, info)
                    GetOrInitTitleBarInfo(curHwnd)
                }
            }
        }
    }
    return true
}

SaveWindowProps(hwnd, info) {
    global wsWindows
    try {
        DllCall("SetProp", "ptr", hwnd, "str", "AHK_WS_MON", "ptr", info.mon)
        DllCall("SetProp", "ptr", hwnd, "str", "AHK_WS_NUM", "ptr", info.ws)
        DllCall("SetProp", "ptr", hwnd, "str", "AHK_WS_X", "int", Round(info.x))
        DllCall("SetProp", "ptr", hwnd, "str", "AHK_WS_Y", "int", Round(info.y))
        DllCall("SetProp", "ptr", hwnd, "str", "AHK_WS_W", "int", Round(info.w))
        DllCall("SetProp", "ptr", hwnd, "str", "AHK_WS_H", "int", Round(info.h))
        DllCall("SetProp", "ptr", hwnd, "str", "AHK_WS_MAX", "int", info.isMax ? 1 : 0)
    }
}

RemoveWindowProps(hwnd) {
    global wsWindows
    try {
        DllCall("RemoveProp", "ptr", hwnd, "str", "AHK_WS_MON")
        DllCall("RemoveProp", "ptr", hwnd, "str", "AHK_WS_NUM")
        DllCall("RemoveProp", "ptr", hwnd, "str", "AHK_WS_X")
        DllCall("RemoveProp", "ptr", hwnd, "str", "AHK_WS_Y")
        DllCall("RemoveProp", "ptr", hwnd, "str", "AHK_WS_W")
        DllCall("RemoveProp", "ptr", hwnd, "str", "AHK_WS_H")
        DllCall("RemoveProp", "ptr", hwnd, "str", "AHK_WS_MAX")
    }
}

RecoverAllOffscreenWindows(force := false) {
    global wsWindows
    for hwnd in WinGetList() {
        try {
            if !WinExist("ahk_id " hwnd) || !IsMainWindow(hwnd)
                continue
            if !IsManagedWindow(hwnd)
                continue

            if (!force) {
                propWs := DllCall("GetProp", "ptr", hwnd, "str", "AHK_WS_NUM", "ptr")
                if (propWs > 0)
                    continue
            }
                
            wx := 0, wy := 0, ww := 0, wh := 0
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
            if IsPosOffscreen(wx, wy, ww, wh) {
                wMon := 1
                left := 0, top := 0, right := 0, bottom := 0
                if MonitorGetWorkArea(wMon, &left, &top, &right, &bottom) {
                    DllCall("user32\SetWindowPos", "ptr", hwnd, "ptr", 0
                        , "int", left + 80, "int", top + 80, "int", 0, "int", 0
                        , "uint", 0x4015)
                }
            }
        }
    }
}
