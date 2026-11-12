#Requires AutoHotkey v2.0

class WindowMover {
    static DefaultSafeZone := 8
    static MaxSafeZone := 100
    static DefaultKeyboardStep := 20
    static MaxKeyboardStep := 200
    static MinWidth := 200
    static MinHeight := 120

    ; Cursor movement (px) required before a drag or resize begins.
    ; Acts as a click-safe dead zone for LayerPeeker and plain clicks.
    static SafeZonePx() {
        value := ConfigManager.Get("general.windowMover.safeZone", this.DefaultSafeZone)
        try {
            value := Integer(value)
        } catch {
            value := this.DefaultSafeZone
        }
        return Max(1, Min(this.MaxSafeZone, value))
    }

    ; Distance (px) one keyboard move/resize action shifts the window.
    static KeyboardStepPx() {
        value := ConfigManager.Get("general.windowMover.keyboardStep", this.DefaultKeyboardStep)
        try {
            value := Integer(value)
        } catch {
            value := this.DefaultKeyboardStep
        }
        return Max(1, Min(this.MaxKeyboardStep, value))
    }

    ; "custom" snaps with SetWindowPos (instant), "native" lets Windows snap
    ; halves with Win+Arrow and falls back to custom for other zones.
    static SnapMode() {
        mode := ConfigManager.Get("general.windowMover.snapMode", "custom")
        return (mode == "native") ? "native" : "custom"
    }
}

; A click-through rectangle that previews where a dragged window will snap.
class SnapPreview {
    static gui := 0
    static lastRect := ""

    static Show(zone) {
        rect := zone["x"] "," zone["y"] "," zone["w"] "," zone["h"]
        if (this.gui && rect == this.lastRect)
            return

        if !this.gui {
            this.gui := Gui("-Caption +ToolWindow +AlwaysOnTop +E0x20 +E0x08000000")
            this.gui.BackColor := "0078D7"
        }
        this.gui.Show("NA x" zone["x"] " y" zone["y"] " w" zone["w"] " h" zone["h"])
        try WinSetTransparent(110, this.gui.Hwnd)
        this.lastRect := rect
    }

    static Hide() {
        if this.gui
            this.gui.Hide()
        this.lastRect := ""
    }
}

; Returns the zone under the cursor, or 0. Corners win over edges, the top
; edge centre maximises (handled by the drag loop).
ComputeSnapZone(curX, curY, mL, mT, mR, mB, threshold := 20) {
    width := mR - mL
    height := mB - mT
    if (width <= 0 || height <= 0)
        return 0

    halfW := Round(width / 2)
    halfH := Round(height / 2)
    nearLeft := (curX <= mL + threshold)
    nearRight := (curX >= mR - threshold)
    nearTop := (curY <= mT + threshold)
    nearBottom := (curY >= mB - threshold)

    if (nearTop && nearLeft)
        return Map("kind", "quarter", "x", mL, "y", mT, "w", halfW, "h", halfH)
    if (nearTop && nearRight)
        return Map("kind", "quarter", "x", mL + halfW, "y", mT, "w", width - halfW, "h", halfH)
    if (nearBottom && nearLeft)
        return Map("kind", "quarter", "x", mL, "y", mT + halfH, "w", halfW, "h", height - halfH)
    if (nearBottom && nearRight)
        return Map("kind", "quarter", "x", mL + halfW, "y", mT + halfH, "w", width - halfW, "h", height - halfH)
    if nearTop
        return Map("kind", "max", "x", mL, "y", mT, "w", width, "h", height)
    if nearBottom
        return Map("kind", "bottom", "x", mL, "y", mT + halfH, "w", width, "h", height - halfH)
    if nearLeft
        return Map("kind", "left", "x", mL, "y", mT, "w", halfW, "h", height)
    if nearRight
        return Map("kind", "right", "x", mL + halfW, "y", mT, "w", width - halfW, "h", height)
    return 0
}

; Windows draws the visible frame inside the window rect (8 px borders on
; Win10/11), so a raw SetWindowPos leaves gaps between snapped windows.
GetFramePadding(hwnd) {
    empty := Map("left", 0, "top", 0, "right", 0, "bottom", 0)
    try {
        wx := 0, wy := 0, ww := 0, wh := 0
        WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
        if (ww <= 0 || wh <= 0)
            return empty

        buf := Buffer(16, 0)
        result := DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd
            , "uint", 9 ; DWMWA_EXTENDED_FRAME_BOUNDS
            , "ptr", buf, "uint", 16, "int")
        if (result != 0)
            return empty

        visibleLeft := NumGet(buf, 0, "Int"), visibleTop := NumGet(buf, 4, "Int")
        visibleRight := NumGet(buf, 8, "Int"), visibleBottom := NumGet(buf, 12, "Int")
        if (visibleRight <= visibleLeft || visibleBottom <= visibleTop)
            return empty

        return Map(
            "left", Max(0, visibleLeft - wx),
            "top", Max(0, visibleTop - wy),
            "right", Max(0, (wx + ww) - visibleRight),
            "bottom", Max(0, (wy + wh) - visibleBottom)
        )
    } catch {
        return empty
    }
}

