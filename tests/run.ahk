#Requires AutoHotkey v2.0
#Warn All, Off
#SingleInstance Force

; Minimal test runner for logic that does not need a GUI.
; Run:  AutoHotkey64.exe tests\run.ahk
; Exit: 0 = all passed, 1 = failures
;
; Only pure code is covered. Anything touching Win32, WebView2 or the registry
; stays untested here and is verified by hand.

#Include ..\Lib\JSON.ahk
#Include ..\core\Globals.ahk
#Include ..\core\App.ahk
#Include ..\core\ErrorLogger.ahk
#Include ..\core\Autostart.ahk
#Include ..\core\ConfigManager.ahk
#Include ..\modules\Workspaces\WindowMover.ahk

global gRun := 0
global gFail := 0
global gOut := ""

AssertEq(name, actual, expected) {
    global gRun, gFail, gOut
    gRun++
    if (actual == expected)
        return
    gFail++
    gOut .= "FAIL " name ": got " FormatValue(actual) ", expected " FormatValue(expected) "`n"
}

AssertTrue(name, condition) {
    AssertEq(name, condition ? 1 : 0, 1)
}

FormatValue(value) {
    if (value is Map)
        return "Map(" value.Count ")"
    if (value is Array)
        return "Array(" value.Length ")"
    return "[" Type(value) "] " String(value)
}

SetSafeZone(value) {
    ConfigManager.configData := Map("general", Map("windowMover", Map("safeZone", value)))
}

; ---------------------------------------------------------------- SafeZonePx

ConfigManager.configData := Map()
AssertEq("safe zone default", WindowMover.SafeZonePx(), 8)

SetSafeZone(15)
AssertEq("safe zone configured", WindowMover.SafeZonePx(), 15)

SetSafeZone(0)
AssertEq("safe zone clamps low", WindowMover.SafeZonePx(), 1)

SetSafeZone(1000)
AssertEq("safe zone clamps high", WindowMover.SafeZonePx(), 100)

SetSafeZone("abc")
AssertEq("safe zone falls back on garbage", WindowMover.SafeZonePx(), 8)

SetSafeZone(7.9)
AssertEq("safe zone truncates fractions", WindowMover.SafeZonePx(), 7)

SetKeyboardStep(value) {
    ConfigManager.configData := Map("general", Map("windowMover", Map("keyboardStep", value)))
}

ConfigManager.configData := Map()
AssertEq("keyboard step default", WindowMover.KeyboardStepPx(), 20)

SetKeyboardStep(35)
AssertEq("keyboard step configured", WindowMover.KeyboardStepPx(), 35)

SetKeyboardStep(0)
AssertEq("keyboard step clamps low", WindowMover.KeyboardStepPx(), 1)

SetKeyboardStep(1000)
AssertEq("keyboard step clamps high", WindowMover.KeyboardStepPx(), 200)

SetKeyboardStep("abc")
AssertEq("keyboard step falls back on garbage", WindowMover.KeyboardStepPx(), 20)

; ------------------------------------------------------------------ Get paths

ConfigManager.configData := Map("general", Map("windowMover", Map("safeZone", 12)))
AssertEq("Get nested value", ConfigManager.Get("general.windowMover.safeZone"), 12)
AssertEq("Get missing leaf uses default", ConfigManager.Get("general.windowMover.missing", "fallback"), "fallback")
AssertEq("Get missing branch uses default", ConfigManager.Get("general.nope.deeper", -1), -1)
AssertEq("Get through scalar uses default", ConfigManager.Get("general.windowMover.safeZone.deeper", -1), -1)

; ---------------------------------------------------------------- MergeMaps

base := Map(
    "scalar", 1,
    "nested", Map("keep", 1, "replace", 2),
    "list", [1, 2, 3]
)
override := Map(
    "scalar", 9,
    "nested", Map("replace", 5),
    "list", [7]
)
merged := ConfigManager._MergeMaps(base, override)

