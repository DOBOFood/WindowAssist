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
#Include ..\core\Theme.ahk
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

SetSnapMode(value) {
    ConfigManager.configData := Map("general", Map("windowMover", Map("snapMode", value)))
}

ConfigManager.configData := Map()
AssertEq("snap mode default", WindowMover.SnapMode(), "custom")

SetSnapMode("native")
AssertEq("snap mode native", WindowMover.SnapMode(), "native")

SetSnapMode("weird")
AssertEq("snap mode falls back on garbage", WindowMover.SnapMode(), "custom")

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

; Schema 2 rebinds the keyboard defaults, but only where the old default is intact.
v1 := Map(
    "configVersion", 1,
    "hotkeys", Map("profiles", Map(
        "default", Map(
            "window_move_left", ["NumLock + Alt + Left"],
            "window_close", ["NumLock + Q"]
        ),
        "custom", Map(
            "window_move_left", ["Ctrl + Shift + L"]
        )
    ))
)
AssertTrue("keyboard bindings migrate", ConfigManager.Migrate(v1))
AssertEq("old default rebound", JSON.Dump(v1["hotkeys"]["profiles"]["default"]["window_move_left"]), '["NumLock + Left"]')
AssertEq("custom binding kept", JSON.Dump(v1["hotkeys"]["profiles"]["custom"]["window_move_left"]), '["Ctrl + Shift + L"]')
AssertEq("other bindings kept", JSON.Dump(v1["hotkeys"]["profiles"]["default"]["window_close"]), '["NumLock + Q"]')
AssertEq("version bumped to schema 2", v1["configVersion"], 2)
AssertTrue("rebind migration is idempotent", !ConfigManager.Migrate(v1))

; ------------------------------------------------------------------- Import

imported := ConfigManager.PrepareImported(Map(
    "general", Map("windowMover", Map("safeZone", 33))
))
AssertEq("import keeps provided values", imported["general"]["windowMover"]["safeZone"], 33)
AssertEq("import fills missing defaults", imported["general"]["windowMover"]["keyboardStep"], 20)
AssertEq("import stamps schema version", imported["configVersion"], ConfigManager.SchemaVersion)
AssertTrue("import provides default hotkeys", imported["hotkeys"]["profiles"]["default"].Has("window_move_left"))

importError := ""
try {
    ConfigManager.PrepareImported("not a config")
} catch as e {
    importError := e.Message
}
AssertTrue("import rejects non-object payloads", importError != "")

legacyImport := ConfigManager.PrepareImported(Map(
    "titleBar", Map("visibleHeight", 77),
    "general", Map()
))
AssertEq("import migrates legacy sections", legacyImport["general"]["titleBar"]["visibleHeight"], 77)
AssertTrue("import drops legacy titleBar", !legacyImport.Has("titleBar"))

ConfigManager.configData := Map("probe", 1)
exportPath := A_ScriptDir "\tmp-export.json"
AssertTrue("export writes a file", ConfigManager.ExportToFile(exportPath))
AssertTrue("export contains config data", InStr(FileRead(exportPath, "UTF-8"), '"probe"') > 0)
try FileDelete(exportPath)

; ---------------------------------------------------------------- Snap zones

zone := ComputeSnapZone(10, 10, 0, 0, 1000, 800, 20)
AssertEq("snap top-left kind", zone["kind"], "quarter")
AssertEq("snap top-left x", zone["x"], 0)
AssertEq("snap top-left y", zone["y"], 0)
AssertEq("snap top-left width", zone["w"], 500)
AssertEq("snap top-left height", zone["h"], 400)

zone := ComputeSnapZone(990, 10, 0, 0, 1000, 800, 20)
AssertEq("snap top-right x", zone["x"], 500)
AssertEq("snap top-right width", zone["w"], 500)

zone := ComputeSnapZone(10, 790, 0, 0, 1000, 800, 20)
AssertEq("snap bottom-left y", zone["y"], 400)

zone := ComputeSnapZone(500, 5, 0, 0, 1000, 800, 20)
AssertEq("snap top edge maximises", zone["kind"], "max")
AssertEq("snap top edge height", zone["h"], 800)

zone := ComputeSnapZone(5, 400, 0, 0, 1000, 800, 20)
AssertEq("snap left half", zone["kind"], "left")
AssertEq("snap left half width", zone["w"], 500)

zone := ComputeSnapZone(995, 400, 0, 0, 1000, 800, 20)
AssertEq("snap right half", zone["kind"], "right")

zone := ComputeSnapZone(500, 795, 0, 0, 1000, 800, 20)
AssertEq("snap bottom half", zone["kind"], "bottom")

