#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
; #Warn  ; Enable warnings to assist with detecting common errors.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.
#SingleInstance force
#Persistent
#include <AutoHotInterception>

AHI := new AutoHotInterception()

keyboardId := AHI.GetKeyboardId(0x413C, 0x2003)
AHI.SubscribeKeyboard(keyboardId, true, Func("KeyEvent"))

return


; wrtie marcro keyboard command in this
KeyEvent(code, state){
	if chekStatus(code,state,2){ ;2
		Run chrome.exe "https://www.youtube.com/"
	}
	else if chekStatus(code,state,3){ ;3
		Run chrome.exe
	}
	else if chekStatus(code,state,4){ ;3
		Run msedge.exe
	}
	else if chekStatus(code,state,10){ ; 9
		Run "C:\Program Files\Star Rail\Games\StarRail.exe"
	}
	else if chekStatus(code,state,11){ ;0
		Run "C:\Program Files\Genshin Impact\Genshin Impact game\GenshinImpact.exe"
	}
	else if chekStatus(code,state,16){ ;q
		Run "C:\Users\Reconnecting\AppData\Local\Programs\Microsoft VS Code\Code.exe"
	}
	else if chekStatus(code,state,17){ ; w
		Run msedge.exe "https://www.facebook.com/"
	}
	else if chekStatus(code,state,18){ ;e
		Run "C:\Users\Reconnecting\AppData\Local\Discord\app-1.0.9147\Discord.exe"
	}
	else if chekStatus(code,state,24){ ;c
		Run chrome.exe "https://chatgpt.com/"
	}
	else if chekStatus(code,state,25){ ;p
		Run chrome.exe "https://github.com/"
	}
	else if chekStatus(code,state,26){ ;[
		Run "C:\Users\Reconnecting\AppData\Local\Programs\beekeeper-studio\Beekeeper Studio.exe"
	}
	else if chekStatus(code,state,27){ ;]
		Run "C:\Users\Reconnecting\AppData\Local\Postman\Postman.exe"
	}
	else if chekStatus(code,state,30){
		Run "C:\Program Files\Android\Android Studio\bin\studio64.exe"
	}

}

chekStatus(code,state,key){
return (state) & (code = key)
}


 ; ^ is control
 ; use in all keyboard without marco keyboard
^Esc::
	ExitApp