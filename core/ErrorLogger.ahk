#Requires AutoHotkey v2.0

; Logs uncaught runtime errors to a file so they can be inspected after the fact.
; The normal AutoHotkey error dialog is preserved (the handler returns 0).
class ErrorLogger {
    static fileName    := "error.log"
    static maxBytes    := 512 * 1024
    static fallbackDir := "WindowAssist"

    static Init() {
        OnError(ObjBindMethod(this, "Handle"))
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
        return text
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
