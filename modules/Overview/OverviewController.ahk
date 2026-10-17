#Requires AutoHotkey v2.0

class OverviewController {
    static isOpen := false
    static overlayGui := 0
    static webInstance := 0
    static currentMon := 1

    static Toggle() {
        if (this.isOpen)
            this.Close()
        else
            this.Open()
    }

    static Open() {
        global maxWorkspacesPerMon, currentWorkspaces, wsWindows
        if (this.isOpen)
            return

        monIdx := GetCurrentTargetMonitor()
        this.currentMon := monIdx

        mL := 0, mT := 0, mR := 0, mB := 0
        MonitorGet(monIdx, &mL, &mT, &mR, &mB)
        w := mR - mL, h := mB - mT

        this.isOpen := true

        ; Окно + WebView2 создаём ОДИН раз и дальше переиспользуем
        if (!this.overlayGui || !this.webInstance) {
            this.overlayGui := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale")
            this.overlayGui.BackColor := "000000"

            ; DWM Glass / композиция на всю область окна для прозрачности WebView2
            try {
                ovHwnd := this.overlayGui.Hwnd
                margins := Buffer(16, 0)
                NumPut('int', -1, 'int', -1, 'int', -1, 'int', -1, margins)
                DllCall('dwmapi\DwmExtendFrameIntoClientArea', 'ptr', ovHwnd, 'ptr', margins)
            }

            this.overlayGui.OnEvent("Size", (guiObj, minMax, newW, newH) => WebViewManager.Resize(this.webInstance, newW, newH))

            htmlFile := A_ScriptDir "\web\overview.html"
            this.webInstance := WebViewManager.Create(
                this.overlayGui.Hwnd,
                htmlFile,
                ObjBindMethod(this, "OnIPCMessage")
            )

            if (!this.webInstance) {
                this.isOpen := false
                this.overlayGui.Destroy()
                this.overlayGui := 0
                return
            }
        }

        ; Отображаем окно с актуальными размерами текущего монитора мгновенно
        this.overlayGui.Show("x" mL " y" mT " w" w " h" h)
        DllCall("user32\SetForegroundWindow", "ptr", this.overlayGui.Hwnd)

        ; Хоткей Esc для закрытия
        HotIfWinActive("ahk_id " this.overlayGui.Hwnd)
        Hotkey("Escape", (*) => OverviewController.Close(), "On")
        HotIfWinActive()

        ; Скрываем рамки окон кармана, чтобы они находились строго под Overview
        for h in PocketManager.pocketWindows {
            if PocketManager.borderGuis.Has(h) {
                try PocketManager.borderGuis[h].Hide()
            }
        }

        ; Отправка актуальных столов текущего монитора
        this.PushStateToWeb(monIdx)
    }

    static EnsureTopmost() {
        if (this.isOpen && this.overlayGui) {
            DllCall("user32\SetWindowPos", "ptr", this.overlayGui.Hwnd, "ptr", -1, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0013) ; SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE
        }
    }

    static Close() {
        if (!this.isOpen)
            return
        this.isOpen := false
        if (this.overlayGui) {
            try {
                HotIfWinActive("ahk_id " this.overlayGui.Hwnd)
                Hotkey("Escape", "Off")
                HotIfWinActive()
            }
            ; Прячем окно без уничтожения WebView2 для мгновенного повторного открытия
            this.overlayGui.Hide()
        }

        ; Восстанавливаем рамки окон кармана при закрытии Overview
        for h in PocketManager.pocketWindows {
            PocketManager.UpdateBorder(h)
        }
    }

    static MoveToMonitor(monIdx) {
        if (!this.isOpen || !this.overlayGui)
            return

        this.currentMon := monIdx

        mL := 0, mT := 0, mR := 0, mB := 0
        MonitorGet(monIdx, &mL, &mT, &mR, &mB)
        w := mR - mL, h := mB - mT

        this.overlayGui.Show("x" mL " y" mT " w" w " h" h)
        DllCall("user32\SetForegroundWindow", "ptr", this.overlayGui.Hwnd)

        this.PushStateToWeb(monIdx)
    }

    static PushStateToWeb(monIdx := 0) {
        global maxWorkspacesPerMon, currentWorkspaces, wsWindows
        if (!this.webInstance)
            return

        if (!monIdx)
            monIdx := this.currentMon ? this.currentMon : GetCurrentTargetMonitor()

        this.currentMon := monIdx
        curWs := currentWorkspaces.Has(monIdx) ? currentWorkspaces[monIdx] : 1
        totalWs := maxWorkspacesPerMon.Has(monIdx) ? maxWorkspacesPerMon[monIdx] : 8

        workspacesArr := []
        Loop totalWs {
            wsNum := A_Index
            appCards := []

            for hwnd, info in wsWindows {
                if (info.mon == monIdx && info.ws == wsNum && WinExist("ahk_id " hwnd)) {
                    title := WinGetTitle("ahk_id " hwnd)
                    if (title == "")
                        title := WinGetProcessName("ahk_id " hwnd)

                    ; Быстрое получение иконки окна
                    iconB64 := ""
                    try iconB64 := CaptureEngine.GetWindowIconBase64(hwnd)

                    isFloating := (info.HasProp("isFloating") && info.isFloating)

                    appCards.Push(Map(
                        "hwnd", hwnd,
                        "title", title,
                        "icon", iconB64,
                        "hasPreview", false,
                        "isFloating", isFloating
                    ))
                }
            }

            workspacesArr.Push(Map(
                "id", wsNum,
                "name", "Стол " wsNum,
                "apps", appCards
            ))
        }

        pocketApps := PocketManager.GetOverviewData()

        animDuration := ConfigManager.Get("appearance.animationDurationMs", 200)
        appColors := ConfigManager.Get("appearance.colors", Map())
        appLang := ConfigManager.Get("language", "en")

        payload := Map(
            "action", "INIT_STATE",
            "currentWs", curWs,
            "workspaces", workspacesArr,
            "pocketApps", pocketApps,
            "animDuration", animDuration,
            "colors", appColors,
            "language", appLang
        )
        WebViewManager.Send(this.webInstance, payload)
    }

