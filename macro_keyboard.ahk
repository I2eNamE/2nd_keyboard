#NoEnv
SendMode Input
SetWorkingDir %A_ScriptDir%
#SingleInstance force
#Persistent
#include <AutoHotInterception>
#Include Neutron.ahk

global AHI := new AutoHotInterception()
global macroKeyboardId := 0
global isMacroEnabled := false
global isSelecting := false
global subscribedIds := []
global macros := {} ; Format: macros[scanCode] := {type: "Program", data: "...", keyName: "..."}
global selectedScanCode := ""
global neutron

; Register message listeners
OnMessage(0x0219, "WM_DEVICECHANGE")

; Configure system tray menu
Menu, Tray, NoStandard
Menu, Tray, Add, Show Manager, ShowManager
Menu, Tray, Add, Toggle Macro (Ctrl+F12), TrayToggleMacro
Menu, Tray, Add ; Separator
Menu, Tray, Add, Exit, ExitAppLabel
Menu, Tray, Default, Show Manager
Menu, Tray, Tip, Macro Keyboard Manager

; Create Neutron Window
neutron := new NeutronWindow()
neutron.Load("ui.html")
neutron.Gui("+LabelNeutron")
neutron.Show("w740 h620", "Macro Keyboard Manager")

; Load default config if it exists
defaultConfig := A_ScriptDir . "\default_config.ini"
if (FileExist(defaultConfig)) {
    LoadConfig(neutron, defaultConfig)
}
return



NeutronClose:
    defaultConfig := A_ScriptDir . "\default_config.ini"
    SaveConfig(neutron, defaultConfig)
    neutron.Hide()
    TrayTip, Macro Keyboard Manager, Running in background. Double-click tray icon to open., 3
    return

NeutronSize:
    if (A_EventInfo == 1) { ; Minimized
        neutron.Hide()
        TrayTip, Macro Keyboard Manager, Running in background. Double-click tray icon to open., 3
    }
    return


; ---------------------------------------------------------
; Application Logic
; ---------------------------------------------------------

ToggleMacro(neutron, event := "") {
    global isMacroEnabled, isSelecting, macroKeyboardId, subscribedIds, AHI
    if (isSelecting) {
        ; Cancel selection
        isSelecting := false
        For index, subId in subscribedIds {
            AHI.UnsubscribeKeyboard(subId)
        }
        subscribedIds := []
        
        neutron.doc.getElementById("toggleBtn").innerText := "Enable Macro"
        neutron.doc.getElementById("toggleBtn").className := "btn btn-toggle"
        neutron.doc.getElementById("statusLabel").innerHTML := "Macro Status:<br><b>Disabled</b>"
        return
    }

    if (isMacroEnabled) {
        DisableMacro(neutron)
    } else {
        if (macroKeyboardId == 0) {
            SelectKeyboard(neutron)
        } else {
            EnableMacro(neutron)
        }
    }
}

EnableMacro(neutron) {
    global isSelecting, macroKeyboardId, isMacroEnabled, AHI
    if (isSelecting) {
        MsgBox, 48, Warning, Please finish selecting a keyboard first.
        return
    }
    if (macroKeyboardId == 0) {
        MsgBox, 48, Warning, Please select a keyboard first.
        return
    }
    ; Always unsubscribe first to avoid duplicate subscriptions
    AHI.UnsubscribeKeyboard(macroKeyboardId)
    isMacroEnabled := true
    
    ; Update UI
    neutron.doc.getElementById("toggleBtn").innerText := "Disable Macro"
    neutron.doc.getElementById("toggleBtn").className := "btn btn-toggle enabled"
    neutron.doc.getElementById("statusLabel").innerHTML := "Macro Status:<br><b>Enabled (ID: " . macroKeyboardId . ")</b>"
    
    AHI.SubscribeKeyboard(macroKeyboardId, true, Func("OnMacroKeyEvent"))
    TrayTip, Macro Enabled, Macro mode is ON., 2
}

DisableMacro(neutron) {
    global isMacroEnabled, macroKeyboardId, AHI
    isMacroEnabled := false
    AHI.UnsubscribeKeyboard(macroKeyboardId)
    
    ; Update UI
    neutron.doc.getElementById("toggleBtn").innerText := "Enable Macro"
    neutron.doc.getElementById("toggleBtn").className := "btn btn-toggle"
    neutron.doc.getElementById("statusLabel").innerHTML := "Macro Status:<br><b>Disabled</b>"
    
    TrayTip, Macro Disabled, Macro mode is OFF., 2
}

