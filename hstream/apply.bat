@echo off
:: HSTREAM_OVERLAY
:: Applied by setup.bat / build.bat. Failed checks abort the build.
if defined HSTREAM_APPLY_DONE goto :EOF
set "HSTREAM_APPLY_DONE=1"
set "F2K=%ROOT%\hstream"

if not exist "%F2K%\files\flutter\lib\main.dart" (echo [error] hstream\files missing. & pause & exit /b 1)

echo Applying overlay...

if not exist "%APP%\_fred_backup\HAZIR.git" (
  if not exist "%APP%\_fred_backup" mkdir "%APP%\_fred_backup"
  copy /y "%APP%\flutter\lib\main.dart" "%APP%\_fred_backup\" >nul 2>&1
  for %%F in (utils.dart setup.dart settings_view.dart error.dart correction_modal.dart bottom_nav.dart home.dart) do (
    if exist "%APP%\flutter\lib\%%F" copy /y "%APP%\flutter\lib\%%F" "%APP%\_fred_backup\%%F" >nul 2>&1
  )
  copy /y "%APP%\flutter\android\app\src\main\AndroidManifest.xml" "%APP%\_fred_backup\" >nul 2>&1
  copy /y "%APP%\flutter\pubspec.yaml" "%APP%\_fred_backup\" >nul 2>&1
  if exist "%APP%\flutter\lib\models\source_type.dart" copy /y "%APP%\flutter\lib\models\source_type.dart" "%APP%\_fred_backup\source_type.dart" >nul 2>&1
  xcopy /e /y "%APP%\flutter\android\app\src\main\res" "%APP%\_fred_backup\res\" >nul 2>&1
  xcopy /e /y "%APP%\flutter\android\app\src\main\kotlin" "%APP%\_fred_backup\kotlin\" >nul 2>&1
  xcopy /e /y "%APP%\flutter\assets" "%APP%\_fred_backup\assets\" >nul 2>&1
  type nul > "%APP%\_fred_backup\HAZIR.git"
)
if not exist "%APP%\_fred_backup\SQL_RUST.git" (
  if not exist "%APP%\_fred_backup" mkdir "%APP%\_fred_backup"
  copy /y "%APP%\src\sql.rs" "%APP%\_fred_backup\sql.rs" >nul 2>&1
  copy /y "%APP%\src\lib.rs" "%APP%\_fred_backup\lib.rs" >nul 2>&1
  copy /y "%APP%\Cargo.toml" "%APP%\_fred_backup\Cargo.toml" >nul 2>&1
  type nul > "%APP%\_fred_backup\SQL_RUST.git"
)

xcopy /e /y "%F2K%\files\flutter\*" "%APP%\flutter\" >nul || (echo [error] Copy failed. & pause & exit /b 1)
if exist "%APP%\flutter\lib\whats_new_modal.dart" del /q "%APP%\flutter\lib\whats_new_modal.dart"
if exist "%APP%\flutter\lib\tema.dart" del /q "%APP%\flutter\lib\tema.dart"
if exist "%APP%\flutter\lib\bottom_nav.dart" del /q "%APP%\flutter\lib\bottom_nav.dart"
if exist "%APP%\flutter\lib\hstream_rail.dart" del /q "%APP%\flutter\lib\hstream_rail.dart"
if exist "%APP%\flutter\lib\tv_home.dart" del /q "%APP%\flutter\lib\tv_home.dart"
if exist "%F2K%\files\rust\src\sql.rs" (
  copy /y "%F2K%\files\rust\src\sql.rs" "%APP%\src\sql.rs" >nul || (echo [error] sql.rs & pause & exit /b 1)
  copy /y "%F2K%\files\rust\src\lib.rs" "%APP%\src\lib.rs" >nul || (echo [error] lib.rs & pause & exit /b 1)
  copy /y "%F2K%\files\rust\Cargo.toml" "%APP%\Cargo.toml" >nul || (echo [error] Cargo.toml & pause & exit /b 1)
)

