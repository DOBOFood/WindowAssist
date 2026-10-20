#Requires AutoHotkey v2.0

class WebViewManager {
    static instances := Map()
    static sharedEnv := 0

    /**
     * Initializes or retrieves the shared WebView2 environment across all application windows.
     * Sharing a single environment prevents COM E_ABORT (0x80004004) crashes.
     */
    static GetSharedEnv() {
        if this.sharedEnv
            return this.sharedEnv

        userDataDir := A_Temp "\WindowAssist_WebView2"
        if !DirExist(userDataDir)
            DirCreate(userDataDir)

        this.sharedEnv := WebView2.CreateEnvironmentAsync(, userDataDir).await()
        return this.sharedEnv
    }

    /**
     * Creates and attaches a WebView2 controller to a designated window.
     * @param guiHwnd Parent window handle.
     * @param htmlPath Path to target HTML document.
     * @param onMessageCallback Callback invoked when a JSON message is received from WebView2.
     * @returns {Object|Integer} Controller instance wrapper or 0 on failure.
     */
    static Create(guiHwnd, htmlPath, onMessageCallback) {
        if !FileExist(htmlPath) {
            MsgBox("File not found:`n" htmlPath, "WindowAssist Error", 0x10)
            return 0
        }

        uri := "file:///" . StrReplace(StrReplace(htmlPath, "\", "/"), " ", "%20")
        
        userDataDir := A_Temp "\WindowAssist_WebView2"
        if !DirExist(userDataDir)
            DirCreate(userDataDir)

        try {
            env := 0
            try env := this.GetSharedEnv()

            wvc := env ? env.CreateCoreWebView2ControllerAsync(guiHwnd).await() : WebView2.create(guiHwnd, , , userDataDir)
            if !IsObject(wvc)
                return 0

            wvc.Fill()
            wvc.IsVisible := true

            ; Set background to transparent (0x00000000) for custom glass / alpha styling
            try wvc.DefaultBackgroundColor := 0x00000000

            wv := wvc.CoreWebView2

            try {
                settings := wv.Settings
                settings.AreDefaultContextMenusEnabled := false
                settings.AreDevToolsEnabled := true
                settings.IsZoomControlEnabled := false
            }

            wv.add_WebMessageReceived((wvObj, args) => this._HandleWebMessage(args, onMessageCallback))
            wv.Navigate(uri)
            
            instance := {
                wvc: wvc,
                wv: wv,
                hwnd: guiHwnd
            }
            this.instances[guiHwnd] := instance
            return instance
        } catch as err {
            msg := InStr(err.Message, "0x80070002")
                ? "Microsoft Edge WebView2 Runtime is not installed.`nPlease install the Evergreen Bootstrapper from Microsoft."
                : ("Failed to initialize WebView2:`n" err.Message)
            MsgBox(msg, "WindowAssist Error", 0x10)
            return 0
        }
    }

    static Send(instance, payloadObj) {
        if (!instance || !instance.HasOwnProp("wv") || !instance.wv)
            return
        try {
            jsonStr := JSON.Dump(payloadObj)
            instance.wv.PostWebMessageAsJson(jsonStr)
        }
    }

    static _HandleWebMessage(args, callback) {
        try {
            rawJson := ""
            try rawJson := args.WebMessageAsJson
            if (rawJson == "")
                try rawJson := args.TryGetWebMessageAsString()
            
            if (rawJson != "") {
                data := JSON.Load(rawJson)
                ; Handle nested serialized JSON string payloads
                if (data is String) {
                    try data := JSON.Load(data)
                }
                if (data is Map)
                    callback(data)
            }
        }
    }

    static Resize(instance, w, h) {
        if (!instance || !instance.HasOwnProp("wvc") || !instance.wvc)
            return
        try {
            instance.wvc.Fill()
        }
    }

    static Destroy(guiHwnd) {
        if this.instances.Has(guiHwnd) {
            try this.instances[guiHwnd].wvc.Close()
            this.instances.Delete(guiHwnd)
        }
    }
}
