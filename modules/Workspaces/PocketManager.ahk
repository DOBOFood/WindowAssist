#Requires AutoHotkey v2.0

class PocketManager {
    ; Список hwnd окон, находящихся в кармане
    static pocketWindows := []
    ; Текущий индекс активного окна из кармана (1-based)
    static currentIndex := 0
    ; Map hwnd -> Gui (обводка для каждого окна кармана)
    static borderGuis := Map()
    ; Map borderHwnd -> targetHwnd для мгновенного определения принадлежности рамки
    static borderHwndToTarget := Map()
    ; Последние известные координаты окон {x, y, w, h}
    static lastCoords := Map()
    ; Последняя установленная прозрачность окна/рамки
    static lastAlpha := Map()
    ; Цвет обводки (желтый, по умолчанию "FFD700")
    static borderColor := "FFD700"
    static borderWidth := 3
    ; Флаг работы сторожевого таймера
    static isWatchdogRunning := false

    static Init() {
        if (!this.isWatchdogRunning) {
            this.isWatchdogRunning := true
            ; Таймер 60 мс для плавной синхронизации рамки без перегрузки очередей сообщений
            SetTimer(() => this.Watchdog(), 60)
        }
    }

    ; Проверка, является ли данный hwnd окном рамки
    static IsBorderHwnd(hwnd) {
        return this.borderHwndToTarget.Has(hwnd)
    }

    ; Получение целевого окна приложения по hwnd его рамки
    static GetTargetFromBorder(hwnd) {
        return this.borderHwndToTarget.Has(hwnd) ? this.borderHwndToTarget[hwnd] : 0
    }

    ; Проверка: есть ли в данный момент хоть одно окно из кармана на экране (видимо и не свернуто)
    static GetVisiblePocketWindow() {
        for h in this.pocketWindows {
            if WinExist("ahk_id " h) {
                if (DllCall("user32\IsWindowVisible", "ptr", h) && WinGetMinMax("ahk_id " h) != -1) {
                    return h
                }
            }
        }
        return 0
    }

    ; Скрыть конкретное окно кармана с экрана (сворачивание + скрытие рамки)
    static HidePocketWindow(hwnd) {
        if (!hwnd || !WinExist("ahk_id " hwnd))
            return
        try WinSetTransparent("Off", "ahk_id " hwnd)
        if this.lastAlpha.Has(hwnd)
            this.lastAlpha.Delete(hwnd)
        try DllCall("ShowWindowAsync", "ptr", hwnd, "int", 6) ; SW_MINIMIZE
        if this.borderGuis.Has(hwnd) {
            try this.borderGuis[hwnd].Hide()
        }
    }

    ; Скрыть все окна кармана кроме исключенного (обеспечивает правило: не более 1 окна кармана на экране)
    static HideOtherPocketWindows(exceptHwnd := 0) {
        for h in this.pocketWindows {
            if (h != exceptHwnd && WinExist("ahk_id " h)) {
                this.HidePocketWindow(h)
            }
        }
    }

    ; Добавить/убрать активное окно в карман
    static ToggleCurrentWindow() {
        activeHwnd := WinExist("A")
        if (!activeHwnd)
            return

        ; Если активна рамка, получаем само приложение
        if this.IsBorderHwnd(activeHwnd)
            activeHwnd := this.GetTargetFromBorder(activeHwnd)

        ; Корневое окно
        rootHwnd := GetRootManagedWindow(activeHwnd)
        if (!rootHwnd)
            rootHwnd := activeHwnd

        this.ToggleWindow(rootHwnd)
    }

    ; Добавление / удаление конкретного окна
    static ToggleWindow(hwnd) {
        if (!hwnd || !WinExist("ahk_id " hwnd))
            return

        idx := this.FindIndex(hwnd)
        if (idx > 0) {
            this.RemoveWindow(hwnd)
        } else {
            this.AddWindow(hwnd)
        }
    }

