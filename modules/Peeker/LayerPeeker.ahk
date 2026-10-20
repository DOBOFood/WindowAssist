#Requires AutoHotkey v2.0

class LayerPeeker {
    /**
     * Cycles overlapping floating windows directly under the mouse cursor.
     */
    static OnClick() {
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

    static Reset() {
    }
}
