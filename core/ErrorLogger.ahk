#Requires AutoHotkey v2.0

; Logs uncaught runtime errors to a file so they can be inspected after the fact.
; The normal AutoHotkey error dialog is preserved (the handler returns 0).
class ErrorLogger {
    static fileName    := "error.log"
    static maxBytes    := 512 * 1024
    static fallbackDir := "WindowAssist"
    static maxActions  := 20
    static actions     := []
    static startedAt   := A_TickCount

    static Init() {
        OnError(ObjBindMethod(this, "Handle"))
    }

    /**
     * Remembers what the app was doing, so an uncaught error can be reproduced.
     * Cheap: one string push per action, capped at maxActions.
     */
    static Record(action) {
        try {
            this.actions.Push(FormatTime(A_Now, "HH:mm:ss") " " action)
            if (this.actions.Length > this.maxActions)
                this.actions.RemoveAt(1)
        }
    }

    static Handle(err, mode) {
        try this.Write(this.Format(err, mode))
        return 0 ; Let AutoHotkey handle the error as usual (dialog + thread exit).
    }

    static Format(err, mode) {
        text := "==============================================================`n"
        text .= "[" FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "] Unhandled error (mode: " mode ")`n"

        if (err is Error) {
            text .= "Message: " (err.Message != "" ? err.Message : "(none)") "`n"
            if (err.What != "")
                text .= "What: " err.What "`n"
            if (err.Extra != "")
                text .= "Extra: " err.Extra "`n"
            if (err.File != "")
                text .= "Location: " err.File ":" err.Line "`n"
            if (err.Stack != "")
                text .= "Stack:`n" err.Stack "`n"
        } else {
            text .= "Thrown value: " String(err) "`n"
        }

        text .= "Script: " A_ScriptFullPath "`n"
        text .= "AutoHotkey: " A_AhkVersion " (" (A_PtrSize * 8) "-bit)`n"
        if (A_ThisHotkey != "")
            text .= "Hotkey: " A_ThisHotkey "`n"
        text .= this.Context()
        return text
    }

    ; Everything here is best-effort: a failing probe must never break the log.
    static Context() {
        text := "`n--- Context ---`n"
        text .= "Version: " this.AppVersion() "`n"
        text .= "OS: " this.OSVersion() "`n"
        text .= "Uptime: " this.Uptime() "`n"
        text .= "Active window: " this.ActiveWindow() "`n"
        text .= "Monitors: " this.Monitors() "`n"
        text .= "Workspaces: " this.Workspaces() "`n"
        text .= "Recent actions:`n"
        if (this.actions.Length == 0) {
            text .= "  (none)`n"
        } else {
            for action in this.actions
                text .= "  " action "`n"
        }
        return text
    }

    static AppVersion() {
        try return App.Version
        catch
            return "unknown"
    }

    static OSVersion() {
        try {
            version := RegRead("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion", "DisplayVersion")
            build := RegRead("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion", "CurrentBuildNumber")
            return A_OSVersion " " version " (build " build ")"
        } catch
            return A_OSVersion
    }

    static Uptime() {
        elapsed := A_TickCount - this.startedAt
        return Format("{:.1f}s", elapsed / 1000)
    }

    static ActiveWindow() {
        try {
            hwnd := WinExist("A")
            if !hwnd
                return "(none)"
            pid := WinGetPID("ahk_id " hwnd)
            process := ""
            try process := ProcessGetName(pid)
            return '"' WinGetTitle("ahk_id " hwnd) '" class=' WinGetClass("ahk_id " hwnd)
                . " pid=" pid (process != "" ? " (" process ")" : "")
        } catch
            return "unavailable"
    }

    static Monitors() {
        try {
            count := MonitorGetCount()
            primary := MonitorGetPrimary()
            text := count " (primary " primary ")"
            Loop count {
                mL := 0, mT := 0, mR := 0, mB := 0
                if MonitorGet(A_Index, &mL, &mT, &mR, &mB)
                    text .= "`n  #" A_Index ": " (mR - mL) "x" (mB - mT) " at " mL "," mT
            }
            return text
        } catch
            return "unavailable"
    }

    static Workspaces() {
        try {
            global currentWorkspaces, isMovingOrResizing, isPanicMode
            text := ""
            for index, workspace in currentWorkspaces
                text .= (text != "" ? ", " : "") "mon" index "=" workspace
            return text " (moving=" (isMovingOrResizing ? 1 : 0) ", panic=" (isPanicMode ? 1 : 0) ")"
        } catch
            return "unavailable"
    }

    static Write(text) {
        ; Prefer the portable location used by config.json/state.json, but fall back
        ; to %APPDATA% when the script directory is not writable (e.g. installed exe).
        if this.Append(this.PrimaryPath(), text)
            return
        this.Append(this.FallbackPath(), text)
    }

    static PrimaryPath() {
        return A_ScriptDir "\" this.fileName
    }

    static FallbackPath() {
        return A_AppData "\" this.fallbackDir "\" this.fileName
    }

    static Append(path, text) {
        try {
            SplitPath(path, , &dir)
            if (dir != "" && !DirExist(dir))
                DirCreate(dir)
            this.Rotate(path)
            FileAppend(text, path, "UTF-8")
            return true
        }
        return false
    }

    ; Keep at most one previous log to prevent unbounded growth.
    static Rotate(path) {
        try {
            if (FileExist(path) && FileGetSize(path) > this.maxBytes)
                FileMove(path, path ".old", true)
        }
    }
}