AssertEq("merge overrides scalar", merged["scalar"], 9)
AssertEq("merge keeps missing nested key", merged["nested"]["keep"], 1)
AssertEq("merge overrides nested key", merged["nested"]["replace"], 5)
AssertEq("merge replaces arrays", JSON.Dump(merged["list"]), "[7]")
AssertEq("merge does not mutate defaults", base["scalar"], 1)
AssertEq("merge does not mutate default nested", base["nested"]["replace"], 2)

; --------------------------------------------------------- NormalizeParsedJSON

list := ConfigManager._NormalizeParsedJSON(Map("0", "a", "1", "b"))
AssertTrue("indexed map becomes array", list is Array)
AssertEq("array content preserved", JSON.Dump(list), '["a", "b"]')

obj := ConfigManager._NormalizeParsedJSON(Map("key", Map("0", 1)))
AssertTrue("named map stays map", obj is Map)
AssertTrue("nested indexed map becomes array", obj["key"] is Array)

AssertEq("scalars pass through", ConfigManager._NormalizeParsedJSON(5), 5)

; ----------------------------------------------------------------- Migration

legacy := Map(
    "altTab", Map("enabled", 0),
    "general", Map(
        "altTab", Map("enabled", 1),
        "titleBar", Map("triggerHeightMaximized", 12)
    ),
    "titleBar", Map("triggerHeightMaximized", 10, "visibleHeight", 55)
)
AssertTrue("legacy config reports migration", ConfigManager.Migrate(legacy))
AssertTrue("top-level titleBar removed", !legacy.Has("titleBar"))
AssertTrue("top-level altTab removed", !legacy.Has("altTab"))
AssertEq("legacy altTab wins over general", legacy["general"]["altTab"]["enabled"], 0)
AssertEq("general titleBar wins over legacy", legacy["general"]["titleBar"]["triggerHeightMaximized"], 12)
AssertEq("visibleHeight moved to general", legacy["general"]["titleBar"]["visibleHeight"], 55)
AssertEq("schema version stamped", legacy["configVersion"], ConfigManager.SchemaVersion)
AssertTrue("second migration run is a no-op", !ConfigManager.Migrate(legacy))

defaults := ConfigManager.GetDefaultConfig()
AssertTrue("defaults carry configVersion", defaults.Has("configVersion"))
AssertTrue("defaults have no legacy titleBar", !defaults.Has("titleBar"))
AssertTrue("defaults have no legacy altTab", !defaults.Has("altTab"))
AssertEq("visibleHeight lives in general", defaults["general"]["titleBar"]["visibleHeight"], 40)
AssertTrue("keyboard step default", defaults["general"]["windowMover"]["keyboardStep"] == 20)
AssertTrue("autostart default is off", !defaults["general"]["autostart"]["enabled"])

keyboardActions := [
    "window_move_left", "window_move_right", "window_move_up", "window_move_down",
    "window_resize_wider", "window_resize_narrower", "window_resize_taller", "window_resize_shorter"
]
defaultBinds := defaults["hotkeys"]["profiles"]["default"]
for actionKey in keyboardActions
    AssertTrue("default binding " actionKey, defaultBinds.Has(actionKey) && defaultBinds[actionKey].Length > 0)

settingsJs := FileRead(A_ScriptDir "\..\web\js\settings.js", "UTF-8")
for actionKey in keyboardActions
    AssertTrue("settings list " actionKey, InStr(settingsJs, '"' actionKey '"') > 0)

; ------------------------------------------------------------- Autostart XML

taskXml := AutostartManager.BuildTaskXml()
AssertTrue("autostart xml declares task", InStr(taskXml, "<Task version=") > 0)
AssertTrue("autostart runs elevated", InStr(taskXml, "<RunLevel>HighestAvailable</RunLevel>") > 0)
AssertTrue("autostart triggers on logon", InStr(taskXml, "<LogonTrigger>") > 0)
AssertTrue("autostart command points at the app", InStr(taskXml, "<Command>" AutostartManager.ExecCommand()) > 0)
if !A_IsCompiled
    AssertTrue("autostart arguments run the script", InStr(taskXml, AutostartManager.EscapeXml(A_ScriptFullPath)) > 0)

