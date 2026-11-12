#Requires AutoHotkey v2.0

class App {
    static Version := "1.0.0"

    ; Registry values temporarily changed while the app runs. Originals are backed
    ; up on the first start so a clean exit can put them back.
    static RegistryBackupPath := A_ScriptDir "\system-backup.json"
    static RegistryOverrides := [
        Map("key", "HKEY_CURRENT_USER\Control Panel\Desktop", "name", "ForegroundFlashCount"),
        Map("key", "HKEY_CURRENT_USER\Control Panel\Desktop", "name", "ForegroundLockTimeout")
    ]
    static RegistryAbsent := "__absent__"

    static Init() {
        global hWinEventHook, winEventCallback, hMouseHook, mouseEventCallback

        if !A_IsAdmin {
            try {
                if A_IsCompiled
                    Run('*RunAs "' A_ScriptFullPath '"')
                else
                    Run('*RunAs "' A_AhkPath '" /restart "' A_ScriptFullPath '"')
            }
            ExitApp()
        }

        this.BackupSystemRegistry()
        this.ApplySystemRegistry()

        DllCall("winmm\timeBeginPeriod", "uint", 1)
        A_IconTip := "WindowAssist v" this.Version

        ConfigManager.Load()
        ; Reconcile the "run at startup" flag with the actual scheduled task
        ; after the hot path is up.
        SetTimer(() => AutostartManager.SyncConfig(), -1500)

        hasRestoredState := LoadState()

        if (!hasRestoredState)
            RecoverAllOffscreenWindows(false)

        InitExistingWindows()

        WindowTracker.Init()
        HotkeyManager.Init()
        global hasHooksInitialized
        hasHooksInitialized := true
        
        CrossWorkspaceAltTab.Init()

        OnExit(ObjBindMethod(this, "CleanExit"))
    }

    static CleanExit(ExitReason, ExitCode) {
        global hWinEventHook, winEventCallback, hMouseHook, mouseEventCallback

        WindowTracker.UnHook()
        DllCall("winmm\timeEndPeriod", "uint", 1)
        ReleaseCursorClip()
        
        OverviewController.Close()
        CaptureEngine.Shutdown()

        SaveState()

        ; When reloading the script, leave offscreen window coordinates intact
        if (ExitReason == "Reload") {
            return
        }

        RestoreAllTitleBars()
        RecoverAllOffscreenWindows(true)
        ConfigManager.ApplyTaskbarVisibility(false)
        this.RestoreSystemRegistry()
    }

    /**
     * Saves the current values of App.RegistryOverrides, once.
     * The backup survives reloads and crashes, so the real originals are never
     * overwritten with the values this app writes.
     */
    static BackupSystemRegistry() {
        if FileExist(this.RegistryBackupPath)
            return

        backup := Map()
        for item in this.RegistryOverrides {
            try
                backup[item["name"]] := RegRead(item["key"], item["name"])
            catch
                backup[item["name"]] := this.RegistryAbsent
        }

        try FileAppend(JSON.Dump(backup, "  "), this.RegistryBackupPath, "UTF-8-RAW")
    }

    static ApplySystemRegistry() {
        for item in this.RegistryOverrides {
            try RegWrite(0, "REG_DWORD", item["key"], item["name"])
        }
    }

    static RestoreSystemRegistry() {
        if !FileExist(this.RegistryBackupPath)
            return

        restored := false
        try {
            backup := JSON.Load(FileRead(this.RegistryBackupPath, "UTF-8"))
            if (backup is Map) {
                for item in this.RegistryOverrides {
                    name := item["name"]
                    if !backup.Has(name)
                        continue
                    if (backup[name] == this.RegistryAbsent)
                        RegDelete(item["key"], name)
                    else
                        RegWrite(backup[name], "REG_DWORD", item["key"], name)
                }
            }
            restored := true
        }

        if restored
            try FileDelete(this.RegistryBackupPath)
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