    static AddWindow(hwnd) {
        global currentWorkspaces, wsWindows
        if (!hwnd || !WinExist("ahk_id " hwnd))
            return

        if (this.FindIndex(hwnd) > 0)
            return

        ; Если на экране уже есть окно из кармана, скрываем его с экрана
        this.HideOtherPocketWindows(hwnd)

        this.pocketWindows.Push(hwnd)
        this.currentIndex := this.pocketWindows.Length

        ; Отвязываем окно от любого конкретного рабочего стола (ws := 0)
        mon := GetWindowMonitor(hwnd)
        if wsWindows.Has(hwnd) {
            wsWindows[hwnd].ws := 0
            wsWindows[hwnd].mon := mon
            wsWindows[hwnd].isOffscreen := false
            SaveWindowProps(hwnd, wsWindows[hwnd])
        }

        ; Если Overview сейчас открыт, не активируем и не выводим окно поверх меню Overview
        if (OverviewController.isOpen) {
            ; Скрываем окно и не показываем рамку
            this.HidePocketWindow(hwnd)
        } else {
            ; Устанавливаем AlwaysOnTop и выводим на самый верх
            try WinSetAlwaysOnTop(true, "ahk_id " hwnd)
            try WinActivate("ahk_id " hwnd)
            this.UpdateBorder(hwnd)
            this.ApplyLayerHierarchy()
        }

        this.Init()
        this.NotifyOverview()
    }

    static RemoveWindow(hwnd) {
        global currentWorkspaces, wsWindows
        idx := this.FindIndex(hwnd)
        if (idx == 0)
            return

        this.pocketWindows.RemoveAt(idx)
        if (this.pocketWindows.Length == 0) {
            this.currentIndex := 0
        } else if (this.currentIndex > this.pocketWindows.Length) {
            this.currentIndex := this.pocketWindows.Length
        }

        try WinSetTransparent("Off", "ahk_id " hwnd)
        if this.lastAlpha.Has(hwnd)
            this.lastAlpha.Delete(hwnd)

        this.RemoveBorder(hwnd)
        try WinSetAlwaysOnTop(false, "ahk_id " hwnd)
        try DllCall("user32\SetWindowPos", "ptr", hwnd, "ptr", -2, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0003) ; HWND_NOTOPMOST

        ; При удалении из кармана окно начинает принадлежать текущему активному рабочему столу
        mon := GetWindowMonitor(hwnd)
        curWs := currentWorkspaces.Has(mon) ? currentWorkspaces[mon] : 1
        if wsWindows.Has(hwnd) {
            wsWindows[hwnd].ws := curWs
            wsWindows[hwnd].mon := mon
            wsWindows[hwnd].isOffscreen := false
            SaveWindowProps(hwnd, wsWindows[hwnd])
        }

        this.NotifyOverview()
    }

    ; Переключение между окнами в кармане (NumLock + F):
    ; - если ни одно окно кармана не вызвано на экран -> вызываем текущее без переключения
    ; - если хоть какое-то окно кармана уже на экране -> скрываем его и переключаемся на следующее
    static Cycle() {
        this.CleanupDeadWindows()
        count := this.pocketWindows.Length
        if (count == 0)
            return

        visibleHwnd := this.GetVisiblePocketWindow()

        if (!visibleHwnd) {
            ; На экране нет ни одного окна кармана -> просто вызываем текущее окно
            if (this.currentIndex < 1 || this.currentIndex > count)
                this.currentIndex := 1

            targetHwnd := this.pocketWindows[this.currentIndex]
            this.ActivatePocketWindow(targetHwnd)
            return
        }

        ; Если в кармане всего одно окно и оно уже на экране — просто активируем его
        if (count == 1) {
            targetHwnd := this.pocketWindows[1]
            this.ActivatePocketWindow(targetHwnd)
            return
        }

        ; На экране уже есть окно из кармана -> скрываем его и переключаемся на следующее
        this.HidePocketWindow(visibleHwnd)

        ; Синхронизируем индекс с текущим отображаемым окном перед переключением
        curPos := this.FindIndex(visibleHwnd)
        if (curPos > 0)
            this.currentIndex := curPos

        this.currentIndex += 1
        if (this.currentIndex > count)
            this.currentIndex := 1

        targetHwnd := this.pocketWindows[this.currentIndex]
        this.ActivatePocketWindow(targetHwnd)
    }

