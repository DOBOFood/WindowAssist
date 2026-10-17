#Requires AutoHotkey v2.0

class MouseHook {
    static dummy() => true
}

#HotIf !GetKeyState("NumLock", "P")
~LButton:: {
    global lastTaskbarClickTime
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mX, &mY, &mHwnd)
    if !mHwnd
        return

    if IsTaskbarOrPreviewHwnd(mHwnd, mX, mY) {
        lastTaskbarClickTime := A_TickCount
    }

    rootHwnd := GetRootManagedWindow(mHwnd)
    if (rootHwnd) {
        CrossWorkspaceAltTab.RecordActiveWindow(rootHwnd)
    }
}

~LButton Up:: {
    global lastTaskbarClickTime
    CoordMode("Mouse", "Screen")
    MouseGetPos(&mX, &mY, &mHwnd)
    if !mHwnd
        return

    if IsTaskbarOrPreviewHwnd(mHwnd, mX, mY) {
        lastTaskbarClickTime := A_TickCount
    }
}
#HotIf
