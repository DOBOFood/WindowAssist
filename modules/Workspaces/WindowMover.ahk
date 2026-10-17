#Requires AutoHotkey v2.0

class WindowMover {
    static dummy() => true
}

MoveWindowWithMouse() {
    global isMovingOrResizing, Rules, wsWindows, currentWorkspaces, titleBarInfo, desktopStates
    CoordMode("Mouse", "Screen")
    MouseGetPos(&startX, &startY, &rawHwnd)

    ; Ждем движения мыши или отпускания кнопки, чтобы отличить клик (Peeker) от перетаскивания (Move)
    dragThreshold := 4
    hasMovedPastThreshold := false

    while GetKeyState("LButton", "P") {
        MouseGetPos(&curX, &curY)
        if (Abs(curX - startX) >= dragThreshold || Abs(curY - startY) >= dragThreshold) {
            hasMovedPastThreshold := true
            break
        }
        DllCall("Sleep", "uint", 10)
    }

    ; Если кнопка была отпущена до превышения порога перемещения - это клик для LayerPeeker!
    if (!hasMovedPastThreshold) {
        LayerPeeker.OnClick()
        return
    }

    if !rawHwnd
        return

    ; Если клик пришелся на рамку кармана — перенаправляем на целевое окно приложения
    if PocketManager.IsBorderHwnd(rawHwnd)
        rawHwnd := PocketManager.GetTargetFromBorder(rawHwnd)
        
    winId := DllCall("GetAncestor", "ptr", rawHwnd, "uint", 2, "ptr")
    winId := winId ? winId : rawHwnd

    ; Проверяем, не является ли предок рамкой
    if PocketManager.IsBorderHwnd(winId)
        winId := PocketManager.GetTargetFromBorder(winId)
        
    if !WinExist("ahk_id " winId) || IsGameOrExclusiveWindow(winId)
        return
        
    winClass := StrLower(WinGetClass("ahk_id " winId))
    if Rules.systemClasses.Has(winClass)
        return
        
    style := WinGetStyle("ahk_id " winId)
    if (style & 0x01000000) ; WS_MAXIMIZE
        return
        
    ; Прерываем Peeker если было начато реальное перетаскивание
    LayerPeeker.Reset()

    isMovingOrResizing := true
    try {
        isPinned := (WinGetExStyle("ahk_id " winId) & 0x8)
        WinGetPos(&origX, &origY, &origW, &origH, "ahk_id " winId)
        
        if (DllCall("GetForegroundWindow", "ptr") != winId)
            DllCall("user32\SetForegroundWindow", "ptr", winId)
        
        lastDx := 0, lastDy := 0
        while GetKeyState("LButton", "P") {
            MouseGetPos(&curX, &curY)
            dx := curX - startX
            dy := curY - startY
            
            if (dx != lastDx || dy != lastDy) {
                lastDx := dx, lastDy := dy
                newX := origX + dx
                newY := origY + dy
                
                DllCall("user32\SetWindowPos", "ptr", winId, "ptr", 0
                    , "int", newX, "int", newY, "int", 0, "int", 0
                    , "uint", 0x0215)

                ; Мгновенно синхронизируем рамку окна кармана во время перемещения
                if PocketManager.IsInPocket(winId)
                    PocketManager.UpdateBorder(winId)
            }
            DllCall("Sleep", "uint", 2)
        }

        wMon := GetWindowMonitor(winId)
        if wsWindows.Has(winId) {
            oldMon := wsWindows[winId].mon
            wsWindows[winId].mon := wMon
            wsWindows[winId].ws := currentWorkspaces[wMon]
            wx := 0, wy := 0, ww := 0, wh := 0
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " winId)
            wsWindows[winId].x := wx, wsWindows[winId].y := wy
            wsWindows[winId].w := ww, wsWindows[winId].h := wh
            SaveWindowProps(winId, wsWindows[winId])
            
            if IsAppGrouped(winId)
                SyncAppWindowsLocation(winId, wMon, currentWorkspaces[wMon])

            if (oldMon != wMon) {
                CrossWorkspaceAltTab.RecordActiveWindow(winId)
                if (OverviewController.isOpen)
                    SetTimer(() => OverviewController.PushStateToWeb(OverviewController.currentMon), -50)
            }
        }

        if titleBarInfo.Has(winId)
            titleBarInfo[winId].boundsValid := false

        curWs := currentWorkspaces[wMon]
        stateKey := wMon "_" curWs
        if ((desktopStates.Has(stateKey) && desktopStates[stateKey] && IsEligibleFloatingWindow(winId)) || isPinned)
            WinSetAlwaysOnTop(true, "ahk_id " winId)

        ; Окно кармана всегда должно оставаться на самом верхнем слое над закрепленными окнами
        PocketManager.EnsurePocketTopmost()

        if PocketManager.IsInPocket(winId)
            PocketManager.UpdateBorder(winId)

        SetTimer(() => SaveState(), -300)
    } finally {
        isMovingOrResizing := false
    }
}

