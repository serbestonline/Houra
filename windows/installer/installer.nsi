; Houra'nın kendi kurulum penceresi: çerçevesiz, koyu, tek pencere (açılış → kuruluyor → hazır).
; Pencere yalnız bir görsel gösterir (scripts/installer-art.js çizer); tıklanacak yerler aşağıda aynı ölçülerle durur.
; Asıl kurulumu, içine gömülü electron-builder kurulumu sessiz kipte yapar. O kurulum dosyaları önce kendi geçici
; klasörüne açar, sonra kurulum klasörüne kopyalar; ilerleme bu iki klasörün dolmasından ölçülür.
; Derleme: node scripts/make-installer.js (OUT, CORE, ART, ICON, TOTAL_KB tanımlarını o verir).

Unicode true
ManifestDPIAware true
RequestExecutionLevel user
SetCompressor lzma
Name "Houra"
Caption "Houra"
BrandingText " "
OutFile "${OUT}"
Icon "${ICON}"

!include LogicLib.nsh
!include nsDialogs.nsh
!include WinMessages.nsh
!include FileFunc.nsh

!define APP_DIR "$LOCALAPPDATA\Programs\Houra"
; Görseldeki ölçüler (yüzde 100 ölçekte nokta)
!define WIDTH 560
!define HEIGHT 360

