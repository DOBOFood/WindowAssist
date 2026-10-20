#Requires AutoHotkey v2.0

class PocketManager {
    static pocketWindows := []
    static currentIndex := 0
    static borderGuis := Map()
    static borderHwndToTarget := Map()
    static lastCoords := Map()
    static lastAlpha := Map()
    static borderColor := "FFD700"
    static borderWidth := 3
    static isWatchdogRunning := false

    static Init() {
        if (!this.isWatchdogRunning) {
            this.isWatchdogRunning := true
            ; Run watchdog timer every 60ms to keep border geometry in sync without flooding message queues
            SetTimer(() => this.Watchdog(), 60)
        }
    }

    static IsBorderHwnd(hwnd) {
        return this.borderHwndToTarget.Has(hwnd)
    }

    static GetTargetFromBorder(hwnd) {
        return this.borderHwndToTarget.Has(hwnd) ? this.borderHwndToTarget[hwnd] : 0
    }

    static GetVisiblePocketWindow() {
        for h in this.pocketWindows {
            if WinExist("ahk_id " h) {
                if (DllCall("user32\IsWindowVisible", "ptr", h) && WinGetMinMax("ahk_id " h) != -1) {
                    return h
                }
            }
        }
        return 0
    }

    static HidePocketWindow(hwnd) {
        if (!hwnd || !WinExist("ahk_id " hwnd))
            return
        try WinSetTransparent("Off", "ahk_id " hwnd)
        if this.lastAlpha.Has(hwnd)
            this.lastAlpha.Delete(hwnd)
        try DllCall("ShowWindowAsync", "ptr", hwnd, "int", 6) ; SW_MINIMIZE
        if this.borderGuis.Has(hwnd) {
            try this.borderGuis[hwnd].Hide()
        }
    }

    ; Ensures at most one pocket window remains visible on screen at any given time
    static HideOtherPocketWindows(exceptHwnd := 0) {
        for h in this.pocketWindows {
            if (h != exceptHwnd && WinExist("ahk_id " h)) {
                this.HidePocketWindow(h)
            }
        }
    }

    static ToggleCurrentWindow() {
        activeHwnd := WinExist("A")
        if (!activeHwnd)
            return

        if this.IsBorderHwnd(activeHwnd)
            activeHwnd := this.GetTargetFromBorder(activeHwnd)

        rootHwnd := GetRootManagedWindow(activeHwnd)
        if (!rootHwnd)
            rootHwnd := activeHwnd

        this.ToggleWindow(rootHwnd)
    }

    static ToggleWindow(hwnd) {
        if (!hwnd || !WinExist("ahk_id " hwnd))
            return

        idx := this.FindIndex(hwnd)
        if (idx > 0) {
            this.RemoveWindow(hwnd)
        } else {
            this.AddWindow(hwnd)
        }
    }

    static AddWindow(hwnd) {
        global currentWorkspaces, wsWindows
        if (!hwnd || !WinExist("ahk_id " hwnd))
            return

        if (this.FindIndex(hwnd) > 0)
            return

        this.HideOtherPocketWindows(hwnd)

        this.pocketWindows.Push(hwnd)
        this.currentIndex := this.pocketWindows.Length

        ; Pocket windows detach from individual workspaces (ws := 0)
        mon := GetWindowMonitor(hwnd)
        if wsWindows.Has(hwnd) {
            wsWindows[hwnd].ws := 0
            wsWindows[hwnd].mon := mon
            wsWindows[hwnd].isOffscreen := false
            SaveWindowProps(hwnd, wsWindows[hwnd])
        }

        ; If Overview is open, keep pocket window hidden so it does not occlude the overview canvas
        if (OverviewController.isOpen) {
            this.HidePocketWindow(hwnd)
        } else {
            try WinSetAlwaysOnTop(true, "ahk_id " hwnd)
            try WinActivate("ahk_id " hwnd)
            this.UpdateBorder(hwnd)
            this.ApplyLayerHierarchy()
        }

        this.Init()
        this.NotifyOverview()
    }

