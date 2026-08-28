@echo off
setlocal EnableExtensions
title HStream

:: Portable Windows toolchain: Git, JDK 17, Flutter, Android SDK/NDK, Rust.
:: Nothing is installed system-wide. Output: output\HStream.apk

set "FLUTTER_VERSION=3.47.0"
set "NDK_VERSION=29.0.14206865"
set "CMDTOOLS_BUILD=14742923"
set "MINGIT_VERSION=2.47.1"
set "PERL_VERSION=5.32.1.1"
set "APK_ADI=HStream.apk"

set "KAYNAK_ZIP=https://github.com/Fredolx/fred-tv-mobile/archive/refs/heads/main.zip"

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
:: 8.3 short path if the folder name has non-ASCII characters
for %%i in ("%ROOT%") do set "ROOT_KISA=%%~si"
if not "%ROOT_KISA%"=="" if not "%ROOT_KISA%"=="%ROOT%" set "ROOT=%ROOT_KISA%"
set "TOOLS=%ROOT%\tools"
set "DL=%ROOT%\downloads"
set "APP=%ROOT%\app"
set "OUT=%ROOT%\output"

set "JAVA_DIR=%TOOLS%\jdk"
set "FLUTTER_DIR=%TOOLS%\flutter"
set "MGIT=%TOOLS%\git"
set "ANDROID_DIR=%TOOLS%\android-sdk"
set "PERL_DIR=%TOOLS%\perl"
set "RUSTUP_HOME=%TOOLS%\rust\rustup"
set "CARGO_HOME=%TOOLS%\rust\cargo"

:MENU
cls
echo.
echo  HStream
echo  %ROOT%
echo.
echo   [1]  Setup and build
echo   [2]  Build
echo   [3]  Refresh source
echo   [4]  Exit
echo.
set "SEC="
set /p SEC="> "
if "%SEC%"=="1" goto FULL
if "%SEC%"=="2" goto DERLE
if "%SEC%"=="3" goto KAYNAK_YENILE
if "%SEC%"=="4" exit /b 0
goto MENU

:FULL
call :HAZIRLIK || goto HATA
call :GIT_KUR || goto HATA
call :JDK_KUR || goto HATA
call :FLUTTER_KUR || goto HATA
call :ANDROID_KUR || goto HATA
call :RUST_KUR || goto HATA
call :PERL_KUR || goto HATA
call :KAYNAK_INDIR || goto HATA
call :SDK_PAKET || goto HATA
goto DERLE

:HAZIRLIK
echo [setup] Folders
mkdir "%TOOLS%" 2>nul
mkdir "%DL%" 2>nul
mkdir "%OUT%" 2>nul
where curl >nul 2>&1
if errorlevel 1 (
    echo [error] curl not found. Windows 10 1803 or later is required.
    exit /b 1
)
exit /b 0

:INDIR
echo [download] %~nx2
curl -L --progress-bar --retry 3 --retry-delay 2 -o "%~2" "%~1"
if errorlevel 1 exit /b 1
exit /b 0

:GIT_KUR
if exist "%MGIT%\cmd\git.exe" (
    echo [ok] Git
    exit /b 0
)
echo [setup] Git
call :INDIR "https://github.com/git-for-windows/git/releases/download/v%MINGIT_VERSION%.windows.1/MinGit-%MINGIT_VERSION%-64-bit.zip" "%DL%\mingit.zip" || exit /b 1
mkdir "%MGIT%" 2>nul
tar -xf "%DL%\mingit.zip" -C "%MGIT%"
if errorlevel 1 exit /b 1
echo [ok] Git
exit /b 0

:JDK_KUR
if exist "%JAVA_DIR%\bin\java.exe" (
    echo [ok] JDK
    exit /b 0
)
echo [setup] JDK 17
call :INDIR "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse" "%DL%\jdk17.zip" || exit /b 1
tar -xf "%DL%\jdk17.zip" -C "%TOOLS%"
if errorlevel 1 exit /b 1
for /d %%D in ("%TOOLS%\jdk-*") do move "%%D" "%JAVA_DIR%" >nul
if not exist "%JAVA_DIR%\bin\java.exe" (
    echo [error] JDK extract failed.
    exit /b 1
)
echo [ok] JDK
exit /b 0

:FLUTTER_KUR
if exist "%FLUTTER_DIR%\bin\flutter.bat" (
    echo [ok] Flutter
    exit /b 0
)
echo [setup] Flutter %FLUTTER_VERSION%
call :INDIR "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_%FLUTTER_VERSION%-stable.zip" "%DL%\flutter.zip" || exit /b 1
tar -xf "%DL%\flutter.zip" -C "%TOOLS%"
if errorlevel 1 exit /b 1
if not exist "%FLUTTER_DIR%\bin\flutter.bat" (
    echo [error] Flutter extract failed.
    exit /b 1
)
echo [ok] Flutter
exit /b 0

