@echo off
setlocal enableextensions
title HStream - imzalama anahtari
set "HERE=%~dp0"
if "%HERE:~-1%"=="\" set "HERE=%HERE:~0,-1%"
for %%i in ("%HERE%\..") do set "ROOT=%%~fi"
set "KEYDIR=%ROOT%\keys"
set "KS=%KEYDIR%\hstream-release.jks"
set "PROP=%KEYDIR%\key.properties"

set "KEYTOOL=keytool"
if exist "%ROOT%\tools\jdk\bin\keytool.exe" set "KEYTOOL=%ROOT%\tools\jdk\bin\keytool.exe"

where "%KEYTOOL%" >nul 2>&1
if errorlevel 1 (
  if not exist "%KEYTOOL%" (
    echo [hata] keytool bulunamadi.
    echo        setup.bat calistir ^(JDK iner^) veya JDK kur.
    pause & exit /b 1
  )
)

if exist "%KS%" (
  echo [uyari] %KS% zaten var.
  set /p "OVR=Uzerine yazilsin mi? Mevcut anahtar KAYBOLUR. (e/H): "
  if /i not "%OVR%"=="e" (echo Iptal. & pause & exit /b 0)
)

if not exist "%KEYDIR%" mkdir "%KEYDIR%"

set "PASS="
echo Parola kurallari: yalnizca harf, rakam, nokta, tire ve alt cizgi kullan.
echo (^& ^^^! ^< ^> ^| ^%% gibi karakterler komut satirini bozar.)
echo.
set /p "PASS=Imzalama parolasi (bos birak = otomatik uret): "
if "%PASS%"=="" (
  set "PASS=HStream-%RANDOM%-%RANDOM%-%RANDOM%-%RANDOM%"
  echo Otomatik parola uretildi.
)

echo.
echo === HStream imzalama anahtari olusturuluyor (30 yil gecerli) ===
"%KEYTOOL%" -genkeypair ^
  -keystore "%KS%" ^
  -alias hstream ^
  -keyalg RSA -keysize 4096 -validity 10950 ^
  -storepass "%PASS%" -keypass "%PASS%" ^
  -dname "CN=HStream, OU=BerkeHazar, O=HStream, C=TR"
if errorlevel 1 (echo. & echo [hata] keytool basarisiz. & pause & exit /b 1)

:: : storeFile DUZ BOLU ile yazilir. `key.properties` Java .properties
:: formatindadir ve orada ters bolu (\) KACIS karakteridir: tek ters bolu ile
:: yazilan "C:\Users\..." degeri okunurken "C:Users..." olur ve Gradle
:: anahtari bulamaz (validateSigningRelease: Keystore file ... not found).
:: Duz bolu her platformda sorunsuz okunur.
set "KS_DUZ=%KS:\=/%"
> "%PROP%" echo storePassword=%PASS%
>> "%PROP%" echo keyPassword=%PASS%
>> "%PROP%" echo keyAlias=hstream
>> "%PROP%" echo storeFile=%KS_DUZ%
>> "%PROP%" echo storeType=pkcs12

set "OKU=%KEYDIR%\OKUBENI.txt"
> "%OKU%" echo HStream imzalama anahtari - YEDEKLEME TALIMATI
>> "%OKU%" echo ===============================================
>> "%OKU%" echo.
>> "%OKU%" echo Bu klasordeki iki dosya uygulamanin dijital muhru:
>> "%OKU%" echo   hstream-release.jks   -^> muhur
>> "%OKU%" echo   key.properties        -^> muhur + parola
>> "%OKU%" echo.
>> "%OKU%" echo BU KLASORU GITHUB'A YUKLEME. Asla. Kimse gormemeli.
>> "%OKU%" echo.
>> "%OKU%" echo.
>> "%OKU%" echo NEREYE YEDEKLENIR
>> "%OKU%" echo -----------------
>> "%OKU%" echo 1. Parolayi bir PAROLA YONETICISINE kaydet
>> "%OKU%" echo    Bitwarden, 1Password, Keepass gibi.
>> "%OKU%" echo 2. keys klasorunun tamamini ozel bir bulut klasorune kopyala
>> "%OKU%" echo    Google Drive veya OneDrive - PAYLASIMA ACIK OLMASIN.
>> "%OKU%" echo 3. Bir USB bellege de kopyala.
>> "%OKU%" echo 4. Parola ile dosyayi AYRI yerlerde tut.
>> "%OKU%" echo    Biri sizarsa digeri kurtarir.
>> "%OKU%" echo.
>> "%OKU%" echo.
>> "%OKU%" echo KAYBEDERSEN NE OLUR
>> "%OKU%" echo -------------------
>> "%OKU%" echo Uygulamayi bir daha guncelleyemezsin. Kullanicilar yeni
>> "%OKU%" echo surumu eskisinin ustune kuramaz; silip bastan kurmalari
>> "%OKU%" echo gerekir ve tum ayarlari, kaynaklari, gecmisi gider.
>> "%OKU%" echo Geri donusu yok.
>> "%OKU%" echo.
>> "%OKU%" echo.
>> "%OKU%" echo Hicbir sey yapmana gerek yok - bu klasor yerinde durdugu
>> "%OKU%" echo surece derleme anahtari otomatik kullanir.

echo Yedekleme talimati yazildi: %OKU%

echo.
echo ============================================================
echo  ANAHTAR HAZIR
echo ============================================================
echo  Keystore : %KS%
echo  Parola   : %PASS%
echo.
echo  ^>^>^> BU PAROLAYI VE keys\ KLASORUNU KAYBETME!
echo      - Parolayi bir parola yoneticisine kaydet.
echo      - keys\ klasorunu yedekle (bulut, USB...).
echo      - Kaybedersen uygulamayi bir daha guncelleyemezsin:
echo        kullanicilar yeni surumu eskisinin ustune kuramaz.
echo ============================================================
pause
