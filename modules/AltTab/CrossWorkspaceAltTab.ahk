#Requires AutoHotkey v2.0

class CrossWorkspaceAltTab {
    static isShowing := false
    static guiObj := 0
    static entries := []
    static selectedIndex := 1
    static historyPerMon := Map() ; Key: mon (int), Val: Array of hwnd (MRU order: [newest, ..., oldest])
    static activeIcons := []
    static targetMon := 1
    static guiBounds := {x: 0, y: 0, w: 0, h: 0}

    static Init() {
        Hotkey("!Tab", ObjBindMethod(this, "OnAltTab"), "On")
        Hotkey("!+Tab", ObjBindMethod(this, "OnAltShiftTab"), "On")
    }

    static RecordActiveWindow(hwnd) {
        global wsWindows
        if (!hwnd || !wsWindows.Has(hwnd))
            return
        ; Окна кармана не сохраняем в историю Alt+Tab
        if (PocketManager.IsInPocket(hwnd))
            return
        info := wsWindows[hwnd]
        if (info.isOffscreen)
            return

        mon := info.mon
        if (!this.historyPerMon.Has(mon))
            this.historyPerMon[mon] := []

        list := this.historyPerMon[mon]

        ; Удаляем окно из предыдущей позиции в истории, если оно уже там было
        for idx, h in list {
            if (h == hwnd) {
                list.RemoveAt(idx)
                break
            }
        }
        ; Добавляем на 1 место в истории (MRU: 1 = текущее активное окно)
        list.InsertAt(1, hwnd)
    }

    static RemoveWindow(hwnd) {
        for mon, list in this.historyPerMon {
            for idx, h in list {
                if (h == hwnd) {
                    list.RemoveAt(idx)
                    break
                }
            }
        }
    }

    static OnAltTab(hotkeyName) {
        if !ConfigManager.Get("altTab.enabled", true) {
            Send("!{Tab}")
            return
        }
        this.Cycle(1)
    }

    static OnAltShiftTab(hotkeyName) {
        if !ConfigManager.Get("altTab.enabled", true) {
            Send("!+{Tab}")
            return
        }
        this.Cycle(-1)
    }

    static Cycle(direction := 1) {
        if (!this.isShowing) {
            this.BuildCandidateList()
            if (this.entries.Length == 0)
                return

            if (direction > 0)
                this.selectedIndex := (this.entries.Length > 1) ? 2 : 1
            else
                this.selectedIndex := this.entries.Length

            this.ShowGui()
            SetTimer(ObjBindMethod(this, "WatchEvents"), 15)
        } else {
            count := this.entries.Length
            this.selectedIndex += direction
            if (this.selectedIndex > count)
                this.selectedIndex := 1
            if (this.selectedIndex < 1)
                this.selectedIndex := count
            this.UpdateSelection()
        }
    }

    static GetHIcon(hwnd) {
        if (!hwnd || !DllCall("IsWindow", "Ptr", hwnd, "Int"))
            return 0

        hIcon := 0
        ; 1. Запрос WM_GETICON (ICON_BIG) с таймаутом (SMTO_ABORTIFHUNG = 0x0002, 10ms)
        hIcon := 0
        DllCall("SendMessageTimeout", "Ptr", hwnd, "UInt", 0x007F, "Ptr", 1, "Ptr", 0, "UInt", 0x0002, "UInt", 10, "Ptr*", &hIcon)
        ; 2. Запрос WM_GETICON (ICON_SMALL2) с таймаутом
        if (!hIcon)
            DllCall("SendMessageTimeout", "Ptr", hwnd, "UInt", 0x007F, "Ptr", 2, "Ptr", 0, "UInt", 0x0002, "UInt", 10, "Ptr*", &hIcon)
        ; 3. Классовая иконка GCLP_HICON (-14)
        if (!hIcon)
            hIcon := DllCall("GetClassLongPtr", "Ptr", hwnd, "Int", -14, "Ptr")
        ; 4. Извлечение первой иконки из exe-файла
        if (!hIcon) {
            try {
                exePath := WinGetProcessPath("ahk_id " hwnd)
                hIconBuf := Buffer(A_PtrSize, 0)
                if (DllCall("shell32\ExtractIconExW", "WStr", exePath, "Int", 0, "Ptr", hIconBuf, "Ptr", 0, "UInt", 1) > 0)
                    hIcon := NumGet(hIconBuf, 0, "Ptr")
            }
        }
        return hIcon
    }

