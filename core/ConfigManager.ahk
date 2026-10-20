#Requires AutoHotkey v2.0

class ConfigManager {
    static configPath := A_ScriptDir "\config.json"
    static configData := Map()

    static GetDefaultConfig() {
        return Map(
            "language", "en",
            "hotkeys", Map(
                "activeProfile", "default",
                "profiles", Map(
                    "default", Map(
                        "alt_tab", ["Alt + Tab"],
                        "move_window_prefix", ["NumLock + Shift"],
                        "open_settings", ["NumLock + I"],
                        "overview_toggle", ["NumLock + Tab", "NumLock + Space"],
                        "panic_key", ["NumLock + Insert"],
                        "pocket_cycle", ["NumLock + F"],
                        "pocket_summon", ["NumLock + MButton"],
                        "pocket_toggle_window", ["NumLock + C"],
                        "reload_script", ["NumLock + Ctrl + R"],
                        "window_close", ["NumLock + Q"],
                        "window_minimize", ["NumLock + A"],
                        "window_mouse_modifier", ["NumLock"],
                        "window_pin", ["NumLock + E"],
                        "workspace_move_1", ["NumLock + Shift + 1"],
                        "workspace_move_2", ["NumLock + Shift + 2"],
                        "workspace_move_3", ["NumLock + Shift + 3"],
                        "workspace_move_4", ["NumLock + Shift + 4"],
                        "workspace_move_5", ["NumLock + Shift + 5"],
                        "workspace_move_6", ["NumLock + Shift + 6"],
                        "workspace_move_7", ["NumLock + Shift + 7"],
                        "workspace_move_8", ["NumLock + Shift + 8"],
                        "workspace_move_9", ["NumLock + Shift + 9"],
                        "workspace_next", ["NumLock + X", "NumLock + WheelDown"],
                        "workspace_prev", ["NumLock + Z", "NumLock + WheelUp"],
                        "workspace_switch_1", ["NumLock + 1"],
                        "workspace_switch_2", ["NumLock + 2"],
                        "workspace_switch_3", ["NumLock + 3"],
                        "workspace_switch_4", ["NumLock + 4"],
                        "workspace_switch_5", ["NumLock + 5"],
                        "workspace_switch_6", ["NumLock + 6"],
                        "workspace_switch_7", ["NumLock + 7"],
                        "workspace_switch_8", ["NumLock + 8"],
                        "workspace_switch_9", ["NumLock + 9"]
                    )
                )
            ),
            "general", Map(
                "osd", Map(
                    "fontSize", 13,
                    "position", "bottom_center",
                    "posYPercent", 82,
                    "hideDelayMs", 400
                ),
                "titleBar", Map(
                    "autoHide", true,
                    "darkTheme", true,
                    "triggerHeightMaximized", 10,
                    "triggerHeightFloating", 10
                ),
                "taskbar", Map(
                    "hideTaskList", false
                ),
                "altTab", Map(
                    "enabled", true,
                    "showWorkspaceBadge", true
                )
            ),
            "appearance", Map(
                "animationsEnabled", true,
                "animationDurationMs", 200,
                "colors", Map(
                    "workspaceBorderHover", "#0078D7",
                    "pocketTheme", "#FFDB58",
                    "windowDragPulse", "#0078D7",
                    "windowDragPulseWidth", 3,
                    "pocketWindowBorder", "#FFDB58",
                    "pocketBorderWidth", 2
                )
            ),
            "workspaces", Map(
                "maxWorkspacesPerMonitor", [8, 4, 4, 4]
            ),
            "titleBar", Map(
                "triggerHeightMaximized", 10,
                "triggerHeightFloating", 10,
                "visibleHeight", 40
            ),
            "altTab", Map(
                "enabled", true,
                "showWorkspaceBadge", true
            ),
            "rules", Map(
                "groupedProcesses", ["prismlauncher.exe"],
                "ignoreProcesses", []
            )
        )
    }

    static Load() {
        defaultConfig := this.GetDefaultConfig()

        if FileExist(this.configPath) {
            try {
                raw := FileRead(this.configPath, "UTF-8")
                loaded := JSON.Load(raw)
                if (loaded is Map) {
                    loaded := this._NormalizeParsedJSON(loaded)
                    if (!loaded.Has("hotkeys") || !(loaded["hotkeys"] is Map) || !loaded["hotkeys"].Has("profiles")) {
                        loaded["hotkeys"] := defaultConfig["hotkeys"]
                    }
                    this.configData := this._MergeMaps(defaultConfig, loaded)
                } else {
                    this.configData := defaultConfig
                }
            } catch {
                this.configData := defaultConfig
            }
        } else {
            this.configData := defaultConfig
            this.Save()
        }

        this.ApplyToRuntime()
    }

    static Save(newConfigMap := "") {
        if (newConfigMap is Map)
            this.configData := newConfigMap

        try {
            this.configData := this._NormalizeParsedJSON(this.configData)
            jsonStr := JSON.Dump(this.configData, "  ")
            if FileExist(this.configPath)
                FileDelete(this.configPath)
            FileAppend(jsonStr, this.configPath, "UTF-8")
            this.ApplyToRuntime()
            return true
        } catch {
            return false
        }
    }

    static Get(keyPath, defaultVal := "") {
        keys := StrSplit(keyPath, ".")
        curr := this.configData
        for k in keys {
            if (curr is Map && curr.Has(k))
                curr := curr[k]
            else
                return defaultVal
        }
        return curr
    }

