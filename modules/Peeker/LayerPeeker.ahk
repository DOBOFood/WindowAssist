#Requires AutoHotkey v2.0

class LayerPeeker {
    static lastPeekTime := 0
    static lastX := -1
    static lastY := -1
    static cycleHwnds := []
    static cycleIndex := 0
    static cycleMode := ""

    static Reset() {
        this.lastPeekTime := 0
        this.lastX := -1
        this.lastY := -1
        this.cycleHwnds := []
        this.cycleIndex := 0
        this.cycleMode := ""
    }

    /**
     * If there is a maximized window on the current workspace, executes the legacy LayerPeeker algorithm.
     * Otherwise, brings forward the window on the layer below the current one under the cursor (or cycles).
     */
    static OnClick() {
        global wsWindows, currentWorkspaces, Rules

        monIdx := GetCurrentTargetMonitor()
        curWs  := currentWorkspaces[monIdx]

        ; Check if there is any maximized window on the current workspace of this monitor
        hasMaximized := false
        for hwnd in WinGetList() {
            if !hwnd || !WinExist("ahk_id " hwnd) || !DllCall("user32\IsWindowVisible", "ptr", hwnd) || IsWindowCloaked(hwnd)
                continue

            if this.IsTopLayerElement(hwnd)
                continue

            wClass := StrLower(WinGetClass("ahk_id " hwnd))
            if (Rules.systemClasses.Has(wClass) || wClass = "progman" || wClass = "workerw" || wClass = "shell_traywnd" || wClass = "shell_secondarytraywnd")
                continue

            if !IsMainWindow(hwnd)
                continue

            if wsWindows.Has(hwnd) {
                info := wsWindows[hwnd]
                if (info.mon != monIdx || info.ws != curWs || info.isOffscreen)
                    continue
            } else {
                if (GetWindowMonitor(hwnd) != monIdx)
                    continue
            }

            style := WinGetStyle("ahk_id " hwnd)
            if (style & 0x01000000) || (WinGetMinMax("ahk_id " hwnd) == 1) {
                hasMaximized := true
                break
            }
        }

        if (hasMaximized) {
            this.OnClickLegacy()
            return
        }

        CoordMode("Mouse", "Screen")
        MouseGetPos(&mX, &mY)

        ; Collect eligible floating windows under cursor and across current workspace in top-to-bottom Z-order
        windowsUnderCursor := []
        allEligibleWindows := []
        for hwnd in WinGetList() {
            if !this.IsEligibleFloating(hwnd, monIdx, curWs)
                continue

            allEligibleWindows.Push(hwnd)

            try {
                WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
                if (mX >= wx && mX < (wx + ww) && mY >= wy && mY < (wy + wh)) {
                    windowsUnderCursor.Push(hwnd)
                }
            }
        }

        targetHwnd := 0

        if (windowsUnderCursor.Length >= 2) {
            isContinuation := false
            if ((A_TickCount - this.lastPeekTime < 2000)
                && (Abs(mX - this.lastX) < 15 && Abs(mY - this.lastY) < 15)
                && (this.cycleHwnds.Length >= 2)
                && this.cycleMode == "cursor") {
                allValid := true
                for h in this.cycleHwnds {
                    if !WinExist("ahk_id " h) {
                        allValid := false
                        break
                    }
                    try {
                        WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " h)
                        if (mX < wx || mX >= (wx + ww) || mY < wy || mY >= (wy + wh)) {
                            allValid := false
                            break
                        }
                    } catch {
                        allValid := false
                        break
                    }
                }
                if (allValid)
                    isContinuation := true
            }

            if (isContinuation) {
                this.cycleIndex++
                if (this.cycleIndex > this.cycleHwnds.Length)
                    this.cycleIndex := 1
                targetHwnd := this.cycleHwnds[this.cycleIndex]
            } else {
                this.cycleMode := "cursor"
                this.cycleHwnds := windowsUnderCursor
                this.cycleIndex := 2
                targetHwnd := windowsUnderCursor[2]
            }
        } else if (allEligibleWindows.Length >= 2) {
            isContinuation := false
            if ((A_TickCount - this.lastPeekTime < 2000)
                && (this.cycleHwnds.Length >= 2)
                && this.cycleMode == "workspace") {
                allValid := true
                for h in this.cycleHwnds {
                    if !WinExist("ahk_id " h) {
                        allValid := false
                        break
                    }
                }
                if (allValid)
                    isContinuation := true
            }

            if (isContinuation) {
                this.cycleIndex++
                if (this.cycleIndex > this.cycleHwnds.Length)
                    this.cycleIndex := 1
                targetHwnd := this.cycleHwnds[this.cycleIndex]
            } else {
                topHwnd := (windowsUnderCursor.Length > 0) ? windowsUnderCursor[1] : allEligibleWindows[1]
                ordered := []
                for h in allEligibleWindows {
                    if (h != topHwnd)
                        ordered.Push(h)
                }
                ordered.Push(topHwnd)

                this.cycleMode := "workspace"
                this.cycleHwnds := ordered
                this.cycleIndex := 1
                targetHwnd := ordered[1]
            }
        } else {
            this.Reset()
            return
        }

        if (targetHwnd && WinExist("ahk_id " targetHwnd)) {
            this.lastPeekTime := A_TickCount
            this.lastX := mX
            this.lastY := mY

            if (WinGetExStyle("ahk_id " targetHwnd) & 0x8)
                WinSetAlwaysOnTop(false, "ahk_id " targetHwnd)

            DllCall("user32\SetWindowPos", "ptr", targetHwnd, "ptr", 0, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0013)
            ForceActivateWindow(targetHwnd)
            CrossWorkspaceAltTab.RecordActiveWindow(targetHwnd)
            PocketManager.ApplyLayerHierarchy()
        }
    }

