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
global hwndHdr1 := 0, hwndHdr2 := 0, hwndHdrLine := 0

; Register message listeners
OnMessage(0x0219, "WM_DEVICECHANGE")

; ---------------------------------------------------------
; GUI Creation - Clean Light Theme
; ---------------------------------------------------------
Gui, +AlwaysOnTop -MaximizeBox
Gui, Color, FFFFFF

; === TOP BAR ===
; Use Progress controls to simulate colored button backgrounds
Gui, Add, Progress, x20 y20 w140 h36 Background1a2b7a Disabled
Gui, Font, s10 Bold cFFFFFF, Segoe UI
Gui, Add, Text, x20 y20 w140 h36 gSelectKeyboard vSelectBtn BackgroundTrans Center +0x200, Select Keyboard

Gui, Add, Progress, x170 y20 w110 h36 Background85c1e9 Disabled vBgToggle
Gui, Font, s10 Norm cFFFFFF, Segoe UI
Gui, Add, Text, x170 y20 w110 h36 gToggleMacro vToggleBtn BackgroundTrans Center +0x200, Enable Macro

; Toggle switch area
Gui, Font, s9 c000000, Segoe UI
Gui, Add, GroupBox, x390 y10 w70 h46, Macro
Gui, Add, Checkbox, x400 y30 w50 h20 vMacroToggle gToggleSwitchCheck, off

Gui, Font, s9 c000000, Segoe UI
Gui, Add, Text, x470 y20 w120 vStatusLabel, Macro Status:`nDisabled

; Top separator (Light grey)
Gui, Add, Text, x20 y75 w580 h1 BackgroundEAEAEA,

; === LEFT COLUMN: Configured Macros ===
Gui, Font, s14 Bold c111111, Segoe UI
Gui, Add, Text, x20 y90, Configured Macros
Gui, Font, s10 c333333, Segoe UI
; No headers, flat border
Gui, Add, ListView, x20 y125 w280 h320 vMacroList gOnMacroListEvent -Hdr -E0x200 AltSubmit, Desc|SC
LV_ModifyCol(1, 270)
LV_ModifyCol(2, 0)

; Edit / Delete row buttons
Gui, Font, s9 Norm c333333, Segoe UI
Gui, Add, Button, x20 y455 w90 h28 gOnEditSelected, Edit
Gui, Add, Button, x120 y455 w90 h28 gDeleteKeyMacro, Delete

; Vertical separator (Light grey)
Gui, Add, Text, x320 y90 w1 h390 BackgroundEAEAEA,

; === RIGHT COLUMN: Edit / Add Macro ===
Gui, Font, s14 Bold c111111, Segoe UI
Gui, Add, Text, x340 y90, Edit / Add Macro

Gui, Font, s10 Norm c111111, Segoe UI
Gui, Add, Text, x340 y130, Step 1: Press Key
Gui, Add, Hotkey, x340 y150 w260 h30 vInputKey,

Gui, Add, Text, x340 y195, Step 2: Action
Gui, Add, DropDownList, x340 y215 w260 vActionType, Program||Website|Text

Gui, Add, Text, x340 y260, Step 3: Details
Gui, Add, Edit, x340 y280 w260 h30 vActionData,

Gui, Font, s10 Bold c1a2b7a, Segoe UI
Gui, Add, Text, x340 y330 w130 h36 gSaveKeyMacro Border Center +0x200, + Add to Config
Gui, Font, s10 Norm c111111, Segoe UI
Gui, Add, Text, x480 y330 w80 h36 gClearForm Center +0x200, - Clear

; Save / Load Config (bottom right)
Gui, Font, s10 Norm c1a2b7a, Segoe UI
Gui, Add, Text, x390 y455 w100 h30 gSaveConfigToFile Center +0x200, Save Config
Gui, Add, Text, x500 y455 w100 h30 gLoadConfigFromFile Center +0x200, Load Config

Gui, Show, w620 h510, Macro Keyboard Manager
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
    GuiControl, +Backgrounde74c3c, BgToggle ; Change background to red when enabled
    GuiControl,, ToggleBtn, Disable Macro
    GuiControl,, StatusLabel, Macro Status:`nEnabled
    GuiControl,, MacroToggle, 1
    GuiControl, Text, MacroToggle, on
    AHI.SubscribeKeyboard(macroKeyboardId, true, Func("OnMacroKeyEvent"))
    TrayTip, Macro Enabled, Macro mode is ON., 2
return

DisableMacro:
    isMacroEnabled := false
    AHI.UnsubscribeKeyboard(macroKeyboardId)
    GuiControl, +Background85c1e9, BgToggle ; Restore light blue background
    GuiControl,, ToggleBtn, Enable Macro
    GuiControl,, StatusLabel, Macro Status:`nDisabled
    GuiControl,, MacroToggle, 0
    GuiControl, Text, MacroToggle, off
    TrayTip, Macro Disabled, Macro mode is OFF., 2
return

ToggleSwitchCheck:
    if (isMacroEnabled) {
        GoSub, DisableMacro
    } else {
        GoSub, EnableMacro
    }
return

SelectKeyboard:
    if (isMacroEnabled) {
        MsgBox, 48, Warning, Please disable macro mode first before selecting a new keyboard.
        return
    }
    isSelecting := true
    GuiControl,, StatusLabel, Macro Status:`nSelecting...
    
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
        
        For index, subId in subscribedIds {
            AHI.UnsubscribeKeyboard(subId)
        }
        subscribedIds := []
        
        GuiControl,, StatusLabel, Macro Status:`nReady (ID: %id%)
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
        GuiControl, +Background85c1e9, BgToggle
        GuiControl,, ToggleBtn, Enable Macro
        GuiControl,, StatusLabel, Macro Status:`nDisabled
        GuiControl,, MacroToggle, 0
        GuiControl, Text, MacroToggle, off
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
    GuiControl,, StatusLabel, Macro Status:`nDisabled
    MsgBox, 48, Device Changed, Keyboard plugged/unplugged.`nMacro mode exited.`n`nPlease select your keyboard again.
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
        MsgBox, 48, Warning, Please select a macro row first.
        return
    }
    LV_GetText(scStr, RowNumber, 2)
    macros.Delete(scStr)
    GoSub, RefreshListView
return

OnEditSelected:
    RowNumber := LV_GetNext(0)
    if not RowNumber {
        MsgBox, 48, Warning, Please select a macro row first.
        return
    }
    LV_GetText(scStr, RowNumber, 2)
    if (macros.HasKey(scStr)) {
        GuiControl,, InputKey, % macros[scStr].keyName
        GuiControl,, ActionType, % macros[scStr].type
        GuiControl,, ActionData, % macros[scStr].data
    }
return

OnMacroListEvent:
    if (A_GuiEvent = "DoubleClick") {
        GoSub, OnEditSelected
    }
return

ClearForm:
    GuiControl,, InputKey,
    GuiControl,, ActionType, Program
    GuiControl,, ActionData,
return

RefreshListView:
    LV_Delete()
    For sc, action in macros {
        desc := action.keyName . " -> [" . action.type . "] " . action.data
        LV_Add("", desc, sc)
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