echo Verifying overlay...
findstr /c:"clear_history_item" "%APP%\src\sql.rs" >nul || (echo [error] sql.rs & pause & exit /b 1)
findstr /c:"hs_geri10" "%APP%\flutter\android\app\src\main\res\layout\custom_player_control_view.xml" >nul || (echo [error] player XML & pause & exit /b 1)
findstr /c:"updateBufferingOverlay" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt & pause & exit /b 1)
findstr /c:"hamSayi" "%APP%\flutter\lib\home.dart" >nul || (echo [error] home.dart & pause & exit /b 1)
findstr /c:"diziId: widget.home.filters.seriesId" "%APP%\flutter\lib\home.dart" >nul || (echo [error] home.dart & pause & exit /b 1)
findstr /c:"_bolumRozeti" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player.dart & pause & exit /b 1)
findstr /c:"hedefSezon" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player.dart & pause & exit /b 1)
findstr /c:"_yapimKontrol" "%APP%\flutter\lib\hstream_hub.dart" >nul && (echo [error] hstream_hub.dart & pause & exit /b 1)
findstr /c:"Toast.makeText" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt & pause & exit /b 1)
findstr /c:"always" "%APP%\flutter\android\app\src\main\res\values\styles.xml" >nul || (echo [error] styles.xml & pause & exit /b 1)
findstr /c:"1.0.0+1" "%APP%\flutter\pubspec.yaml" >nul || (echo [error] pubspec.yaml & pause & exit /b 1)
  findstr /c:"series_id: row.get" "%APP%\src\sql.rs" >nul || (echo [error] sql.rs & pause & exit /b 1)
  findstr /c:"bolumEkrani" "%APP%\flutter\lib\hstream_card.dart" >nul || (echo [error] hstream_card.dart & pause & exit /b 1)
  findstr /c:"widget.bolumler?.isNotEmpty" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player.dart & pause & exit /b 1)
  findstr /c:"kanal dogar dogmaz" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player.dart & pause & exit /b 1)
  findstr /c:"milliseconds: 2000" "%APP%\flutter\lib\exo_player.dart" >nul && (echo [error] exo_player.dart & pause & exit /b 1)
  findstr /c:"bolumler: widget.home.filters" "%APP%\flutter\lib\home.dart" >nul || (echo [error] home.dart & pause & exit /b 1)
  findstr /c:"darEkranUygula" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt & pause & exit /b 1)
  findstr /c:"safeInsetLeft" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt & pause & exit /b 1)
  findstr /c:"ORIENTATION_PORTRAIT" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt & pause & exit /b 1)
  findstr /c:"rootWindowInsets" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt & pause & exit /b 1)
  findstr /c:"playerView.context.resources" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt & pause & exit /b 1)
  findstr /c:"setControllerAnimationEnabled(false)" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt & pause & exit /b 1)
  findstr /c:"LAYOUT_IN_DISPLAY_CUTOUT_MODE_NEVER" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul && (echo [error] ExoPlayerView.kt & pause & exit /b 1)
  findstr /c:"kumandaTusu" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt & pause & exit /b 1)
  findstr /c:"KEYCODE_MEDIA_REWIND" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt & pause & exit /b 1)
  findstr /c:"KEYCODE_MEDIA_REW," "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul && (echo [error] ExoPlayerView.kt & pause & exit /b 1)
  findstr /c:"ACTION_SCREEN_OFF" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt & pause & exit /b 1)
  findstr /c:"UI_MODE_TYPE_TELEVISION" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt & pause & exit /b 1)
  findstr /c:"hs_circle_cam_odak" "%APP%\flutter\android\app\src\main\res\layout\custom_player_control_view.xml" >nul || (echo [error] player XML & pause & exit /b 1)
  findstr /c:"top: false," "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player.dart & pause & exit /b 1)
  findstr /c:"controllerShowTimeoutMs" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt & pause & exit /b 1)
  findstr /c:"controller_show_timeout_ms" "%APP%\flutter\android\app\src\main\res\layout\exo_player_container.xml" >nul && (echo [error] exo_player_container.xml & pause & exit /b 1)
  findstr /c:"ACTION_SCREEN_ON" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt & pause & exit /b 1)
  findstr /c:"ekranKapattiDurdurdu" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt & pause & exit /b 1)
  findstr /c:"hstream_son_izlenen_goster" "%APP%\flutter\lib\son_izlenen.dart" >nul || (echo [error] son_izlenen.dart & pause & exit /b 1)
  findstr /c:"SonIzlenen.goster" "%APP%\flutter\lib\hstream_hub.dart" >nul || (echo [error] hstream_hub.dart & pause & exit /b 1)
  findstr /c:"_ikiIkiKutular" "%APP%\flutter\lib\hstream_hub.dart" >nul || (echo [error] hstream_hub.dart & pause & exit /b 1)
  findstr /c:"SonIzlenen.ayarla" "%APP%\flutter\lib\settings_view.dart" >nul || (echo [error] settings_view.dart & pause & exit /b 1)
  findstr /c:"SonIzlenen.yukle" "%APP%\flutter\lib\main.dart" >nul || (echo [error] main.dart & pause & exit /b 1)
  findstr /c:"hstream_dil" "%APP%\flutter\lib\l10n.dart" >nul || (echo [error] l10n.dart & pause & exit /b 1)
  findstr /c:"HDil.yukle" "%APP%\flutter\lib\main.dart" >nul || (echo [error] main.dart & pause & exit /b 1)
  findstr /c:"hstream_hub.dart" "%APP%\flutter\lib\main.dart" >nul || (echo [error] main.dart & pause & exit /b 1)
  findstr /c:"themeMode: ThemeMode.dark" "%APP%\flutter\lib\main.dart" >nul || (echo [error] main.dart & pause & exit /b 1)
  findstr /c:"HTema" "%APP%\flutter\lib\main.dart" >nul && (echo [error] main.dart & pause & exit /b 1)
  findstr /c:"darkTheme:" "%APP%\flutter\lib\main.dart" >nul && (echo [error] main.dart & pause & exit /b 1)
  findstr /c:"hKutu" "%APP%\flutter\lib\setup.dart" >nul && (echo [error] setup.dart & pause & exit /b 1)
  findstr /c:"const InputDecoration" "%APP%\flutter\lib\setup.dart" >nul || (echo [error] setup.dart & pause & exit /b 1)
  if exist "%APP%\flutter\lib\tema.dart" (echo [error] tema.dart & pause & exit /b 1)
  if exist "%APP%\flutter\lib\bottom_nav.dart" (echo [error] bottom_nav.dart & pause & exit /b 1)
  if exist "%APP%\flutter\lib\tv_home.dart" (echo [error] tv_home.dart & pause & exit /b 1)
  findstr /c:"_dilSec" "%APP%\flutter\lib\settings_view.dart" >nul || (echo [error] settings_view.dart & pause & exit /b 1)
  findstr /c:"xtreamBilgiCek" "%APP%\flutter\lib\settings_view.dart" >nul || (echo [error] settings_view.dart & pause & exit /b 1)
  findstr /c:"player_api.php" "%APP%\flutter\lib\xtream_bilgi.dart" >nul || (echo [error] xtream_bilgi.dart & pause & exit /b 1)
  findstr /c:"isThreeLine" "%APP%\flutter\lib\settings_view.dart" >nul && (echo [error] settings_view.dart & pause & exit /b 1)
  findstr /c:"xtreamAltYazi" "%APP%\flutter\lib\settings_view.dart" >nul || (echo [error] settings_view.dart & pause & exit /b 1)
  findstr /c:"open_tv/l10n.dart" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player.dart & pause & exit /b 1)
echo Overlay ready.
exit /b 0
