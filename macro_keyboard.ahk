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

; Create Neutron Window
neutron := new NeutronWindow()
neutron.Load("ui.html")
neutron.Gui("+LabelNeutron")
neutron.Show("w740 h620", "Macro Keyboard Manager")
return

NeutronClose:
ExitApp

; ---------------------------------------------------------
; Application Logic
; ---------------------------------------------------------

ToggleMacro(neutron, event) {
    global isMacroEnabled
    if (!isMacroEnabled) {
        EnableMacro(neutron)
    } else {
        DisableMacro(neutron)
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
    neutron.doc.getElementById("statusLabel").innerHTML := "Macro Status:<br><b>Enabled</b>"
    
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

SelectKeyboard(neutron, event) {
    global isMacroEnabled, isSelecting, AHI, subscribedIds
    if (isMacroEnabled) {
        MsgBox, 48, Warning, Please disable macro mode first before selecting a new keyboard.
        return
    }
    isSelecting := true
    neutron.doc.getElementById("statusLabel").innerHTML := "Macro Status:<br><b>Selecting...</b>"
    
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
        
        neutron.doc.getElementById("statusLabel").innerHTML := "Macro Status:<br><b>Ready (ID: " . id . ")</b>"
        MsgBox, 64, Success, Keyboard ID %id% selected as macro keyboard.
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
            } else if (action.type == "Website") {
                Run, % action.data,, UseErrorLevel
                if (ErrorLevel)
                    MsgBox, 16, Error, % "Failed to open website:`n" . action.data
            } else if (action.type == "Text") {
                ; Send raw text to active window
                SendInput, % "{Raw}" . action.data
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

SetSelectedScanCode(neutron, event, sc) {
    global selectedScanCode
    selectedScanCode := sc
}

SaveKeyMacro(neutron, event) {
    global macros
    
    InputKey := neutron.doc.getElementById("inputKey").value
    ActionType := neutron.doc.getElementById("actionType").value
    ActionData := neutron.doc.getElementById("actionData").value
    
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
    
    macros[scanCode] := {type: ActionType, data: ActionData, keyName: InputKey}
    RefreshListView(neutron)
    
    ; Clear inputs for next entry
    neutron.doc.getElementById("inputKey").value := ""
    neutron.doc.getElementById("actionData").value := ""
}

DeleteKeyMacro(neutron, event) {
    global macros, selectedScanCode
    if (selectedScanCode == "") {
        MsgBox, 48, Warning, Please select a macro row first.
        return
    }
    macros.Delete(selectedScanCode)
    selectedScanCode := ""
    RefreshListView(neutron)
}

OnEditSelected(neutron, event) {
    global macros, selectedScanCode
    if (selectedScanCode == "") {
        MsgBox, 48, Warning, Please select a macro row first.
        return
    }
    if (macros.HasKey(selectedScanCode)) {
        neutron.doc.getElementById("inputKey").value := macros[selectedScanCode].keyName
        neutron.doc.getElementById("actionType").value := macros[selectedScanCode].type
        neutron.doc.getElementById("actionData").value := macros[selectedScanCode].data
    }
}

ClearForm(neutron, event) {
    neutron.doc.getElementById("inputKey").value := ""
    neutron.doc.getElementById("actionType").value := "Program"
    neutron.doc.getElementById("actionData").value := ""
}

RefreshListView(neutron) {
    global macros
    html := ""
    For sc, action in macros {
        ; Escape strings for HTML
        safeDesc := action.keyName . " -> [" . action.type . "] " . action.data
        StringReplace, safeDesc, safeDesc, &, &amp;, All
        StringReplace, safeDesc, safeDesc, <, &lt;, All
        StringReplace, safeDesc, safeDesc, >, &gt;, All
        StringReplace, safeDesc, safeDesc, ", &quot;, All
        
        html .= "<div class='macro-item' id='macro_" sc "' onclick='selectMacro(""" sc """)'>" safeDesc "</div>"
    }
    neutron.doc.getElementById("macroList").innerHTML := html
}

SaveConfigToFile(neutron, event) {
    global macros
    FileSelectFile, SelectedFile, S16, %A_ScriptDir%\macro_config.ini, Save Config As, INI Documents (*.ini)
    if (SelectedFile = "")
        return
    if !InStr(SelectedFile, ".ini")
        SelectedFile .= ".ini"
        
    ; Clear existing file
    FileDelete, %SelectedFile%
    
    For sc, action in macros {
        IniWrite, % action.keyName, %SelectedFile%, Macro_%sc%, KeyName
        IniWrite, % action.type, %SelectedFile%, Macro_%sc%, Type
        IniWrite, % action.data, %SelectedFile%, Macro_%sc%, Data
    }
    MsgBox, 64, Success, Configuration saved successfully to:`n%SelectedFile%
}

LoadConfigFromFile(neutron, event) {
    global macros
    FileSelectFile, SelectedFile, 3, %A_ScriptDir%, Load Config, INI Documents (*.ini)
    if (SelectedFile = "")
        return
    
    ; Read all sections
    IniRead, SectionNames, %SelectedFile%
    if (SectionNames == "") {
        MsgBox, 16, Error, Invalid or empty config file.
        return
    }
    
    macros := {}
    Loop, Parse, SectionNames, `n
    {
        section := A_LoopField
        if (InStr(section, "Macro_") == 1) {
            sc := SubStr(section, 7)
            IniRead, keyName, %SelectedFile%, %section%, KeyName
            IniRead, type, %SelectedFile%, %section%, Type
            IniRead, data, %SelectedFile%, %section%, Data
            macros[sc] := {type: type, data: data, keyName: keyName}
        }
    }
    RefreshListView(neutron)
    MsgBox, 64, Success, Configuration loaded successfully.
}