    /**
     * Legacy implementation executed when a maximized window exists on the workspace.
     */
    static OnClickLegacy() {
        global wsWindows, currentWorkspaces, Rules

        CoordMode("Mouse", "Screen")
        MouseGetPos(&mX, &mY)

        monIdx := GetCurrentTargetMonitor()
        curWs  := currentWorkspaces[monIdx]

        fgHwnd := DllCall("GetForegroundWindow", "ptr")
        if (fgHwnd) {
            fgRoot := DllCall("GetAncestor", "ptr", fgHwnd, "uint", 2, "ptr")
            fgHwnd := fgRoot ? fgRoot : fgHwnd
        }

        windowsUnderCursor := []
        candidateFloating := []

        for hwnd in WinGetList() {
            if !WinExist("ahk_id " hwnd) || !DllCall("IsWindowVisible", "ptr", hwnd) || IsWindowCloaked(hwnd)
                continue

            wClass := StrLower(WinGetClass("ahk_id " hwnd))
            if (Rules.systemClasses.Has(wClass) || wClass = "progman" || wClass = "workerw" || wClass = "shell_traywnd")
                continue

            if (WinGetTitle("ahk_id " hwnd) == "")
                continue

            if !IsMainWindow(hwnd)
                continue

            if wsWindows.Has(hwnd) {
                info := wsWindows[hwnd]
                if (info.mon != monIdx || info.ws != curWs || info.isOffscreen)
                    continue
            } else {
                if (GetWindowMonitor(hwnd) != monIdx)
                    continue
            }

            if this.IsPinnedWindow(hwnd)
                continue

            isFloat := this.IsFloatingWindow(hwnd)
            if (isFloat)
                candidateFloating.Push(hwnd)

            try {
                WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
                if (mX >= wx && mX < (wx + ww) && mY >= wy && mY < (wy + wh)) {
                    windowsUnderCursor.Push({ hwnd: hwnd, isFloat: isFloat })
                }
            }
        }

        fgIsPinned := (fgHwnd && this.IsPinnedWindow(fgHwnd))

        ; Send foreground floating window to HWND_BOTTOM so underlying windows emerge
        fgIsFloating := (fgHwnd && this.IsFloatingWindow(fgHwnd) && !fgIsPinned)
        if (fgIsFloating) {
            this.SendToBottom(fgHwnd)
        }

        targetHwnd := 0

        if (windowsUnderCursor.Length > 0) {
            fgIdx := 0
            for idx, item in windowsUnderCursor {
                if (item.hwnd == fgHwnd) {
                    fgIdx := idx
                    break
                }
            }

            if (fgIsFloating) {
                if (fgIdx > 0 && fgIdx < windowsUnderCursor.Length) {
                    targetHwnd := windowsUnderCursor[fgIdx + 1].hwnd
                } else if (fgIdx == 0 && windowsUnderCursor[1].hwnd != fgHwnd) {
                    targetHwnd := windowsUnderCursor[1].hwnd
                } else if (windowsUnderCursor.Length > 1) {
                    targetHwnd := (windowsUnderCursor[1].hwnd != fgHwnd) ? windowsUnderCursor[1].hwnd : windowsUnderCursor[2].hwnd
                }
            } else {
                for item in windowsUnderCursor {
                    if (item.isFloat && item.hwnd != fgHwnd) {
                        targetHwnd := item.hwnd
                        break
                    }
                }
            }
        }

        ; Fallback: Cycle through all floating windows on the workspace
        if (!targetHwnd && candidateFloating.Length > 0) {
            fgIdx := 0
            for idx, h in candidateFloating {
                if (h == fgHwnd) {
                    fgIdx := idx
                    break
                }
            }
            if (fgIdx > 0 && fgIdx < candidateFloating.Length)
                targetHwnd := candidateFloating[fgIdx + 1]
            else
                targetHwnd := candidateFloating[1]
        }

        if (targetHwnd && WinExist("ahk_id " targetHwnd) && targetHwnd != fgHwnd) {
            ForceActivateWindow(targetHwnd)
            PocketManager.ApplyLayerHierarchy()
        } else if (!targetHwnd && fgIsFloating) {
            SafeDesktopFocus()
        }
    }