Var Dialog
Var Image
Var Bitmap
Var Fill
Var Percent
Var Font
Var Lang      ; tr | en
Var Scale     ; 100 | 125 | 150 | 200
Var State     ; welcome | installing | done
Var Process
Var SawEmpty  ; üzerine kurulumda eski dosyalar silinene kadar kurulum klasörü sayılmaz
Var Unpack    ; içteki kurulumun dosyaları açtığı geçici klasör
Var Shown     ; gösterilen yüzde; geri gitmez
Var Ticks     ; kurulum başlayalı geçen zaman (200 ms'lik adım)

Page custom Show

Section
SectionEnd

; $0 noktayı ekran ölçeğine çevirir
!macro Scaled value result
  IntOp ${result} ${value} * $Scale
  IntOp ${result} ${result} / 100
!macroend

Function Show
  InitPluginsDir
  SetOutPath $PLUGINSDIR
  File "${ART}/*.bmp"

  StrCpy $Lang en
  System::Call 'kernel32::GetUserDefaultUILanguage() i .r0'
  IntOp $0 $0 & 0x3FF
  ${If} $0 = 0x1F
    StrCpy $Lang tr
  ${EndIf}

  StrCpy $0 96
  System::Call 'user32::GetDpiForSystem() i .r0'
  ${If} $0 < 108
    StrCpy $Scale 100
  ${ElseIf} $0 < 132
    StrCpy $Scale 125
  ${ElseIf} $0 < 168
    StrCpy $Scale 150
  ${Else}
    StrCpy $Scale 200
  ${EndIf}
  !insertmacro Scaled ${WIDTH} $R0
  !insertmacro Scaled ${HEIGHT} $R1

  nsDialogs::Create 1018
  Pop $Dialog

  ; Çerçeveyi ve kurulum aracının kendi düğmelerini kaldır, pencereyi görselin boyuna getirip ekrana ortala
  System::Call 'user32::SetWindowLong(p $HWNDPARENT, i -16, i 0x920A0000)'
  System::Call 'user32::GetSystemMetrics(i 0) i .r2'
  System::Call 'user32::GetSystemMetrics(i 1) i .r3'
  IntOp $2 $2 - $R0
  IntOp $2 $2 / 2
  IntOp $3 $3 - $R1
  IntOp $3 $3 / 2
  System::Call 'user32::SetWindowPos(p $HWNDPARENT, p 0, i r2, i r3, i R0, i R1, i 0x24)'
  System::Call 'dwmapi::DwmSetWindowAttribute(p $HWNDPARENT, i 33, *i 2, i 4)'   ; Windows 11: yuvarlak köşe
  StrCpy $1 0
  ${Do}
    FindWindow $1 "" "" $HWNDPARENT $1
    ${If} $1 = 0
      ${Break}
    ${EndIf}
    ShowWindow $1 ${SW_HIDE}
  ${Loop}
  ShowWindow $Dialog ${SW_SHOW}
  System::Call 'user32::SetWindowPos(p $Dialog, p 0, i 0, i 0, i R0, i R1, i 0x4)'

  ${NSD_CreateBitmap} 0 0 100% 100% ""
  Pop $Image
  ${NSD_AddStyle} $Image 0x04000100   ; tıklamayı bildir; üstündeki ilerleme çizgisinin üzerine boyama
  ${NSD_OnClick} $Image OnClick

  ; İlerleme çizgisi ve yüzde: görselin üstünde duran iki düz renkli alan
  ${NSD_CreateLabel} 0 0 0 0 ""
  Pop $Fill
  SetCtlColors $Fill "" 0xF5F5F5
  ${NSD_CreateLabel} 0 0 0 0 ""
  Pop $Percent
  ${NSD_AddStyle} $Percent 0x2
  SetCtlColors $Percent 0x8C8C8D 0x181819
  CreateFont $Font "Segoe UI" 9 400
  SendMessage $Percent ${WM_SETFONT} $Font 1
  ShowWindow $Fill ${SW_HIDE}
  ShowWindow $Percent ${SW_HIDE}

  StrCpy $State welcome
  Call SetArt
  nsDialogs::Show
  ${NSD_FreeImage} $Bitmap
FunctionEnd

Function SetArt
  ${If} $Bitmap != ""
    ${NSD_FreeImage} $Bitmap
  ${EndIf}
  ${NSD_SetImage} $Image "$PLUGINSDIR\$Lang-$State-$Scale.bmp" $Bitmap
FunctionEnd

; $R9 = yüzde (0–100)
Function SetProgress
  !insertmacro Scaled 40 $R2
  !insertmacro Scaled 313 $R3
  IntOp $R4 480 * $R9
  IntOp $R4 $R4 / 100
  !insertmacro Scaled $R4 $R4
  !insertmacro Scaled 3 $R5
  System::Call 'user32::SetWindowPos(p $Fill, p 0, i R2, i R3, i R4, i R5, i 0x40)'
  !insertmacro Scaled 440 $R2
  !insertmacro Scaled 283 $R3
  !insertmacro Scaled 80 $R4
  !insertmacro Scaled 20 $R5
  System::Call 'user32::SetWindowPos(p $Percent, p 0, i R2, i R3, i R4, i R5, i 0x40)'
  ${If} $Lang == tr
    ${NSD_SetText} $Percent "%$R9"
  ${Else}
    ${NSD_SetText} $Percent "$R9%"
  ${EndIf}
FunctionEnd

Function OnClick
  Pop $0
  System::Call '*(i, i) p .r1'
  System::Call 'user32::GetCursorPos(p r1)'
  System::Call 'user32::ScreenToClient(p $Dialog, p r1)'
  System::Call '*$1(i .r2, i .r3)'
  System::Free $1
  IntOp $2 $2 * 100
  IntOp $2 $2 / $Scale
  IntOp $3 $3 * 100
  IntOp $3 $3 / $Scale
  ${If} $State != installing
    ${If} $2 >= 510
    ${AndIf} $3 <= 48
      SendMessage $HWNDPARENT ${WM_CLOSE} 0 0
      Return
    ${EndIf}
    ${If} $2 >= 170
    ${AndIf} $2 <= 390
    ${AndIf} $3 >= 264
    ${AndIf} $3 <= 304
      ${If} $State == welcome
        Call Install
      ${Else}
        Exec '"${APP_DIR}\Houra.exe"'
        SendMessage $HWNDPARENT ${WM_CLOSE} 0 0
      ${EndIf}
      Return
    ${EndIf}
  ${EndIf}
  ; Boş yerinden tutulunca pencere sürüklenir
  System::Call 'user32::ReleaseCapture()'
  SendMessage $HWNDPARENT ${WM_NCLBUTTONDOWN} 2 0
FunctionEnd

Function Install
  StrCpy $State installing
  Call SetArt
  StrCpy $R9 0
  Call SetProgress
  System::Call 'user32::UpdateWindow(p $HWNDPARENT)'

  SetOutPath $PLUGINSDIR
  SetCompress off   ; içteki kurulum zaten sıkıştırılmış
  File "/oname=core.exe" "${CORE}"
  SetCompress auto

  ; Sessiz kurulumu başlat ve bitişini izleyebilmek için süreç tutamacını al (SHELLEXECUTEINFO, fMask = SEE_MASK_NOCLOSEPROCESS)
  System::Call '*(i 60, i 0x40, p $HWNDPARENT, t "open", t "$PLUGINSDIR\core.exe", t "/S", p 0, i 1, p 0, p 0, p 0, p 0, i 0, p 0, p 0) p .r0'
  System::Call 'shell32::ShellExecuteExW(p r0) i .r1'
  System::Call '*$0(i, i, p, p, p, p, p, i, p, p, p, p, i, p, p .r2)'
  System::Free $0
  StrCpy $Process $2
  ${If} $1 = 0
  ${OrIf} $Process = 0
    Call Failed
    Return
  ${EndIf}
  StrCpy $SawEmpty 0
  StrCpy $Unpack ""
  StrCpy $Shown 0
  StrCpy $Ticks 0
  ${NSD_CreateTimer} Tick 200
FunctionEnd

Function Tick
  ; İçteki kurulumun geçici klasörünü bul (TEMP altında, içinde 7z-out olan ns*.tmp)
  ${If} $Unpack == ""
    FindFirst $4 $5 "$TEMP\ns*.tmp"
    ${DoWhile} $5 != ""
      ${If} ${FileExists} "$TEMP\$5\7z-out\*.*"
        StrCpy $Unpack "$TEMP\$5\7z-out"
      ${EndIf}
      FindNext $4 $5
    ${Loop}
    FindClose $4
  ${EndIf}
  StrCpy $6 0
  ${If} $Unpack != ""
    ${GetSize} "$Unpack" "/S=0K" $6 $1 $2
  ${EndIf}
  ${GetSize} "${APP_DIR}" "/S=0K" $7 $1 $2
  ClearErrors
  IntOp $8 ${TOTAL_KB} / 5
  ${If} $7 < $8
    StrCpy $SawEmpty 1
  ${EndIf}
  ${If} $SawEmpty = 0
    StrCpy $7 0
  ${EndIf}
  ; İlk yüzde 12 hazırlıktır (eski sürümün kaldırılması, dosyanın açılmaya başlaması): ölçülecek bir şey olmadığı için
  ; çizgi saniyede bir puan ilerler. Kalanı iki aşamadır (açma, kopyalama) ve eşit sayılır.
  IntOp $Ticks $Ticks + 1
  IntOp $9 $Ticks / 5
  ${If} $9 > 12
    StrCpy $9 12
  ${EndIf}
  IntOp $R9 $6 + $7
  IntOp $R9 $R9 * 43
  IntOp $R9 $R9 / ${TOTAL_KB}
  ${If} $R9 > 0
    IntOp $R9 $R9 + 12
  ${Else}
    StrCpy $R9 $9
  ${EndIf}
  ${If} $R9 > 97
    StrCpy $R9 97
  ${EndIf}
  ${If} $R9 < $Shown
    StrCpy $R9 $Shown
  ${EndIf}
  StrCpy $Shown $R9
  Call SetProgress

  System::Call 'kernel32::WaitForSingleObject(p $Process, i 0) i .r3'
  ${If} $3 = 0
    ${NSD_KillTimer} Tick
    System::Call 'kernel32::CloseHandle(p $Process)'
    ShowWindow $Fill ${SW_HIDE}
    ShowWindow $Percent ${SW_HIDE}
    ${IfNot} ${FileExists} "${APP_DIR}\Houra.exe"
      Call Failed
      Return
    ${EndIf}
    StrCpy $State done
    Call SetArt
  ${EndIf}
FunctionEnd

Function Failed
  StrCpy $State failed
  ${If} $Lang == tr
    MessageBox MB_ICONSTOP "Houra kurulamadı. Kurulum dosyasını yeniden indirip tekrar dene."
  ${Else}
    MessageBox MB_ICONSTOP "Houra could not be installed. Download the installer again and retry."
  ${EndIf}
  SendMessage $HWNDPARENT ${WM_CLOSE} 0 0
FunctionEnd

; Kurulum sürerken pencere kapatılamaz
Function .onUserAbort
  ${If} $State == installing
    Abort
  ${EndIf}
FunctionEnd