    ; Вызов кармана по клику колесика мыши (NumLock + MButton):
    ; Если окно активно и показано — сворачиваем/скрываем его.
    ; Иначе показываем текущее окно и скрываем все остальные.
    static ToggleSummon() {
        this.CleanupDeadWindows()
        count := this.pocketWindows.Length
        if (count == 0)
            return

        if (this.currentIndex < 1 || this.currentIndex > count)
            this.currentIndex := 1

        targetHwnd := this.pocketWindows[this.currentIndex]
        if (!targetHwnd || !WinExist("ahk_id " targetHwnd))
            return

        activeHwnd := WinExist("A")
        if this.IsBorderHwnd(activeHwnd)
            activeHwnd := this.GetTargetFromBorder(activeHwnd)

        style := WinGetStyle("ahk_id " targetHwnd)
        isMinimized := (style & 0x20000000) ; WS_MINIMIZE

        ; Если окно активно и не свернуто -> сворачиваем / скрываем
        if (activeHwnd == targetHwnd && !isMinimized) {
            this.HidePocketWindow(targetHwnd)
        } else {
            ; Иначе скрываем другие окна кармана и выводим целевое
            this.HideOtherPocketWindows(targetHwnd)
            this.ActivatePocketWindow(targetHwnd)
        }
    }

    static ActivatePocketWindow(hwnd) {
        global currentWorkspaces, wsWindows
        if (!hwnd || !WinExist("ahk_id " hwnd))
            return

        ; Гарантируем, что на экране не останется других окон кармана
        this.HideOtherPocketWindows(hwnd)

        ; Окно кармана не привязано к конкретному столу (ws := 0)
        mon := GetWindowMonitor(hwnd)
        if wsWindows.Has(hwnd) {
            wsWindows[hwnd].ws := 0
            wsWindows[hwnd].mon := mon
            wsWindows[hwnd].isOffscreen := false
            SaveWindowProps(hwnd, wsWindows[hwnd])
        }

        SetWindowVisibility(hwnd, true)
        try {
            style := WinGetStyle("ahk_id " hwnd)
            if (style & 0x20000000) ; WS_MINIMIZE
                DllCall("ShowWindowAsync", "ptr", hwnd, "int", 9) ; SW_RESTORE
            
            WinSetAlwaysOnTop(true, "ahk_id " hwnd)
            ForceActivateWindow(hwnd)
        }

        this.lastAlpha[hwnd] := 255
        try WinSetTransparent("Off", "ahk_id " hwnd)
        if this.borderGuis.Has(hwnd) {
            try WinSetTransparent("Off", "ahk_id " this.borderGuis[hwnd].Hwnd)
        }

        this.UpdateBorder(hwnd)
        this.ApplyLayerHierarchy()
    }

    static IsInPocket(hwnd) {
        return (this.FindIndex(hwnd) > 0)
    }

    static FindIndex(hwnd) {
        for idx, h in this.pocketWindows {
            if (h == hwnd)
                return idx
        }
        return 0
    }

    static CleanupDeadWindows() {
        toRemove := []
        for h in this.pocketWindows {
            if (!WinExist("ahk_id " h))
                toRemove.Push(h)
        }
        for h in toRemove
            this.RemoveWindow(h)
    }

    ; Синхронизация окон кармана при переключении рабочего стола:
    ; Окна кармана не привязаны к столам (ws=0) и не скрываются
    static OnWorkspaceSwitched(targetMon, targetWs) {
        global wsWindows
        visibleHwnd := this.GetVisiblePocketWindow()

        for hwnd in this.pocketWindows {
            if WinExist("ahk_id " hwnd) {
                if wsWindows.Has(hwnd) {
                    wsWindows[hwnd].mon := targetMon
                    wsWindows[hwnd].ws := 0
                    wsWindows[hwnd].isOffscreen := false
                    SaveWindowProps(hwnd, wsWindows[hwnd])
                }
                ; Показываем только активное окно кармана, остальные держим скрытыми
                if (hwnd == visibleHwnd) {
                    SetWindowVisibility(hwnd, true)
                    this.UpdateBorder(hwnd)
                } else {
                    this.HidePocketWindow(hwnd)
                }
            }
        }
        this.ApplyLayerHierarchy()
    }