    static RemoveWindow(hwnd) {
        global currentWorkspaces, wsWindows
        idx := this.FindIndex(hwnd)
        if (idx == 0)
            return

        this.pocketWindows.RemoveAt(idx)
        if (this.pocketWindows.Length == 0) {
            this.currentIndex := 0
        } else if (this.currentIndex > this.pocketWindows.Length) {
            this.currentIndex := this.pocketWindows.Length
        }

        try WinSetTransparent("Off", "ahk_id " hwnd)
        if this.lastAlpha.Has(hwnd)
            this.lastAlpha.Delete(hwnd)

        this.RemoveBorder(hwnd)
        try WinSetAlwaysOnTop(false, "ahk_id " hwnd)
        try DllCall("user32\SetWindowPos", "ptr", hwnd, "ptr", -2, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0003) ; HWND_NOTOPMOST

        ; Restored window re-attaches to the currently active desktop on its monitor
        mon := GetWindowMonitor(hwnd)
        curWs := currentWorkspaces.Has(mon) ? currentWorkspaces[mon] : 1
        if wsWindows.Has(hwnd) {
            wsWindows[hwnd].ws := curWs
            wsWindows[hwnd].mon := mon
            wsWindows[hwnd].isOffscreen := false
            SaveWindowProps(hwnd, wsWindows[hwnd])
        }

        this.NotifyOverview()
    }

    /**
     * Cycles through pocket windows sequentially:
     * - If no pocket window is currently visible, summons the current one without stepping.
     * - If a pocket window is already active, conceals it and advances to the next entry.
     */
    static Cycle() {
        this.CleanupDeadWindows()
        count := this.pocketWindows.Length
        if (count == 0)
            return

        visibleHwnd := this.GetVisiblePocketWindow()

        if (!visibleHwnd) {
            if (this.currentIndex < 1 || this.currentIndex > count)
                this.currentIndex := 1

            targetHwnd := this.pocketWindows[this.currentIndex]
            this.ActivatePocketWindow(targetHwnd)
            return
        }

        if (count == 1) {
            targetHwnd := this.pocketWindows[1]
            this.ActivatePocketWindow(targetHwnd)
            return
        }

        this.HidePocketWindow(visibleHwnd)

        curPos := this.FindIndex(visibleHwnd)
        if (curPos > 0)
            this.currentIndex := curPos

        this.currentIndex += 1
        if (this.currentIndex > count)
            this.currentIndex := 1

        targetHwnd := this.pocketWindows[this.currentIndex]
        this.ActivatePocketWindow(targetHwnd)
    }

    /**
     * Toggles the visibility of the current pocket scratchpad window.
     * Hides if already visible and active; otherwise displays and brings to front.
     */
    static ToggleSummon() {
        this.CleanupDeadWindows()
        count := this.pocketWindows.Length
        if (count == 0)
            return

        if (this.currentIndex < 1 || this.currentIndex > count)
            this.currentIndex := 1

        targetHwnd := this.pocketWindows[this.currentIndex]
        if (!targetHwnd || !WinExist("ahk_id " targetHwnd))
            return

        activeHwnd := WinExist("A")
        if this.IsBorderHwnd(activeHwnd)
            activeHwnd := this.GetTargetFromBorder(activeHwnd)

        style := WinGetStyle("ahk_id " targetHwnd)
        isMinimized := (style & 0x20000000) ; WS_MINIMIZE

        if (activeHwnd == targetHwnd && !isMinimized) {
            this.HidePocketWindow(targetHwnd)
        } else {
            this.HideOtherPocketWindows(targetHwnd)
            this.ActivatePocketWindow(targetHwnd)
        }
    }

    static ActivatePocketWindow(hwnd) {
        global currentWorkspaces, wsWindows
        if (!hwnd || !WinExist("ahk_id " hwnd))
            return

        this.HideOtherPocketWindows(hwnd)

        mon := GetWindowMonitor(hwnd)
        if wsWindows.Has(hwnd) {
            wsWindows[hwnd].ws := 0
            wsWindows[hwnd].mon := mon
            wsWindows[hwnd].isOffscreen := false
            SaveWindowProps(hwnd, wsWindows[hwnd])
        }

        SetWindowVisibility(hwnd, true)
        try {
            style := WinGetStyle("ahk_id " hwnd)
            if (style & 0x20000000) ; WS_MINIMIZE
                DllCall("ShowWindowAsync", "ptr", hwnd, "int", 9) ; SW_RESTORE
            
            WinSetAlwaysOnTop(true, "ahk_id " hwnd)
            ForceActivateWindow(hwnd)
        }

        this.lastAlpha[hwnd] := 255
        try WinSetTransparent("Off", "ahk_id " hwnd)
        if this.borderGuis.Has(hwnd) {
            try WinSetTransparent("Off", "ahk_id " this.borderGuis[hwnd].Hwnd)
        }

        this.UpdateBorder(hwnd)
        this.ApplyLayerHierarchy()
    }

