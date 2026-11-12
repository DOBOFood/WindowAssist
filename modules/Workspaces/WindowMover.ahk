#Requires AutoHotkey v2.0

class WindowMover {
    static dummy() => true
}

MoveWindowWithMouse() {
    global isMovingOrResizing, Rules, wsWindows, currentWorkspaces, titleBarInfo, desktopStates
    CoordMode("Mouse", "Screen")
    MouseGetPos(&startX, &startY, &rawHwnd)

    dragThreshold := 4
    hasMovedPastThreshold := false

    while GetKeyState("LButton", "P") {
        MouseGetPos(&curX, &curY)
        if (Abs(curX - startX) >= dragThreshold || Abs(curY - startY) >= dragThreshold) {
            hasMovedPastThreshold := true
            break
        }
        DllCall("Sleep", "uint", 1)
    }

    if (!hasMovedPastThreshold) {
        LayerPeeker.OnClick()
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

    LayerPeeker.Reset()

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
        lastCurX := startX, lastCurY := startY

        wMon := GetWindowMonitor(winId)
        mL := 0, mT := 0, mR := 0, mB := 0
        MonitorGet(wMon, &mL, &mT, &mR, &mB)

        isInPocketWin := PocketManager.IsInPocket(winId)
        checkMonCount := 0

        while GetKeyState("LButton", "P") {
            MouseGetPos(&curX, &curY)

            checkMonCount++
            if (checkMonCount >= 30) {
                checkMonCount := 0
                newMon := GetWindowMonitor(winId)
                if (newMon != wMon) {
                    wMon := newMon
                    MonitorGet(wMon, &mL, &mT, &mR, &mB)
                }
            }

            if (curY <= mT + 1) {
                if (!wasSnappedMax) {
                    wasSnappedMax := true
                    DllCall("ShowWindow", "ptr", winId, "int", 3) ; SW_MAXIMIZE
                }
            } else {
                if (wasSnappedMax) {
                    wasSnappedMax := false
                    DllCall("ShowWindow", "ptr", winId, "int", 9) ; SW_RESTORE
                    origW := savedRestW
                    origH := savedRestH
                    origX := Round(curX - (origW / 2))
                    origY := Max(mT, curY - 20)
                    startX := curX
                    startY := curY
                    lastCurX := curX, lastCurY := curY
                    DllCall("user32\SetWindowPos", "ptr", winId, "ptr", 0
                        , "int", origX, "int", origY, "int", origW, "int", origH
                        , "uint", 0x0214)
                }

                if (curX != lastCurX || curY != lastCurY) {
                    lastCurX := curX, lastCurY := curY
                    newX := origX + (curX - startX)
                    newY := origY + (curY - startY)
                    
                    ; Synchronous move: SWP_ASYNCWINDOWPOS queues every request on the target
                    ; thread and makes the window trail the cursor; SWP_NOREDRAW defers the
                    ; repaint until the drag ends. Apply each move immediately instead.
                    DllCall("user32\SetWindowPos", "ptr", winId, "ptr", 0
                        , "int", newX, "int", newY, "int", 0, "int", 0
                        , "uint", 0x0015) ; SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE

                    if (isInPocketWin)
                        PocketManager.UpdateBorder(winId)
                }
            }
            DllCall("Sleep", "uint", 1)
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

        if (isInPocketWin)
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

    dragThreshold := 4
    hasMovedPastThreshold := false

    while GetKeyState("RButton", "P") {
        MouseGetPos(&curX, &curY)
        if (Abs(curX - startX) >= dragThreshold || Abs(curY - startY) >= dragThreshold) {
            hasMovedPastThreshold := true
            break
        }
        DllCall("Sleep", "uint", 1)
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

        minW := 150, minH := 100
        lastCurX := startX, lastCurY := startY
        appliedX := origX, appliedY := origY
        appliedW := origW, appliedH := origH
        isInPocketWin := PocketManager.IsInPocket(winId)

        while GetKeyState("RButton", "P") {
            MouseGetPos(&curX, &curY)

            if (curX != lastCurX || curY != lastCurY) {
                lastCurX := curX, lastCurY := curY
                dx := curX - startX
                dy := curY - startY

                if (isLeft) {
                    nW := origW - dx
                    nX := origX + dx
                } else if (isRight) {
                    nW := origW + dx
                    nX := origX
                } else {
                    nW := origW
                    nX := origX
                }

                if (isTop) {
                    nH := origH - dy
                    nY := origY + dy
                } else if (isBottom) {
                    nH := origH + dy
                    nY := origY
                } else {
                    nH := origH
                    nY := origY
                }

                if (nW < minW) {
                    if (isLeft)
                        nX := origX + origW - minW
                    nW := minW
                }
                if (nH < minH) {
                    if (isTop)
                        nY := origY + origH - minH
                    nH := minH
                }

                if (nX != appliedX || nY != appliedY || nW != appliedW || nH != appliedH) {
                    appliedX := nX, appliedY := nY
                    appliedW := nW, appliedH := nH

                    DllCall("user32\SetWindowPos", "ptr", winId, "ptr", 0
                        , "int", appliedX, "int", appliedY, "int", appliedW, "int", appliedH
                        , "uint", 0x0214) ; SWP_NOZORDER | SWP_NOACTIVATE

                    if (isInPocketWin)
                        PocketManager.UpdateBorder(winId)
                }
            }
            DllCall("Sleep", "uint", 1)
        }

        MouseGetPos(&endX, &endY)
        wMon := GetWindowMonitor(winId)
        mL := 0, mT := 0, mR := 0, mB := 0
        MonitorGet(wMon, &mL, &mT, &mR, &mB)

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

        if (isInPocketWin)
            PocketManager.UpdateBorder(winId)

        SetTimer(() => SaveState(), -300)
    } finally {
        isMovingOrResizing := false
    }
}
