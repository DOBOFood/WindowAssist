#Requires AutoHotkey v2.0

class ActionCatalog {
    static catalog := Map()

    static Init() {
        this.catalog := Map(
            "move_window_prefix", Map("type", "prefix"),
            "overview_toggle", () => OverviewController.Toggle(),
            "pocket_toggle_window", () => PocketManager.ToggleCurrentWindow(),
            "pocket_cycle", () => PocketManager.Cycle(),
            "pocket_summon", () => PocketManager.ToggleSummon(),
            "workspace_switch_1", () => (HotkeyManager.IsMovePrefixActive() ? MoveActiveWindowAndFollow(1) : SwitchWorkspace(GetCurrentTargetMonitor(), 1)),
            "workspace_switch_2", () => (HotkeyManager.IsMovePrefixActive() ? MoveActiveWindowAndFollow(2) : SwitchWorkspace(GetCurrentTargetMonitor(), 2)),
            "workspace_switch_3", () => (HotkeyManager.IsMovePrefixActive() ? MoveActiveWindowAndFollow(3) : SwitchWorkspace(GetCurrentTargetMonitor(), 3)),
            "workspace_switch_4", () => (HotkeyManager.IsMovePrefixActive() ? MoveActiveWindowAndFollow(4) : SwitchWorkspace(GetCurrentTargetMonitor(), 4)),
            "workspace_switch_5", () => (HotkeyManager.IsMovePrefixActive() ? MoveActiveWindowAndFollow(5) : SwitchWorkspace(GetCurrentTargetMonitor(), 5)),
            "workspace_switch_6", () => (HotkeyManager.IsMovePrefixActive() ? MoveActiveWindowAndFollow(6) : SwitchWorkspace(GetCurrentTargetMonitor(), 6)),
            "workspace_switch_7", () => (HotkeyManager.IsMovePrefixActive() ? MoveActiveWindowAndFollow(7) : SwitchWorkspace(GetCurrentTargetMonitor(), 7)),
            "workspace_switch_8", () => (HotkeyManager.IsMovePrefixActive() ? MoveActiveWindowAndFollow(8) : SwitchWorkspace(GetCurrentTargetMonitor(), 8)),
            "workspace_switch_9", () => (HotkeyManager.IsMovePrefixActive() ? MoveActiveWindowAndFollow(9) : SwitchWorkspace(GetCurrentTargetMonitor(), 9)),
            "workspace_move_1", () => MoveActiveWindowAndFollow(1),
            "workspace_move_2", () => MoveActiveWindowAndFollow(2),
            "workspace_move_3", () => MoveActiveWindowAndFollow(3),
            "workspace_move_4", () => MoveActiveWindowAndFollow(4),
            "workspace_move_5", () => MoveActiveWindowAndFollow(5),
            "workspace_move_6", () => MoveActiveWindowAndFollow(6),
            "workspace_move_7", () => MoveActiveWindowAndFollow(7),
            "workspace_move_8", () => MoveActiveWindowAndFollow(8),
            "workspace_move_9", () => MoveActiveWindowAndFollow(9),
            "workspace_prev", () => (HotkeyManager.IsMovePrefixActive() ? MoveActiveWindowDeltaAndFollow(-1) : SwitchWorkspaceDelta(-1)),
            "workspace_next", () => (HotkeyManager.IsMovePrefixActive() ? MoveActiveWindowDeltaAndFollow(1) : SwitchWorkspaceDelta(1)),
            "window_close", CloseActiveWindow,
            "window_minimize", MinimizeActiveWindow,
            "window_pin", () => ToggleFloatingWindows(),
            "layer_peeker", () => LayerPeeker.OnClick(),
            "window_mouse_modifier", Map("type", "prefix"),
            "window_mouse_move", () => MoveWindowWithMouse(),
            "window_mouse_resize", () => ResizeWindowWithMouse(),
            "open_settings", () => OpenSettingsWindow(),
            "reload_script", () => Reload(),
            "panic_key", () => HotkeyManager.TriggerPanic(),
            "alt_tab", () => CrossWorkspaceAltTab.Cycle(1)
        )
    }