    static OnIPCMessage(data) {
        global currentWorkspaces, maxWorkspacesPerMon, wsWindows
        if !(data is Map) || !data.Has("action")
            return

        action := data["action"]

        if (action == "DOM_READY") {
            this.PushStateToWeb(this.currentMon)
        }
        else if (action == "GET_PREVIEW") {
            hwnd := Integer(data["hwnd"])
            if WinExist("ahk_id " hwnd) {
                previewB64 := ""
                try previewB64 := CaptureEngine.CaptureWindowBase64(hwnd)
                if (previewB64 != "") {
                    WebViewManager.Send(this.webInstance, Map(
                        "action", "PREVIEW_RESULT",
                        "hwnd", hwnd,
                        "preview", previewB64
                    ))
                }
            }
        }
        else if (action == "SWITCH_WORKSPACE") {
            targetWs := Integer(data["targetWs"])
            monIdx := this.currentMon ? this.currentMon : GetCurrentTargetMonitor()
            this.Close()
            SwitchWorkspace(monIdx, targetWs)
        }
        else if (action == "SWITCH_TO_WINDOW") {
            hwnd := Integer(data["hwnd"])
            this.Close()
            if WinExist("ahk_id " hwnd) {
                if PocketManager.IsInPocket(hwnd) {
                    PocketManager.ActivatePocketWindow(hwnd)
                } else {
                    if wsWindows.Has(hwnd) {
                        info := wsWindows[hwnd]
                        if (currentWorkspaces[info.mon] != info.ws)
                            SwitchWorkspace(info.mon, info.ws)
                    }
                    ForceActivateWindow(hwnd)
                }
            }
        }
        else if (action == "REMOVE_FROM_POCKET") {
            hwnd := Integer(data["hwnd"])
            PocketManager.RemoveWindow(hwnd)
        }
        else if (action == "ADD_TO_POCKET") {
            hwndsToAdd := []
            if data.Has("hwnds") {
                val := data["hwnds"]
                if (val is Array) {
                    for h in val
                        hwndsToAdd.Push(Integer(h))
                } else if (val is Map) {
                    for k, v in val
                        hwndsToAdd.Push(Integer(v))
                } else if (val is String) {
                    for part in StrSplit(val, [",", ";", " "]) {
                        trimmed := Trim(part)
                        if (trimmed != "")
                            hwndsToAdd.Push(Integer(trimmed))
                    }
                } else if IsNumber(val) {
                    hwndsToAdd.Push(Integer(val))
                }
            } else if data.Has("hwnd") {
                hwndsToAdd.Push(Integer(data["hwnd"]))
            }

            for hwnd in hwndsToAdd {
                PocketManager.AddWindow(hwnd)
            }
            ; Используем асинхронный вызов, чтобы не блокировать UI
            SetTimer(() => this.PushStateToWeb(this.currentMon), -50)
        }
        else if (action == "CLOSE_WINDOW_AHK") {
            hwnd := Integer(data["hwnd"])
            if WinExist("ahk_id " hwnd) {
                PocketManager.RemoveWindow(hwnd)
                PostMessage(0x0010, 0, 0,, "ahk_id " hwnd) ; WM_CLOSE
            }
            SetTimer(() => this.PushStateToWeb(this.currentMon), -100)
        }
        else if (action == "MAXIMIZE_WINDOW_AHK") {
            hwnd := Integer(data["hwnd"])
            if WinExist("ahk_id " hwnd) {
                this.Close()
                if (WinGetMinMax("ahk_id " hwnd) == 1)
                    DllCall("ShowWindowAsync", "ptr", hwnd, "int", 9) ; SW_RESTORE
                else
                    DllCall("ShowWindowAsync", "ptr", hwnd, "int", 3) ; SW_MAXIMIZE
                ForceActivateWindow(hwnd)
            }
        }
        else if (action == "MINIMIZE_WINDOW_AHK") {
            hwnd := Integer(data["hwnd"])
            if WinExist("ahk_id " hwnd)
                DllCall("ShowWindowAsync", "ptr", hwnd, "int", 6) ; SW_MINIMIZE
            SetTimer(() => this.PushStateToWeb(this.currentMon), -100)
        }
        else if (action == "RESET_WINDOW_POS_AHK") {
            hwnd := Integer(data["hwnd"])
            if WinExist("ahk_id " hwnd) {
                this.CenterWindow(hwnd)
                this.PushStateToWeb(this.currentMon)
            }
        }
        else if (action == "ADD_WORKSPACE") {
            monIdx := this.currentMon ? this.currentMon : GetCurrentTargetMonitor()
            maxWs := maxWorkspacesPerMon.Has(monIdx) ? maxWorkspacesPerMon[monIdx] : 8
            if (maxWs < 9) {
                maxWorkspacesPerMon[monIdx] := maxWs + 1
                ConfigManager.Set("workspaces.maxWorkspacesPerMonitor", maxWorkspacesPerMon)
                this.PushStateToWeb(monIdx)
            }
        }
        else if (action == "DELETE_WORKSPACE") {
            wsToDelete := Integer(data["targetWs"])
            monIdx := this.currentMon ? this.currentMon : GetCurrentTargetMonitor()
            maxWs := maxWorkspacesPerMon.Has(monIdx) ? maxWorkspacesPerMon[monIdx] : 8

            if (maxWs <= 1)
                return

            fallbackWs := (wsToDelete > 1) ? wsToDelete - 1 : 1

            for hwnd, info in wsWindows {
                if (info.mon == monIdx) {
                    if (info.ws == wsToDelete) {
                        info.ws := fallbackWs
                        SaveWindowProps(hwnd, info)
                    } else if (info.ws > wsToDelete) {
                        info.ws -= 1
                        SaveWindowProps(hwnd, info)
                    }
                }
            }

            maxWorkspacesPerMon[monIdx] := maxWs - 1
            ConfigManager.Set("workspaces.maxWorkspacesPerMonitor", maxWorkspacesPerMon)
            
            if (currentWorkspaces[monIdx] >= wsToDelete && currentWorkspaces[monIdx] > 1)
                currentWorkspaces[monIdx] -= 1

            this.PushStateToWeb(monIdx)
        }
        else if (action == "OPEN_SETTINGS") {
            this.Close()
            SetTimer(() => OpenSettingsWindow(), -50)
        }
        else if (action == "CLOSE_OVERVIEW") {
            this.Close()
        }
        else if (action == "MOVE_WINDOW") {
            targetWs := Integer(data["targetWs"])
            hwndsToMove := []

            if data.Has("hwnds") {
                val := data["hwnds"]
                if (val is Array) {
                    for h in val
                        hwndsToMove.Push(Integer(h))
                } else if (val is Map) {
                    for k, v in val
                        hwndsToMove.Push(Integer(v))
                } else if (val is String) {
                    for part in StrSplit(val, [",", ";", " "]) {
                        trimmed := Trim(part)
                        if (trimmed != "")
                            hwndsToMove.Push(Integer(trimmed))
                    }
                } else if IsNumber(val) {
                    hwndsToMove.Push(Integer(val))
                }
            } else if data.Has("hwnd") {
                hwndsToMove.Push(Integer(data["hwnd"]))
            }

            monToUpdate := 0
            for hwnd in hwndsToMove {
                if wsWindows.Has(hwnd) {
                    info := wsWindows[hwnd]
                    info.ws := targetWs
                    SaveWindowProps(hwnd, info)
                    
                    curWs := currentWorkspaces[info.mon]
                    if (curWs == targetWs) {
                        if (info.isOffscreen) {
                            SetWindowVisibility(hwnd, true)
                            info.isOffscreen := false
                        }
                    } else {
                        if (!info.isOffscreen) {
                            SetWindowVisibility(hwnd, false)
                            info.isOffscreen := true
                        }
                    }
                    monToUpdate := info.mon
                }
            }

            if (monToUpdate)
                SetTimer(() => this.PushStateToWeb(monToUpdate), -50)
        }
    }

    static CenterWindow(hwnd) {
        global wsWindows
        if (!hwnd || !WinExist("ahk_id " hwnd))
            return

        wMon := GetWindowMonitor(hwnd)
        mL := 0, mT := 0, mR := 0, mB := 0
        MonitorGetWorkArea(wMon, &mL, &mT, &mR, &mB)
        monW := mR - mL, monH := mB - mT

        targetW := Round(monW * 0.7)
        targetH := Round(monH * 0.7)
        targetX := mL + Round((monW - targetW) / 2)
        targetY := mT + Round((monH - targetH) / 2)

        try {
            DllCall("ShowWindowAsync", "ptr", hwnd, "int", 9) ; SW_RESTORE
            DllCall("user32\SetWindowPos", "ptr", hwnd, "ptr", 0, "int", targetX, "int", targetY, "int", targetW, "int", targetH, "uint", 0x4000) ; SWP_ASYNCWINDOWPOS
        }

        if wsWindows.Has(hwnd) {
            info := wsWindows[hwnd]
            info.x := targetX
            info.y := targetY
            info.w := targetW
            info.h := targetH
            info.isMax := false
            SaveWindowProps(hwnd, info)
        }
    }
}
