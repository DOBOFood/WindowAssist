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
    hHook := 0
    hookCb := 0

    try {
        isPinned := (WinGetExStyle("ahk_id " winId) & 0x8)
        WinGetPos(&origX, &origY, &origW, &origH, "ahk_id " winId)
        
        if (DllCall("GetForegroundWindow", "ptr") != winId)
            DllCall("user32\SetForegroundWindow", "ptr", winId)
        
        savedRestW := origW
        savedRestH := origH
        wasSnappedMax := false
        lastMoveX := startX, lastMoveY := startY

        LowLevelMoveProc(nCode, wParam, lParam) {
            if (nCode >= 0 && wParam == 0x0200) { ; WM_MOUSEMOVE
                mX := NumGet(lParam, 0, "int")
                mY := NumGet(lParam, 4, "int")
                
                if (mX != lastMoveX || mY != lastMoveY) {
                    lastMoveX := mX, lastMoveY := mY
                    wMon := GetWindowMonitor(winId)
                    mL := 0, mT := 0, mR := 0, mB := 0
                    MonitorGet(wMon, &mL, &mT, &mR, &mB)

                    if (mY <= mT + 1) {
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
                            origX := Round(mX - (origW / 2))
                            origY := Max(mT, mY - 20)
                            startX := mX
                            startY := mY
                            DllCall("user32\SetWindowPos", "ptr", winId, "ptr", 0
                                , "int", origX, "int", origY, "int", origW, "int", origH
                                , "uint", 0x0214)
                        }

                        newX := origX + (mX - startX)
                        newY := origY + (mY - startY)
                        
                        DllCall("user32\SetWindowPos", "ptr", winId, "ptr", 0
                            , "int", newX, "int", newY, "int", 0, "int", 0
                            , "uint", 0x4215) ; SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_ASYNCWINDOWPOS | SWP_NOREDRAW

                        if PocketManager.IsInPocket(winId)
                            PocketManager.UpdateBorder(winId)
                    }
                }
            }
            return DllCall("user32\CallNextHookEx", "ptr", 0, "int", nCode, "uptr", wParam, "ptr", lParam, "ptr")
        }

        hookCb := CallbackCreate(LowLevelMoveProc, "Fast", 3)
        hHook := DllCall("user32\SetWindowsHookExW", "int", 14, "ptr", hookCb, "ptr", 0, "uint", 0, "ptr") ; WH_MOUSE_LL = 14

        msg := Buffer(A_PtrSize == 8 ? 48 : 28, 0)
        while GetKeyState("LButton", "P") {
            while DllCall("user32\PeekMessageW", "ptr", msg, "ptr", 0, "uint", 0, "uint", 0, "uint", 1) {
                DllCall("user32\TranslateMessage", "ptr", msg)
                DllCall("user32\DispatchMessageW", "ptr", msg)
            }
            DllCall("Sleep", "uint", 1)
        }

        if (hHook) {
            DllCall("user32\UnhookWindowsHookEx", "ptr", hHook)
            hHook := 0
        }
        if (hookCb) {
            CallbackFree(hookCb)
            hookCb := 0
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
        if (hHook)
            DllCall("user32\UnhookWindowsHookEx", "ptr", hHook)
        if (hookCb)
            CallbackFree(hookCb)
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
    hHook := 0
    hookCb := 0

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

        targetX := origX, targetY := origY
        targetW := origW, targetH := origH
        appliedX := origX, appliedY := origY
        appliedW := origW, appliedH := origH
        hasPendingResize := false
        isApplying := false

        ApplyResize() {
            if (!hasPendingResize || isApplying || !WinExist("ahk_id " winId))
                return
            isApplying := true
            hasPendingResize := false
            appliedX := targetX, appliedY := targetY
            appliedW := targetW, appliedH := targetH

            DllCall("user32\SetWindowPos", "ptr", winId, "ptr", 0
                , "int", appliedX, "int", appliedY, "int", appliedW, "int", appliedH
                , "uint", 0x0214) ; SWP_NOZORDER | SWP_NOACTIVATE

            if PocketManager.IsInPocket(winId)
                PocketManager.UpdateBorder(winId)
            isApplying := false
        }

        LowLevelResizeProc(nCode, wParam, lParam) {
            if (nCode >= 0 && wParam == 0x0200) { ; WM_MOUSEMOVE
                mX := NumGet(lParam, 0, "int")
                mY := NumGet(lParam, 4, "int")
                
                dx := mX - startX
                dy := mY - startY

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
                    targetX := nX, targetY := nY
                    targetW := nW, targetH := nH
                    hasPendingResize := true
                }
            }
            return DllCall("user32\CallNextHookEx", "ptr", 0, "int", nCode, "uptr", wParam, "ptr", lParam, "ptr")
        }

        hookCb := CallbackCreate(LowLevelResizeProc, "Fast", 3)
        hHook := DllCall("user32\SetWindowsHookExW", "int", 14, "ptr", hookCb, "ptr", 0, "uint", 0, "ptr") ; WH_MOUSE_LL = 14

        msg := Buffer(A_PtrSize == 8 ? 48 : 28, 0)
        while GetKeyState("RButton", "P") {
            while DllCall("user32\PeekMessageW", "ptr", msg, "ptr", 0, "uint", 0, "uint", 0, "uint", 1) {
                DllCall("user32\TranslateMessage", "ptr", msg)
                DllCall("user32\DispatchMessageW", "ptr", msg)
            }
            ApplyResize()
            DllCall("Sleep", "uint", 1)
        }

        ApplyResize()

        if (hHook) {
            DllCall("user32\UnhookWindowsHookEx", "ptr", hHook)
            hHook := 0
        }
        if (hookCb) {
            CallbackFree(hookCb)
            hookCb := 0
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

        if PocketManager.IsInPocket(winId)
            PocketManager.UpdateBorder(winId)

        SetTimer(() => SaveState(), -300)
    } finally {
        if (hHook)
            DllCall("user32\UnhookWindowsHookEx", "ptr", hHook)
        if (hookCb)
            CallbackFree(hookCb)
        isMovingOrResizing := false
    }
}