    static Get(actionKey) {
        if (!this.catalog.Count)
            this.Init()
        return this.catalog.Has(actionKey) ? this.catalog[actionKey] : 0
    }
}

CloseActiveWindow() {
    try WinClose("A")
}

MinimizeActiveWindow() {
    try WinMinimize("A")
}

class HotkeyManager {
    static activeBinds := []
    static currentModifiers := ["NumLock + Shift"]
    static isRecording := false

    static CreateModifierCondition(hasCtrl, hasShift, hasAlt, hasWin, allowMovePrefix := false) {
        return (*) => (
            (hasCtrl ? GetKeyState("Ctrl", "P") : !GetKeyState("Ctrl", "P")) &&
            (hasShift ? GetKeyState("Shift", "P") : (!GetKeyState("Shift", "P") || (allowMovePrefix && HotkeyManager.IsMovePrefixActive()))) &&
            (hasAlt ? GetKeyState("Alt", "P") : !GetKeyState("Alt", "P")) &&
            (hasWin ? (GetKeyState("LWin", "P") || GetKeyState("RWin", "P")) : (!GetKeyState("LWin", "P") && !GetKeyState("RWin", "P")))
        )
    }

    static Init() {
        ActionCatalog.Init()
        this.RegisterBaseHooks()
        this.ApplyProfile()
        return true
    }

    static IsMovePrefixActive() {
        global pendingMove
        if (pendingMove.hwnd && WinExist("ahk_id " pendingMove.hwnd))
            return true

        return this.AreMovePrefixKeysPressed()
    }

    static AreMovePrefixKeysPressed() {
        if (this.currentModifiers.Length == 0)
            return false

        for pref in this.currentModifiers {
            if this.CheckShortcutPressed(pref)
                return true
        }
        return false
    }

    static CheckShortcutPressed(str) {
        parts := StrSplit(Trim(str), "+")
        if (parts.Length == 0)
            return false

        for p in parts {
            k := Trim(p)
            if (k == "")
                continue
            switch k, false {
                case "Ctrl", "Control":
                    if (!GetKeyState("Ctrl", "P"))
                        return false
                case "Alt":
                    if (!GetKeyState("Alt", "P"))
                        return false
                case "Shift":
                    if (!GetKeyState("Shift", "P"))
                        return false
                case "Win":
                    if (!GetKeyState("LWin", "P") && !GetKeyState("RWin", "P"))
                        return false
                default:
                    if (!GetKeyState(k, "P"))
                        return false
            }
        }
        return true
    }

    static RegisterBaseHooks() {
        ; Динамический хук переноса окон по префиксу move_window_prefix
        this.RegisterPrefixHooks()
    }

    static RegisterPrefixHooks() {
        ; Базовые физические хуки для NumLock + Shift
        try {
            Hotkey("*NumLock", (*) => (this.AreMovePrefixKeysPressed() ? StartPendingMove() : 0), "On")
            Hotkey("*NumLock Up", (*) => (!this.AreMovePrefixKeysPressed() ? EndPendingMove() : 0), "On")
            Hotkey("~*LShift Up", (*) => (!this.AreMovePrefixKeysPressed() ? EndPendingMove() : 0), "On")
            Hotkey("~*RShift Up", (*) => (!this.AreMovePrefixKeysPressed() ? EndPendingMove() : 0), "On")
            Hotkey("~*LShift", (*) => (this.AreMovePrefixKeysPressed() ? StartPendingMove() : 0), "On")
            Hotkey("~*RShift", (*) => (this.AreMovePrefixKeysPressed() ? StartPendingMove() : 0), "On")
        }

        ; Дополнительно вешаем хук на любую произвольную комбинацию из move_window_prefix
        for pref in this.currentModifiers {
            s := Trim(pref)
            if (s == "")
                continue
            
            parts := StrSplit(s, "+")
            lastPart := Trim(parts[parts.Length])
            mods := ""
            Loop parts.Length - 1 {
                p := Trim(parts[A_Index])
                switch p, false {
                    case "Ctrl", "Control": mods .= "^"
                    case "Alt": mods .= "!"
                    case "Shift": mods .= "+"
                    case "Win": mods .= "#"
                }
            }

            try {
                downKey := "~*" mods lastPart
                upKey := "~*" mods lastPart " Up"
                
                Hotkey(downKey, (*) => (this.AreMovePrefixKeysPressed() ? StartPendingMove() : 0), "On")
                Hotkey(upKey, (*) => EndPendingMove(), "On")
            }
        }
    }

