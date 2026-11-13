#Requires AutoHotkey v2.0

class App {
    static Version := "1.0.0"

    ; Registry values temporarily changed while the app runs. Originals are backed
    ; up on the first start so a clean exit can put them back.
    static RegistryBackupPath := A_ScriptDir "\system-backup.json"
    static RegistryOverrides := [
        Map("key", "HKEY_CURRENT_USER\Control Panel\Desktop", "name", "ForegroundFlashCount"),
        Map("key", "HKEY_CURRENT_USER\Control Panel\Desktop", "name", "ForegroundLockTimeout")
    ]
    static RegistryAbsent := "__absent__"

    static Init() {
        global hWinEventHook, winEventCallback, hMouseHook, mouseEventCallback

        if !A_IsAdmin {
            try {
                if A_IsCompiled
                    Run('*RunAs "' A_ScriptFullPath '"')
                else
                    Run('*RunAs "' A_AhkPath '" /restart "' A_ScriptFullPath '"')
            }
            ExitApp()
        }

        this.BackupSystemRegistry()
        this.ApplySystemRegistry()

        DllCall("winmm\timeBeginPeriod", "uint", 1)
        A_IconTip := "WindowAssist v" this.Version

        ConfigManager.Load()
        ; Reconcile the "run at startup" flag with the actual scheduled task
        ; after the hot path is up.
        SetTimer(() => AutostartManager.SyncConfig(), -1500)
        Theme.Init()

        hasRestoredState := LoadState()

        if (!hasRestoredState)
            RecoverAllOffscreenWindows(false)

        InitExistingWindows()

        WindowTracker.Init()
        HotkeyManager.Init()
        global hasHooksInitialized
        hasHooksInitialized := true
        
        CrossWorkspaceAltTab.Init()

        OnExit(ObjBindMethod(this, "CleanExit"))
    }

    static CleanExit(ExitReason, ExitCode) {
        global hWinEventHook, winEventCallback, hMouseHook, mouseEventCallback

        WindowTracker.UnHook()
        DllCall("winmm\timeEndPeriod", "uint", 1)
        ReleaseCursorClip()
        
        OverviewController.Close()
        CaptureEngine.Shutdown()
        OsdRenderer.Shutdown()

        SaveState()

        ; When reloading the script, leave offscreen window coordinates intact
        if (ExitReason == "Reload") {
            return
        }

        RestoreAllTitleBars()
        RecoverAllOffscreenWindows(true)
        ConfigManager.ApplyTaskbarVisibility(false)
        this.RestoreSystemRegistry()
    }

    /**
     * Saves the current values of App.RegistryOverrides, once.
     * The backup survives reloads and crashes, so the real originals are never
     * overwritten with the values this app writes.
     */
    static BackupSystemRegistry() {
        if FileExist(this.RegistryBackupPath)
            return

        backup := Map()
        for item in this.RegistryOverrides {
            try
                backup[item["name"]] := RegRead(item["key"], item["name"])
            catch
                backup[item["name"]] := this.RegistryAbsent
        }

        try FileAppend(JSON.Dump(backup, "  "), this.RegistryBackupPath, "UTF-8-RAW")
    }

    static ApplySystemRegistry() {
        for item in this.RegistryOverrides {
            try RegWrite(0, "REG_DWORD", item["key"], item["name"])
        }
    }

    static RestoreSystemRegistry() {
        if !FileExist(this.RegistryBackupPath)
            return

        restored := false
        try {
            backup := JSON.Load(FileRead(this.RegistryBackupPath, "UTF-8"))
            if (backup is Map) {
                for item in this.RegistryOverrides {
                    name := item["name"]
                    if !backup.Has(name)
                        continue
                    if (backup[name] == this.RegistryAbsent)
                        RegDelete(item["key"], name)
                    else
                        RegWrite(backup[name], "REG_DWORD", item["key"], name)
                }
            }
            restored := true
        }

        if restored
            try FileDelete(this.RegistryBackupPath)
    }
}

class OsdRenderer {
    static pToken := 0
    static hGdip := 0

    static EnsureGdiPlus() {
        if (this.pToken != 0)
            return true
        if (!this.hGdip)
            this.hGdip := DllCall("kernel32\LoadLibrary", "str", "gdiplus", "ptr")
        si := Buffer(A_PtrSize == 8 ? 24 : 16, 0)
        NumPut("uint", 1, si, 0)
        token := 0
        if (DllCall("gdiplus\GdiplusStartup", "ptr*", &token, "ptr", si, "ptr", 0, "int") == 0 && token != 0) {
            this.pToken := token
            return true
        }
        return false
    }

