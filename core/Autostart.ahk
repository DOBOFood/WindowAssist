#Requires AutoHotkey v2.0

; Keeps a per-user logon scheduled task in sync with the "run at startup"
; setting. A task with HighestAvailable starts the app elevated, unlike an
; HKCU\...\Run entry, which would show a UAC prompt on every logon.
class AutostartManager {
    static TaskName := "WindowAssist"
    static XmlPath  := A_Temp "\WindowAssist-autostart.xml"

    static IsEnabled() {
        try
            return RunWait('schtasks /Query /TN "' this.TaskName '"', , "Hide") == 0
        catch
            return false
    }

    static Apply(enabled) {
        try {
            return enabled ? this.Enable() : this.Disable()
        } catch {
            return false
        }
    }

    static Enable() {
        try {
            if FileExist(this.XmlPath)
                FileDelete(this.XmlPath)
            FileAppend(this.BuildTaskXml(), this.XmlPath, "UTF-16")
            code := RunWait('schtasks /Create /TN "' this.TaskName '" /XML "' this.XmlPath '" /F', , "Hide")
            FileDelete(this.XmlPath)
            return code == 0
        } catch {
            try FileDelete(this.XmlPath)
            return false
        }
    }

    static Disable() {
        if !this.IsEnabled()
            return true
        try
            return RunWait('schtasks /Delete /TN "' this.TaskName '" /F', , "Hide") == 0
        catch
            return false
    }

    ; Aligns the stored flag with reality, e.g. after the task was deleted by
    ; hand. Runs once per start, off the critical path.
    static SyncConfig() {
        try {
            actual := this.IsEnabled() ? 1 : 0
            configured := ConfigManager.Get("general.autostart.enabled", false) ? 1 : 0
            if (actual != configured)
                ConfigManager.Set("general.autostart.enabled", actual)
        }
    }

    static ExecCommand() {
        return A_IsCompiled ? A_ScriptFullPath : A_AhkPath
    }

    static ExecArguments() {
        return A_IsCompiled ? "" : '/restart "' A_ScriptFullPath '"'
    }

    static BuildTaskXml() {
        user := A_UserName
        if !InStr(user, "\")
            user := A_ComputerName "\" user
        user := this.EscapeXml(user)

        xml := "<?xml version=`"1.0`" encoding=`"UTF-16`"?>`n"
        xml .= "<Task version=`"1.2`" xmlns=`"http://schemas.microsoft.com/windows/2004/02/mit/task`">`n"
        xml .= "  <RegistrationInfo>`n"
        xml .= "    <Description>WindowAssist autostart</Description>`n"
        xml .= "  </RegistrationInfo>`n"
        xml .= "  <Triggers>`n"
        xml .= "    <LogonTrigger>`n"
        xml .= "      <Enabled>true</Enabled>`n"
        xml .= "      <UserId>" user "</UserId>`n"
        xml .= "    </LogonTrigger>`n"
        xml .= "  </Triggers>`n"
        xml .= "  <Principals>`n"
        xml .= "    <Principal id=`"Author`">`n"
        xml .= "      <UserId>" user "</UserId>`n"
        xml .= "      <LogonType>InteractiveToken</LogonType>`n"
        xml .= "      <RunLevel>HighestAvailable</RunLevel>`n"
        xml .= "    </Principal>`n"
        xml .= "  </Principals>`n"
        xml .= "  <Settings>`n"
        xml .= "    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>`n"
        xml .= "    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>`n"
        xml .= "    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>`n"
        xml .= "    <AllowHardTerminate>true</AllowHardTerminate>`n"
        xml .= "    <StartWhenAvailable>false</StartWhenAvailable>`n"
        xml .= "    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>`n"
        xml .= "    <IdleSettings>`n"
        xml .= "      <StopOnIdleEnd>false</StopOnIdleEnd>`n"
        xml .= "      <RestartOnIdle>false</RestartOnIdle>`n"
        xml .= "    </IdleSettings>`n"
        xml .= "    <AllowStartOnDemand>true</AllowStartOnDemand>`n"
        xml .= "    <Enabled>true</Enabled>`n"
        xml .= "    <Hidden>false</Hidden>`n"
        xml .= "    <RunOnlyIfIdle>false</RunOnlyIfIdle>`n"
        xml .= "    <WakeToRun>false</WakeToRun>`n"
        xml .= "    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>`n"
        xml .= "    <Priority>7</Priority>`n"
        xml .= "  </Settings>`n"
        xml .= "  <Actions Context=`"Author`">`n"
        xml .= "    <Exec>`n"
        xml .= "      <Command>" this.EscapeXml(this.ExecCommand()) "</Command>`n"
        xml .= "      <Arguments>" this.EscapeXml(this.ExecArguments()) "</Arguments>`n"
        xml .= "    </Exec>`n"
        xml .= "  </Actions>`n"
        xml .= "</Task>`n"
        return xml
    }

    static EscapeXml(text) {
        text := StrReplace(text, "&", "&amp;")
        text := StrReplace(text, "<", "&lt;")
        text := StrReplace(text, ">", "&gt;")
        text := StrReplace(text, "`"", "&quot;")
        return text
    }
}