    static UnbindAll() {
        for item in this.activeBinds {
            try {
                if (item.condFunc) {
                    HotIf(item.condFunc)
                    Hotkey(item.key, "Off")
                    HotIf()
                } else {
                    Hotkey(item.key, "Off")
                }
            }
        }
        this.activeBinds := []
    }

    static ApplyProfile(profileName := "") {
        this.UnbindAll()

        if (this.isRecording)
            return

        if (profileName == "")
            profileName := ConfigManager.Get("hotkeys.activeProfile", "default")

        profiles := ConfigManager.Get("hotkeys.profiles", Map())
        if (!profiles.Has(profileName))
            profileName := "default"

        if (!profiles.Has(profileName))
            return

        binds := profiles[profileName]
        if !(binds is Map)
            return

        ; Сначала считываем move_window_prefix
        if binds.Has("move_window_prefix") {
            this.currentModifiers := this._ToArrayList(binds["move_window_prefix"])
            this.RegisterPrefixHooks()
        }

        delayedBinds := []

        ; Обработка модификатора мыши (перемещение - ЛКМ, изменение размера - ПКМ)
        mouseMods := binds.Has("window_mouse_modifier") ? this._ToArrayList(binds["window_mouse_modifier"]) : []
        ; Обратная совместимость, если в профиле старые ключи window_mouse_move / resize
        if (mouseMods.Length == 0 && binds.Has("window_mouse_move")) {
            for m in this._ToArrayList(binds["window_mouse_move"]) {
                cleaned := RegExReplace(m, "\s*\+\s*LButton.*$", "")
                if (cleaned != "" && cleaned != m)
                    mouseMods.Push(cleaned)
            }
        }
        if (mouseMods.Length == 0)
            mouseMods := ["NumLock"]

        for mMod in mouseMods {
            moveSc := Trim(mMod) " + LButton"
            resizeSc := Trim(mMod) " + RButton"
            
            for desc in this.ParseShortcutString(moveSc, false) {
                if (desc["cond"] != 0)
                    this._RegisterSingle(desc["key"], desc["cond"], ActionCatalog.Get("window_mouse_move"), moveSc)
                else
                    delayedBinds.Push({desc: desc, fn: ActionCatalog.Get("window_mouse_move"), scStr: moveSc})
            }
            for desc in this.ParseShortcutString(resizeSc, false) {
                if (desc["cond"] != 0)
                    this._RegisterSingle(desc["key"], desc["cond"], ActionCatalog.Get("window_mouse_resize"), resizeSc)
                else
                    delayedBinds.Push({desc: desc, fn: ActionCatalog.Get("window_mouse_resize"), scStr: resizeSc})
            }
        }

        for actionKey, shortcutVal in binds {
            if (actionKey == "move_window_prefix" || actionKey == "window_mouse_modifier" || actionKey == "window_mouse_move" || actionKey == "window_mouse_resize" || actionKey == "layer_peeker")
                continue

            shortcutList := this._ToArrayList(shortcutVal)
            if (shortcutList.Length == 0)
                continue

            actionFn := ActionCatalog.Get(actionKey)
            if (!actionFn)
                continue

            allowMovePrefix := (actionKey = "workspace_prev" || actionKey = "workspace_next" || SubStr(actionKey, 1, 17) = "workspace_switch_")

            for scStr in shortcutList {
                descriptors := this.ParseShortcutString(scStr, allowMovePrefix)
                for desc in descriptors {
                    if (desc["cond"] != 0) {
                        this._RegisterSingle(desc["key"], desc["cond"], actionFn, scStr)
                    } else {
                        delayedBinds.Push({desc: desc, fn: actionFn, scStr: scStr})
                    }
                }
            }
        }

        for item in delayedBinds {
            this._RegisterSingle(item.desc["key"], item.desc["cond"], item.fn, item.scStr)
        }
    }