    /**
     * Sends the window to the bottom of the Z-order stack (HWND_BOTTOM = 1).
     * @param hwnd Target window handle.
     */
    static SendToBottom(hwnd) {
        try {
            if !hwnd || !WinExist("ahk_id " hwnd)
                return

            if (WinGetExStyle("ahk_id " hwnd) & 0x8)
                WinSetAlwaysOnTop(false, "ahk_id " hwnd)

            ; HWND_BOTTOM = 1, SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE = 0x0013
            DllCall("SetWindowPos", "ptr", hwnd, "ptr", 1, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0013)
        }
    }

    static IsFloatingWindow(hwnd) {
        global Rules
        try {
            style := WinGetStyle("ahk_id " hwnd)
            if (style & 0x20000000) || (style & 0x01000000) ; WS_MINIMIZE || WS_MAXIMIZE
                return false

            procName := StrLower(WinGetProcessName("ahk_id " hwnd))
            if Rules.ignoreProcesses.Has(procName)
                return false

            winClass := StrLower(WinGetClass("ahk_id " hwnd))
            if Rules.systemClasses.Has(winClass)
                return false

            if (WinGetTitle("ahk_id " hwnd) == "")
                return false

            if !IsMainWindow(hwnd)
                return false

            monIdx := GetWindowMonitor(hwnd)
            mL := 0, mT := 0, mR := 0, mB := 0
            if MonitorGet(monIdx, &mL, &mT, &mR, &mB) {
                WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
                if (wx <= mL && wy <= mT && (wx + ww) >= mR && (wy + wh) >= mB)
                    return false
            }

            return true
        } catch {
            return false
        }
    }

    static IsTopLayerElement(hwnd) {
        global osdGlobalGui
        try {
            if !hwnd || !WinExist("ahk_id " hwnd)
                return false

            if PocketManager.IsInPocket(hwnd) || PocketManager.IsBorderHwnd(hwnd)
                return true

            if this.IsPinnedWindow(hwnd)
                return true

            if (osdGlobalGui && hwnd == osdGlobalGui.Hwnd)
                return true

            if (CrossWorkspaceAltTab.guiObj && hwnd == CrossWorkspaceAltTab.guiObj.Hwnd)
                return true

            if (OverviewController.overlayGui && hwnd == OverviewController.overlayGui.Hwnd)
                return true

            return false
        } catch {
            return false
        }
    }

    static IsPinnedWindow(hwnd) {
        global desktopStates, wsWindows
        try {
            if !hwnd || !WinExist("ahk_id " hwnd)
                return false

            if PocketManager.IsInPocket(hwnd) || PocketManager.IsBorderHwnd(hwnd)
                return true

            if (WinGetExStyle("ahk_id " hwnd) & 0x8) ; WS_EX_TOPMOST
                return true

            if wsWindows.Has(hwnd) {
                info := wsWindows[hwnd]
                stateKey := info.mon "_" info.ws
                if (desktopStates.Has(stateKey) && desktopStates[stateKey] && IsEligibleFloatingWindow(hwnd))
                    return true
            }
            return false
        } catch {
            return false
        }
    }

    static IsEligibleFloating(hwnd, monIdx, curWs) {
        global wsWindows, Rules
        try {
            if !hwnd || !WinExist("ahk_id " hwnd) || !DllCall("user32\IsWindowVisible", "ptr", hwnd) || IsWindowCloaked(hwnd)
                return false

            style := WinGetStyle("ahk_id " hwnd)
            if (style & 0x21000000) ; WS_MINIMIZE (0x20000000) || WS_MAXIMIZE (0x01000000)
                return false

            if (WinGetMinMax("ahk_id " hwnd) != 0)
                return false

            if this.IsTopLayerElement(hwnd)
                return false

            winClass := StrLower(WinGetClass("ahk_id " hwnd))
            if (Rules.systemClasses.Has(winClass) || winClass = "progman" || winClass = "workerw" || winClass = "shell_traywnd" || winClass = "shell_secondarytraywnd")
                return false

            procName := StrLower(WinGetProcessName("ahk_id " hwnd))
            if Rules.ignoreProcesses.Has(procName)
                return false

            if (WinGetTitle("ahk_id " hwnd) == "")
                return false

            if !IsMainWindow(hwnd)
                return false

            wMon := GetWindowMonitor(hwnd)
            mL := 0, mT := 0, mR := 0, mB := 0
            if MonitorGet(wMon, &mL, &mT, &mR, &mB) {
                WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
                if (wx <= mL && wy <= mT && (wx + ww) >= mR && (wy + wh) >= mB)
                    return false
            }

            if wsWindows.Has(hwnd) {
                info := wsWindows[hwnd]
                if (info.mon != monIdx || info.ws != curWs || info.isOffscreen)
                    return false
            } else {
                if (wMon != monIdx)
                    return false
            }

            return true
        } catch {
            return false
        }
    }
}