AssertEq("no snap in the middle", Type(ComputeSnapZone(500, 400, 0, 0, 1000, 800, 20)), "Integer")
AssertEq("no snap on a degenerate monitor", Type(ComputeSnapZone(0, 0, 0, 0, 0, 0, 20)), "Integer")

; ------------------------------------------------------ Frame padding (snap)

zone := Map("x", 100, "y", 50, "w", 500, "h", 400)
padding := Map("left", 8, "top", 0, "right", 8, "bottom", 8)
padded := ApplyFramePadding(zone, padding)
AssertEq("padding shifts x outwards", padded["x"], 92)
AssertEq("padding keeps y when top is zero", padded["y"], 50)
AssertEq("padding grows width", padded["w"], 516)
AssertEq("padding grows height", padded["h"], 408)

identity := ApplyFramePadding(zone, Map("left", 0, "top", 0, "right", 0, "bottom", 0))
AssertEq("zero padding keeps x", identity["x"], 100)
AssertEq("zero padding keeps width", identity["w"], 500)

AssertEq("native keys for left half", JSON.Dump(NativeSnapKeys(Map("kind", "left"))), '["#Left"]')
AssertEq("native keys for right half", JSON.Dump(NativeSnapKeys(Map("kind", "right"))), '["#Right"]')
AssertEq("no native keys for quarters", NativeSnapKeys(Map("kind", "quarter")).Length, 0)
AssertEq("no native keys for bottom half", NativeSnapKeys(Map("kind", "bottom")).Length, 0)
AssertEq("no native keys without a zone", NativeSnapKeys(0).Length, 0)

defaults := ConfigManager.GetDefaultConfig()
AssertTrue("defaults carry configVersion", defaults.Has("configVersion"))
AssertTrue("defaults have no legacy titleBar", !defaults.Has("titleBar"))
AssertTrue("defaults have no legacy altTab", !defaults.Has("altTab"))
AssertEq("visibleHeight lives in general", defaults["general"]["titleBar"]["visibleHeight"], 40)
AssertTrue("keyboard step default", defaults["general"]["windowMover"]["keyboardStep"] == 20)
AssertTrue("snap mode default is custom", defaults["general"]["windowMover"]["snapMode"] == "custom")
AssertTrue("autostart default is off", !defaults["general"]["autostart"]["enabled"])

keyboardActions := [
    "window_move_left", "window_move_right", "window_move_up", "window_move_down",
    "window_resize_wider", "window_resize_narrower", "window_resize_taller", "window_resize_shorter"
]
defaultBinds := defaults["hotkeys"]["profiles"]["default"]
for actionKey in keyboardActions
    AssertTrue("default binding " actionKey, defaultBinds.Has(actionKey) && defaultBinds[actionKey].Length > 0)

AssertEq("move left default", JSON.Dump(defaultBinds["window_move_left"]), '["NumLock + Left"]')
AssertEq("move down default", JSON.Dump(defaultBinds["window_move_down"]), '["NumLock + Down"]')
AssertEq("resize wider default", JSON.Dump(defaultBinds["window_resize_wider"]), '["NumLock + Alt + Right"]')
AssertEq("resize shorter default", JSON.Dump(defaultBinds["window_resize_shorter"]), '["NumLock + Alt + Up"]')

settingsJs := FileRead(A_ScriptDir "\..\web\js\settings.js", "UTF-8")
for actionKey in keyboardActions
    AssertTrue("settings list " actionKey, InStr(settingsJs, '"' actionKey '"') > 0)

