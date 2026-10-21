#Requires AutoHotkey v2.0

class WindowMover {
    static dummy() => true
}

MoveWindowWithMouse() {
    global isMovingOrResizing, Rules, wsWindows, currentWorkspaces, titleBarInfo, desktopStates
    CoordMode("Mouse", "Screen")
    MouseGetPos(&startX, &startY, &rawHwnd)

    ; Distinguish short click (LayerPeeker) from drag (Window Move)
    dragThreshold := 4
    hasMovedPastThreshold := false

    while GetKeyState("LButton", "P") {
        MouseGetPos(&curX, &curY)
        if (Abs(curX - startX) >= dragThreshold || Abs(curY - startY) >= dragThreshold) {
            hasMovedPastThreshold := true
            break
        }
        DllCall("Sleep", "uint", 10)
    }

    if (!hasMovedPastThreshold) {
        LayerPeeker.OnClick()
        return
    }

    if !rawHwnd
        return

    ; Redirect clicks on the scratchpad outline to the underlying target application
    if PocketManager.IsBorderHwnd(rawHwnd)
        rawHwnd := PocketManager.GetTargetFromBorder(rawHwnd)
        
    winId := DllCall("GetAncestor", "ptr", rawHwnd, "uint", 2, "ptr")
    winId := winId ? winId : rawHwnd

    if PocketManager.IsBorderHwnd(winId)
        winId := PocketManager.GetTargetFromBorder(winId)
        
    if !WinExist("ahk_id " winId) || IsGameOrExclusiveWindow(winId)
        return
        
    winClass := StrLower(WinGetClass("ahk_id " winId))
    if Rules.systemClasses.Has(winClass)
        return

    LayerPeeker.Reset()

    ; If window is maximized, restore it to a floating window so it can be moved
    style := WinGetStyle("ahk_id " winId)
    isMaxNow := (style & 0x01000000) || (WinGetMinMax("ahk_id " winId) == 1)
    if (isMaxNow) {
        wMon := GetWindowMonitor(winId)
        mL := 0, mT := 0, mR := 0, mB := 0
        MonitorGetWorkArea(wMon, &mL, &mT, &mR, &mB)
        monW := mR - mL, monH := mB - mT

        DllCall("ShowWindow", "ptr", winId, "int", 9) ; SW_RESTORE
        wx := 0, wy := 0, ww := 0, wh := 0
        WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " winId)

        if (ww <= 0 || ww >= monW || wh <= 0 || wh >= monH) {
            ww := Round(monW * 0.7)
            wh := Round(monH * 0.7)
        }

        newX := Round(curX - (ww / 2))
        newY := Max(mT, curY - 20)
        newX := Max(mL, Min(mR - ww, newX))
        newY := Max(mT, Min(mB - wh, newY))

        DllCall("user32\SetWindowPos", "ptr", winId, "ptr", 0
            , "int", newX, "int", newY, "int", ww, "int", wh
            , "uint", 0x0214)

        if wsWindows.Has(winId) {
            wsWindows[winId].isMax := false
            wsWindows[winId].x := newX
            wsWindows[winId].y := newY
            wsWindows[winId].w := ww
            wsWindows[winId].h := wh
            SaveWindowProps(winId, wsWindows[winId])
        }

        startX := curX
        startY := curY
    }

    isMovingOrResizing := true
    try {
        isPinned := (WinGetExStyle("ahk_id " winId) & 0x8)
        WinGetPos(&origX, &origY, &origW, &origH, "ahk_id " winId)
        
        if (DllCall("GetForegroundWindow", "ptr") != winId)
            DllCall("user32\SetForegroundWindow", "ptr", winId)
        
        savedRestW := origW
        savedRestH := origH
        wasSnappedMax := false
        lastDx := 0, lastDy := 0

        while GetKeyState("LButton", "P") {
            MouseGetPos(&curX, &curY)
            wMon := GetWindowMonitor(winId)
            mL := 0, mT := 0, mR := 0, mB := 0
            MonitorGet(wMon, &mL, &mT, &mR, &mB)

            ; When cursor reaches the very top border of the monitor, snap to maximized
            if (curY <= mT + 1) {
                if (!wasSnappedMax) {
                    wasSnappedMax := true
                    DllCall("ShowWindow", "ptr", winId, "int", 3) ; SW_MAXIMIZE
                }
            } else {
                ; If pulled down from top edge, restore back to floating
                if (wasSnappedMax) {
                    wasSnappedMax := false
                    DllCall("ShowWindow", "ptr", winId, "int", 9) ; SW_RESTORE
                    origW := savedRestW
                    origH := savedRestH
                    origX := Round(curX - (origW / 2))
                    origY := Max(mT, curY - 20)
                    startX := curX
                    startY := curY
                    lastDx := 0, lastDy := 0
                    DllCall("user32\SetWindowPos", "ptr", winId, "ptr", 0
                        , "int", origX, "int", origY, "int", origW, "int", origH
                        , "uint", 0x0214)
                }

                dx := curX - startX
                dy := curY - startY
                
                if (dx != lastDx || dy != lastDy) {
                    lastDx := dx, lastDy := dy
                    newX := origX + dx
                    newY := origY + dy
                    
                    DllCall("user32\SetWindowPos", "ptr", winId, "ptr", 0
                        , "int", newX, "int", newY, "int", 0, "int", 0
                        , "uint", 0x0215)

                    if PocketManager.IsInPocket(winId)
                        PocketManager.UpdateBorder(winId)
                }
            }
            DllCall("Sleep", "uint", 2)
        }

        MouseGetPos(&endX, &endY)
        wMon := GetWindowMonitor(winId)
        mL := 0, mT := 0, mR := 0, mB := 0
        MonitorGet(wMon, &mL, &mT, &mR, &mB)

        if (wasSnappedMax || endY <= mT + 1) {
            DllCall("ShowWindow", "ptr", winId, "int", 3) ; SW_MAXIMIZE
            if wsWindows.Has(winId) {
                oldMon := wsWindows[winId].mon
                wsWindows[winId].mon := wMon
                wsWindows[winId].ws := currentWorkspaces[wMon]
                wsWindows[winId].isMax := true
                SaveWindowProps(winId, wsWindows[winId])

                if IsAppGrouped(winId)
                    SyncAppWindowsLocation(winId, wMon, currentWorkspaces[wMon])

                if (oldMon != wMon) {
                    CrossWorkspaceAltTab.RecordActiveWindow(winId)
                    if (OverviewController.isOpen)
                        SetTimer(() => OverviewController.PushStateToWeb(OverviewController.currentMon), -50)
                }
            }
        } else {
            if wsWindows.Has(winId) {
                oldMon := wsWindows[winId].mon
                wsWindows[winId].mon := wMon
                wsWindows[winId].ws := currentWorkspaces[wMon]
                wx := 0, wy := 0, ww := 0, wh := 0
                WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " winId)
                wsWindows[winId].x := wx, wsWindows[winId].y := wy
                wsWindows[winId].w := ww, wsWindows[winId].h := wh
                wsWindows[winId].isMax := false
                SaveWindowProps(winId, wsWindows[winId])
                
                if IsAppGrouped(winId)
                    SyncAppWindowsLocation(winId, wMon, currentWorkspaces[wMon])

                if (oldMon != wMon) {
                    CrossWorkspaceAltTab.RecordActiveWindow(winId)
                    if (OverviewController.isOpen)
                        SetTimer(() => OverviewController.PushStateToWeb(OverviewController.currentMon), -50)
                }
            }
        }

        if titleBarInfo.Has(winId)
            titleBarInfo[winId].boundsValid := false

        curWs := currentWorkspaces[wMon]
        stateKey := wMon "_" curWs
        if ((desktopStates.Has(stateKey) && desktopStates[stateKey] && IsEligibleFloatingWindow(winId)) || isPinned)
            WinSetAlwaysOnTop(true, "ahk_id " winId)

        PocketManager.EnsurePocketTopmost()

        if PocketManager.IsInPocket(winId)
            PocketManager.UpdateBorder(winId)

        SetTimer(() => SaveState(), -300)
    } finally {
        isMovingOrResizing := false
    }
}