    static Shutdown() {
        if (this.pToken != 0) {
            try DllCall("gdiplus\GdiplusShutdown", "ptr", this.pToken)
            this.pToken := 0
        }
    }

    static NormalizeHex(hex, fallback := "#1A1A1A") {
        s := Trim(String(hex))
        if (SubStr(s, 1, 1) == "#")
            s := SubStr(s, 2)
        if !RegExMatch(s, "^[0-9A-Fa-f]{6}$")
            return fallback
        return "#" StrUpper(s)
    }

    static HexToArgb(hex, alpha := 255) {
        norm := this.NormalizeHex(hex, "#000000")
        rgb := Integer("0x" SubStr(norm, 2))
        a := this.ClampInt(alpha, 0, 255, 255)
        return ((a & 0xFF) << 24) | rgb
    }

    static ClampInt(val, minVal, maxVal, fallback) {
        try {
            n := Integer(val)
        } catch {
            return fallback
        }
        return Min(maxVal, Max(minVal, n))
    }

    static ResolveStyle() {
        fontSize := this.ClampInt(ConfigManager.Get("general.osd.fontSize", 13), 8, 72, 13)
        bgColor := this.NormalizeHex(ConfigManager.Get("appearance.osd.backgroundColor", "#1A1A1A"), "#1A1A1A")
        bgOpacity := this.ClampInt(ConfigManager.Get("appearance.osd.backgroundOpacity", 100), 0, 100, 100)
        textColor := this.NormalizeHex(ConfigManager.Get("appearance.osd.textColor", "#FFFFFF"), "#FFFFFF")
        borderTransparent := !!ConfigManager.Get("appearance.osd.borderTransparent", false)
        borderColor := this.NormalizeHex(ConfigManager.Get("appearance.osd.borderColor", "#3D3D3D"), "#3D3D3D")
        borderWidth := this.ClampInt(ConfigManager.Get("appearance.osd.borderWidth", 1), 1, 10, 1)

        return {
            fontSize: fontSize,
            bgColor: bgColor,
            bgOpacity: bgOpacity,
            bgAlpha: Round(bgOpacity * 2.55),
            textColor: textColor,
            borderTransparent: borderTransparent,
            borderColor: borderColor,
            borderWidth: borderWidth
        }
    }

    static GetMonitorDpi(left, top, right, bottom) {
        try {
            rc := Buffer(16, 0)
            NumPut("int", left, "int", top, "int", right, "int", bottom, rc)
            hMon := DllCall("user32\MonitorFromRect", "ptr", rc, "uint", 2, "ptr")
            if (hMon) {
                dpiX := 96, dpiY := 96
                if (DllCall("shcore\GetDpiForMonitor", "ptr", hMon, "int", 0, "uint*", &dpiX, "uint*", &dpiY, "int") == 0 && dpiX > 0)
                    return dpiX
            }
        }
        return A_ScreenDPI ? A_ScreenDPI : 96
    }

    static CreateRoundedRectPath(x, y, w, h, radius) {
        pPath := 0
        DllCall("gdiplus\GdipCreatePath", "int", 0, "ptr*", &pPath)
        if (!pPath)
            return 0
        dia := Min(radius * 2.0, Min(w, h))
        if (dia <= 1.0) {
            DllCall("gdiplus\GdipAddPathRectangle", "ptr", pPath, "float", x, "float", y, "float", w, "float", h)
        } else {
            DllCall("gdiplus\GdipAddPathArc", "ptr", pPath, "float", x, "float", y, "float", dia, "float", dia, "float", 180.0, "float", 90.0)
            DllCall("gdiplus\GdipAddPathArc", "ptr", pPath, "float", x + w - dia, "float", y, "float", dia, "float", dia, "float", 270.0, "float", 90.0)
            DllCall("gdiplus\GdipAddPathArc", "ptr", pPath, "float", x + w - dia, "float", y + h - dia, "float", dia, "float", dia, "float", 0.0, "float", 90.0)
            DllCall("gdiplus\GdipAddPathArc", "ptr", pPath, "float", x, "float", y + h - dia, "float", dia, "float", dia, "float", 90.0, "float", 90.0)
            DllCall("gdiplus\GdipClosePathFigure", "ptr", pPath)
        }
        return pPath
    }