    ; Обновление прозрачности: 50% если окно не в фокусе, 100% если в фокусе
    static UpdateTransparency(h) {
        if (!h || !WinExist("ahk_id " h))
            return
        fgHwnd := DllCall("GetForegroundWindow", "ptr")
        isFocused := (fgHwnd && (fgHwnd == h || IsWindowOrChildOf(fgHwnd, h)))
        targetAlpha := isFocused ? 255 : 128
        currAlpha := this.lastAlpha.Has(h) ? this.lastAlpha[h] : 255
        if (currAlpha != targetAlpha) {
            this.lastAlpha[h] := targetAlpha
            try WinSetTransparent(isFocused ? "Off" : targetAlpha, "ahk_id " h)
            if this.borderGuis.Has(h) {
                try WinSetTransparent(isFocused ? "Off" : targetAlpha, "ahk_id " this.borderGuis[h].Hwnd)
            }
        }
    }

    ; Гарантирует строгую иерархию слоев:
    ; Закрепленные окна -> Окно кармана -> Рамка кармана -> OSD -> Overview
    static ApplyLayerHierarchy() {
        global osdGlobalGui
        pocketHwnd := this.GetVisiblePocketWindow()
        if (!pocketHwnd || !WinExist("ahk_id " pocketHwnd))
            return

        ; 1. Гарантируем AlwaysOnTop для окна кармана и поднимаем его на вершину HWND_TOPMOST
        if !(WinGetExStyle("ahk_id " pocketHwnd) & 0x8)
            WinSetAlwaysOnTop(true, "ahk_id " pocketHwnd)
        DllCall("user32\SetWindowPos", "ptr", pocketHwnd, "ptr", -1, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0013) ; HWND_TOPMOST | SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE

        ; 2. Рамку кармана поднимаем поверх окна кармана
        if this.borderGuis.Has(pocketHwnd) {
            g := this.borderGuis[pocketHwnd]
            if (DllCall("user32\IsWindow", "ptr", g.Hwnd, "int")) {
                DllCall("user32\SetWindowPos", "ptr", g.Hwnd, "ptr", -1, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0013)
            }
        }

        ; 3. Опускаем все закрепленные окна ПОД окно кармана
        this.LowerPinnedWindowsUnderPocket()

        ; 4. Обновляем прозрачность
        this.UpdateTransparency(pocketHwnd)

        ; 5. Если активно окно OSD (уведомление рабочего стола), поднимаем его выше кармана
        if (osdGlobalGui && DllCall("user32\IsWindow", "ptr", osdGlobalGui.Hwnd, "int") && DllCall("user32\IsWindowVisible", "ptr", osdGlobalGui.Hwnd, "int")) {
            DllCall("user32\SetWindowPos", "ptr", osdGlobalGui.Hwnd, "ptr", -1, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0013)
        }

        ; 6. Оверлей Overview всегда должен быть на самом верху
        if (OverviewController.isOpen) {
            OverviewController.EnsureTopmost()
        }
    }

    ; Гарантирует, что окна кармана находятся в Topmost пуле
    static EnsurePocketTopmost() {
        this.ApplyLayerHierarchy()
    }

    ; Опускает закрепленные приложения под карманное окно
    static LowerPinnedWindowsUnderPocket() {
        global wsWindows, desktopStates, Rules
        pocketHwnd := this.GetVisiblePocketWindow()
        if (!pocketHwnd || !WinExist("ahk_id " pocketHwnd))
            return

        ; Собираем все закрепленные окна в порядке их текущего расположения в Z-order
        pinnedList := []
        for hwnd in WinGetList() {
            if (!hwnd || hwnd == pocketHwnd || !WinExist("ahk_id " hwnd))
                continue

            ; Исключаем окна кармана и их рамки
            if this.IsInPocket(hwnd) || this.IsBorderHwnd(hwnd)
                continue

            ; Исключаем оверлей Overview
            if (OverviewController.isOpen && OverviewController.overlayGui && hwnd == OverviewController.overlayGui.Hwnd)
                continue

            try {
                if (!DllCall("user32\IsWindowVisible", "ptr", hwnd) || IsWindowCloaked(hwnd))
                    continue

                style := WinGetStyle("ahk_id " hwnd)
                if (style & 0x20000000) ; WS_MINIMIZE
                    continue

                winClass := StrLower(WinGetClass("ahk_id " hwnd))
                if (Rules.systemClasses.Has(winClass) || winClass = "shell_traywnd" || winClass = "shell_secondarytraywnd")
                    continue

                if (wsWindows.Has(hwnd) && wsWindows[hwnd].isOffscreen)
                    continue

                exStyle := WinGetExStyle("ahk_id " hwnd)
                isTop := (exStyle & 0x8) ; WS_EX_TOPMOST

                isPinned := isTop
                if (!isPinned && wsWindows.Has(hwnd)) {
                    info := wsWindows[hwnd]
                    stateKey := info.mon "_" info.ws
                    if (desktopStates.Has(stateKey) && desktopStates[stateKey] && IsEligibleFloatingWindow(hwnd))
                        isPinned := true
                }

                if (isPinned) {
                    pinnedList.Push(hwnd)
                }
            }
        }

        ; Помещаем закрепленные окна строго ПОД окно кармана
        lastHwnd := pocketHwnd
        for pHwnd in pinnedList {
            DllCall("user32\SetWindowPos", "ptr", pHwnd, "ptr", lastHwnd, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0013) ; SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE
            lastHwnd := pHwnd
        }
    }