    static _RegisterSingle(key, cond, actionFn, scStr) {
        try {
            if (cond != 0) {
                HotIf(cond)
                Hotkey(key, (*) => (actionFn()), "On")
                HotIf()
            } else {
                Hotkey(key, (*) => (actionFn()), "On")
            }

            this.activeBinds.Push({
                key: key,
                condFunc: cond,
                str: scStr
            })
        }
    }

    static _ToArrayList(val) {
        if (val is Array)
            return val
        arr := []
        if (val is Map) {
            Loop val.Count {
                idxKey := String(A_Index - 1)
                if val.Has(idxKey)
                    arr.Push(val[idxKey])
            }
            if (arr.Length == 0) {
                for k, v in val
                    arr.Push(v)
            }
        } else if (val != "") {
            arr.Push(String(val))
        }
        return arr
    }

    static ParseShortcutString(str, allowMovePrefix := false) {
        s := Trim(String(str))
        if (s == "")
            return []

        parts := StrSplit(s, "+")
        clean := []
        for p in parts {
            t := Trim(p)
            if (t != "")
                clean.Push(t)
        }
        if (clean.Length == 0)
            return []

        if (clean.Length == 1) {
            k := clean[1]
            return [Map("key", k, "cond", 0)]
        }

        hasNumLock := false
        hasShift := false
        hasCtrl := false
        hasAlt := false
        hasWin := false
        otherPrefix := ""
        key := clean[clean.Length]

        Loop clean.Length - 1 {
            p := clean[A_Index]
            switch p, false {
                case "NumLock": hasNumLock := true
                case "Shift": hasShift := true
                case "Ctrl", "Control": hasCtrl := true
                case "Alt": hasAlt := true
                case "Win": hasWin := true
                default: otherPrefix := p
            }
        }

        ; Пользовательские двухклавишные сочетания (например, "Tab + Win")
        if (otherPrefix != "") {
            cond := this.CreateModifierCondition(hasCtrl, hasShift, hasAlt, hasWin, allowMovePrefix)
            if (key = "Win")
                return [
                    Map("key", otherPrefix " & LWin", "cond", cond),
                    Map("key", otherPrefix " & RWin", "cond", cond)
                ]
            if (key = "Alt")
                return [
                    Map("key", otherPrefix " & LAlt", "cond", cond),
                    Map("key", otherPrefix " & RAlt", "cond", cond)
                ]
            if (key = "Ctrl" || key = "Control")
                return [
                    Map("key", otherPrefix " & LCtrl", "cond", cond),
                    Map("key", otherPrefix " & RCtrl", "cond", cond)
                ]
            if (key = "Shift")
                return [
                    Map("key", otherPrefix " & LShift", "cond", cond),
                    Map("key", otherPrefix " & RShift", "cond", cond)
                ]
            return [Map("key", otherPrefix " & " key, "cond", cond)]
        }

        ; Сочетания с NumLock как модификатором
        if (hasNumLock) {
            ahkKey := (StrLen(key) == 1) ? StrLower(key) : key
            cond := this.CreateModifierCondition(hasCtrl, hasShift, hasAlt, hasWin, allowMovePrefix)
            return [Map("key", "NumLock & " ahkKey, "cond", cond)]
        }

        ; Стандартные модификаторы Win, Ctrl, Alt, Shift
        mods := (hasWin ? "#" : "") (hasCtrl ? "^" : "") (hasAlt ? "!" : "") (hasShift ? "+" : "")
        ahkKey := (StrLen(key) == 1) ? StrLower(key) : key
        return [Map("key", mods ahkKey, "cond", 0)]
    }

    static StartRecording() {
        this.isRecording := true
        Suspend(true)
    }

    static StopRecording() {
        this.isRecording := false
        Suspend(false)
        this.ApplyProfile()
    }

    static TriggerPanic() {
        ExitApp()
    }
}