jsDefaults := FileRead(A_ScriptDir "\..\web\js\defaults.js", "UTF-8")
AssertTrue("generated web defaults carry configVersion", InStr(jsDefaults, '"configVersion": ' ConfigManager.SchemaVersion) > 0)

; --------------------------------------------------------------- ErrorLogger

ErrorLogger.Record("unit test action")
logText := ErrorLogger.Format(Error("boom", -1), "unit")
AssertTrue("log includes version", InStr(logText, "Version: " App.Version) > 0)
AssertTrue("log includes OS", InStr(logText, "OS: ") > 0)
AssertTrue("log includes active window", InStr(logText, "Active window: ") > 0)
AssertTrue("log includes monitors", InStr(logText, "Monitors: ") > 0)
AssertTrue("log includes recent action", InStr(logText, "unit test action") > 0)

ErrorLogger.actions := []
Loop 25
    ErrorLogger.Record("action " A_Index)
AssertEq("action ring is capped", ErrorLogger.actions.Length, ErrorLogger.maxActions)
AssertTrue("oldest actions are dropped", InStr(ErrorLogger.actions[1], "action 6") > 0)

; -------------------------------------------------------------------- i18n

CountText(haystack, needle) {
    return (StrLen(haystack) - StrLen(StrReplace(haystack, needle, ""))) / StrLen(needle)
}

i18nText := FileRead(A_ScriptDir "\..\web\js\i18n.js", "UTF-8")
for key in ["profileAlreadyExists", "defaultProfileName", "groupHotkeysSys",
            "groupHotkeysOverview", "groupHotkeysPocket", "groupHotkeysWorkspaces",
            "groupHotkeysWindow", "windowMoverKeyboardStep", "groupStartup",
            "autostartEnabled", "autostartFailed",
            "act_window_move_left", "act_window_move_right", "act_window_move_up",
            "act_window_move_down", "act_window_resize_wider", "act_window_resize_narrower",
            "act_window_resize_taller", "act_window_resize_shorter"] {
    count := CountText(i18nText, key ":")
    AssertEq("i18n key " key " exists in ru and en", count, 2)
}

; ------------------------------------------------------------------- Versions

AssertTrue("App.Version is set", App.Version != "")

exeDirective := ""
mainScript := FileRead(A_ScriptDir "\..\WindowAssist.ahk", "UTF-8")
if RegExMatch(mainScript, "@Ahk2Exe-SetVersion\s+([\d.]+)", &m)
    exeDirective := m[1]
AssertTrue(
    "Ahk2Exe version matches App.Version",
    exeDirective == App.Version || exeDirective == App.Version ".0"
)

; ------------------------------------------------------------------- Defaults

defaults := ConfigManager.GetDefaultConfig()
AssertEq(
    "Globals workspaces match defaults",
    JSON.Dump(maxWorkspacesPerMon),
    JSON.Dump(defaults["workspaces"]["maxWorkspacesPerMonitor"])
)

if (A_AhkPath != "") {
    genExit := RunWait('"' A_AhkPath '" "' A_ScriptDir '\..\tools\gen_defaults.ahk" check', , "Hide")
    AssertEq("web/js/defaults.js is generated and current", genExit, 0)
}

; --------------------------------------------------------------------- Report

summary := (gFail = 0 ? "PASS" : "FAIL") " - " (gRun - gFail) "/" gRun " tests passed`n"
report := summary . gOut
try FileAppend report, "*" ; stdout is absent when the runner is started by double-click
try FileDelete(A_ScriptDir "\last-run.txt")
FileAppend report, A_ScriptDir "\last-run.txt", "UTF-8-RAW"

ExitApp(gFail ? 1 : 0)
