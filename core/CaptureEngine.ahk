#Requires AutoHotkey v2.0

class CaptureEngine {
    static pToken := 0

    static Init() {
        if (this.pToken != 0)
            return
        si := Buffer(A_PtrSize == 8 ? 24 : 16, 0)
        NumPut("UInt", 1, si, 0)
        pTokenBuf := Buffer(A_PtrSize, 0)
        DllCall("gdiplus\GdiplusStartup", "Ptr", pTokenBuf, "Ptr", si, "Ptr", 0)
        this.pToken := NumGet(pTokenBuf, 0, "Ptr")
    }

    static Shutdown() {
        if (this.pToken != 0) {
            DllCall("gdiplus\GdiplusShutdown", "Ptr", this.pToken)
            this.pToken := 0
        }
    }

    /**
     * Captures a window's contents and encodes it to a Base64 JPEG data URL.
     * @param hwnd Window handle to capture.
     * @param maxW Maximum thumbnail width.
     * @param maxH Maximum thumbnail height.
     * @returns {String} Data URL string or empty on failure.
     */
    static CaptureWindowBase64(hwnd, maxW := 480, maxH := 270) {
        if (!hwnd || !DllCall("IsWindow", "Ptr", hwnd, "Int"))
            return ""

        this.Init()
        rc := Buffer(16, 0)
        DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rc)
        w := NumGet(rc, 8, "Int") - NumGet(rc, 0, "Int")
        h := NumGet(rc, 12, "Int") - NumGet(rc, 4, "Int")
        if (w <= 0 || h <= 0)
            return ""

        hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
        hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
        hbm := DllCall("CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", w, "Int", h, "Ptr")
        hbmOld := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")

        ; PW_RENDERFULLCONTENT (0x00000002) renders hardware-accelerated DWM windows directly
        ; from the compositor cache without blocking the thread if the target window hangs.
        rendered := DllCall("PrintWindow", "Ptr", hwnd, "Ptr", hdcMem, "UInt", 2, "Int")
        if (!rendered) {
            ; Fallback to standard PrintWindow (which sends WM_PRINT and may hang uncooperative windows);
            ; execute only if the target process is actively responding.
            if (!DllCall("IsHungAppWindow", "Ptr", hwnd)) {
                DllCall("PrintWindow", "Ptr", hwnd, "Ptr", hdcMem, "UInt", 0, "Int")
            }
        }

