#Requires AutoHotkey v2.0

class LayerPeeker {
    ; Вызывается при клике Meta + LButton (подобие Alt+Tab для перекрывающихся плавающих окон)
    static OnClick() {
        global wsWindows, currentWorkspaces, Rules

        CoordMode("Mouse", "Screen")
        MouseGetPos(&mX, &mY)

        monIdx := GetCurrentTargetMonitor()
        curWs  := currentWorkspaces[monIdx]

        ; Текущее активное окно в фокусе
        fgHwnd := DllCall("GetForegroundWindow", "ptr")
        if (fgHwnd) {
            fgRoot := DllCall("GetAncestor", "ptr", fgHwnd, "uint", 2, "ptr")
            fgHwnd := fgRoot ? fgRoot : fgHwnd
        }

        ; Собираем окна текущего рабочего стола под курсором в точном Z-порядке сверху вниз
        windowsUnderCursor := []                                 
        candidateFloating := []

        for hwnd in WinGetList() {
            if !WinExist("ahk_id " hwnd) || !DllCall("IsWindowVisible", "ptr", hwnd) || IsWindowCloaked(hwnd)
                continue

            wClass := StrLower(WinGetClass("ahk_id " hwnd))
            if (Rules.systemClasses.Has(wClass) || wClass = "progman" || wClass = "workerw" || wClass = "shell_traywnd")
                continue

            if (WinGetTitle("ahk_id " hwnd) == "")
                continue

            if !IsMainWindow(hwnd)
                continue

            ; Окно должно принадлежать текущему монитору и рабочему столу
            if wsWindows.Has(hwnd) {
                info := wsWindows[hwnd]
                if (info.mon != monIdx || info.ws != curWs || info.isOffscreen)
                    continue
            } else {
                ; Для неуправляемых окон проверяем монитор
                if (GetWindowMonitor(hwnd) != monIdx)
                    continue
            }

            ; Исключаем закрепленные окна из перебора
            if this.IsPinnedWindow(hwnd)
                continue

            isFloat := this.IsFloatingWindow(hwnd)
            if (isFloat)
                candidateFloating.Push(hwnd)

            try {
                WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
                if (mX >= wx && mX < (wx + ww) && mY >= wy && mY < (wy + wh)) {
                    windowsUnderCursor.Push({ hwnd: hwnd, isFloat: isFloat })
                }
            }
        }

        ; Закрепленные окна (AlwaysOnTop или из кармана) не должны перебираться
        fgIsPinned := (fgHwnd && this.IsPinnedWindow(fgHwnd))

        ; Если в фокусе обычное плавающее окно - всегда отправляем его на самый задний слой (HWND_BOTTOM),
        ; чтобы оно уходило под maximized/fullscreen окна
        fgIsFloating := (fgHwnd && this.IsFloatingWindow(fgHwnd) && !fgIsPinned)
        if (fgIsFloating) {
            this.SendToBottom(fgHwnd)
        }

        ; Ищем целевое окно для активации
        targetHwnd := 0

        if (windowsUnderCursor.Length > 0) {
            fgIdx := 0
            for idx, item in windowsUnderCursor {
                if (item.hwnd == fgHwnd) {
                    fgIdx := idx
                    break
                }
            }

            if (fgIsFloating) {
                ; Если плавающее окно ушло вниз, активируем следующее окно под курсором
                if (fgIdx > 0 && fgIdx < windowsUnderCursor.Length) {
                    targetHwnd := windowsUnderCursor[fgIdx + 1].hwnd
                } else if (fgIdx == 0 && windowsUnderCursor[1].hwnd != fgHwnd) {
                    targetHwnd := windowsUnderCursor[1].hwnd
                } else if (windowsUnderCursor.Length > 1) {
                    targetHwnd := (windowsUnderCursor[1].hwnd != fgHwnd) ? windowsUnderCursor[1].hwnd : windowsUnderCursor[2].hwnd
                }
            } else {
                ; Если в фокусе было не плавающее окно (maximized, fullscreen, карман и т.д.),
                ; выбираем первое плавающее окно под курсором
                for item in windowsUnderCursor {
                    if (item.isFloat && item.hwnd != fgHwnd) {
                        targetHwnd := item.hwnd
                        break
                    }
                }
            }
        }

        ; Fallback: если под курсором не было окон, циклически переключаем плавающие окна (как Alt+Tab)
        if (!targetHwnd && candidateFloating.Length > 0) {
            fgIdx := 0
            for idx, h in candidateFloating {
                if (h == fgHwnd) {
                    fgIdx := idx
                    break
                }
            }
            if (fgIdx > 0 && fgIdx < candidateFloating.Length)
                targetHwnd := candidateFloating[fgIdx + 1]
            else
                targetHwnd := candidateFloating[1]
        }

        if (targetHwnd && WinExist("ahk_id " targetHwnd) && targetHwnd != fgHwnd) {
            ForceActivateWindow(targetHwnd)
        } else if (!targetHwnd && fgIsFloating) {
            SafeDesktopFocus()
        }
    }

