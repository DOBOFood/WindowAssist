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