    ; Создание или обновление желтой рамки вокруг окна кармана
    static UpdateBorder(hwnd) {
        if (!hwnd || !WinExist("ahk_id " hwnd) || !DllCall("user32\IsWindowVisible", "ptr", hwnd)) {
            this.RemoveBorder(hwnd)
            return
        }

        ; Если открыт Overview — скрываем рамку, чтобы она была под ним и не мешала интерфейсу
        if (OverviewController.isOpen) {
            if this.borderGuis.Has(hwnd) {
                try this.borderGuis[hwnd].Hide()
            }
            return
        }

        ; Если окно свернуто, скрываем рамку
        style := WinGetStyle("ahk_id " hwnd)
        if (style & 0x20000000) { ; WS_MINIMIZE
            if this.borderGuis.Has(hwnd) {
                try this.borderGuis[hwnd].Hide()
            }
            return
        }

        rectBuf := Buffer(16, 0)
        ; DWMWA_EXTENDED_FRAME_BOUNDS = 9
        hr := DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 9, "ptr", rectBuf, "uint", 16)
        if (hr == 0) {
            wx := NumGet(rectBuf, 0, "int")
            wy := NumGet(rectBuf, 4, "int")
            ww := NumGet(rectBuf, 8, "int") - wx
            wh := NumGet(rectBuf, 12, "int") - wy
        } else {
            wx := 0, wy := 0, ww := 0, wh := 0
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
        }

        if (ww <= 0 || wh <= 0) {
            this.RemoveBorder(hwnd)
            return
        }

        ; Проверяем, изменились ли координаты/размер
        last := this.lastCoords.Has(hwnd) ? this.lastCoords[hwnd] : {x: 0, y: 0, w: 0, h: 0}
        sizeChanged := (last.w != ww || last.h != wh)
        posChanged := (last.x != wx || last.y != wy)

        bw := this.borderWidth
        g := 0
        if (this.borderGuis.Has(hwnd) && DllCall("user32\IsWindow", "ptr", this.borderGuis[hwnd].Hwnd, "int")) {
            g := this.borderGuis[hwnd]
        } else {
            ; Если существовала старая невалидная ссылка, уничтожаем её
            if this.borderGuis.Has(hwnd) {
                oldG := this.borderGuis[hwnd]
                if this.borderHwndToTarget.Has(oldG.Hwnd)
                    this.borderHwndToTarget.Delete(oldG.Hwnd)
                try oldG.Destroy()
                this.borderGuis.Delete(hwnd)
            }

            ; Создаем независимое +AlwaysOnTop окно (без +Owner, чтобы не зависеть от Z-порядка владельца)
            ; Прозрачна для кликов мыши (+E0x20) и не получает фокус (+E0x08000000)
            g := Gui("-Caption +AlwaysOnTop +ToolWindow -DPIScale +E0x20 +E0x08000000")
            g.BackColor := this.borderColor
            this.borderGuis[hwnd] := g
            this.borderHwndToTarget[g.Hwnd] := hwnd
            sizeChanged := true
        }