    static BuildCandidateList() {
        global wsWindows, currentWorkspaces
        this.entries := []

        curMon := GetCurrentTargetMonitor()
        this.targetMon := curMon

        fgHwnd := 0
        try fgHwnd := WinGetID("A")
        if (fgHwnd && wsWindows.Has(fgHwnd) && !wsWindows[fgHwnd].isOffscreen && !PocketManager.IsInPocket(fgHwnd)) {
            this.RecordActiveWindow(fgHwnd)
        }

        seenHwnds := Map()
        seenWs := Map()

        ; 1. Добавляем окна из истории текущего монитора (MRU порядок)
        if (this.historyPerMon.Has(curMon)) {
            cleanList := []
            for hwnd in this.historyPerMon[curMon] {
                if (hwnd && WinExist("ahk_id " hwnd) && wsWindows.Has(hwnd)) {
                    if (PocketManager.IsInPocket(hwnd))
                        continue

                    info := wsWindows[hwnd]
                    if (info.mon == curMon) {
                        cleanList.Push(hwnd)
                        if (!seenHwnds.Has(hwnd) && !seenWs.Has(info.ws)) {
                            seenHwnds[hwnd] := true
                            seenWs[info.ws] := true
                            title := WinGetTitle("ahk_id " hwnd)
                            if (title == "")
                                title := WinGetProcessName("ahk_id " hwnd)

                            hIcon := this.GetHIcon(hwnd)
                            this.entries.Push({
                                hwnd: hwnd,
                                mon: info.mon,
                                ws: info.ws,
                                title: title,
                                hIcon: hIcon
                            })
                        }
                    }
                }
            }
            this.historyPerMon[curMon] := cleanList
        }

        ; 2. Добавляем остальные существующие окна текущего монитора
        for hwnd, info in wsWindows {
            if (PocketManager.IsInPocket(hwnd))
                continue

            if (info.mon == curMon && !seenHwnds.Has(hwnd) && !seenWs.Has(info.ws) && WinExist("ahk_id " hwnd)) {
                seenHwnds[hwnd] := true
                seenWs[info.ws] := true
                title := WinGetTitle("ahk_id " hwnd)
                if (title == "")
                    title := WinGetProcessName("ahk_id " hwnd)

                hIcon := this.GetHIcon(hwnd)
                this.entries.Push({
                    hwnd: hwnd,
                    mon: info.mon,
                    ws: info.ws,
                    title: title,
                    hIcon: hIcon
                })
            }
        }
    }

    ; Форматирование заголовка на 2 строки без лишних отступов и с многоточием
    static FormatTwoLineTitle(title, maxPerLine := 16) {
        title := Trim(title)
        if (StrLen(title) <= maxPerLine)
            return title

        line1 := Trim(SubStr(title, 1, maxPerLine))
        rem := Trim(SubStr(title, maxPerLine + 1))

        if (StrLen(rem) <= maxPerLine)
            return line1 . "`n" . rem
        else
            return line1 . "`n" . SubStr(rem, 1, maxPerLine - 2) . "..."
    }