SelectKeyboard(neutron, event := "") {
    global isMacroEnabled, isSelecting, AHI, subscribedIds
    if (isMacroEnabled) {
        MsgBox, 48, Warning, Please disable macro mode first before selecting a new keyboard.
        return
    }
    isSelecting := true
    neutron.doc.getElementById("statusLabel").innerHTML := "Macro Status:<br><b>Selecting...</b>"
    
    ; Change button text to indicate selection cancel option
    neutron.doc.getElementById("toggleBtn").innerText := "Cancel Selection"
    neutron.doc.getElementById("toggleBtn").className := "btn btn-toggle enabled"
    
    ; Subscribe to all keyboards temporarily to catch which one is pressed
    DeviceList := AHI.GetDeviceList()
    Loop 10 {
        if (IsObject(DeviceList[A_Index])) {
            AHI.SubscribeKeyboard(A_Index, false, Func("OnSelectionEvent").Bind(A_Index))
            subscribedIds.Push(A_Index)
        }
    }
}

OnSelectionEvent(id, code, state) {
    global isSelecting, macroKeyboardId, subscribedIds, AHI, neutron
    if (isSelecting && state = 1) {
        isSelecting := false
        macroKeyboardId := id
        
        For index, subId in subscribedIds {
            AHI.UnsubscribeKeyboard(subId)
        }
        subscribedIds := []
        
        ; Automatically enable macro once keyboard is selected!
        EnableMacro(neutron)
        
        MsgBox, 64, Success, Keyboard ID %id% selected and macro enabled!
    }
}

