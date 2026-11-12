#Requires AutoHotkey v2.0

; Reads the Windows app theme and accent color so the settings UI can match the
; system without acrylic or any custom colors.
class Theme {
    ; Optional callback invoked when Windows broadcasts WM_SETTINGCHANGE.
    static Sink := 0

    static Init() {
        OnMessage(0x001A, ObjBindMethod(this, "OnSettingChange")) ; WM_SETTINGCHANGE
    }

    static OnSettingChange(*) {
        if !this.Sink
            return
        try this.Sink(this.Payload())
    }

    static Attach(sink) {
        this.Sink := sink
        try sink(this.Payload())
    }

    static Detach() {
        this.Sink := 0
    }

    static Payload() {
        info := this.Read()
        info["action"] := "THEME"
        return info
    }

    static Read() {
        dark := false
        try dark := (RegRead("HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
            , "AppsUseLightTheme") == 0)

        build := this.BuildNumber()
        return Map(
            "dark", dark ? 1 : 0,
            "accent", this.AccentColor(),
            "build", build,
            "os", this.OSFamily(build)
        )
    }

    static AccentColor() {
        ; AccentColorMenu is ABGR and is not affected by transparency effects.
        try {
            hex := this.HexFromAbgr(RegRead("HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent"
                , "AccentColorMenu"))
            if (hex != "#000000")
                return hex
        }
        ; Fallback for systems without the Accent key: DWM colorization (ARGB).
        try {
            hex := this.HexFromArgb(RegRead("HKEY_CURRENT_USER\Software\Microsoft\Windows\DWM"
                , "ColorizationColor"))
            if (hex != "#000000")
                return hex
        }
        return "#0078D7"
    }

    static BuildNumber() {
        try {
            return Integer(RegRead("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
                , "CurrentBuildNumber"))
        }
        return 0
    }

    static OSFamily(build) {
        return (build >= 22000) ? "win11" : "win10"
    }

    ; 0xAARRGGBB (DWM colorization).
    static HexFromArgb(value) {
        value := value & 0xFFFFFFFF
        return Format("#{:02X}{:02X}{:02X}"
            , (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
    }

    ; 0xAABBGGRR (Explorer accent values).
    static HexFromAbgr(value) {
        value := value & 0xFFFFFFFF
        return Format("#{:02X}{:02X}{:02X}"
            , value & 0xFF, (value >> 8) & 0xFF, (value >> 16) & 0xFF)
    }
}