        ; Пересоздаем регион только если изменились ширина или высота
        if (sizeChanged) {
            hRgnOuter := DllCall("gdi32\CreateRectRgn", "int", 0, "int", 0, "int", ww, "int", wh, "ptr")
            hRgnInner := DllCall("gdi32\CreateRectRgn", "int", bw, "int", bw, "int", ww - bw, "int", wh - bw, "ptr")
            hRgnDiff  := DllCall("gdi32\CreateRectRgn", "int", 0, "int", 0, "int", 0, "int", 0, "ptr")
            DllCall("gdi32\CombineRgn", "ptr", hRgnDiff, "ptr", hRgnOuter, "ptr", hRgnInner, "int", 4)
            DllCall("user32\SetWindowRgn", "ptr", g.Hwnd, "ptr", hRgnDiff, "int", 1)
            DllCall("gdi32\DeleteObject", "ptr", hRgnOuter)
            DllCall("gdi32\DeleteObject", "ptr", hRgnInner)
        }

        if (posChanged || sizeChanged || !DllCall("user32\IsWindowVisible", "ptr", g.Hwnd)) {
            g.Show("x" wx " y" wy " w" ww " h" wh " NoActivate")
            this.lastCoords[hwnd] := {x: wx, y: wy, w: ww, h: wh}
            ; Рамка поверх окна кармана
            DllCall("user32\SetWindowPos", "ptr", g.Hwnd, "ptr", -1, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0013) ; SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE
            if (this.lastAlpha.Has(hwnd) && this.lastAlpha[hwnd] != 255) {
                try WinSetTransparent(this.lastAlpha[hwnd], "ahk_id " g.Hwnd)
            }
        }
    }

    static RemoveBorder(hwnd) {
        if this.borderGuis.Has(hwnd) {
            g := this.borderGuis[hwnd]
            if this.borderHwndToTarget.Has(g.Hwnd)
                this.borderHwndToTarget.Delete(g.Hwnd)
            try g.Destroy()
            this.borderGuis.Delete(hwnd)
        }
        if this.lastCoords.Has(hwnd)
            this.lastCoords.Delete(hwnd)
        if this.lastAlpha.Has(hwnd)
            this.lastAlpha.Delete(hwnd)
    }

    ; Фоновый сторожевой таймер: обновляет геометрию только при необходимости без кражи фокуса
    static Watchdog() {
        this.CleanupDeadWindows()
        if (this.pocketWindows.Length == 0)
            return

        visibleHwnd := this.GetVisiblePocketWindow()
        if (visibleHwnd) {
            this.HideOtherPocketWindows(visibleHwnd)
        }

        for h in this.pocketWindows {
            if WinExist("ahk_id " h) {
                if (h == visibleHwnd) {
                    ; Проверяем AlwaysOnTop без принудительного повторного вызова если стиль уже установлен
                    isTop := (WinGetExStyle("ahk_id " h) & 0x8)
                    if (!isTop) {
                        try WinSetAlwaysOnTop(true, "ahk_id " h)
                    }
                    ; Поддерживаем рамку на актуальных координатах
                    this.UpdateBorder(h)
                    ; Поддерживаем актуальную прозрачность в зависимости от фокуса
                    this.UpdateTransparency(h)
                } else {
                    if this.borderGuis.Has(h) {
                        try this.borderGuis[h].Hide()
                    }
                }
            }
        }
    }

    static NotifyOverview() {
        if (OverviewController.isOpen) {
            SetTimer(() => OverviewController.PushStateToWeb(OverviewController.currentMon), -50)
        }
    }

    ; Получение массива данных для Overview
    static GetOverviewData() {
        this.CleanupDeadWindows()
        res := []
        for hwnd in this.pocketWindows {
            if WinExist("ahk_id " hwnd) {
                title := WinGetTitle("ahk_id " hwnd)
                if (title == "")
                    title := WinGetProcessName("ahk_id " hwnd)

                iconB64 := ""
                try iconB64 := CaptureEngine.GetWindowIconBase64(hwnd)

                res.Push(Map(
                    "hwnd", hwnd,
                    "title", title,
                    "icon", iconB64,
                    "hasPreview", false
                ))
            }
        }
        return res
    }
}