; Grows a visible target rectangle into the window rectangle Windows expects.
ApplyFramePadding(zone, padding) {
    return Map(
        "x", zone["x"] - padding["left"],
        "y", zone["y"] - padding["top"],
        "w", zone["w"] + padding["left"] + padding["right"],
        "h", zone["h"] + padding["top"] + padding["bottom"]
    )
}

ApplySnapGeometry(winId, zone) {
    padded := ApplyFramePadding(zone, GetFramePadding(winId))
    DllCall("user32\SetWindowPos", "ptr", winId, "ptr", 0
        , "int", padded["x"], "int", padded["y"]
        , "int", padded["w"], "int", padded["h"]
        , "uint", 0x0014) ; SWP_NOZORDER | SWP_NOACTIVATE
}

; Native Aero Snap can only produce left/right halves and maximize through
; Win+Arrow; quarters and the bottom half keep the custom placement.
NativeSnapKeys(zone) {
    if !zone
        return []
    kind := zone["kind"]
    if (kind == "left")
        return ["#Left"]
    if (kind == "right")
        return ["#Right"]
    return []
}

TryNativeSnap(winId, zone) {
    keys := NativeSnapKeys(zone)
    if (keys.Length == 0)
        return false

    ; A held modifier would change what Win+Arrow does.
    if (GetKeyState("Alt", "P") || GetKeyState("Ctrl", "P") || GetKeyState("Shift", "P")
        || GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))
        return false

    if (DllCall("GetForegroundWindow", "ptr") != winId) {
        DllCall("user32\SetForegroundWindow", "ptr", winId)
        Sleep(30)
        if (DllCall("GetForegroundWindow", "ptr") != winId)
            return false
    }

    for key in keys
        Send(key)
    return true
}

MoveWindowWithMouse() {
    global isMovingOrResizing, Rules, wsWindows, currentWorkspaces, titleBarInfo, desktopStates
    CoordMode("Mouse", "Screen")
    MouseGetPos(&startX, &startY, &rawHwnd)

    dragThreshold := WindowMover.SafeZonePx()
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
        ErrorLogger.Record("peeker click at " startX "," startY)
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

    ErrorLogger.Record("move start hwnd=" winId)

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

    ; Position the drag anchor at the point where the safe zone was left,
    ; so the window does not jump by the threshold once the drag starts.
    startX := curX
    startY := curY

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
        snapThreshold := 20

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

            ; Maximize only on the top edge centre, corners are snap zones.
            if (curY <= mT + 1 && curX > mL + snapThreshold && curX < mR - snapThreshold) {
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

            ; Show where the window will land; top-centre maximises live instead.
            previewZone := ComputeSnapZone(curX, curY, mL, mT, mR, mB, snapThreshold)
            if (previewZone && previewZone["kind"] != "max")
                SnapPreview.Show(previewZone)
            else
                SnapPreview.Hide()

            DllCall("Sleep", "uint", 1)
        }

        MouseGetPos(&endX, &endY)
        wMon := GetWindowMonitor(winId)
        mL := 0, mT := 0, mR := 0, mB := 0
        MonitorGet(wMon, &mL, &mT, &mR, &mB)

        SnapPreview.Hide()
        appliedSnap := false
        finalZone := ComputeSnapZone(endX, endY, mL, mT, mR, mB, snapThreshold)
        if (finalZone && finalZone["kind"] != "max") {
            if (wasSnappedMax) {
                wasSnappedMax := false
                DllCall("ShowWindow", "ptr", winId, "int", 9) ; SW_RESTORE
            }

            if (WindowMover.SnapMode() == "native") {
                beforeX := 0, beforeY := 0, beforeW := 0, beforeH := 0
                WinGetPos(&beforeX, &beforeY, &beforeW, &beforeH, "ahk_id " winId)

                if (TryNativeSnap(winId, finalZone)) {
                    ; Let the system snap animation finish before saving geometry.
                    Sleep(220)
                }

                afterX := 0, afterY := 0, afterW := 0, afterH := 0
                WinGetPos(&afterX, &afterY, &afterW, &afterH, "ahk_id " winId)

                ; If snapping is disabled in Windows, Win+Arrow did nothing.
                ; Fall back to custom placement so the window still lands flush.
                changed := Abs(afterX - beforeX) > 4 || Abs(afterY - beforeY) > 4
                    || Abs(afterW - beforeW) > 4 || Abs(afterH - beforeH) > 4
                if !changed
                    ApplySnapGeometry(winId, finalZone)
            } else {
                ; Custom placement also compensates the invisible DWM borders,
                ; otherwise visible window edges leave gaps.
                ApplySnapGeometry(winId, finalZone)
            }
            appliedSnap := true
        }

        if (!appliedSnap && (wasSnappedMax || endY <= mT + 1)) {
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
        SnapPreview.Hide()
        isMovingOrResizing := false
    }
}

