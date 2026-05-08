#NoEnv
SendMode Input
SetWorkingDir %A_ScriptDir%
#SingleInstance force
#Persistent
#include <AutoHotInterception>

global AHI := new AutoHotInterception()
global macroKeyboardId := 0
global isMacroEnabled := false
global isSelecting := false
global subscribedIds := []
global macros := {} ; Format: macros[scanCode] := {type: "Program", data: "...", keyName: "..."}

; Register device change listener
OnMessage(0x0219, "WM_DEVICECHANGE")

; ---------------------------------------------------------
; GUI Creation
; ---------------------------------------------------------
Gui, +AlwaysOnTop -MaximizeBox
Gui, Font, s10, Segoe UI

; Status section
Gui, Add, GroupBox, x10 y10 w420 h80, Macro Keyboard Status
Gui, Add, Text, x20 y35 w250 vStatusText, Status: Macro Disabled
Gui, Add, Text, x20 y60 w250 vKeyboardText, Keyboard: None Selected

Gui, Add, Button, x280 y30 w130 h40 gToggleMacro vToggleBtn, Enable Macro

; Configuration Section
Gui, Add, GroupBox, x10 y100 w420 h180, Configured Macros (Template)
Gui, Add, ListView, x20 y125 w400 h140 vMacroList gOnMacroListEvent, Scan Code|Key Name|Action Type|Data
LV_ModifyCol(1, 80)
LV_ModifyCol(2, 80)
LV_ModifyCol(3, 80)
LV_ModifyCol(4, 150)

; Edit/Add Section
Gui, Add, GroupBox, x10 y290 w420 h160, Edit / Add Macro
Gui, Add, Text, x20 y320, Press Key:
Gui, Add, Hotkey, x95 y315 w100 vInputKey, 

Gui, Add, Text, x20 y355, Action Type:
Gui, Add, DropDownList, x95 y350 w100 vActionType, Program||Website|Text

Gui, Add, Text, x20 y390, Action Data:
Gui, Add, Edit, x95 y385 w315 vActionData

Gui, Add, Button, x95 y415 w100 h30 gSaveKeyMacro, Save Key
Gui, Add, Button, x205 y415 w100 h30 gDeleteKeyMacro, Delete Key

; Bottom Controls
Gui, Add, Button, x10 y465 w120 h40 gSelectKeyboard vSelectBtn, Select Keyboard
Gui, Add, Button, x160 y465 w120 h40 gSaveConfigToFile, Save Config
Gui, Add, Button, x310 y465 w120 h40 gLoadConfigFromFile, Load Config

Gui, Show, w440 h515, Macro Keyboard Manager
return

GuiClose:
ExitApp

; ---------------------------------------------------------
; Application Logic
; ---------------------------------------------------------

ToggleMacro:
    if (!isMacroEnabled) {
        GoSub, EnableMacro
    } else {
        GoSub, DisableMacro
    }
return

EnableMacro:
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
    GuiControl,, StatusText, Status: Macro Enabled
    GuiControl,, ToggleBtn, Disable Macro
    AHI.SubscribeKeyboard(macroKeyboardId, true, Func("OnMacroKeyEvent"))
    TrayTip, Macro Enabled, Macro mode is ON., 2
return

DisableMacro:
    isMacroEnabled := false
    AHI.UnsubscribeKeyboard(macroKeyboardId)
    GuiControl,, StatusText, Status: Macro Disabled
    GuiControl,, ToggleBtn, Enable Macro
    TrayTip, Macro Disabled, Macro mode is OFF., 2
return

SelectKeyboard:
    if (isMacroEnabled) {
        MsgBox, 48, Warning, Please disable macro mode first before selecting a new keyboard.
        return
    }
    isSelecting := true
    GuiControl,, KeyboardText, Keyboard: Press Any Key on Target...
    
    ; Subscribe to all keyboards temporarily to catch which one is pressed
    DeviceList := AHI.GetDeviceList()
    Loop 10 {
        if (IsObject(DeviceList[A_Index])) {
            AHI.SubscribeKeyboard(A_Index, false, Func("OnSelectionEvent").Bind(A_Index))
            subscribedIds.Push(A_Index)
        }
    }
return

OnSelectionEvent(id, code, state) {
    if (isSelecting && state = 1) {
        isSelecting := false
        macroKeyboardId := id
        
        ; Unsubscribe from all keyboards used for selection
        For index, subId in subscribedIds {
            AHI.UnsubscribeKeyboard(subId)
        }
        subscribedIds := []
        
        GuiControl,, KeyboardText, Keyboard: Selected ID %id%
        MsgBox, 64, Success, Keyboard ID %id% selected as macro keyboard.
    }
}

OnMacroKeyEvent(code, state) {
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
    if (isMacroEnabled) {
        isMacroEnabled := false
        GuiControl,, StatusText, Status: Macro Disabled
        GuiControl,, ToggleBtn, Enable Macro
        if (macroKeyboardId != 0) {
            AHI.UnsubscribeKeyboard(macroKeyboardId)
        }
    }
    if (isSelecting) {
        isSelecting := false
        For index, subId in subscribedIds {
            AHI.UnsubscribeKeyboard(subId)
        }
        subscribedIds := []
    }
    
    macroKeyboardId := 0
    GuiControl,, KeyboardText, Keyboard: None Selected
    
    ; Alert user that a device change happened
    MsgBox, 48, Device Changed, Keyboard connection changed (plugged/unplugged).`nExiting macro mode.`n`nPlease select your macro keyboard again.
return

; ---------------------------------------------------------
; GUI Event Handlers
; ---------------------------------------------------------

SaveKeyMacro:
    Gui, Submit, NoHide
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
        MsgBox, 16, Error, Invalid key selected. Could not determine scan code.
        return
    }
    
    macros[scanCode] := {type: ActionType, data: ActionData, keyName: InputKey}
    GoSub, RefreshListView
    
    ; Clear inputs for next entry
    GuiControl,, InputKey, 
    GuiControl,, ActionData, 
return

DeleteKeyMacro:
    RowNumber := LV_GetNext(0)
    if not RowNumber {
        MsgBox, 48, Warning, Please select a macro from the list to delete.
        return
    }
    LV_GetText(scStr, RowNumber, 1)
    macros.Delete(scStr)
    GoSub, RefreshListView
return

OnMacroListEvent:
    if (A_GuiEvent = "DoubleClick") {
        RowNumber := LV_GetNext(0)
        if not RowNumber
            return
        LV_GetText(scStr, RowNumber, 1)
        if (macros.HasKey(scStr)) {
            GuiControl,, InputKey, % macros[scStr].keyName
            GuiControl,, ActionType, % macros[scStr].type
            GuiControl,, ActionData, % macros[scStr].data
        }
    }
return

RefreshListView:
    LV_Delete()
    For sc, action in macros {
        LV_Add("", sc, action.keyName, action.type, action.data)
    }
return

SaveConfigToFile:
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
return

LoadConfigFromFile:
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
    GoSub, RefreshListView
    MsgBox, 64, Success, Configuration loaded successfully.
return