    static CreateFontResources(emPx, &pFamily, &pFont, &pFormat) {
        pFamily := 0, pFont := 0, pFormat := 0
        DllCall("gdiplus\GdipCreateFontFamilyFromName", "wstr", "Segoe UI", "ptr", 0, "ptr*", &pFamily)
        if (!pFamily)
            DllCall("gdiplus\GdipGetGenericFontFamilySansSerif", "ptr*", &pFamily)
        if (pFamily)
            DllCall("gdiplus\GdipCreateFont", "ptr", pFamily, "float", emPx, "int", 1, "int", 2, "ptr*", &pFont) ; Bold, UnitPixel
        DllCall("gdiplus\GdipCreateStringFormat", "int", 0, "ushort", 0, "ptr*", &pFormat)
        if (pFormat) {
            DllCall("gdiplus\GdipSetStringFormatAlign", "ptr", pFormat, "int", 1)     ; Center
            DllCall("gdiplus\GdipSetStringFormatLineAlign", "ptr", pFormat, "int", 1) ; Middle
        }
    }

    static FreeFontResources(pFamily, pFont, pFormat) {
        if (pFormat)
            DllCall("gdiplus\GdipDeleteStringFormat", "ptr", pFormat)
        if (pFont)
            DllCall("gdiplus\GdipDeleteFont", "ptr", pFont)
        if (pFamily)
            DllCall("gdiplus\GdipDeleteFontFamily", "ptr", pFamily)
    }

    static ComputeLayout(textStr, style, dpi) {
        scale := dpi / 96.0
        emPx := style.fontSize * (dpi / 72.0)
        padX := Max(10, Round(style.fontSize * 0.9)) * scale
        padY := Max(6, Round(style.fontSize * 0.45)) * scale
        bw := style.borderTransparent ? 0.0 : (style.borderWidth * scale)

        isPin := (textStr == "__PINNED__")
        isUnpin := (textStr == "__UNPINNED__")
        isIcon := (isPin || isUnpin)

        iconSize := Max(12.0, Round(emPx * 1.1))
        if (isIcon) {
            contentW := iconSize
            contentH := iconSize
        } else {
            textW := emPx * 0.8
            textH := emPx * 1.3
            hdcTmp := DllCall("user32\GetDC", "ptr", 0, "ptr")
            if (hdcTmp) {
                pG := 0
                DllCall("gdiplus\GdipCreateFromHDC", "ptr", hdcTmp, "ptr*", &pG)
                if (pG) {
                    DllCall("gdiplus\GdipSetTextRenderingHint", "ptr", pG, "int", 4)
                    this.CreateFontResources(emPx, &pFamily, &pFont, &pFormat)
                    if (pFont && pFormat) {
                        maxW := InStr(textStr, "`n") ? (360.0 * scale) : (2000.0 * scale)
                        layoutRect := Buffer(16, 0)
                        NumPut("float", 0.0, "float", 0.0, "float", maxW, "float", 2000.0 * scale, layoutRect)
                        boundRect := Buffer(16, 0)
                        chars := 0, lines := 0
                        DllCall("gdiplus\GdipMeasureString", "ptr", pG, "wstr", textStr, "int", -1, "ptr", pFont, "ptr", layoutRect, "ptr", pFormat, "ptr", boundRect, "int*", &chars, "int*", &lines)
                        textW := NumGet(boundRect, 8, "float")
                        textH := NumGet(boundRect, 12, "float")
                    }
                    this.FreeFontResources(pFamily, pFont, pFormat)
                    DllCall("gdiplus\GdipDeleteGraphics", "ptr", pG)
                }
                DllCall("user32\ReleaseDC", "ptr", 0, "ptr", hdcTmp)
            }
            contentW := Max(textW + 2.0 * scale, textH * 0.75)
            contentH := Max(textH, emPx)
        }

        w := Max(1, Ceil(contentW + padX * 2.0 + bw * 2.0))
        h := Max(1, Ceil(contentH + padY * 2.0 + bw * 2.0))
        return {
            w: w,
            h: h,
            scale: scale,
            emPx: emPx,
            bw: bw,
            iconSize: iconSize,
            isPin: isPin,
            isUnpin: isUnpin,
            isIcon: isIcon
        }
    }

