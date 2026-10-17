#Requires AutoHotkey v2.0

class JSON {
    static Load(jsonStr) {
        if (jsonStr == "")
            return Map()
        
        try {
            doc := ComObject("htmlfile")
            doc.write("<meta http-equiv='X-UA-Compatible' content='IE=edge'>")
            return this._ParseJS(doc.parentWindow.JSON.parse(jsonStr))
        } catch {
            return Map()
        }
    }
    
    static Dump(obj, indent := "") {
        if IsObject(obj) {
            if obj is Array {
                res := "["
                for idx, val in obj {
                    res .= (idx > 1 ? ", " : "") . this.Dump(val, indent)
                }
                return res . "]"
            } else if obj is Map {
                res := "{"
                i := 0
                for k, v in obj {
                    i++
                    res .= (i > 1 ? ", " : "") . '"' . k . '": ' . this.Dump(v, indent)
                }
                return res . "}"
            }
        } else if IsNumber(obj) {
            return String(obj)
        } else {
            str := String(obj)
            str := StrReplace(str, "\", "\\")
            str := StrReplace(str, '"', '\"')
            str := StrReplace(str, "`n", "\n")
            str := StrReplace(str, "`r", "\r")
            str := StrReplace(str, "`t", "\t")
            return '"' . str . '"'
        }
        return '""'
    }

    static _ParseJS(jsObj) {
        if !IsObject(jsObj)
            return jsObj
        
        try {
            if (jsObj.constructor.name == "Array") {
                arr := []
                Loop jsObj.length {
                    arr.Push(this._ParseJS(jsObj.%A_Index - 1%))
                }
                return arr
            }
        }
        
        m := Map()
        try {
            doc := ComObject("htmlfile")
            doc.write("<meta http-equiv='X-UA-Compatible' content='IE=edge'>")
            keys := doc.parentWindow.Object.keys(jsObj)
            Loop keys.length {
                k := keys.%A_Index - 1%
                m[k] := this._ParseJS(jsObj.%k%)
            }
        }
        return m
    }
}