    static IsInPocket(hwnd) {
        return (this.FindIndex(hwnd) > 0)
    }

    static FindIndex(hwnd) {
        for idx, h in this.pocketWindows {
            if (h == hwnd)
                return idx
        }
        return 0
    }

    static CleanupDeadWindows() {
        toRemove := []
        for h in this.pocketWindows {
            if (!WinExist("ahk_id " h))
                toRemove.Push(h)
        }
        for h in toRemove
            this.RemoveWindow(h)
    }

    static OnWorkspaceSwitched(targetMon, targetWs) {
        global wsWindows
        visibleHwnd := this.GetVisiblePocketWindow()

        for hwnd in this.pocketWindows {
            if WinExist("ahk_id " hwnd) {
                if wsWindows.Has(hwnd) {
                    wsWindows[hwnd].mon := targetMon
                    wsWindows[hwnd].ws := 0
                    wsWindows[hwnd].isOffscreen := false
                    SaveWindowProps(hwnd, wsWindows[hwnd])
                }
                if (hwnd == visibleHwnd) {
                    SetWindowVisibility(hwnd, true)
                    this.UpdateBorder(hwnd)
                } else {
                    this.HidePocketWindow(hwnd)
                }
            }
        }
        this.ApplyLayerHierarchy()
    }

    ; Dim pocket window to 50% opacity (128) when unfocused to keep desktop legible
    static UpdateTransparency(h) {
        if (!h || !WinExist("ahk_id " h))
            return
        fgHwnd := DllCall("GetForegroundWindow", "ptr")
        isFocused := (fgHwnd && (fgHwnd == h || IsWindowOrChildOf(fgHwnd, h)))
        targetAlpha := isFocused ? 255 : 128
        currAlpha := this.lastAlpha.Has(h) ? this.lastAlpha[h] : 255
        if (currAlpha != targetAlpha) {
            this.lastAlpha[h] := targetAlpha
            try WinSetTransparent(isFocused ? "Off" : targetAlpha, "ahk_id " h)
            if this.borderGuis.Has(h) {
                try WinSetTransparent(isFocused ? "Off" : targetAlpha, "ahk_id " this.borderGuis[h].Hwnd)
            }
        }
    }

    /**
     * Enforces Z-order layer hierarchy:
     * Pinned normal windows -> Pocket window -> Pocket border -> OSD -> Overview canvas
     */
    static ApplyLayerHierarchy() {
        global osdGlobalGui
        pocketHwnd := this.GetVisiblePocketWindow()
        if (!pocketHwnd || !WinExist("ahk_id " pocketHwnd))
            return

        ; 1. Keep pocket window at HWND_TOPMOST
        if !(WinGetExStyle("ahk_id " pocketHwnd) & 0x8)
            WinSetAlwaysOnTop(true, "ahk_id " pocketHwnd)
        DllCall("user32\SetWindowPos", "ptr", pocketHwnd, "ptr", -1, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0013) ; HWND_TOPMOST | SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE

        ; 2. Ensure pocket outline remains immediately above pocket window
        if this.borderGuis.Has(pocketHwnd) {
            g := this.borderGuis[pocketHwnd]
            if (DllCall("user32\IsWindow", "ptr", g.Hwnd, "int")) {
                DllCall("user32\SetWindowPos", "ptr", g.Hwnd, "ptr", -1, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0013)
            }
        }

        ; 3. Lower standard pinned windows underneath the pocket window
        this.LowerPinnedWindowsUnderPocket()

        ; 4. Synchronize opacity based on focus
        this.UpdateTransparency(pocketHwnd)

        ; 5. Elevate OSD HUD above pocket window
        if (osdGlobalGui && DllCall("user32\IsWindow", "ptr", osdGlobalGui.Hwnd, "int") && DllCall("user32\IsWindowVisible", "ptr", osdGlobalGui.Hwnd, "int")) {
            DllCall("user32\SetWindowPos", "ptr", osdGlobalGui.Hwnd, "ptr", -1, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0013)
        }

        ; 6. Maintain Overview overlay at the supreme top layer
        if (OverviewController.isOpen) {
            OverviewController.EnsureTopmost()
        }
    }