    static Render(hwnd, x, y, textStr, style, layout) {
        if (!this.EnsureGdiPlus())
            return false

        w := layout.w
        h := layout.h
        bw := layout.bw
        scale := layout.scale

        pBitmap := 0
        DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", w, "int", h, "int", 0, "int", 0xE200B, "ptr", 0, "ptr*", &pBitmap) ; PixelFormat32bppPARGB
        if (!pBitmap)
            return false

        pGraphics := 0
        DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", pBitmap, "ptr*", &pGraphics)
        if (!pGraphics) {
            DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)
            return false
        }

        DllCall("gdiplus\GdipSetSmoothingMode", "ptr", pGraphics, "int", 4)      ; SmoothingModeAntiAlias
        DllCall("gdiplus\GdipSetTextRenderingHint", "ptr", pGraphics, "int", 4)  ; TextRenderingHintAntiAlias
        DllCall("gdiplus\GdipSetPixelOffsetMode", "ptr", pGraphics, "int", 4)    ; PixelOffsetModeHighQuality
        DllCall("gdiplus\GdipGraphicsClear", "ptr", pGraphics, "uint", 0x00000000)

        inset := (bw > 0) ? (bw / 2.0) : 0.5
        rw := Max(1.0, w - inset * 2.0)
        rh := Max(1.0, h - inset * 2.0)
        radius := Max(1.0, Min(10.0 * scale, Min(w, h) * 0.35) - inset)

        pPath := this.CreateRoundedRectPath(inset, inset, rw, rh, radius)
        if (pPath) {
            if (style.bgAlpha > 0) {
                pBgBrush := 0
                DllCall("gdiplus\GdipCreateSolidFill", "uint", this.HexToArgb(style.bgColor, style.bgAlpha), "ptr*", &pBgBrush)
                if (pBgBrush) {
                    DllCall("gdiplus\GdipFillPath", "ptr", pGraphics, "ptr", pBgBrush, "ptr", pPath)
                    DllCall("gdiplus\GdipDeleteBrush", "ptr", pBgBrush)
                }
            }

            if (!style.borderTransparent && bw > 0) {
                pPen := 0
                DllCall("gdiplus\GdipCreatePen1", "uint", this.HexToArgb(style.borderColor, 255), "float", bw, "int", 2, "ptr*", &pPen)
                if (pPen) {
                    DllCall("gdiplus\GdipDrawPath", "ptr", pGraphics, "ptr", pPen, "ptr", pPath)
                    DllCall("gdiplus\GdipDeletePen", "ptr", pPen)
                }
            }
            DllCall("gdiplus\GdipDeletePath", "ptr", pPath)
        }

        fgArgb := this.HexToArgb(style.textColor, 255)
        if (layout.isIcon) {
            cx := w / 2.0
            cy := h / 2.0
            iconSize := layout.iconSize
            strokeW := Max(1.5, iconSize * 0.13)
            ringDia := Max(4.0, iconSize - strokeW)
            ringX := cx - ringDia / 2.0
            ringY := cy - ringDia / 2.0

            pRingPen := 0
            DllCall("gdiplus\GdipCreatePen1", "uint", fgArgb, "float", strokeW, "int", 2, "ptr*", &pRingPen)
            if (pRingPen) {
                DllCall("gdiplus\GdipDrawEllipse", "ptr", pGraphics, "ptr", pRingPen, "float", ringX, "float", ringY, "float", ringDia, "float", ringDia)
                DllCall("gdiplus\GdipDeletePen", "ptr", pRingPen)
            }

            if (layout.isPin) {
                dotDia := Max(3.0, iconSize * 0.34)
                dotX := cx - dotDia / 2.0
                dotY := cy - dotDia / 2.0
                pDotBrush := 0
                DllCall("gdiplus\GdipCreateSolidFill", "uint", fgArgb, "ptr*", &pDotBrush)
                if (pDotBrush) {
                    DllCall("gdiplus\GdipFillEllipse", "ptr", pGraphics, "ptr", pDotBrush, "float", dotX, "float", dotY, "float", dotDia, "float", dotDia)
                    DllCall("gdiplus\GdipDeleteBrush", "ptr", pDotBrush)
                }
            }
        } else {
            this.CreateFontResources(layout.emPx, &pFamily, &pFont, &pFormat)
            pTextBrush := 0
            DllCall("gdiplus\GdipCreateSolidFill", "uint", fgArgb, "ptr*", &pTextBrush)
            if (pFont && pFormat && pTextBrush) {
                drawRect := Buffer(16, 0)
                NumPut("float", 0.0, "float", 0.0, "float", Float(w), "float", Float(h), drawRect)
                DllCall("gdiplus\GdipDrawString", "ptr", pGraphics, "wstr", textStr, "int", -1, "ptr", pFont, "ptr", drawRect, "ptr", pFormat, "ptr", pTextBrush)
            }
            if (pTextBrush)
                DllCall("gdiplus\GdipDeleteBrush", "ptr", pTextBrush)
            this.FreeFontResources(pFamily, pFont, pFormat)
        }