ResizeWindowWithMouse() {
    global isMovingOrResizing, Rules, wsWindows, currentWorkspaces, titleBarInfo, desktopStates
    CoordMode("Mouse", "Screen")
    MouseGetPos(&startX, &startY, &rawHwnd)

    ; Ждем движения мыши или отпускания кнопки, чтобы отличить клик (Toggle Pin) от изменения размера (Resize)
    dragThreshold := 4
    hasMovedPastThreshold := false

    while GetKeyState("RButton", "P") {
        MouseGetPos(&curX, &curY)
        if (Abs(curX - startX) >= dragThreshold || Abs(curY - startY) >= dragThreshold) {
            hasMovedPastThreshold := true
            break
        }
        DllCall("Sleep", "uint", 10)
    }

    ; Если кнопка была отпущена до превышения порога перемещения - это клик для закрепления (Pin)
    if (!hasMovedPastThreshold) {
        ToggleFloatingWindows()
        return
    }

    if !rawHwnd
        return

    ; Если клик пришелся на рамку кармана — перенаправляем на целевое окно приложения
    if PocketManager.IsBorderHwnd(rawHwnd)
        rawHwnd := PocketManager.GetTargetFromBorder(rawHwnd)
        
    winId := DllCall("GetAncestor", "ptr", rawHwnd, "uint", 2, "ptr")
    winId := winId ? winId : rawHwnd

    if PocketManager.IsBorderHwnd(winId)
        winId := PocketManager.GetTargetFromBorder(winId)
        
    if !WinExist("ahk_id " winId) || IsGameOrExclusiveWindow(winId)
        return
        
    winClass := StrLower(WinGetClass("ahk_id " winId))
    if Rules.systemClasses.Has(winClass)
        return
        
    style := WinGetStyle("ahk_id " winId)
    if (style & 0x01000000) ; WS_MAXIMIZE
        return
        
    isMovingOrResizing := true
    try {
        isPinned := (WinGetExStyle("ahk_id " winId) & 0x8)
        WinGetPos(&origX, &origY, &origW, &origH, "ahk_id " winId)
        if (origW <= 0 || origH <= 0)
            return

        if (DllCall("GetForegroundWindow", "ptr") != winId)
            DllCall("user32\SetForegroundWindow", "ptr", winId)

        relX := (startX - origX) / origW
        relY := (startY - origY) / origH

        threshold := 0.30
        isLeft   := (relX < threshold)
        isRight  := (relX > 1 - threshold)
        isTop    := (relY < threshold)
        isBottom := (relY > 1 - threshold)

        if (!isLeft && !isRight && !isTop && !isBottom) {
            isLeft   := (relX < 0.5)
            isRight  := (relX >= 0.5)
            isTop    := (relY < 0.5)
            isBottom := (relY >= 0.5)
        }

        lastDx := 0, lastDy := 0
        minW := 150, minH := 100

        while GetKeyState("RButton", "P") {
            MouseGetPos(&curX, &curY)
            dx := curX - startX
            dy := curY - startY
            
            if (dx != lastDx || dy != lastDy) {
                lastDx := dx, lastDy := dy

                if (isLeft) {
                    newW := origW - dx
                    newX := origX + dx
                } else if (isRight) {
                    newW := origW + dx
                    newX := origX
                } else {
                    newW := origW
                    newX := origX
                }

                if (isTop) {
                    newH := origH - dy
                    newY := origY + dy
                } else if (isBottom) {
                    newH := origH + dy
                    newY := origY
                } else {
                    newH := origH
                    newY := origY
                }

                if (newW < minW) {
                    if (isLeft)
                        newX := origX + origW - minW
                    newW := minW
                }
                if (newH < minH) {
                    if (isTop)
                        newY := origY + origH - minH
                    newH := minH
                }

                DllCall("user32\SetWindowPos", "ptr", winId, "ptr", 0
                    , "int", newX, "int", newY, "int", newW, "int", newH
                    , "uint", 0x0214)

                ; Мгновенно синхронизируем рамку окна кармана во время изменения размера
                if PocketManager.IsInPocket(winId)
                    PocketManager.UpdateBorder(winId)
            }
            DllCall("Sleep", "uint", 2)
        }

        wMon := GetWindowMonitor(winId)
        if wsWindows.Has(winId) {
            oldMon := wsWindows[winId].mon
            wx := 0, wy := 0, ww := 0, wh := 0
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " winId)
            wsWindows[winId].x := wx, wsWindows[winId].y := wy
            wsWindows[winId].w := ww, wsWindows[winId].h := wh
            wsWindows[winId].mon := wMon
            wsWindows[winId].ws := currentWorkspaces[wMon]
            SaveWindowProps(winId, wsWindows[winId])

            if (oldMon != wMon) {
                CrossWorkspaceAltTab.RecordActiveWindow(winId)
                if (OverviewController.isOpen)
                    SetTimer(() => OverviewController.PushStateToWeb(OverviewController.currentMon), -50)
            }
        }

        if titleBarInfo.Has(winId)
            titleBarInfo[winId].boundsValid := false

        curWs := currentWorkspaces[wMon]
        stateKey := wMon "_" curWs
        if ((desktopStates.Has(stateKey) && desktopStates[stateKey] && IsEligibleFloatingWindow(winId)) || isPinned)
            WinSetAlwaysOnTop(true, "ahk_id " winId)

        ; Окно кармана всегда должно оставаться на самом верхнем слое над закрепленными окнами
        PocketManager.EnsurePocketTopmost()

        if PocketManager.IsInPocket(winId)
            PocketManager.UpdateBorder(winId)

        SetTimer(() => SaveState(), -300)
    } finally {
        isMovingOrResizing := false
    }
}