    static ShowGui() {
        this.CleanupGui()

        this.guiObj := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x08000000")
        this.guiObj.BackColor := "1E1E1E"
        this.guiObj.SetFont("s9 cWhite", "Segoe UI Variable Text")

        this.itemControls := []
        itemW := 142, itemH := 126, gap := 12
        totalW := (itemW + gap) * this.entries.Length + gap
        totalH := itemH + gap * 2

        this.guiObj.MarginX := gap
        this.guiObj.MarginY := gap

        for idx, item in this.entries {
            xPos := gap + (idx - 1) * (itemW + gap)
            
            ; 1. Внутренний серый квадрат (bgBox)
            bgBox := this.guiObj.Add("Text", "x" xPos " y" gap " w" itemW " h" itemH " Background252525")

            ; 2. Бейдж рабочего стола
            wsBadge := this.guiObj.Add("Text", "x" (xPos + 6) " y" (gap + 6) " w46 h20 Center Background3A3A3A cWhite", "WS " item.ws)
            
            ; 3. Иконка приложения (32x32) на y = gap + 30
            iconCtrl := 0
            if (item.hIcon) {
                try {
                    iconCtrl := this.guiObj.Add("Picture", "x" (xPos + (itemW - 32) // 2) " y" (gap + 30) " w32 h32 BackgroundTrans", "HICON:*" item.hIcon)
                    this.activeIcons.Push(item.hIcon)
                } catch {
                    iconCtrl := 0
                }
            }
            
            ; 4. Заголовок окна: ровно +10px под иконкой (y = gap + 30 + 32 + 10 = gap + 72)
            formattedTitle := this.FormatTwoLineTitle(item.title, 16)
            titleLabel := this.guiObj.Add("Text", "x" (xPos + 6) " y" (gap + 72) " w" (itemW - 12) " h42 Center BackgroundTrans cCCCCCC", formattedTitle)

            ; 5. Четыре линии белой рамки (толщиной 2px), создаются ПОСЛЕ bgBox,
            ; благодаря чему они гарантированно находятся выше по Z-order и всегда отображаются поверх серого квадрата
            tLine := this.guiObj.Add("Text", "x" xPos " y" gap " w" itemW " h2 BackgroundFFFFFF")
            bLine := this.guiObj.Add("Text", "x" xPos " y" (gap + itemH - 2) " w" itemW " h2 BackgroundFFFFFF")
            lLine := this.guiObj.Add("Text", "x" xPos " y" gap " w2 h" itemH " BackgroundFFFFFF")
            rLine := this.guiObj.Add("Text", "x" (xPos + itemW - 2) " y" gap " w2 h" itemH " BackgroundFFFFFF")

            borders := [tLine, bLine, lLine, rLine]
            for b in borders
                b.Visible := false

            clickHandler := ObjBindMethod(CrossWorkspaceAltTab, "SelectAndExecute", idx)
            bgBox.OnEvent("Click", clickHandler)
            wsBadge.OnEvent("Click", clickHandler)
            if (iconCtrl)
                iconCtrl.OnEvent("Click", clickHandler)
            titleLabel.OnEvent("Click", clickHandler)
            tLine.OnEvent("Click", clickHandler)
            bLine.OnEvent("Click", clickHandler)
            lLine.OnEvent("Click", clickHandler)
            rLine.OnEvent("Click", clickHandler)

            this.itemControls.Push({
                bg: bgBox,
                badge: wsBadge,
                label: titleLabel,
                icon: iconCtrl,
                borders: borders
            })
        }

        ; Позиционируем окно ровно по центру целевого монитора
        mL := 0, mT := 0, mR := 0, mB := 0
        MonitorGet(this.targetMon, &mL, &mT, &mR, &mB)
        monW := mR - mL, monH := mB - mT
        guiX := mL + (monW - totalW) // 2
        guiY := mT + (monH - totalH) // 2

        this.guiBounds := {x: guiX, y: guiY, w: totalW, h: totalH}

        this.guiObj.Show("x" guiX " y" guiY " w" totalW " h" totalH " NoActivate")
        this.isShowing := true
        this.UpdateSelection()
    }

    static UpdateSelection() {
        if (!this.guiObj)
            return
        for idx, ctrlGroup in this.itemControls {
            isSelected := (idx == this.selectedIndex)
            for b in ctrlGroup.borders {
                try b.Visible := isSelected
            }

            if (isSelected) {
                try ctrlGroup.bg.Opt("Background4A4A4A")
                try ctrlGroup.label.Opt("cWhite")
            } else {
                try ctrlGroup.bg.Opt("Background252525")
                try ctrlGroup.label.Opt("cCCCCCC")
            }
        }
    }

    static WatchEvents() {
        if (!this.isShowing) {
            SetTimer(ObjBindMethod(this, "WatchEvents"), 0)
            return
        }

        ; 1. Отпускание клавиши Alt -> переключение на выбранное окно
        if !GetKeyState("Alt", "P") {
            SetTimer(ObjBindMethod(this, "WatchEvents"), 0)
            this.ExecuteSelection()
            return
        }

        ; 2. Клик мышью за пределами окна Alt+Tab -> закрытие
        if GetKeyState("LButton", "P") || GetKeyState("RButton", "P") {
            CoordMode("Mouse", "Screen")
            MouseGetPos(&mX, &mY)
            b := this.guiBounds
            if (mX < b.x || mX > b.x + b.w || mY < b.y || mY > b.y + b.h) {
                SetTimer(ObjBindMethod(this, "WatchEvents"), 0)
                this.CleanupGui()
                return
            }
        }
    }

    static SelectAndExecute(index, *) {
        if (this.isShowing) {
            this.selectedIndex := index
            SetTimer(ObjBindMethod(this, "WatchEvents"), 0)
            this.ExecuteSelection()
        }
    }

    static ExecuteSelection() {
        if (this.isShowing) {
            target := (this.entries.Length >= this.selectedIndex && this.selectedIndex > 0) ? this.entries[this.selectedIndex] : 0
            this.CleanupGui()

            if (target && target.hwnd && WinExist("ahk_id " target.hwnd)) {
                this.RecordActiveWindow(target.hwnd)
                SwitchWorkspace(target.mon, target.ws, target.hwnd)
            }
        }
    }

    static CleanupGui() {
        this.isShowing := false
        if (this.guiObj) {
            try this.guiObj.Destroy()
            this.guiObj := 0
        }
        this.itemControls := []
        for hIcon in this.activeIcons {
            try DllCall("DestroyIcon", "Ptr", hIcon)
        }
        this.activeIcons := []
    }
}