        hBitmap := 0
        DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "ptr", pBitmap, "ptr*", &hBitmap, "uint", 0x00000000)
        if (hBitmap) {
            hdcScreen := DllCall("user32\GetDC", "ptr", 0, "ptr")
            hdcMem := DllCall("gdi32\CreateCompatibleDC", "ptr", hdcScreen, "ptr")
            oldBmp := DllCall("gdi32\SelectObject", "ptr", hdcMem, "ptr", hBitmap, "ptr")

            ptDst := Buffer(8, 0)
            NumPut("int", x, "int", y, ptDst)
            sz := Buffer(8, 0)
            NumPut("int", w, "int", h, sz)
            ptSrc := Buffer(8, 0)
            blend := Buffer(4, 0)
            NumPut("uchar", 0, "uchar", 0, "uchar", 255, "uchar", 1, blend)

            DllCall("user32\UpdateLayeredWindow", "ptr", hwnd, "ptr", hdcScreen, "ptr", ptDst, "ptr", sz, "ptr", hdcMem, "ptr", ptSrc, "uint", 0, "ptr", blend, "uint", 2)

            DllCall("gdi32\SelectObject", "ptr", hdcMem, "ptr", oldBmp)
            DllCall("gdi32\DeleteDC", "ptr", hdcMem)
            DllCall("user32\ReleaseDC", "ptr", 0, "ptr", hdcScreen)
            DllCall("gdi32\DeleteObject", "ptr", hBitmap)
        }

        DllCall("gdiplus\GdipDeleteGraphics", "ptr", pGraphics)
        DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)
        return (hBitmap != 0)
    }
}

ShowOSD(text) {
    global currentWorkspaces, osdGlobalGui
    static osdGui    := ""
    static hideTimer := ""

    textStr := String(text)
    style := OsdRenderer.ResolveStyle()
    posMode := ConfigManager.Get("general.osd.position", "bottom_center")
    posYPercent := OsdRenderer.ClampInt(ConfigManager.Get("general.osd.posYPercent", 82), 0, 100, 82)
    hideDelay := OsdRenderer.ClampInt(ConfigManager.Get("general.osd.hideDelayMs", 400), 100, 3000, 400)

    if (!osdGui || !DllCall("user32\IsWindow", "ptr", osdGui.Hwnd, "int")) {
        osdGui := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x80000 +E0x20 +E0x08000000")
        osdGlobalGui := osdGui
        osdGui.Show("Hide")
    }

    try {
        monIdx := GetCurrentTargetMonitor()
        left := 0, top := 0, right := 0, bottom := 0
        MonitorGetWorkArea(monIdx, &left, &top, &right, &bottom)
        mW := right - left
        mH := bottom - top

        dpi := OsdRenderer.GetMonitorDpi(left, top, right, bottom)
        OsdRenderer.EnsureGdiPlus()
        layout := OsdRenderer.ComputeLayout(textStr, style, dpi)
        w := layout.w
        h := layout.h

        x := Round(left + (mW - w) / 2)
        switch posMode {
            case "top_center":
                y := Round(top + mH * 0.1)
            case "center":
                y := Round(top + (mH - h) / 2)
            case "custom":
                y := Round(top + (mH - h) * (posYPercent / 100))
            default: ; "bottom_center"
                y := Round(top + (mH - h) * 0.82)
        }

        if OsdRenderer.Render(osdGui.Hwnd, x, y, textStr, style, layout) {
            DllCall("user32\SetWindowPos", "ptr", osdGui.Hwnd, "ptr", -1, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x0053)
        }
    }

    if (hideTimer)
        SetTimer(hideTimer, 0)
    hideTimer := () => (osdGui ? osdGui.Hide() : 0)
    SetTimer(hideTimer, -hideDelay)
}