settingsHtml := FileRead(A_ScriptDir "\..\web\settings.html", "UTF-8")
AssertTrue("settings expose the snap mode control", InStr(settingsHtml, 'id="gen_wm_snapMode"') > 0)

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
            "autostartEnabled", "autostartFailed", "groupData", "settingsExport",
            "settingsImport", "settingsExported", "settingsImportFailed",
            "hotkeyConflictBadge", "hotkeyConflictsSummary",
            "windowMoverSnapMode", "snapMode_custom", "snapMode_native",
            "act_window_move_left", "act_window_move_right", "act_window_move_up",
            "act_window_move_down", "act_window_resize_wider", "act_window_resize_narrower",
            "act_window_resize_taller", "act_window_resize_shorter",
            "groupOsdDesign", "osdPreview", "osdBgColor", "osdBgOpacity",
            "osdTextColor", "osdBorderTransparent", "osdBorderColor", "osdBorderWidth"] {
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

; --------------------------------------------------------------- Theme

AssertEq("ARGB accent converts", Theme.HexFromArgb(0xC469797E), "#69797E")
AssertEq("ABGR accent converts", Theme.HexFromAbgr(0xFF7E7969), "#69797E")
AssertEq("black accent converts", Theme.HexFromArgb(0x00000000), "#000000")
AssertEq("Windows 10 build family", Theme.OSFamily(19045), "win10")
AssertEq("Windows 11 build family", Theme.OSFamily(22621), "win11")
AssertEq("unknown build defaults to win10", Theme.OSFamily(0), "win10")

themeInfo := Theme.Read()
AssertTrue("theme info reports dark flag", themeInfo["dark"] == 0 || themeInfo["dark"] == 1)
AssertTrue("theme info reports an accent", InStr(themeInfo["accent"], "#") == 1 && StrLen(themeInfo["accent"]) == 7)
AssertTrue("theme info reports an OS family", themeInfo["os"] == "win10" || themeInfo["os"] == "win11")
AssertEq("theme payload is a THEME message", Theme.Payload()["action"], "THEME")

; ------------------------------------------------------- Settings design

settingsCss := FileRead(A_ScriptDir "\..\web\css\settings.css", "UTF-8")
AssertTrue("settings CSS has no acrylic or blur", !RegExMatch(settingsCss, "i)backdrop-filter|\bblur\("))
AssertTrue("settings CSS defines a dark theme", InStr(settingsCss, 'html[data-theme="dark"]') > 0)
AssertTrue("settings CSS defines Windows 10 tone", InStr(settingsCss, 'html[data-os="win10"]') > 0)

themeScript := FileRead(A_ScriptDir "\..\web\js\settings.js", "UTF-8")
AssertTrue("settings JS applies the system theme", InStr(themeScript, "function applyTheme") > 0)
AssertTrue("settings JS handles THEME messages", InStr(themeScript, 'msg.action === "THEME"') > 0)

; ---------------------------------------------------------- OSD Style & Layout

AssertEq("OSD hex normalizes lowercase", OsdRenderer.NormalizeHex("#ff8800"), "#FF8800")
AssertEq("OSD hex adds missing hash", OsdRenderer.NormalizeHex("00aaee"), "#00AAEE")
AssertEq("OSD hex falls back on invalid", OsdRenderer.NormalizeHex("bad", "#1A1A1A"), "#1A1A1A")
AssertEq("OSD HexToArgb full opacity", OsdRenderer.HexToArgb("#1A1A1A", 255), 0xFF1A1A1A)
AssertEq("OSD HexToArgb zero opacity", OsdRenderer.HexToArgb("#FFFFFF", 0), 0x00FFFFFF)
AssertEq("OSD ClampInt clamps low", OsdRenderer.ClampInt(-5, 0, 100, 50), 0)
AssertEq("OSD ClampInt clamps high", OsdRenderer.ClampInt(999, 1, 10, 1), 10)
AssertEq("OSD ClampInt falls back on garbage", OsdRenderer.ClampInt("abc", 1, 10, 3), 3)

ConfigManager.configData := Map()
osdDef := OsdRenderer.ResolveStyle()
AssertEq("OSD default bgColor", osdDef.bgColor, "#1A1A1A")
AssertEq("OSD default bgOpacity", osdDef.bgOpacity, 100)
AssertEq("OSD default textColor", osdDef.textColor, "#FFFFFF")
AssertEq("OSD default borderTransparent", osdDef.borderTransparent ? 1 : 0, 0)
AssertEq("OSD default borderColor", osdDef.borderColor, "#3D3D3D")
AssertEq("OSD default borderWidth", osdDef.borderWidth, 1)

ConfigManager.configData := Map(
    "general", Map("osd", Map("fontSize", 20)),
    "appearance", Map("osd", Map(
        "backgroundColor", "#112233",
        "backgroundOpacity", 75,
        "textColor", "#AABBCC",
        "borderTransparent", true,
        "borderColor", "#445566",
        "borderWidth", 4
    ))
)
osdCustom := OsdRenderer.ResolveStyle()
AssertEq("OSD custom fontSize", osdCustom.fontSize, 20)
AssertEq("OSD custom bgColor", osdCustom.bgColor, "#112233")
AssertEq("OSD custom bgOpacity", osdCustom.bgOpacity, 75)
AssertEq("OSD custom textColor", osdCustom.textColor, "#AABBCC")
AssertEq("OSD custom borderTransparent", osdCustom.borderTransparent ? 1 : 0, 1)
AssertEq("OSD custom borderColor", osdCustom.borderColor, "#445566")
AssertEq("OSD custom borderWidth", osdCustom.borderWidth, 4)

OsdRenderer.EnsureGdiPlus()
pinLayout := OsdRenderer.ComputeLayout("__PINNED__", osdDef, 96)
AssertTrue("OSD pinned layout is icon", pinLayout.isIcon && pinLayout.isPin && !pinLayout.isUnpin)
AssertTrue("OSD pinned layout has positive size", pinLayout.w > 0 && pinLayout.h > 0)

unpinLayout := OsdRenderer.ComputeLayout("__UNPINNED__", osdDef, 96)
AssertTrue("OSD unpinned layout is icon", unpinLayout.isIcon && !unpinLayout.isPin && unpinLayout.isUnpin)
AssertEq("OSD unpinned matches pinned size", unpinLayout.w, pinLayout.w)
AssertEq("OSD unpinned matches pinned height", unpinLayout.h, pinLayout.h)

wsLayout := OsdRenderer.ComputeLayout("1", osdDef, 96)
AssertTrue("OSD text layout is not icon", !wsLayout.isIcon)
AssertTrue("OSD text layout has positive size", wsLayout.w > 0 && wsLayout.h > 0)
OsdRenderer.Shutdown()

settingsHtmlOsd := FileRead(A_ScriptDir "\..\web\settings.html", "UTF-8")
for ctrlId in ["col_osd_bgColor", "app_osd_bgOpacity", "col_osd_textColor",
               "app_osd_borderTransparent", "col_osd_borderColor", "app_osd_borderWidth",
               "osd-preview-strip"] {
    AssertTrue("settings expose OSD control " ctrlId, InStr(settingsHtmlOsd, 'id="' ctrlId '"') > 0)
}

; ---------------------------------------------------------------- Languages

languagesJs := FileRead(A_ScriptDir "\..\web\js\languages.js", "UTF-8")
AssertEq("twelve languages are offered", CountText(languagesJs, 'code: "'), 12)
for code in ["ru", "en", "zh-CN", "es", "de", "fr", "pt-BR", "ja", "ko", "it", "pl", "tr"]
    AssertTrue("language listed " code, InStr(languagesJs, '"' code '"') > 0)

settingsHtmlText := FileRead(A_ScriptDir "\..\web\settings.html", "UTF-8")
overviewHtmlText := FileRead(A_ScriptDir "\..\web\overview.html", "UTF-8")
for fileName in ["languages.js", "i18n.zh-CN.js", "i18n.es.js", "i18n.de.js", "i18n.fr.js"
    , "i18n.pt-BR.js", "i18n.ja.js", "i18n.ko.js", "i18n.it.js", "i18n.pl.js", "i18n.tr.js"] {
    AssertTrue("settings loads " fileName, InStr(settingsHtmlText, "js/" fileName) > 0)
}
for fileName in ["i18n.zh-CN.js", "i18n.ja.js", "i18n.pt-BR.js", "i18n.tr.js"]
    AssertTrue("overview loads " fileName, InStr(overviewHtmlText, "js/" fileName) > 0)

nodeFound := false
if (A_ComSpec != "")
    nodeFound := (RunWait('"' A_ComSpec '" /c where node >nul 2>&1', , "Hide") == 0)
if nodeFound {
    i18nExit := RunWait('"' A_ComSpec '" /c node "' A_ScriptDir '\..\tools\check_i18n.js"', , "Hide")
    AssertEq("translation key sets match English", i18nExit, 0)
}

; ------------------------------------------------------- AHK v1 leftovers

; AHK v1 built-ins that no longer exist in v2. They only produce a VarUnset
; warning at runtime (not caught by /validate), so scan the sources instead.
; Needles are built by concatenation so this file does not match itself.
v1Needles := ["FileSelect" "File", "FileSelect" "Folder", "StringRe" "place(", "StringSp" "lit(", "FileRead" "Line("]
Loop Files, A_ScriptDir "\..\*.ahk", "R" {
    content := FileRead(A_LoopFileFullPath, "UTF-8")
    for needle in v1Needles
        AssertTrue("no v1 API " needle " in " A_LoopFileName, !InStr(content, needle))
}

; --------------------------------------------------------------------- Report

summary := (gFail = 0 ? "PASS" : "FAIL") " - " (gRun - gFail) "/" gRun " tests passed`n"
report := summary . gOut
try FileAppend report, "*" ; stdout is absent when the runner is started by double-click
try FileDelete(A_ScriptDir "\last-run.txt")
FileAppend report, A_ScriptDir "\last-run.txt", "UTF-8-RAW"

ExitApp(gFail ? 1 : 0)