    static EnsurePocketTopmost() {
        this.ApplyLayerHierarchy()
    }

    static LowerPinnedWindowsUnderPocket() {
        global wsWindows, desktopStates, Rules
        pocketHwnd := this.GetVisiblePocketWindow()
        if (!pocketHwnd || !WinExist("ahk_id " pocketHwnd))
            return

        pinnedList := []
        for hwnd in WinGetList() {
            if (!hwnd || hwnd == pocketHwnd || !WinExist("ahk_id " hwnd))
                continue

            if this.IsInPocket(hwnd) || this.IsBorderHwnd(hwnd)
                continue

            if (OverviewController.isOpen && OverviewController.overlayGui && hwnd == OverviewController.overlayGui.Hwnd)
                continue

            try {
                if (!DllCall("user32\IsWindowVisible", "ptr", hwnd) || IsWindowCloaked(hwnd))
                    continue

                style := WinGetStyle("ahk_id " hwnd)
                if (style & 0x20000000) ; WS_MINIMIZE
                    continue

                winClass := StrLower(WinGetClass("ahk_id " hwnd))
                if (Rules.systemClasses.Has(winClass) || winClass = "shell_traywnd" || winClass = "shell_secondarytraywnd")
                    continue

                if (wsWindows.Has(hwnd) && wsWindows[hwnd].isOffscreen)
                    continue

                exStyle := WinGetExStyle("ahk_id " hwnd)
                isTop := (exStyle & 0x8) ; WS_EX_TOPMOST

                isPinned := isTop
                if (!isPinned && wsWindows.Has(hwnd)) {
                    info := wsWindows[hwnd]
                    stateKey := info.mon "_" info.ws
                    if (desktopStates.Has(stateKey) && desktopStates[stateKey] && IsEligibleFloatingWindow(hwnd))
                        isPinned := true
                }

                if (isPinned) {
                    pinnedList.Push(hwnd)
                }
            }
        }

        lastHwnd := pocketHwnd
        for pHwnd in pinnedList {
            DllCall("user32\SetWindowPos", "ptr", pHwnd, "ptr", lastHwnd, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0013) ; SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE
            lastHwnd := pHwnd
        }
    }