        pBitmapOrig := 0
        pBitmapResized := 0
        pBitmapBuf := Buffer(A_PtrSize, 0)
        DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "Ptr", hbm, "Ptr", 0, "Ptr", pBitmapBuf)
        pBitmapOrig := NumGet(pBitmapBuf, 0, "Ptr")

        DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbmOld)
        DllCall("DeleteObject", "Ptr", hbm)
        DllCall("DeleteDC", "Ptr", hdcMem)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)

        if (!pBitmapOrig)
            return ""

        scale := Min(maxW / w, maxH / h, 1.0)
        finalW := Max(1, Round(w * scale))
        finalH := Max(1, Round(h * scale))

        pThumbBuf := Buffer(A_PtrSize, 0)
        DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", finalW, "Int", finalH, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr", pThumbBuf)
        pBitmapResized := NumGet(pThumbBuf, 0, "Ptr")

        pGraphicsBuf := Buffer(A_PtrSize, 0)
        DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", pBitmapResized, "Ptr", pGraphicsBuf)
        pGraphics := NumGet(pGraphicsBuf, 0, "Ptr")

        DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", pGraphics, "Int", 7) ; HighQualityBicubic
        DllCall("gdiplus\GdipDrawImageRectRectI", "Ptr", pGraphics, "Ptr", pBitmapOrig,
            "Int", 0, "Int", 0, "Int", finalW, "Int", finalH,
            "Int", 0, "Int", 0, "Int", w, "Int", h,
            "Int", 2, "Ptr", 0, "Ptr", 0, "Ptr", 0)

        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)
        DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmapOrig)

        base64Str := this._BitmapToBase64(pBitmapResized)
        DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmapResized)

        return base64Str ? "data:image/jpeg;base64," base64Str : ""
    }

    /**
     * Retrieves a window's icon and encodes it to a Base64 PNG data URL.
     * @param hwnd Window handle.
     * @returns {String} Data URL string or empty on failure.
     */
    static GetWindowIconBase64(hwnd) {
        if (!hwnd || !DllCall("IsWindow", "Ptr", hwnd, "Int"))
            return ""

        this.Init()
        hIcon := 0
        ; Query WM_GETICON with timeout (SMTO_ABORTIFHUNG = 0x0002, 10ms) to avoid hanging
        DllCall("SendMessageTimeout", "Ptr", hwnd, "UInt", 0x007F, "Ptr", 2, "Ptr", 0, "UInt", 0x0002, "UInt", 10, "Ptr*", &hIcon) ; ICON_BIG2
        if (!hIcon)
            DllCall("SendMessageTimeout", "Ptr", hwnd, "UInt", 0x007F, "Ptr", 1, "Ptr", 0, "UInt", 0x0002, "UInt", 10, "Ptr*", &hIcon) ; ICON_BIG
        if (!hIcon)
            hIcon := DllCall("GetClassLongPtr", "Ptr", hwnd, "Int", -14, "Ptr") ; GCLP_HICON

        if (!hIcon) {
            try {
                exePath := WinGetProcessPath("ahk_id " hwnd)
                hIconBuf := Buffer(A_PtrSize, 0)
                if (DllCall("shell32\ExtractIconExW", "WStr", exePath, "Int", 0, "Ptr", hIconBuf, "Ptr", 0, "UInt", 1) > 0)
                    hIcon := NumGet(hIconBuf, 0, "Ptr")
            }
        }

        if (!hIcon)
            return ""

        pBitmapBuf := Buffer(A_PtrSize, 0)
        DllCall("gdiplus\GdipCreateBitmapFromHICON", "Ptr", hIcon, "Ptr", pBitmapBuf)
        pBitmap := NumGet(pBitmapBuf, 0, "Ptr")
        DllCall("DestroyIcon", "Ptr", hIcon)

        if (!pBitmap)
            return ""

        base64Str := this._BitmapToBase64(pBitmap, "{557CF406-1A04-11D3-9A73-0000F81EF32E}") ; PNG
        DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)

        return base64Str ? "data:image/png;base64," base64Str : ""
    }

    static _BitmapToBase64(pBitmap, encoderClsid := "{557CF401-1A04-11D3-9A73-0000F81EF32E}") { ; JPEG default
        clsid := Buffer(16, 0)
        DllCall("ole32\CLSIDFromString", "WStr", encoderClsid, "Ptr", clsid)

        pStreamBuf := Buffer(A_PtrSize, 0)
        DllCall("ole32\CreateStreamOnHGlobal", "Ptr", 0, "Int", true, "Ptr", pStreamBuf)
        pStream := NumGet(pStreamBuf, 0, "Ptr")
        if (!pStream)
            return ""

        DllCall("gdiplus\GdipSaveImageToStream", "Ptr", pBitmap, "Ptr", pStream, "Ptr", clsid, "Ptr", 0)

        hGlobalBuf := Buffer(A_PtrSize, 0)
        DllCall("ole32\GetHGlobalFromStream", "Ptr", pStream, "Ptr", hGlobalBuf)
        hGlobal := NumGet(hGlobalBuf, 0, "Ptr")
        size := DllCall("kernel32\GlobalSize", "Ptr", hGlobal, "UPtr")
        pData := DllCall("kernel32\GlobalLock", "Ptr", hGlobal, "Ptr")

        strLen := 0
        DllCall("crypt32\CryptBinaryToStringW", "Ptr", pData, "UInt", size, "UInt", 0x40000001, "Ptr", 0, "UInt*", &strLen) ; CRYPT_STRING_BASE64 | NOCRLF
        outBuf := Buffer(strLen * 2, 0)
        DllCall("crypt32\CryptBinaryToStringW", "Ptr", pData, "UInt", size, "UInt", 0x40000001, "Ptr", outBuf, "UInt*", &strLen)

        DllCall("kernel32\GlobalUnlock", "Ptr", hGlobal)
        ObjRelease(pStream)

        return StrGet(outBuf, "UTF-16")
    }
}