    ; Отправляет окно на самый задний слой Z-порядка (под все обычные, maximized и fullscreen окна)
    static SendToBottom(hwnd) {
        try {
            if !hwnd || !WinExist("ahk_id " hwnd)
                return

            ; Снимаем AlwaysOnTop если был установлен
            if (WinGetExStyle("ahk_id " hwnd) & 0x8)
                WinSetAlwaysOnTop(false, "ahk_id " hwnd)

            ; HWND_BOTTOM = 1, SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE = 0x0013
            DllCall("SetWindowPos", "ptr", hwnd, "ptr", 1, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0013)
        }
    }

    ; Проверка, является ли окно закрепленным (AlwaysOnTop, на закрепленном столе или в кармане)
    static IsPinnedWindow(hwnd) {
        global desktopStates, wsWindows
        try {
            if !hwnd || !WinExist("ahk_id " hwnd)
                return false

            if PocketManager.IsInPocket(hwnd) || PocketManager.IsBorderHwnd(hwnd)
                return true

            if (WinGetExStyle("ahk_id " hwnd) & 0x8) ; WS_EX_TOPMOST
                return true

            if wsWindows.Has(hwnd) {
                info := wsWindows[hwnd]
                stateKey := info.mon "_" info.ws
                if (desktopStates.Has(stateKey) && desktopStates[stateKey] && IsEligibleFloatingWindow(hwnd))
                    return true
            }
            return false
        } catch {
            return false
        }
    }

    ; Проверка: обычное плавающее окно (не maximized и не fullscreen)
    static IsFloatingWindow(hwnd) {
        global Rules
        try {
            ; Свёрнутые или максимизированные окна исключаются
            style := WinGetStyle("ahk_id " hwnd)
            if (style & 0x20000000) || (style & 0x01000000) ; WS_MINIMIZE || WS_MAXIMIZE
                return false

            ; Исключаем игнорируемые процессы и системные классы
            procName := StrLower(WinGetProcessName("ahk_id " hwnd))
            if Rules.ignoreProcesses.Has(procName)
                return false

            wClass := StrLower(WinGetClass("ahk_id " hwnd))
            if Rules.systemClasses.Has(wClass)
                return false

            ; Исключаем окна без заголовка
            if (WinGetTitle("ahk_id " hwnd) == "")
                return false

            ; Проверка на главное окно
            if !IsMainWindow(hwnd)
                return false

            ; Проверка на Fullscreen (окно перекрывает монитор целиком без рамок)
            monIdx := GetWindowMonitor(hwnd)
            mL := 0, mT := 0, mR := 0, mB := 0
            if MonitorGet(monIdx, &mL, &mT, &mR, &mB) {
                WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)
                if (wx <= mL && wy <= mT && (wx + ww) >= mR && (wy + wh) >= mB)
                    return false
            }

            return true
        } catch {
            return false
        }
    }

    static Reset() {
    }
}