ResizeWindowWithMouse() {
    global isMovingOrResizing, Rules, wsWindows, currentWorkspaces, titleBarInfo, desktopStates
    CoordMode("Mouse", "Screen")
    MouseGetPos(&startX, &startY, &rawHwnd)

    dragThreshold := WindowMover.SafeZonePx()
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

    ; Keep the original grab point for edge selection; startX/startY are
    ; rebased to the safe-zone exit point below.
    clickX := startX, clickY := startY

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
        
    ErrorLogger.Record("resize start hwnd=" winId)
        
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

    ; Position the resize anchor at the point where the safe zone was left,
    ; so the window does not jump by the threshold once resizing starts.
    startX := curX
    startY := curY

    isMovingOrResizing := true
    try {
        isPinned := (WinGetExStyle("ahk_id " winId) & 0x8)
        WinGetPos(&origX, &origY, &origW, &origH, "ahk_id " winId)
        if (origW <= 0 || origH <= 0)
            return

        if (DllCall("GetForegroundWindow", "ptr") != winId)
            DllCall("user32\SetForegroundWindow", "ptr", winId)

        relX := (clickX - origX) / origW
        relY := (clickY - origY) / origH

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

; ------------------------------------------------------------------------------
; Keyboard move / resize of the active window
; ------------------------------------------------------------------------------

EnsureActiveWindowSize() {
    winId := WinExist("A")
    if !winId || IsGameOrExclusiveWindow(winId)
        return 0

    style := WinGetStyle("ahk_id " winId)
    if ((style & 0x01000000) || WinGetMinMax("ahk_id " winId) == 1) {
        try DllCall("ShowWindow", "ptr", winId, "int", 9) ; SW_RESTORE
    }
    return winId
}

VirtualScreenBounds() {
    left := SysGet(76)    ; SM_XVIRTUALSCREEN
    top := SysGet(77)     ; SM_YVIRTUALSCREEN
    width := SysGet(78)   ; SM_CXVIRTUALSCREEN
    height := SysGet(79)  ; SM_CYVIRTUALSCREEN
    return {left: left, top: top, right: left + width, bottom: top + height}
}

SaveKeyboardGeometry(winId, wx, wy, ww, wh) {
    global wsWindows, titleBarInfo

    if wsWindows.Has(winId) {
        wsWindows[winId].isMax := false
        wsWindows[winId].x := wx, wsWindows[winId].y := wy
        wsWindows[winId].w := ww, wsWindows[winId].h := wh
        SaveWindowProps(winId, wsWindows[winId])
        SetTimer(() => SaveState(), -300)
    }

    if titleBarInfo.Has(winId)
        titleBarInfo[winId].boundsValid := false

    if PocketManager.IsInPocket(winId)
        PocketManager.UpdateBorder(winId)
}

MoveActiveWindowBy(dx, dy) {
    global isMovingOrResizing

    winId := EnsureActiveWindowSize()
    if !winId
        return

    wx := 0, wy := 0, ww := 0, wh := 0
    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " winId)
    if (ww <= 0 || wh <= 0)
        return

    bounds := VirtualScreenBounds()
    newX := wx + dx
    newY := wy + dy
    ; Keep the frame inside the virtual desktop so it cannot be lost off-screen,
    ; but allow moving across monitors.
    newX := Max(bounds.left, Min(bounds.right - ww, newX))
    newY := Max(bounds.top, Min(bounds.bottom - wh, newY))

    isMovingOrResizing := true
    try {
        DllCall("user32\SetWindowPos", "ptr", winId, "ptr", 0
            , "int", newX, "int", newY, "int", 0, "int", 0
            , "uint", 0x0015) ; SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE
        SaveKeyboardGeometry(winId, newX, newY, ww, wh)
    } finally {
        isMovingOrResizing := false
    }
}

ResizeActiveWindowBy(dw, dh) {
    global isMovingOrResizing

    winId := EnsureActiveWindowSize()
    if !winId
        return

    wx := 0, wy := 0, ww := 0, wh := 0
    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " winId)
    if (ww <= 0 || wh <= 0)
        return

    bounds := VirtualScreenBounds()
    newW := Max(WindowMover.MinWidth, ww + dw)
    newH := Max(WindowMover.MinHeight, wh + dh)
    newW := Min(newW, bounds.right - wx)
    newH := Min(newH, bounds.bottom - wy)

    isMovingOrResizing := true
    try {
        DllCall("user32\SetWindowPos", "ptr", winId, "ptr", 0
            , "int", 0, "int", 0, "int", newW, "int", newH
            , "uint", 0x0016) ; SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE
        SaveKeyboardGeometry(winId, wx, wy, newW, newH)
    } finally {
        isMovingOrResizing := false
    }
}