ResizeWindowWithMouse() {
    global isMovingOrResizing, Rules, wsWindows, currentWorkspaces, titleBarInfo, desktopStates
    CoordMode("Mouse", "Screen")
    MouseGetPos(&startX, &startY, &rawHwnd)

    ; Distinguish short click (Pin Toggle) from drag (Window Resize)
    dragThreshold := 4
    hasMovedPastThreshold := false

    while GetKeyState("RButton", "P") {
        MouseGetPos(&curX, &curY)
        if (Abs(curX - startX) >= dragThreshold || Abs(curY - startY) >= dragThreshold) {
            hasMovedPastThreshold := true
            break
        }
        DllCall("Sleep", "uint", 10)
    }

    if (!hasMovedPastThreshold) {
        ToggleFloatingWindows()
        return
    }

    if !rawHwnd
        return

    if PocketManager.IsBorderHwnd(rawHwnd)
        rawHwnd := PocketManager.GetTargetFromBorder(rawHwnd)
        
    winId := DllCall("GetAncestor", "ptr", rawHwnd, "uint", 2, "ptr")
    winId := winId ? winId : rawHwnd

    if PocketManager.IsBorderHwnd(winId)
        winId := PocketManager.GetTargetFromBorder(winId)
        
    if !WinExist("ahk_id " winId) || IsGameOrExclusiveWindow(winId)
        return
        
    winClass := StrLower(WinGetClass("ahk_id " winId))
    if Rules.systemClasses.Has(winClass)
        return
        
    ; If window is maximized, restore it to floating so it can be resized
    style := WinGetStyle("ahk_id " winId)
    isMaxNow := (style & 0x01000000) || (WinGetMinMax("ahk_id " winId) == 1)
    if (isMaxNow) {
        wMon := GetWindowMonitor(winId)
        mL := 0, mT := 0, mR := 0, mB := 0
        MonitorGetWorkArea(wMon, &mL, &mT, &mR, &mB)
        monW := mR - mL, monH := mB - mT

        DllCall("ShowWindow", "ptr", winId, "int", 9) ; SW_RESTORE
        wx := 0, wy := 0, ww := 0, wh := 0
        WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " winId)

        if (ww <= 0 || ww >= monW || wh <= 0 || wh >= monH) {
            ww := Round(monW * 0.7)
            wh := Round(monH * 0.7)
            newX := mL + Round((monW - ww) / 2)
            newY := mT + Round((monH - wh) / 2)
            DllCall("user32\SetWindowPos", "ptr", winId, "ptr", 0
                , "int", newX, "int", newY, "int", ww, "int", wh
                , "uint", 0x0214)
        }

        if wsWindows.Has(winId) {
            wsWindows[winId].isMax := false
            SaveWindowProps(winId, wsWindows[winId])
        }

        startX := curX
        startY := curY
    }
        
    isMovingOrResizing := true
    try {
        isPinned := (WinGetExStyle("ahk_id " winId) & 0x8)
        WinGetPos(&origX, &origY, &origW, &origH, "ahk_id " winId)
        if (origW <= 0 || origH <= 0)
            return

        if (DllCall("GetForegroundWindow", "ptr") != winId)
            DllCall("user32\SetForegroundWindow", "ptr", winId)

        relX := (startX - origX) / origW
        relY := (startY - origY) / origH

        threshold := 0.30
        isLeft   := (relX < threshold)
        isRight  := (relX > 1 - threshold)
        isTop    := (relY < threshold)
        isBottom := (relY > 1 - threshold)

        if (!isLeft && !isRight && !isTop && !isBottom) {
            isLeft   := (relX < 0.5)
            isRight  := (relX >= 0.5)
            isTop    := (relY < 0.5)
            isBottom := (relY >= 0.5)
        }

        lastDx := 0, lastDy := 0
        minW := 150, minH := 100

        while GetKeyState("RButton", "P") {
            MouseGetPos(&curX, &curY)
            dx := curX - startX
            dy := curY - startY
            
            if (dx != lastDx || dy != lastDy) {
                lastDx := dx, lastDy := dy

                if (isLeft) {
                    newW := origW - dx
                    newX := origX + dx
                } else if (isRight) {
                    newW := origW + dx
                    newX := origX
                } else {
                    newW := origW
                    newX := origX
                }

                if (isTop) {
                    newH := origH - dy
                    newY := origY + dy
                } else if (isBottom) {
                    newH := origH + dy
                    newY := origY
                } else {
                    newH := origH
                    newY := origY
                }

                if (newW < minW) {
                    if (isLeft)
                        newX := origX + origW - minW
                    newW := minW
                }
                if (newH < minH) {
                    if (isTop)
                        newY := origY + origH - minH
                    newH := minH
                }

                DllCall("user32\SetWindowPos", "ptr", winId, "ptr", 0
                    , "int", newX, "int", newY, "int", newW, "int", newH
                    , "uint", 0x0214)

                if PocketManager.IsInPocket(winId)
                    PocketManager.UpdateBorder(winId)
            }
            DllCall("Sleep", "uint", 2)
        }

        MouseGetPos(&endX, &endY)
        wMon := GetWindowMonitor(winId)
        mL := 0, mT := 0, mR := 0, mB := 0
        MonitorGet(wMon, &mL, &mT, &mR, &mB)

        ; If user dragged cursor flush to top border, maximize the window
        if (endY <= mT + 1) {
            DllCall("ShowWindow", "ptr", winId, "int", 3) ; SW_MAXIMIZE
            if wsWindows.Has(winId) {
                oldMon := wsWindows[winId].mon
                wsWindows[winId].mon := wMon
                wsWindows[winId].ws := currentWorkspaces[wMon]
                wsWindows[winId].isMax := true
                SaveWindowProps(winId, wsWindows[winId])

                if (oldMon != wMon) {
                    CrossWorkspaceAltTab.RecordActiveWindow(winId)
                    if (OverviewController.isOpen)
                        SetTimer(() => OverviewController.PushStateToWeb(OverviewController.currentMon), -50)
                }
            }
        } else {
            if wsWindows.Has(winId) {
                oldMon := wsWindows[winId].mon
                wx := 0, wy := 0, ww := 0, wh := 0
                WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " winId)
                wsWindows[winId].x := wx, wsWindows[winId].y := wy
                wsWindows[winId].w := ww, wsWindows[winId].h := wh
                wsWindows[winId].mon := wMon
                wsWindows[winId].ws := currentWorkspaces[wMon]
                wsWindows[winId].isMax := false
                SaveWindowProps(winId, wsWindows[winId])

                if (oldMon != wMon) {
                    CrossWorkspaceAltTab.RecordActiveWindow(winId)
                    if (OverviewController.isOpen)
                        SetTimer(() => OverviewController.PushStateToWeb(OverviewController.currentMon), -50)
                }
            }
        }

        if titleBarInfo.Has(winId)
            titleBarInfo[winId].boundsValid := false

        curWs := currentWorkspaces[wMon]
        stateKey := wMon "_" curWs
        if ((desktopStates.Has(stateKey) && desktopStates[stateKey] && IsEligibleFloatingWindow(winId)) || isPinned)
            WinSetAlwaysOnTop(true, "ahk_id " winId)

        PocketManager.EnsurePocketTopmost()

        if PocketManager.IsInPocket(winId)
            PocketManager.UpdateBorder(winId)

        SetTimer(() => SaveState(), -300)
    } finally {
        isMovingOrResizing := false
    }
}
