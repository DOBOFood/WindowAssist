#Requires AutoHotkey v2.0

class Win32API {
    static SetDwmAttribute(hwnd, attr, colorVal) {
        static buf := Buffer(4, 0)
        NumPut("uint", colorVal, buf, 0)
        DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "uint", attr, "ptr", buf, "uint", 4)
    }

    static GetWindowFramePadding(hwnd, &bx, &by) {
        try {
            dpi := DllCall("GetDpiForWindow", "ptr", hwnd, "uint")
            if (dpi > 0) {
                bx := DllCall("GetSystemMetricsForDpi", "int", 32, "uint", dpi, "int") + DllCall("GetSystemMetricsForDpi", "int", 92, "uint", dpi, "int")
                by := DllCall("GetSystemMetricsForDpi", "int", 33, "uint", dpi, "int") + DllCall("GetSystemMetricsForDpi", "int", 92, "uint", dpi, "int")
                if (bx > 0 && by > 0)
                    return
            }
        }
        bx := DllCall("GetSystemMetrics", "int", 32, "int") + DllCall("GetSystemMetrics", "int", 92, "int")
        by := DllCall("GetSystemMetrics", "int", 33, "int") + DllCall("GetSystemMetrics", "int", 92, "int")
        bx := (bx <= 0) ? 8 : bx
        by := (by <= 0) ? 8 : by
    }

    static IsWindowCloaked(hwnd) {
        static buf := Buffer(4, 0)
        NumPut("uint", 0, buf, 0)
        if (DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 14, "ptr", buf, "uint", 4) == 0)
            return (NumGet(buf, 0, "uint") != 0)
        return false
    }

    static StopWindowFlash(hwnd) {
        static fwi := Buffer(A_PtrSize == 8 ? 32 : 20, 0)
        NumPut("uint", fwi.Size, fwi, 0)
        NumPut("ptr", hwnd, fwi, A_PtrSize == 8 ? 8 : 4)
        NumPut("uint", 0, fwi, A_PtrSize == 8 ? 16 : 8)
        DllCall("FlashWindowEx", "ptr", fwi)
    }

    static ForceActivateWindow(hwnd) {
        try {
            if !hwnd || !WinExist("ahk_id " hwnd) || this.IsWindowCloaked(hwnd)
                return

            if (DllCall("GetForegroundWindow", "ptr") == hwnd)
                return

            DllCall("user32\AllowSetForegroundWindow", "int", -1)
            DllCall("user32\keybd_event", "uchar", 0x12, "uchar", 0, "uint", 0, "uptr", 0)
            DllCall("user32\keybd_event", "uchar", 0x12, "uchar", 0, "uint", 2, "uptr", 0)

            DllCall("user32\SetForegroundWindow", "ptr", hwnd)
            DllCall("BringWindowToTop", "ptr", hwnd)
            this.StopWindowFlash(hwnd)
        }
    }

    static SafeDesktopFocus() {
        if progman := WinExist("ahk_class Progman")
            DllCall("user32\SetForegroundWindow", "ptr", progman)
    }

    static ReleaseCursorClip() {
        DllCall("user32\ClipCursor", "ptr", 0)
    }

    static ClickTaskbarIconForWindow(hwnd) {
        try {
            if (!hwnd || !DllCall("IsWindow", "Ptr", hwnd, "Int"))
                return false

            ; Инициализация UI Automation
            static IUIAutomationType := "{C2B544FB-0728-11D3-9D7B-0000F81EF32E}"
            static CUIAutomationType := "{FF48DB72-60D9-4F45-8119-DEC84DB5D98D}"
            
            uia := ComObject(CUIAutomationType, IUIAutomationType)
            if (!uia)
                return false

            ; Получаем корневой элемент рабочего стола
            uia.GetRootElement(&rootElement)
            if (!rootElement)
                return false

            ; Условие поиска панели задач (class Shell_TrayWnd или Shell_SecondaryTrayWnd)
            condTray := uia.CreatePropertyCondition(30022, "Shell_TrayWnd")
            condSecTray := uia.CreatePropertyCondition(30022, "Shell_SecondaryTrayWnd")
            condTrayAny := uia.CreateOrCondition(condTray, condSecTray)

            trayElements := rootElement.FindAll(2, condTrayAny)
            if (!trayElements)
                return false

            trayCount := trayElements.Length
            if (trayCount <= 0)
                return false

            pid := 0
            DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid)
            if (!pid)
                return false

            Loop trayCount {
                trayEl := trayElements.GetElement(A_Index - 1)
                if (!trayEl)
                    continue

                ; Ищем элементы внутри таскбара, которые соответствуют нашему ProcessId или связаны с окном
                condBtn1 := uia.CreatePropertyCondition(30022, "Taskbar.TaskListButtonAccessible")
                condBtn2 := uia.CreatePropertyCondition(30022, "Taskbar.TaskButtonAutomationPeer")
                condBtnAny := uia.CreateOrCondition(condBtn1, condBtn2)

                buttons := trayEl.FindAll(2, condBtnAny)
                if (!buttons)
                    continue

                btnCount := buttons.Length
                Loop btnCount {
                    btnEl := buttons.GetElement(A_Index - 1)
                    if (!btnEl)
                        continue

                    btnPid := 0
                    try btnPid := btnEl.CurrentProcessId
                    if (btnPid == pid) {
                        ; Находим паттерн Invoke или просто кликаем по центру элемента
                        try {
                            invokePattern := btnEl.GetCurrentPattern(10000)
                            if (invokePattern) {
                                invokePattern.Invoke()
                                return true
                            }
                        }

                        ; Если Invoke недоступен, кликаем по boundingRect
                        try {
                            rect := btnEl.CurrentBoundingRectangle
                            if (rect) {
                                x := rect.l + (rect.r - rect.l) // 2
                                y := rect.t + (rect.b - rect.t) // 2
                                if (x > 0 && y > 0) {
                                    DllCall("SetCursorPos", "Int", x, "Int", y)
                                    DllCall("mouse_event", "UInt", 2, "UInt", 0, "UInt", 0, "UInt", 0, "UPtr", 0)
                                    DllCall("mouse_event", "UInt", 4, "UInt", 0, "UInt", 0, "UInt", 0, "UPtr", 0)
                                    return true
                                }
                            }
                        }
                    }
                }
            }
        }
        return false
    }
}

; Helper global functions for direct callers
SetDwmAttribute(hwnd, attr, colorVal) => Win32API.SetDwmAttribute(hwnd, attr, colorVal)
GetWindowFramePadding(hwnd, &bx, &by) => Win32API.GetWindowFramePadding(hwnd, &bx, &by)
IsWindowCloaked(hwnd) => Win32API.IsWindowCloaked(hwnd)
StopWindowFlash(hwnd) => Win32API.StopWindowFlash(hwnd)
ForceActivateWindow(hwnd) => Win32API.ForceActivateWindow(hwnd)
SafeDesktopFocus() => Win32API.SafeDesktopFocus()
ReleaseCursorClip() => Win32API.ReleaseCursorClip()
ClickTaskbarIconForWindow(hwnd) => Win32API.ClickTaskbarIconForWindow(hwnd)