OnMacroKeyEvent(code, state) {
    global macros
    if (state == 1) { ; Key down
        if (macros.HasKey(code)) {
            action := macros[code]
            if (action.type == "Program") {
                Run, % action.data,, UseErrorLevel
                if (ErrorLevel)
                    MsgBox, 16, Error, % "Failed to run program:`n" . action.data
            } else if (action.type == "Folder") {
                Run, % "explorer.exe """ . action.data . """",, UseErrorLevel
                if (ErrorLevel)
                    MsgBox, 16, Error, % "Failed to open folder:`n" . action.data
            } else if (action.type == "Website") {
                targetUrl := action.data
                Run, chrome.exe "%targetUrl%",, UseErrorLevel
                if (ErrorLevel) {
                    if (!InStr(targetUrl, "://"))
                        targetUrl := "http://" . targetUrl
                    Run, %targetUrl%,, UseErrorLevel
                    if (ErrorLevel)
                        MsgBox, 16, Error, % "Failed to open website:`n" . action.data
                }
            } else if (action.type == "Text") {
                ; Send text and support special keys (e.g. {Tab}, {Enter})
                SendTextWithKeys(action.data)
            }
        }
    }
}

WM_DEVICECHANGE(wParam, lParam) {
    ; 0x8000 = DBT_DEVICEARRIVAL
    ; 0x8004 = DBT_DEVICEREMOVECOMPLETE
    if (wParam == 0x8000 || wParam == 0x8004) {
        ; Use a timer to process outside the message handler thread
        SetTimer, HandleDeviceChange, -100
    }
}

HandleDeviceChange:
    global isMacroEnabled, macroKeyboardId, isSelecting, subscribedIds, AHI, neutron
    if (isMacroEnabled) {
        isMacroEnabled := false
        neutron.doc.getElementById("toggleBtn").innerText := "Enable Macro"
        neutron.doc.getElementById("toggleBtn").className := "btn btn-toggle"
        neutron.doc.getElementById("statusLabel").innerHTML := "Macro Status:<br><b>Disabled</b>"
        if (macroKeyboardId != 0)
            AHI.UnsubscribeKeyboard(macroKeyboardId)
    }
    if (isSelecting) {
        isSelecting := false
        For index, subId in subscribedIds {
            AHI.UnsubscribeKeyboard(subId)
        }
        subscribedIds := []
    }
    macroKeyboardId := 0
    neutron.doc.getElementById("statusLabel").innerHTML := "Macro Status:<br><b>Disabled</b>"
    MsgBox, 48, Device Changed, Keyboard plugged/unplugged.`nMacro mode exited.`n`nPlease select your keyboard again.
return

; ---------------------------------------------------------
; GUI Event Handlers
; ---------------------------------------------------------

SetSelectedScanCode(neutron, sc) {
    global selectedScanCode
    selectedScanCode := sc
}

SaveKeyMacro(neutron, event := "") {
    global macros
    
    InputKey := neutron.doc.getElementById("inputKey").value
    ActionType := neutron.doc.getElementById("actionType").value
    ActionData := neutron.doc.getElementById("actionData").value
    MacroName := neutron.doc.getElementById("inputName").value
    
    if (InputKey == "") {
        MsgBox, 48, Warning, Please press a key in the 'Press Key' field.
        return
    }
    if (ActionData == "") {
        MsgBox, 48, Warning, Please enter data (Path, URL, or Text) for the action.
        return
    }
    
    ; Convert InputKey to scan code
    scanCode := GetKeySC(InputKey)
    if (scanCode == 0 || scanCode == "") {
        MsgBox, 16, Error, Invalid key selected. Could not determine scan code for "%InputKey%".
        return
    }
    
    macros[scanCode] := {type: ActionType, data: ActionData, keyName: InputKey, name: MacroName}
    RefreshListView(neutron)
    
    ; Clear inputs for next entry
    neutron.doc.getElementById("inputKey").value := ""
    neutron.doc.getElementById("actionData").value := ""
    neutron.doc.getElementById("inputName").value := ""
}

DeleteKeyMacro(neutron, event := "") {
    global macros, selectedScanCode
    if (selectedScanCode == "") {
        MsgBox, 48, Warning, Please select a macro row first.
        return
    }
    macros.Delete(selectedScanCode)
    selectedScanCode := ""
    RefreshListView(neutron)
}

OnEditSelected(neutron, event := "") {
    global macros, selectedScanCode
    if (selectedScanCode == "") {
        MsgBox, 48, Warning, Please select a macro row first.
        return
    }
    if (macros.HasKey(selectedScanCode)) {
        neutron.doc.getElementById("inputKey").value := macros[selectedScanCode].keyName
        neutron.doc.getElementById("actionType").value := macros[selectedScanCode].type
        neutron.doc.getElementById("actionData").value := macros[selectedScanCode].data
        
        nameVal := macros[selectedScanCode].HasKey("name") ? macros[selectedScanCode].name : ""
        neutron.doc.getElementById("inputName").value := nameVal
    }
}

ClearForm(neutron, event := "") {
    neutron.doc.getElementById("inputKey").value := ""
    neutron.doc.getElementById("actionType").value := "Program"
    neutron.doc.getElementById("actionData").value := ""
    neutron.doc.getElementById("inputName").value := ""
}

RefreshListView(neutron) {
    global macros
    html := ""
    For sc, action in macros {
        icon := "assets/keyboard.svg"
        if (action.type == "Program")
            icon := "assets/program.svg"
        else if (action.type == "Folder")
            icon := "assets/Open%20Folder.svg"
        else if (action.type == "Website")
            icon := "assets/website%20URL.svg"
        else if (action.type == "Text")
            icon := "assets/Send%20Text.svg"
            
        macroName := action.HasKey("name") ? action.name : ""
        if (macroName == "") {
            titleText := action.keyName . " Macro"
            detailsText := action.data
        } else {
            titleText := macroName
            detailsText := action.keyName . " -> " . action.data
        }
        
        ; Escape strings for HTML
        StringReplace, titleText, titleText, &, &amp;, All
        StringReplace, titleText, titleText, <, &lt;, All
        StringReplace, titleText, titleText, >, &gt;, All
        StringReplace, titleText, titleText, ", &quot;, All
        
        StringReplace, detailsText, detailsText, &, &amp;, All
        StringReplace, detailsText, detailsText, <, &lt;, All
        StringReplace, detailsText, detailsText, >, &gt;, All
        StringReplace, detailsText, detailsText, ", &quot;, All
        
        html .= "<div class='macro-item' id='macro_" . sc . "' onclick='selectMacro(""" . sc . """)'>"
        html .= "  <span class='macro-icon'><img src='" . icon . "' class='macro-svg-icon' /></span>"
        html .= "  <div class='macro-content'>"
        html .= "    <div class='macro-title'>" . titleText . "</div>"
        html .= "    <div class='macro-details'>" . detailsText . "</div>"
        html .= "  </div>"
        html .= "</div>"
    }
    neutron.doc.getElementById("macroList").innerHTML := html
}

SaveConfig(neutron, filePath) {
    global macros
    
    ; Delete existing file to avoid remnants
    FileDelete, %filePath%
    
    ; Save Macros
    For sc, action in macros {
        IniWrite, % action.keyName, %filePath%, Macro_%sc%, KeyName
        IniWrite, % action.type, %filePath%, Macro_%sc%, Type
        IniWrite, % action.data, %filePath%, Macro_%sc%, Data
        
        macroName := action.HasKey("name") ? action.name : ""
        IniWrite, % macroName, %filePath%, Macro_%sc%, Name
    }
    return true
}

LoadConfig(neutron, filePath) {
    global macros
    if (!FileExist(filePath))
        return false
        
    ; Read all sections
    IniRead, SectionNames, %filePath%
    if (SectionNames == "")
        return false
        
    macros := {}
    Loop, Parse, SectionNames, `n
    {
        section := A_LoopField
        if (InStr(section, "Macro_") == 1) {
            sc := SubStr(section, 7)
            IniRead, keyName, %filePath%, %section%, KeyName
            IniRead, type, %filePath%, %section%, Type
            IniRead, data, %filePath%, %section%, Data
            IniRead, name, %filePath%, %section%, Name, % ""
            macros[sc] := {type: type, data: data, keyName: keyName, name: name}
        }
    }
    RefreshListView(neutron)
    return true
}

SaveConfigToFile(neutron, event := "") {
    FileSelectFile, SelectedFile, S16, %A_ScriptDir%\macro_config.ini, Save Config As, INI Documents (*.ini)
    if (SelectedFile = "")
        return
    if !InStr(SelectedFile, ".ini")
        SelectedFile .= ".ini"
        
    if (SaveConfig(neutron, SelectedFile)) {
        MsgBox, 64, Success, Configuration saved successfully to:`n%SelectedFile%
    } else {
        MsgBox, 16, Error, Failed to save configuration to:`n%SelectedFile%
    }
}

LoadConfigFromFile(neutron, event := "") {
    FileSelectFile, SelectedFile, 3, %A_ScriptDir%, Load Config, INI Documents (*.ini)
    if (SelectedFile = "")
        return
    
    if (LoadConfig(neutron, SelectedFile)) {
        MsgBox, 64, Success, Configuration loaded successfully.
    } else {
        MsgBox, 16, Error, Invalid or empty config file.
    }
}

; ---------------------------------------------------------
; Hotkeys
; ---------------------------------------------------------

; Ctrl + F12 to toggle macro keyboard enabling and selection
^F12::
    ToggleMacro(neutron)
    return

SendTextWithKeys(data) {
    pos := 1
    while (pos <= StrLen(data)) {
        nextBrace := InStr(data, "{", , pos)
        if (nextBrace == 0) {
            remaining := SubStr(data, pos)
            SendInput, % "{Raw}" . remaining
            break
        }
        
        if (nextBrace > pos) {
            before := SubStr(data, pos, nextBrace - pos)
            SendInput, % "{Raw}" . before
        }
        
        closeBrace := InStr(data, "}", , nextBrace)
        if (closeBrace == 0) {
            remaining := SubStr(data, nextBrace)
            SendInput, % "{Raw}" . remaining
            break
        }
        
        tag := SubStr(data, nextBrace, closeBrace - nextBrace + 1)
        tagName := SubStr(tag, 2, StrLen(tag) - 2)
        
        StringLower, lowerTagName, tagName
        
        isKey := false
        if (lowerTagName = "tab" || lowerTagName = "enter" || lowerTagName = "space" 
            || lowerTagName = "esc" || lowerTagName = "escape" || lowerTagName = "backspace" || lowerTagName = "bs"
            || lowerTagName = "delete" || lowerTagName = "del" || lowerTagName = "insert" || lowerTagName = "ins"
            || lowerTagName = "up" || lowerTagName = "down" || lowerTagName = "left" || lowerTagName = "right"
            || lowerTagName = "home" || lowerTagName = "end" || lowerTagName = "pgup" || lowerTagName = "pgdn"
            || RegExMatch(lowerTagName, "^f\d{1,2}$")) {
            isKey := true
        }
        
        if (isKey) {
            SendInput, % tag
        } else {
            SendInput, % "{Raw}" . tag
        }
        
        pos := closeBrace + 1
    }
}

; ---------------------------------------------------------
; System Tray Menu Handlers
; ---------------------------------------------------------

ShowManager:
    neutron.Show()
    return

TrayToggleMacro:
    ToggleMacro(neutron)
    return

ExitAppLabel:
    defaultConfig := A_ScriptDir . "\default_config.ini"
    SaveConfig(neutron, defaultConfig)
    ExitApp