OpenSettingsWindow() {
    static settingsGui := 0
    static webInst := 0

    if (settingsGui && WinExist("ahk_id " settingsGui.Hwnd)) {
        WinActivate("ahk_id " settingsGui.Hwnd)
        if (webInst)
            WebViewManager.Send(webInst, Map("action", "LOAD_CONFIG", "config", ConfigManager.configData))
        return
    }

    settingsGui := Gui("+Resize", "Настройки WindowAssist")
    htmlFile := A_ScriptDir "\web\settings.html"
    
    onMsg := (data) => SettingsIPCHandler(data, webInst)

    webInst := WebViewManager.Create(settingsGui.Hwnd, htmlFile, onMsg)
    if (!webInst) {
        settingsGui.Destroy()
        settingsGui := 0
        webInst := 0
        return
    }

    settingsGui.OnEvent("Size", (guiObj, minMax, w, h) => WebViewManager.Resize(webInst, w, h))
    settingsGui.OnEvent("Close", (guiObj) => (
        HotkeyManager.StopRecording(),
        WebViewManager.Destroy(guiObj.Hwnd),
        settingsGui := 0,
        webInst := 0
    ))

    settingsGui.Show("w860 h620 Center")
    WebViewManager.Resize(webInst, 860, 620)

    ; Передаем актуальный конфиг в веб-форму
    SetTimer(() => WebViewManager.Send(webInst, Map("action", "LOAD_CONFIG", "config", ConfigManager.configData)), -200)
    SetTimer(() => WebViewManager.Send(webInst, Map("action", "LOAD_CONFIG", "config", ConfigManager.configData)), -600)
}

SettingsIPCHandler(data, webInst) {
    if !(data is Map) || !data.Has("action")
        return

    action := data["action"]

    if (action == "START_KEY_RECORDING") {
        HotkeyManager.StartRecording()
    }
    else if (action == "STOP_KEY_RECORDING") {
        HotkeyManager.StopRecording()
    }
    else if (action == "SET_SETTING") {
        if (data.Has("key") && data.Has("value")) {
            keyPath := data["key"]
            val := data["value"]
            ConfigManager.Set(keyPath, val)

            activeProf := ConfigManager.Get("hotkeys.activeProfile", "default")
            if InStr(keyPath, "hotkeys.profiles." activeProf) || InStr(keyPath, "hotkeys.activeProfile") {
                HotkeyManager.ApplyProfile(activeProf)
            }
        }
    }
    else if (action == "SWITCH_KEYBIND_PROFILE") {
        if data.Has("profile") {
            newProf := data["profile"]
            ConfigManager.Set("hotkeys.activeProfile", newProf)
            HotkeyManager.ApplyProfile(newProf)
        }
    }
    else if (action == "SAVE_KEYBIND_PROFILE") {
        if data.Has("profile") {
            pName := data["profile"]
            binds := data.Has("binds") && (data["binds"] is Map) ? data["binds"] : Map()
            
            profiles := ConfigManager.Get("hotkeys.profiles", Map())
            profiles[pName] := binds
            ConfigManager.Set("hotkeys.profiles", profiles)
            ConfigManager.Set("hotkeys.activeProfile", pName)
            HotkeyManager.ApplyProfile(pName)
        }
    }
    else if (action == "RENAME_KEYBIND_PROFILE") {
        if data.Has("oldName") && data.Has("newName") {
            oldName := data["oldName"]
            newName := data["newName"]
            profiles := ConfigManager.Get("hotkeys.profiles", Map())
            if profiles.Has(oldName) {
                binds := profiles[oldName]
                profiles.Delete(oldName)
                profiles[newName] := binds
                ConfigManager.Set("hotkeys.profiles", profiles)
                ConfigManager.Set("hotkeys.activeProfile", newName)
                HotkeyManager.ApplyProfile(newName)
            }
        }
    }
    else if (action == "DELETE_KEYBIND_PROFILE") {
        if data.Has("profile") {
            pName := data["profile"]
            if (pName != "default") {
                profiles := ConfigManager.Get("hotkeys.profiles", Map())
                if profiles.Has(pName)
                    profiles.Delete(pName)
                ConfigManager.Set("hotkeys.profiles", profiles)
                ConfigManager.Set("hotkeys.activeProfile", "default")
                HotkeyManager.ApplyProfile("default")
            }
        }
    }
}
