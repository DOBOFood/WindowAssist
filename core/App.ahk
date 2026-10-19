#Requires AutoHotkey v2.0

class App {
    static Init() {
        global hWinEventHook, winEventCallback, hMouseHook, mouseEventCallback

        if !A_IsAdmin {
            try Run('*RunAs "' A_ScriptFullPath '"')
            ExitApp()
        }

        try {
            RegWrite(0, "REG_DWORD", "HKEY_CURRENT_USER\Control Panel\Desktop", "ForegroundFlashCount")
            RegWrite(0, "REG_DWORD", "HKEY_CURRENT_USER\Control Panel\Desktop", "ForegroundLockTimeout")
        }

        ConfigManager.Load()

        ; Восстановление состояния после Reload
        hasRestoredState := LoadState()

        if (!hasRestoredState)
            RecoverAllOffscreenWindows(false)

        ; Регистрация уже существующих окон
        InitExistingWindows()

        ; Инициализация хуков и обработчиков
        WindowTracker.Init()
        HotkeyManager.Init()
        global hasHooksInitialized
        hasHooksInitialized := true
        
        ; Инициализация кастомного Alt+Tab
        CrossWorkspaceAltTab.Init()

        OnExit(ObjBindMethod(this, "CleanExit"))
    }

    static CleanExit(ExitReason, ExitCode) {
        global hWinEventHook, winEventCallback, hMouseHook, mouseEventCallback

        WindowTracker.UnHook()
        DllCall("winmm\timeEndPeriod", "uint", 1)
        ReleaseCursorClip()
        
        ; Закрываем оверлей Overview и выгружаем GDI+
        OverviewController.Close()
        CaptureEngine.Shutdown()

        ; Сохраняем состояние столов и окон в state.json перед выходом
        SaveState()

        ; При перезагрузке не сбрасываем окна на экран
        if (ExitReason == "Reload") {
            return
        }

        ; При полном выходе: возвращаем окна и рамки
        RestoreAllTitleBars()
        RecoverAllOffscreenWindows(true)
        ConfigManager.ApplyTaskbarVisibility(false)
    }
}

ShowOSD(text) {
    global currentWorkspaces, osdGlobalGui
    static osdGui    := ""
    static osdText   := ""
    static hideTimer := ""
    static lastFontSize := 0

    fontSize := ConfigManager.Get("general.osd.fontSize", 13)
    posMode := ConfigManager.Get("general.osd.position", "bottom_center")
    posYPercent := ConfigManager.Get("general.osd.posYPercent", 82)
    hideDelay := ConfigManager.Get("general.osd.hideDelayMs", 400)

    padX := Max(10, Round(fontSize * 0.9))
    padY := Max(6, Round(fontSize * 0.45))

    if (!osdGui || fontSize != lastFontSize) {
        if (osdGui) {
            try osdGui.Destroy()
        }
        osdGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x08000000")
        osdGlobalGui := osdGui
        osdGui.BackColor := "1A1A1A"
        osdGui.MarginX := padX
        osdGui.MarginY := padY
        osdGui.SetFont("s" fontSize " cWhite Bold", "Segoe UI")
        if InStr(text, "`n")
            osdText := osdGui.Add("Text", "Center w360", text)
        else
            osdText := osdGui.Add("Text", "Center", text)
        lastFontSize := fontSize
    } else {
        if InStr(text, "`n")
            osdText.Move(,, 360)
        osdText.Value := text
    }

    try {
        monIdx := GetCurrentTargetMonitor()
        left := 0, top := 0, right := 0, bottom := 0
        MonitorGetWorkArea(monIdx, &left, &top, &right, &bottom)
        mW := right - left
        mH := bottom - top
        
        osdGui.Show("AutoSize Hide")
        osdGui.GetPos(,, &w, &h)
        
        x := Round(left + (mW - w) / 2)
        
        switch posMode {
            case "top_center":
                y := Round(top + mH * 0.1)
            case "center":
                y := Round(top + (mH - h) / 2)
            case "custom":
                y := Round(top + (mH - h) * (posYPercent / 100))
            default: ; "bottom_center"
                y := Round(top + (mH - h) * 0.82)
        }
        
        osdGui.Show("X" x " Y" y " NoActivate")
        DllCall("user32\SetWindowPos", "ptr", osdGui.Hwnd, "ptr", -1, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0253)
    } catch {
        osdGui.Show("y80% AutoSize NoActivate")
    }

    if (hideTimer)
        SetTimer(hideTimer, 0)
    hideTimer := () => osdGui.Hide()
    SetTimer(hideTimer, -hideDelay)
}