    static Set(keyPath, val) {
        keys := StrSplit(keyPath, ".")
        curr := this.configData
        lastIdx := keys.Length
        for i, k in keys {
            if (i == lastIdx) {
                curr[k] := val
            } else {
                if (!curr.Has(k) || !(curr[k] is Map))
                    curr[k] := Map()
                curr := curr[k]
            }
        }
        this.Save()
    }

    static ApplyToRuntime() {
        global Rules, maxWorkspacesPerMon, triggerHeightMaximized, triggerHeightFloating, titleBarVisibleHeight, titleBarInfo

        if this.configData.Has("workspaces") && this.configData["workspaces"].Has("maxWorkspacesPerMonitor") {
            maxList := this.configData["workspaces"]["maxWorkspacesPerMonitor"]
            if (maxList is Array)
                maxWorkspacesPerMon := maxList
        }

        if this.configData.Has("titleBar") {
            tb := this.configData["titleBar"]
            if tb.Has("triggerHeightMaximized")
                triggerHeightMaximized := tb["triggerHeightMaximized"]
            if tb.Has("triggerHeightFloating")
                triggerHeightFloating := tb["triggerHeightFloating"]
            if tb.Has("visibleHeight")
                titleBarVisibleHeight := tb["visibleHeight"]
        }

        if this.configData.Has("general") && this.configData["general"].Has("titleBar") {
            tb := this.configData["general"]["titleBar"]
            if tb.Has("triggerHeightMaximized")
                triggerHeightMaximized := tb["triggerHeightMaximized"]
            if tb.Has("triggerHeightFloating")
                triggerHeightFloating := tb["triggerHeightFloating"]
            
            ; При изменении настроек в рантайме обновляем окна
            if tb.Has("autoHide") && !tb["autoHide"] {
                for hwnd, info in titleBarInfo {
                    if (info.hidden && WinExist("ahk_id " hwnd))
                        ShowTitleBar(hwnd, info)
                }
            }
            if tb.Has("darkTheme") {
                isDark := tb["darkTheme"]
                for hwnd, info in titleBarInfo {
                    if WinExist("ahk_id " hwnd) && info.eligible {
                        info.themedActive := -1
                        ApplyTitleBarTheme(hwnd, WinActive("ahk_id " hwnd))
                    }
                }
            }
        }

        if this.configData.Has("general") && this.configData["general"].Has("taskbar") {
            tbSettings := this.configData["general"]["taskbar"]
            if tbSettings.Has("hideTaskList") {
                this.ApplyTaskbarVisibility(tbSettings["hideTaskList"])
            }
        }

        if this.configData.Has("appearance") {
            appConf := this.configData["appearance"]
            if appConf.Has("colors") && (appConf["colors"] is Map) {
                cols := appConf["colors"]
                if cols.Has("pocketWindowBorder") {
                    PocketManager.borderColor := StrReplace(cols["pocketWindowBorder"], "#", "")
                }
                if cols.Has("pocketBorderWidth") {
                    PocketManager.borderWidth := Integer(cols["pocketBorderWidth"])
                }
            }
        }

        if this.configData.Has("rules") {
            r := this.configData["rules"]
            if r.Has("groupedProcesses") && (r["groupedProcesses"] is Array) {
                Rules.groupedProcesses := Map()
                for p in r["groupedProcesses"]
                    Rules.groupedProcesses[StrLower(p)] := true
            }
            if r.Has("ignoreProcesses") && (r["ignoreProcesses"] is Array) {
                Rules.ignoreProcesses := Map()
                for p in r["ignoreProcesses"]
                    Rules.ignoreProcesses[StrLower(p)] := true
            }
        }
    }

    static ApplyTaskbarVisibility(hideTaskList) {
        try {
            if WinExist("ahk_class Shell_TrayWnd") {
                if (hideTaskList)
                    ControlHide("MSTaskListWClass1", "ahk_class Shell_TrayWnd")
                else
                    ControlShow("MSTaskListWClass1", "ahk_class Shell_TrayWnd")
            }
            for sHwnd in WinGetList("ahk_class Shell_SecondaryTrayWnd") {
                if (hideTaskList)
                    ControlHide("MSTaskListWClass1", "ahk_id " sHwnd)
                else
                    ControlShow("MSTaskListWClass1", "ahk_id " sHwnd)
            }
        }
    }

    static _NormalizeParsedJSON(node) {
        if (node is Array) {
            newArr := []
            for item in node
                newArr.Push(this._NormalizeParsedJSON(item))
            return newArr
        }
        if !(node is Map)
            return node

        isIndexedList := (node.Count > 0)
        Loop node.Count {
            if !node.Has(String(A_Index - 1)) {
                isIndexedList := false
                break
            }
        }

        if (isIndexedList) {
            arr := []
            Loop node.Count {
                val := node[String(A_Index - 1)]
                arr.Push(this._NormalizeParsedJSON(val))
            }
            return arr
        }

        normalizedMap := Map()
        for k, v in node
            normalizedMap[k] := this._NormalizeParsedJSON(v)
        return normalizedMap
    }

    static _MergeMaps(target, source) {
        merged := Map()
        for k, v in target
            merged[k] := v
        for k, v in source {
            if (merged.Has(k) && (merged[k] is Map) && (v is Map))
                merged[k] := this._MergeMaps(merged[k], v)
            else
                merged[k] := v
        }
        return merged
    }
}