    static UpdateBorder(hwnd) {
        if (!hwnd || !WinExist("ahk_id " hwnd) || !DllCall("user32\IsWindowVisible", "ptr", hwnd)) {
            this.RemoveBorder(hwnd)
            return
        }

        if (OverviewController.isOpen) {
            if this.borderGuis.Has(hwnd) {
                try this.borderGuis[hwnd].Hide()
            }
            return
        }

        style := WinGetStyle("ahk_id " hwnd)
        if (style & 0x20000000) { ; WS_MINIMIZE
            if this.borderGuis.Has(hwnd) {
                try this.borderGuis[hwnd].Hide()
            }
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
            this.RemoveBorder(hwnd)
            return
        }

        last := this.lastCoords.Has(hwnd) ? this.lastCoords[hwnd] : {x: 0, y: 0, w: 0, h: 0}
        sizeChanged := (last.w != ww || last.h != wh)
        posChanged := (last.x != wx || last.y != wy)

        bw := this.borderWidth
        g := 0
        if (this.borderGuis.Has(hwnd) && DllCall("user32\IsWindow", "ptr", this.borderGuis[hwnd].Hwnd, "int")) {
            g := this.borderGuis[hwnd]
        } else {
            if this.borderGuis.Has(hwnd) {
                oldG := this.borderGuis[hwnd]
                if this.borderHwndToTarget.Has(oldG.Hwnd)
                    this.borderHwndToTarget.Delete(oldG.Hwnd)
                try oldG.Destroy()
                this.borderGuis.Delete(hwnd)
            }

            ; Standalone AlwaysOnTop GUI window (+E0x20 transparent to input, +E0x08000000 unactivatable)
            g := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20 +E0x08000000")
            g.BackColor := this.borderColor
            this.borderGuis[hwnd] := g
            this.borderHwndToTarget[g.Hwnd] := hwnd
            sizeChanged := true
        }

        ; Recompute window region cutout only when dimensions change
        if (sizeChanged) {
            hRgnOuter := DllCall("gdi32\CreateRectRgn", "int", 0, "int", 0, "int", ww, "int", wh, "ptr")
            hRgnInner := DllCall("gdi32\CreateRectRgn", "int", bw, "int", bw, "int", ww - bw, "int", wh - bw, "ptr")
            hRgnDiff  := DllCall("gdi32\CreateRectRgn", "int", 0, "int", 0, "int", 0, "int", 0, "ptr")
            DllCall("gdi32\CombineRgn", "ptr", hRgnDiff, "ptr", hRgnOuter, "ptr", hRgnInner, "int", 4)
            DllCall("user32\SetWindowRgn", "ptr", g.Hwnd, "ptr", hRgnDiff, "int", 1)
            DllCall("gdi32\DeleteObject", "ptr", hRgnOuter)
            DllCall("gdi32\DeleteObject", "ptr", hRgnInner)
        }

        if (posChanged || sizeChanged || !DllCall("user32\IsWindowVisible", "ptr", g.Hwnd)) {
            g.Show("x" wx " y" wy " w" ww " h" wh " NoActivate")
            this.lastCoords[hwnd] := {x: wx, y: wy, w: ww, h: wh}
            DllCall("user32\SetWindowPos", "ptr", g.Hwnd, "ptr", -1, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0013) ; SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE
            if (this.lastAlpha.Has(hwnd) && this.lastAlpha[hwnd] != 255) {
                try WinSetTransparent(this.lastAlpha[hwnd], "ahk_id " g.Hwnd)
            }
        }
    }

    static RemoveBorder(hwnd) {
        if this.borderGuis.Has(hwnd) {
            g := this.borderGuis[hwnd]
            if this.borderHwndToTarget.Has(g.Hwnd)
                this.borderHwndToTarget.Delete(g.Hwnd)
            try g.Destroy()
            this.borderGuis.Delete(hwnd)
        }
        if this.lastCoords.Has(hwnd)
            this.lastCoords.Delete(hwnd)
        if this.lastAlpha.Has(hwnd)
            this.lastAlpha.Delete(hwnd)
    }

    static Watchdog() {
        this.CleanupDeadWindows()
        if (this.pocketWindows.Length == 0)
            return

        visibleHwnd := this.GetVisiblePocketWindow()
        if (visibleHwnd) {
            this.HideOtherPocketWindows(visibleHwnd)
        }

        for h in this.pocketWindows {
            if WinExist("ahk_id " h) {
                if (h == visibleHwnd) {
                    isTop := (WinGetExStyle("ahk_id " h) & 0x8)
                    if (!isTop) {
                        try WinSetAlwaysOnTop(true, "ahk_id " h)
                    }
                    this.UpdateBorder(h)
                    this.UpdateTransparency(h)
                } else {
                    if this.borderGuis.Has(h) {
                        try this.borderGuis[h].Hide()
                    }
                }
            }
        }
    }

    static NotifyOverview() {
        if (OverviewController.isOpen) {
            SetTimer(() => OverviewController.PushStateToWeb(OverviewController.currentMon), -50)
        }
    }

    static GetOverviewData() {
        this.CleanupDeadWindows()
        res := []
        for hwnd in this.pocketWindows {
            if WinExist("ahk_id " hwnd) {
                title := WinGetTitle("ahk_id " hwnd)
                if (title == "")
                    title := WinGetProcessName("ahk_id " hwnd)

                iconB64 := ""
                try iconB64 := CaptureEngine.GetWindowIconBase64(hwnd)

                res.Push(Map(
                    "hwnd", hwnd,
                    "title", title,
                    "icon", iconB64,
                    "hasPreview", false
                ))
            }
        }
        return res
    }
}