:ANDROID_KUR
if exist "%ANDROID_DIR%\cmdline-tools\latest\bin\sdkmanager.bat" (
    echo [ok] Android cmdline-tools
    exit /b 0
)
echo [setup] Android cmdline-tools
call :INDIR "https://dl.google.com/android/repository/commandlinetools-win-%CMDTOOLS_BUILD%_latest.zip" "%DL%\cmdline-tools.zip" || exit /b 1
mkdir "%ANDROID_DIR%" 2>nul
tar -xf "%DL%\cmdline-tools.zip" -C "%ANDROID_DIR%"
if errorlevel 1 exit /b 1
:: zip extracts "cmdline-tools"; the SDK expects "cmdline-tools\latest"
move "%ANDROID_DIR%\cmdline-tools" "%ANDROID_DIR%\ct-tmp" >nul
mkdir "%ANDROID_DIR%\cmdline-tools"
move "%ANDROID_DIR%\ct-tmp" "%ANDROID_DIR%\cmdline-tools\latest" >nul
echo [setup] platform-tools
call :INDIR "https://dl.google.com/android/repository/platform-tools-latest-windows.zip" "%DL%\platform-tools.zip" || exit /b 1
tar -xf "%DL%\platform-tools.zip" -C "%ANDROID_DIR%"
if errorlevel 1 exit /b 1
echo [ok] Android SDK tools
exit /b 0

:SDK_PAKET
echo [setup] Android SDK / NDK %NDK_VERSION%
echo         This step may take several minutes.
set "JAVA_HOME=%JAVA_DIR%"
set "PATH=%JAVA_DIR%\bin;%PATH%"
if not exist "%DL%\yes.txt" (for /l %%i in (1,1,80) do @echo y) > "%DL%\yes.txt"
call "%ANDROID_DIR%\cmdline-tools\latest\bin\sdkmanager.bat" --sdk_root="%ANDROID_DIR%" --licenses < "%DL%\yes.txt" >nul 2>&1
call "%ANDROID_DIR%\cmdline-tools\latest\bin\sdkmanager.bat" --sdk_root="%ANDROID_DIR%" "platform-tools" "ndk;%NDK_VERSION%" "cmake;3.22.1"
if errorlevel 1 (
    echo [error] SDK packages failed. Check the network connection.
    exit /b 1
)
echo [ok] SDK / NDK
exit /b 0

:RUST_KUR
if exist "%CARGO_HOME%\bin\cargo.exe" if exist "%CARGO_HOME%\bin\cargo-ndk.exe" (
    echo [ok] Rust / cargo-ndk
    exit /b 0
)
if not exist "%CARGO_HOME%\bin\cargo.exe" (
    echo [setup] Rust
    call :INDIR "https://win.rustup.rs/x86_64" "%DL%\rustup-init.exe" || exit /b 1
    set "PATH=%CARGO_HOME%\bin;%PATH%"
    "%DL%\rustup-init.exe" -y --default-host x86_64-pc-windows-gnu --default-toolchain stable --profile minimal --no-modify-path
    if errorlevel 1 (
        echo [error] Rust setup failed.
        exit /b 1
    )
)
set "PATH=%CARGO_HOME%\bin;%PATH%"
echo [setup] Rust Android targets
"%CARGO_HOME%\bin\rustup.exe" target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
if errorlevel 1 exit /b 1
if not exist "%CARGO_HOME%\bin\cargo-ndk.exe" (
    echo [setup] cargo-ndk
    "%CARGO_HOME%\bin\cargo.exe" install cargo-ndk --locked
    if errorlevel 1 (
        echo [error] cargo-ndk install failed.
        exit /b 1
    )
)
echo [ok] Rust / cargo-ndk
exit /b 0

:PERL_KUR
if exist "%PERL_DIR%\perl\bin\perl.exe" (
    echo [ok] Perl
    exit /b 0
)
echo [setup] Perl
call :INDIR "https://strawberryperl.com/download/%PERL_VERSION%/strawberry-perl-%PERL_VERSION%-64bit-portable.zip" "%DL%\perl.zip" || exit /b 1
mkdir "%PERL_DIR%" 2>nul
tar -xf "%DL%\perl.zip" -C "%PERL_DIR%"
if errorlevel 1 exit /b 1
echo [ok] Perl
exit /b 0

:KAYNAK_INDIR
if exist "%APP%\flutter\pubspec.yaml" (
    echo [ok] Source
    exit /b 0
)
:KAYNAK_YENILE
echo [source] Fred TV
if exist "%APP%" rmdir /s /q "%APP%"
call :INDIR "%KAYNAK_ZIP%" "%DL%\fred-tv.zip"
if errorlevel 1 goto KAYNAK_GIT
tar -xf "%DL%\fred-tv.zip" -C "%ROOT%"
if errorlevel 1 goto KAYNAK_GIT
:: zip extracts a single root folder; rename it to app
for /d %%D in ("%ROOT%\fred-tv-mobile-*") do move /y "%%D" "%APP%" >nul 2>&1
if exist "%APP%\flutter\pubspec.yaml" goto KAYNAK_OK
:KAYNAK_GIT
if exist "%APP%" rmdir /s /q "%APP%"
if exist "%ROOT%\fred-tv-mobile-main" rmdir /s /q "%ROOT%\fred-tv-mobile-main"
echo [source] Zip failed, trying git clone
set "GIT_EXE=%MGIT%\cmd\git.exe"
where git >nul 2>&1 && set "GIT_EXE=git"
"%GIT_EXE%" clone --depth 1 https://github.com/Fredolx/fred-tv-mobile.git "%APP%"
if errorlevel 1 (
    echo [error] Could not download source.
    exit /b 1
)
:KAYNAK_OK
if not exist "%APP%\flutter\pubspec.yaml" (
    echo [error] Source extract failed.
    exit /b 1
)
echo [ok] Source
if "%SEC%"=="3" (
    echo Source refreshed. Choose [2] to build.
    pause
    goto MENU
)
exit /b 0

:DERLE
echo.
echo Building...
if not exist "%APP%\flutter\pubspec.yaml" (
    echo [error] No source. Run [1] first.
    pause & goto MENU
)

if exist "%ROOT%\hstream\apply.bat" if not defined HSTREAM_APPLY_DONE (
    call "%ROOT%\hstream\apply.bat"
    if errorlevel 1 (echo [error] Overlay failed. & pause & goto MENU)
)

:: Git's MSYS perl must precede Strawberry Perl so OpenSSL Android
:: builds get Unix-style paths. Do not name this env GIT_DIR.
set "JAVA_HOME=%JAVA_DIR%"
set "ANDROID_HOME=%ANDROID_DIR%"
set "ANDROID_SDK_ROOT=%ANDROID_DIR%"
set "ANDROID_NDK_HOME=%ANDROID_DIR%\ndk\%NDK_VERSION%"
set "PATH=%MGIT%\usr\bin;%MGIT%\cmd;%FLUTTER_DIR%\bin;%JAVA_DIR%\bin;%CARGO_HOME%\bin;%ANDROID_DIR%\cmake\3.22.1\bin;%PERL_DIR%\perl\bin;%PERL_DIR%\c\bin;%ANDROID_DIR%\platform-tools;%PATH%"
if not exist "%MGIT%\usr\bin\perl.exe" (
    echo [warn] MSYS perl not found in Git.
)
set "CMAKE_GENERATOR=Ninja"

echo.
echo [patch] TLS backend
findstr /C:"native-tls-vendored" "%APP%\Cargo.toml" >nul 2>&1
if not errorlevel 1 (
    echo [patch] Switching Cargo TLS backend to rustls
    powershell -NoProfile -Command "(Get-Content '%APP%\Cargo.toml') -replace 'native-tls-vendored','rustls' | Set-Content '%APP%\Cargo.toml'"
    findstr /C:"native-tls-vendored" "%APP%\Cargo.toml" >nul 2>&1 && echo [warn] Patch failed. || echo [ok] Patch
) else (
    echo [ok] TLS backend
)

echo [1/3] cargo ndk
cd /d "%APP%"
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 --platform 24 -o flutter\android\app\src\main\jniLibs build --release
if errorlevel 1 (
    echo [error] Rust build failed.
    pause & goto MENU
)

echo.
echo [2/3] flutter build apk
cd /d "%APP%\flutter"
if exist "%FLUTTER_DIR%\bin\cache\flutter.version.json" del /q "%FLUTTER_DIR%\bin\cache\flutter.version.json"
call flutter pub get
if errorlevel 1 (echo [error] flutter pub get failed. & pause & goto MENU)
call flutter build apk --release
if errorlevel 1 (
    echo [error] Flutter build failed.
    pause & goto MENU
)

echo.
echo [3/3] Copying APK
if not exist "%OUT%" mkdir "%OUT%"
copy /y "%APP%\flutter\build\app\outputs\flutter-apk\app-release.apk" "%OUT%\%APK_ADI%" >nul
if errorlevel 1 (
    echo [error] Could not copy APK.
    pause & goto MENU
)

echo.
echo  APK: %OUT%\%APK_ADI%
pause
goto MENU

:HATA
echo.
echo [error] Setup stopped. Check the message above and retry.
echo         Incomplete downloads resume on the next run.
pause
goto MENU
