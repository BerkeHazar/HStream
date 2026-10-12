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
  copy /y "%APP%\flutter\android\app\build.gradle" "%APP%\_fred_backup\build.gradle" >nul 2>&1
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
:: : m3u.rs artik overlay'e ait. Temel Fred TV dosyasi BOM'lu ya da
:: girintili m3u listelerini sifir kanal olarak ayristiriyordu; ayrica
:: nitelik icindeki virgulde adi bozuyor ve tum link kaynaklari ayni
:: gecici dosyayi paylasiyordu. Duzeltilmis surum buradan kopyalanir.
::
:: NOT: bu yorumlar BILEREK parantezli blogun DISINDA tutulur. Cmd,
:: `( ... )` blogu icindeki `::` satirlarini etiket gibi ayristirir ve
:: blok kapanirken "Sistem belirtilen surucuyu bulamiyor." hatasi basar
:: (kopyalama yine de calisir; yalnizca gereksiz korkutucu cikti olur).
:: Blok icinde yorum gerekiyorsa `rem` kullanilmalidir.
if exist "%F2K%\files\rust\src\sql.rs" (
  copy /y "%F2K%\files\rust\src\sql.rs" "%APP%\src\sql.rs" >nul || (echo [error] sql.rs & pause & exit /b 1)
  copy /y "%F2K%\files\rust\src\lib.rs" "%APP%\src\lib.rs" >nul || (echo [error] lib.rs & pause & exit /b 1)
  copy /y "%F2K%\files\rust\src\m3u.rs" "%APP%\src\m3u.rs" >nul || (echo [error] m3u.rs & pause & exit /b 1)
  copy /y "%F2K%\files\rust\src\xtream.rs" "%APP%\src\xtream.rs" >nul || (echo [error] xtream.rs & pause & exit /b 1)
  copy /y "%F2K%\files\rust\src\tls.rs" "%APP%\src\tls.rs" >nul || (echo [error] tls.rs & pause & exit /b 1)
  copy /y "%F2K%\files\rust\Cargo.toml" "%APP%\Cargo.toml" >nul || (echo [error] Cargo.toml & pause & exit /b 1)
)

if exist "%ROOT%\keys\key.properties" (
  copy /y "%ROOT%\keys\key.properties" "%APP%\flutter\android\key.properties" >nul
  echo Imzalama anahtari baglandi.
) else (
  echo keys\key.properties yok - release derlemesi debug anahtariyla imzalanacak.
  echo Kendi anahtarin icin: hstream\keystore.bat
)

echo Verifying overlay...
findstr /c:"io.github.berkehazar.hstream" "%APP%\flutter\android\app\build.gradle" >nul || (echo [error] build.gradle & pause & exit /b 1)
findstr /c:"dev.fredol.open_tv" "%APP%\flutter\android\app\build.gradle" >nul || (echo [error] build.gradle namespace & pause & exit /b 1)
findstr /c:"clear_history_item" "%APP%\src\sql.rs" >nul || (echo [error] sql.rs & pause & exit /b 1)
findstr /c:"hs_geri_ok" "%APP%\flutter\android\app\src\main\res\layout\custom_player_control_view.xml" >nul || (echo [error] player XML & pause & exit /b 1)
findstr /c:"updateBufferingOverlay" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt & pause & exit /b 1)
findstr /c:"hamSayi" "%APP%\flutter\lib\home.dart" >nul || (echo [error] home.dart & pause & exit /b 1)
findstr /c:"diziId: widget.home.filters.seriesId" "%APP%\flutter\lib\home.dart" >nul || (echo [error] home.dart & pause & exit /b 1)
findstr /c:"_bolumRozeti" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player.dart & pause & exit /b 1)
findstr /c:"hedefSezon" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player.dart & pause & exit /b 1)
findstr /c:"_yapimKontrol" "%APP%\flutter\lib\hstream_hub.dart" >nul && (echo [error] hstream_hub.dart & pause & exit /b 1)
findstr /c:"Toast.makeText" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt & pause & exit /b 1)
findstr /c:"always" "%APP%\flutter\android\app\src\main\res\values\styles.xml" >nul || (echo [error] styles.xml & pause & exit /b 1)
  :: : SURUM KONTROLU ARTIK SABIT DEGIL. Onceden burada "1.0.0+1"
  :: araniyordu; her surum yukseltmesinde bu satirin elle guncellenmesi
  :: gerekiyordu ve unutulunca derleme anlasilmaz bir hatayla duruyordu.
  :: Artik yalnizca dosyanin HStream'e ait oldugu ve bir surum satiri
  :: tasidigi dogrulanir - surum numarasi serbestce degistirilebilir.
  findstr /c:"name: open_tv" "%APP%\flutter\pubspec.yaml" >nul || (echo [error] pubspec.yaml & pause & exit /b 1)
  findstr /c:"HStream - IPTV player" "%APP%\flutter\pubspec.yaml" >nul || (echo [error] pubspec.yaml aciklama & pause & exit /b 1)
  findstr /b /c:"version: " "%APP%\flutter\pubspec.yaml" >nul || (echo [error] pubspec.yaml surum satiri & pause & exit /b 1)
  findstr /c:"series_id: row.get" "%APP%\src\sql.rs" >nul || (echo [error] sql.rs & pause & exit /b 1)
  findstr /c:"bolumEkrani" "%APP%\flutter\lib\hstream_card.dart" >nul || (echo [error] hstream_card.dart & pause & exit /b 1)
  findstr /c:"widget.bolumler?.isNotEmpty" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player.dart & pause & exit /b 1)
  findstr /c:"kanal dogar dogmaz" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player.dart & pause & exit /b 1)
  findstr /c:"milliseconds: 2000" "%APP%\flutter\lib\exo_player.dart" >nul && (echo [error] exo_player.dart & pause & exit /b 1)
  findstr /c:"bolumler: widget.home.filters" "%APP%\flutter\lib\home.dart" >nul || (echo [error] home.dart & pause & exit /b 1)
  findstr /c:"darEkranUygula" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt & pause & exit /b 1)
  findstr /c:"safeInsetLeft" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt & pause & exit /b 1)
  findstr /c:"rootWindowInsets" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt & pause & exit /b 1)
  findstr /c:"pipAcik" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt pipAcik & pause & exit /b 1)
  findstr /c:"menu ogesi gorunurluk ile kontrol edilemez" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt darEkran & pause & exit /b 1)
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
  findstr /c:"_heroKarusel" "%APP%\flutter\lib\hstream_hub.dart" >nul || (echo [error] hstream_hub.dart & pause & exit /b 1)
  findstr /c:"_Basma" "%APP%\flutter\lib\hstream_hub.dart" >nul || (echo [error] hstream_hub.dart & pause & exit /b 1)
  findstr /c:"class P" "%APP%\flutter\lib\palet.dart" >nul || (echo [error] palet.dart & pause & exit /b 1)
  findstr /c:"hs_brand" "%APP%\flutter\android\app\src\main\res\values\hs_renkler.xml" >nul || (echo [error] hs_renkler.xml & pause & exit /b 1)
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
  findstr /c:"player_preferences.dart" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player.dart player_preferences & pause & exit /b 1)
  findstr /c:"class PlayerPreferences" "%APP%\flutter\lib\player_preferences.dart" >nul || (echo [error] player_preferences.dart & pause & exit /b 1)
  findstr /c:"tamponSecenekler" "%APP%\flutter\lib\player_preferences.dart" >nul || (echo [error] player_preferences.dart tampon & pause & exit /b 1)
  findstr /c:"_tamponSec" "%APP%\flutter\lib\settings_view.dart" >nul || (echo [error] settings_view.dart tampon & pause & exit /b 1)
  findstr /c:"_altyaziBoyutSec" "%APP%\flutter\lib\settings_view.dart" >nul || (echo [error] settings_view.dart altyazi & pause & exit /b 1)
  findstr /c:"hs_more_button" "%APP%\flutter\android\app\src\main\res\layout\custom_player_control_view.xml" >nul || (echo [error] player XML more & pause & exit /b 1)
  findstr /c:"showMoreMenu" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt more & pause & exit /b 1)
  findstr /c:"showSleepDialog" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt uyku & pause & exit /b 1)
  findstr /c:"enterPip" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt pip & pause & exit /b 1)
  findstr /c:"applySubtitleSize" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt altyazi & pause & exit /b 1)
  findstr /c:"hs_speed_button" "%APP%\flutter\android\app\src\main\res\layout\custom_player_control_view.xml" >nul && (echo [error] player XML hiz satirda kalmis & pause & exit /b 1)
  findstr /c:"supportsPictureInPicture" "%APP%\flutter\android\app\src\main\AndroidManifest.xml" >nul || (echo [error] AndroidManifest pip & pause & exit /b 1)
  findstr /c:"_hizliIslemler" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player.dart hizli islemler & pause & exit /b 1)
  findstr /c:"_uykuDialogGoster" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player.dart uyku cipi & pause & exit /b 1)
  findstr /c:"_altyaziDialogGoster" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player.dart altyazi cipi & pause & exit /b 1)
  findstr /c:"_hizDialogGoster" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player.dart hiz cipi & pause & exit /b 1)
  findstr /c:"_pipAc" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player.dart pip cipi & pause & exit /b 1)
  findstr /c:"brandSoft" "%APP%\flutter\lib\palet.dart" >nul || (echo [error] palet.dart brandSoft & pause & exit /b 1)
  findstr /c:"_oynatmaHizi" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player.dart oynatma hizi & pause & exit /b 1)
  findstr /c:"\"setSpeed\"" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt setSpeed & pause & exit /b 1)
  findstr /c:"\"setSubtitleSize\"" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt setSubtitleSize & pause & exit /b 1)
  findstr /c:"\"enterPip\"" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView.kt enterPip metodu & pause & exit /b 1)
  findstr /c:"\"uyku_iptal\"" "%APP%\flutter\lib\l10n.dart" >nul || (echo [error] l10n.dart uyku_iptal & pause & exit /b 1)
  findstr /c:"\"dakika_n\"" "%APP%\flutter\lib\l10n.dart" >nul || (echo [error] l10n.dart dakika_n & pause & exit /b 1)
  findstr /c:"open_tv/xtream_bilgi.dart" "%APP%\flutter\lib\hstream_detail.dart" >nul || (echo [error] hstream_detail import eksik & pause & exit /b 1)
  :: --- /: tespit edilen 5 arayuz hatasinin duzeltmeleri ---
  :: 2) hero karti (kucuk/ortada duran ChannelTile yerine tam genislik kart)
  findstr /c:"_heroKart" "%APP%\flutter\lib\hstream_hub.dart" >nul || (echo [error] hstream_hub hero kart & pause & exit /b 1)
  findstr /c:"_turEtiketi" "%APP%\flutter\lib\hstream_hub.dart" >nul || (echo [error] hstream_hub tur etiketi & pause & exit /b 1)
  findstr /c:"_gecmisAc" "%APP%\flutter\lib\hstream_hub.dart" >nul || (echo [error] hstream_hub gecmis ac & pause & exit /b 1)
  findstr /c:"tur_canli" "%APP%\flutter\lib\l10n.dart" >nul || (echo [error] l10n tur_canli & pause & exit /b 1)
  findstr /c:"cached_network_image" "%APP%\flutter\lib\hstream_hub.dart" >nul || (echo [error] hstream_hub cached_network_image & pause & exit /b 1)
  :: 3) dikey panel kasmasi: geri sayim ValueNotifier ile izole edildi
  findstr /c:"_uykuKalan" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player uyku notifier & pause & exit /b 1)
  findstr /c:"ValueListenableBuilder" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player ValueListenableBuilder & pause & exit /b 1)
  findstr /c:"setState(() => _uykuKalanSn--)" "%APP%\flutter\lib\exo_player.dart" >nul && (echo [error] exo_player saniyelik setState geri gelmis & pause & exit /b 1)
  :: 4) PiP penceresinde durdurma/oynatma dugmeleri
  findstr /c:"setActions" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView PiP setActions & pause & exit /b 1)
  findstr /c:"RemoteAction" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView RemoteAction & pause & exit /b 1)
  findstr /c:"ACTION_PIP_DURDUR" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView pip durdur & pause & exit /b 1)
  findstr /c:"onPipDurumuDegisti" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\MainActivity.kt" >nul || (echo [error] MainActivity pip durumu & pause & exit /b 1)
  :: 5) altyazi menusu: media3 kose diyalogu yerine ozel ortalama
  findstr /c:"showSubtitleDialog" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView altyazi diyalogu & pause & exit /b 1)
  findstr /c:"hs_subtitle_button" "%APP%\flutter\android\app\src\main\res\layout\custom_player_control_view.xml" >nul || (echo [error] player XML altyazi dugmesi & pause & exit /b 1)
  findstr /c:"setShowSubtitleButton(false)" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView varsayilan altyazi dugmesi kapatilmali & pause & exit /b 1)
  findstr /c:"@id/exo_subtitle" "%APP%\flutter\android\app\src\main\res\layout\custom_player_control_view.xml" >nul && (echo [error] player XML media3 altyazi dugmesi geri gelmis & pause & exit /b 1)
  :: 1) launcher ikonu: <inset> ile guvenli alana cekildi
  findstr /c:"android:inset" "%APP%\flutter\android\app\src\main\res\mipmap-anydpi-v26\ic_launcher.xml" >nul || (echo [error] ic_launcher inset & pause & exit /b 1)
  findstr /c:"android:inset" "%APP%\flutter\android\app\src\main\res\mipmap-anydpi-v26\ic_launcher_round.xml" >nul || (echo [error] ic_launcher_round inset & pause & exit /b 1)
  :: --- /: 2. tur arayuz duzeltmeleri ---
  :: A) altyazi ve ses parcalarinda isim + dil birlikte gosterilsin
  findstr /c:"dilAdi" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView dilAdi & pause & exit /b 1)
  findstr /c:"dilAdiDene" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView dilAdiDene & pause & exit /b 1)
  findstr /c:"iso3" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView iso3 tablosu & pause & exit /b 1)
  findstr /c:"altyaziEtiketi" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView altyaziEtiketi & pause & exit /b 1)
  findstr /c:"audioTrackLabel" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView audioTrackLabel & pause & exit /b 1)
  findstr /c:"\"Mono\"" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView kanal sayisi yedegi & pause & exit /b 1)
  :: B) telefon yatay modda ana ekran butonlari sikismasin (LayoutBuilder + olcekli hero)
  findstr /c:"_yatayDuzen" "%APP%\flutter\lib\hstream_hub.dart" >nul || (echo [error] hstream_hub yatay duzen & pause & exit /b 1)
  findstr /c:"c.maxHeight - ustBarY - ara" "%APP%\flutter\lib\hstream_hub.dart" >nul || (echo [error] hstream_hub yatay yukseklik hesabi & pause & exit /b 1)
  findstr /c:"heroY" "%APP%\flutter\lib\hstream_hub.dart" >nul || (echo [error] hstream_hub hero yuksekligi & pause & exit /b 1)
  findstr /c:"final kucuk = h < 132;" "%APP%\flutter\lib\hstream_hub.dart" >nul || (echo [error] hstream_hub kart icerik olcegi & pause & exit /b 1)
  :: C) ana ekran gecis lag'i: bekletmeden yonlendir + haptic onTapUp + onbellekli bolumler
  findstr /c:"_bolumlerCache" "%APP%\flutter\lib\hstream_hub.dart" >nul || (echo [error] hstream_hub bolum onbellegi & pause & exit /b 1)
  findstr /c:"_bolumlerDil" "%APP%\flutter\lib\hstream_hub.dart" >nul || (echo [error] hstream_hub bolum onbellek dili & pause & exit /b 1)
  findstr /c:"ayarGelecek" "%APP%\flutter\lib\hstream_hub.dart" >nul || (echo [error] hstream_hub gecikmesiz yonlendirme & pause & exit /b 1)
  findstr /c:"onTapUp" "%APP%\flutter\lib\hstream_hub.dart" >nul || (echo [error] hstream_hub haptic onTapUp & pause & exit /b 1)
  findstr /c:"onTapDown: (_) => HapticFeedback" "%APP%\flutter\lib\hstream_hub.dart" >nul && (echo [error] hstream_hub haptic onTapDown geri gelmis & pause & exit /b 1)
  findstr /c:"final ayarGelecek = NativeBridge.instance.getSettings();" "%APP%\flutter\lib\hstream_hub.dart" >nul || (echo [error] hstream_hub awaitsiz ayar cagrisi & pause & exit /b 1)
  :: D) dikey moddaki panel kaydirirken kasmasin (RepaintBoundary + ListView + fizik)
  findstr /c:"RepaintBoundary" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player RepaintBoundary & pause & exit /b 1)
  findstr /c:"ClampingScrollPhysics" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player clamping fizik & pause & exit /b 1)
  findstr /c:"_dikeyPanel" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player dikey panel & pause & exit /b 1)
  findstr /c:"const Spacer()" "%APP%\flutter\lib\exo_player.dart" >nul && (echo [error] exo_player dikey panelde Spacer geri gelmis & pause & exit /b 1)
  findstr /c:"RepaintBoundary" "%APP%\flutter\lib\hstream_bolum.dart" >nul || (echo [error] hstream_bolum RepaintBoundary & pause & exit /b 1)
  findstr /c:"boxShadow" "%APP%\flutter\lib\hstream_bolum.dart" >nul && (echo [error] hstream_bolum secili bolum golgesi geri gelmis & pause & exit /b 1)
  :: E) haptic geri bildirimi DENGELI: yalniz 3 nokta (az ama oz)
  findstr /c:"void _titre()" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player titre yardimcisi & pause & exit /b 1)
  findstr /c:"onTapUp: (_) => _titre()" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player bolum atlama haptic & pause & exit /b 1)
  findstr /c:"onTapUp: (_) => HapticFeedback.selectionClick()" "%APP%\flutter\lib\hstream_hub.dart" >nul || (echo [error] hstream_hub ana ekran haptic & pause & exit /b 1)
  :: menulere/vitrin kutularina abartili haptic SERPILMEMELI (geri donus korumasi)
  findstr /c:"HapticFeedback" "%APP%\flutter\lib\settings_view.dart" >nul && (echo [error] settings_view haptic serpilmis & pause & exit /b 1)
  findstr /c:"HapticFeedback" "%APP%\flutter\lib\hstream_bolum.dart" >nul && (echo [error] hstream_bolum haptic serpilmis & pause & exit /b 1)
  findstr /c:"HapticFeedback" "%APP%\flutter\lib\hstream_detail.dart" >nul && (echo [error] hstream_detail haptic serpilmis & pause & exit /b 1)
  :: F) kaynak satirindaki sil/duzenle alani cok dardi -> kompakt aksiyon dugmesi
  findstr /c:"_kaynakAksiyon" "%APP%\flutter\lib\settings_view.dart" >nul || (echo [error] settings_view kaynak aksiyon dugmesi & pause & exit /b 1)
  findstr /c:"width: 36," "%APP%\flutter\lib\settings_view.dart" >nul || (echo [error] settings_view aksiyon boyutu & pause & exit /b 1)
  findstr /c:"contentPadding: const EdgeInsets.only(left: 16, right: 4)" "%APP%\flutter\lib\settings_view.dart" >nul || (echo [error] settings_view kaynak satiri dolgusu & pause & exit /b 1)
  findstr /c:"horizontalTitleGap: 16" "%APP%\flutter\lib\settings_view.dart" >nul || (echo [error] settings_view baslik ikon araligi & pause & exit /b 1)
  :: --- /: 3. tur duzeltmeleri ---
  :: G) PiP durdurma: Android 14+ receiver kaydi (targetSdk 36)
  findstr /c:"ContextCompat.registerReceiver" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView ContextCompat receiver & pause & exit /b 1)
  findstr /c:"ContextCompat.RECEIVER_NOT_EXPORTED" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView RECEIVER_NOT_EXPORTED & pause & exit /b 1)
  findstr /c:"androidx.core.content.ContextCompat" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView ContextCompat import & pause & exit /b 1)
  findstr /c:"unregisterReceiver(pipEylemler)" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView pip receiver temizligi & pause & exit /b 1)
  :: eski 2-argumanli registerReceiver GERI GELMEMELI (sessizce basarisiz oluyor)
  findstr /c:"playerView.context.registerReceiver(" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul && (echo [error] ExoPlayerView eski registerReceiver geri gelmis & pause & exit /b 1)
  :: H) ileri/geri "10" cift etiketi: media3 metni tek kalsin
  findstr /c:"hs_ileri_ok" "%APP%\flutter\android\app\src\main\res\layout\custom_player_control_view.xml" >nul || (echo [error] player XML ileri ok & pause & exit /b 1)
  findstr /c:"hs_geri10" "%APP%\flutter\android\app\src\main\res\layout\custom_player_control_view.xml" >nul && (echo [error] player XML rakamli geri ikonu geri gelmis & pause & exit /b 1)
  findstr /c:"hs_ileri10" "%APP%\flutter\android\app\src\main\res\layout\custom_player_control_view.xml" >nul && (echo [error] player XML rakamli ileri ikonu geri gelmis & pause & exit /b 1)
  findstr /c:"exo_rew_with_amount" "%APP%\flutter\android\app\src\main\res\layout\custom_player_control_view.xml" >nul || (echo [error] player XML rew id korunmali & pause & exit /b 1)
  :: I) altyazi varsayilani 18 (TV + mobil) + tek seferlik goc
  findstr /c:"static const int altyaziVarsayilan = 18;" "%APP%\flutter\lib\player_preferences.dart" >nul || (echo [error] player_preferences altyazi 18 & pause & exit /b 1)
  findstr /c:"_altyaziGocAnahtar" "%APP%\flutter\lib\player_preferences.dart" >nul || (echo [error] player_preferences altyazi gocu & pause & exit /b 1)
  findstr /c:"?: 18" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView altyazi yedek 18 & pause & exit /b 1)
  :: J) bolum "Film/Dizi" degil "Bolum N" yazmali
  findstr /c:"kanal.episodeNum != null" "%APP%\flutter\lib\hstream_hub.dart" >nul || (echo [error] hstream_hub bolum etiketi & pause & exit /b 1)
  :: K) m3u ayristirici duzeltmeleri (overlay'e alindi)
  findstr /c:"gorunen_ad" "%APP%\src\m3u.rs" >nul || (echo [error] m3u.rs tirnak disi virgul & pause & exit /b 1)
  findstr /c:"VOD_UZANTILAR" "%APP%\src\m3u.rs" >nul || (echo [error] m3u.rs medya turu & pause & exit /b 1)
  findstr /c:"read_m3u8_from" "%APP%\src\m3u.rs" >nul || (echo [error] m3u.rs ortak okuma & pause & exit /b 1)
  findstr /c:"trim_start_matches" "%APP%\src\m3u.rs" >nul || (echo [error] m3u.rs BOM toleransi & pause & exit /b 1)
  :: L) ana ekran karti kasma duzeltmeleri
  findstr /c:"onTapUp: (_) => HapticFeedback.selectionClick()" "%APP%\flutter\lib\hstream_card.dart" >nul || (echo [error] hstream_card haptic onTapUp & pause & exit /b 1)
  findstr /c:"onTapDown: (_) => HapticFeedback" "%APP%\flutter\lib\hstream_card.dart" >nul && (echo [error] hstream_card haptic onTapDown geri gelmis & pause & exit /b 1)
  findstr /c:"shadows: [" "%APP%\flutter\lib\hstream_card.dart" >nul && (echo [error] hstream_card metin golgesi geri gelmis & pause & exit /b 1)
  findstr /c:"ODAK KASMASI DUZELTMESI" "%APP%\flutter\lib\hstream_card.dart" >nul || (echo [error] hstream_card odak setState kaldirilmali & pause & exit /b 1)
  :: M) video platform view katman izolasyonu
  findstr /c:"PLATFORM VIEW KATMAN IZOLASYONU" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player platform view izolasyonu & pause & exit /b 1)
  :: N) bos kapak URL'i "kapak yok" sayilmali (canli yayin kasmasinin sebebi)
  findstr /c:"bool get kapakVar" "%APP%\flutter\lib\models\channel.dart" >nul || (echo [error] channel.dart kapakVar & pause & exit /b 1)
  findstr /c:"widget.channel.kapakVar" "%APP%\flutter\lib\hstream_card.dart" >nul || (echo [error] hstream_card kapakVar & pause & exit /b 1)
  findstr /c:"kanal.kapakVar" "%APP%\flutter\lib\hstream_hub.dart" >nul || (echo [error] hstream_hub kapakVar & pause & exit /b 1)
  :: dogrudan `image != null` karsilastirmasi GERI GELMEMELI (bos string tuzagi)
  findstr /c:"channel.image != null" "%APP%\flutter\lib\hstream_card.dart" >nul && (echo [error] hstream_card image != null geri gelmis & pause & exit /b 1)
  findstr /c:"kanal.image != null" "%APP%\flutter\lib\hstream_hub.dart" >nul && (echo [error] hstream_hub image != null geri gelmis & pause & exit /b 1)
  :: --- /: 4. tur duzeltmeleri ---
  :: O) PiP canli yayinda da acilmali (onceden `&& !isLive` vardi)
  findstr /c:"private fun pipKullanilabilir(): Boolean =" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView pipKullanilabilir & pause & exit /b 1)
  findstr /c:"pipAcik &&" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView pipAcik kosulu & pause & exit /b 1)
  findstr /c:"pipAcik && !isLive" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul && (echo [error] ExoPlayerView canli PiP kisiti geri gelmis & pause & exit /b 1)
  findstr /c:"final pipVar = PlayerPreferences.pipAcik;" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player canli PiP cipi & pause & exit /b 1)
  findstr /c:"final pipVar = !_isLive" "%APP%\flutter\lib\exo_player.dart" >nul && (echo [error] exo_player canli PiP cipi geri gelmis & pause & exit /b 1)
  :: P) PiP penceresini HStream katmanlari kaplamamali (kontrol + bekleme halkasi)
  findstr /c:"playerView.useController = !pipIcinde" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView PiP kontrol katmani & pause & exit /b 1)
  findstr /c:"private var pipIcinde = false" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView pipIcinde alani & pause & exit /b 1)
  findstr /c:"isBuffering && !pipIcinde" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView PiP bekleme halkasi & pause & exit /b 1)
  :: Q) PiP'te 10 sn geri/ileri eylemleri (yalniz VOD) + oran gercek videodan
  findstr /c:"ACTION_PIP_GERI" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView PiP geri sarim & pause & exit /b 1)
  findstr /c:"ACTION_PIP_ILERI" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView PiP ileri sarim & pause & exit /b 1)
  findstr /c:"private fun pipOrani()" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul || (echo [error] ExoPlayerView pipOrani & pause & exit /b 1)
  findstr /c:"setAspectRatio(android.util.Rational(16, 9))" "%APP%\flutter\android\app\src\main\kotlin\com\example\open_tv\ExoPlayerView.kt" >nul && (echo [error] ExoPlayerView sabit PiP orani geri gelmis & pause & exit /b 1)
  findstr /c:"hs_pip_geri_10" "%APP%\flutter\android\app\src\main\res\values\strings.xml" >nul || (echo [error] strings.xml PiP geri aciklamasi & pause & exit /b 1)
  findstr /c:"hs_pip_ileri_10" "%APP%\flutter\android\app\src\main\res\values\strings.xml" >nul || (echo [error] strings.xml PiP ileri aciklamasi & pause & exit /b 1)
  findstr /c:"hs_pip_geri_10" "%APP%\flutter\android\app\src\main\res\values-en\strings.xml" >nul || (echo [error] values-en PiP geri aciklamasi & pause & exit /b 1)
  :: R) dizi bolumu Son Izlenenler'de "Film" gorunmemeli (series_id asil sinyal)
  findstr /c:"if (kanal.seriesId != null || kanal.episodeNum != null)" "%APP%\flutter\lib\hstream_hub.dart" >nul || (echo [error] hstream_hub bolum turu & pause & exit /b 1)
  :: S) kalinan dakika rozeti (film/dizi/bolum) + gecmisten acilista dizi kimligi
  findstr /c:"_konumMetni" "%APP%\flutter\lib\hstream_hub.dart" >nul || (echo [error] hstream_hub kalinan dakika & pause & exit /b 1)
  findstr /c:"_rozet(" "%APP%\flutter\lib\hstream_hub.dart" >nul || (echo [error] hstream_hub rozet & pause & exit /b 1)
  findstr /c:"diziId: kanal.seriesId," "%APP%\flutter\lib\hstream_hub.dart" >nul || (echo [error] hstream_hub bolum kimligi tasinmiyor & pause & exit /b 1)
  findstr /c:"Future<void> _konumKaydet()" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player konum kaydi & pause & exit /b 1)
  findstr /c:"_konumSayac" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player konum sayaci & pause & exit /b 1)
  findstr /c:"didChangeAppLifecycleState" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player yasam dongusu konum kaydi & pause & exit /b 1)
  findstr /c:"with WidgetsBindingObserver" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player WidgetsBindingObserver & pause & exit /b 1)
  :: T) cip satiri kaydirma kasmasini onleyen yapi
  findstr /c:"overscroll: false" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player tasma efekti kapatilmali & pause & exit /b 1)
  findstr /c:"cacheExtent: 900" "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player cip satiri onbellek & pause & exit /b 1)
  findstr /c:"height: 44," "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player cip satiri yuksekligi & pause & exit /b 1)
  :: : cip satiri LAZY liste olmali (itemCount: cipler.length). Eski hal
  :: `SingleChildScrollView` + `Row` idi; o yapiya donus `i < cipler.length`
  :: dongusuyle anlasilir. (NOT: `SingleChildScrollView` metni tek basina
  :: ARANMAZ - uyku diyalogunda da kullaniliyor, yanlis alarm verir.)
  findstr /c:"itemCount: cipler.length," "%APP%\flutter\lib\exo_player.dart" >nul || (echo [error] exo_player cip satiri lazy liste degil & pause & exit /b 1)
  findstr /c:"i < cipler.length" "%APP%\flutter\lib\exo_player.dart" >nul && (echo [error] exo_player cip satiri eski Row yapisina donmus & pause & exit /b 1)
  :: --- /: 5. tur (yayinlama hazirligi) ---
  :: U) imzalama: storeType key.properties'ten okunmali (JDK varsayilanina
  :: bagli kalirsa farkli JDK ile derleme sessizce yanlis cozumler)
  findstr /c:"storeType = keystoreProperties" "%APP%\flutter\android\app\build.gradle" >nul || (echo [error] build.gradle storeType & pause & exit /b 1)
  :: : key.properties Java .properties formatidir; ters bolu KACIS karakteridir.
  :: Windows yolu tek ters bolu ile yazilirsa yol bozulur ("C:Users...") ve
  :: Gradle "Keystore file ... not found" diyerek durur. Bu yuzden (a) yol
  :: normalize edilmeli, (b) bulunamazsa proje kokundeki standart konuma
  :: dusulmeli, (c) keystore araclari yolu DUZ BOLU yazmali.
  findstr /c:"releaseStoreFile = file(hamYol.toString().replace" "%APP%\flutter\android\app\build.gradle" >nul || (echo [error] build.gradle storeFile onarimi & pause & exit /b 1)
  findstr /c:"../../../keys/hstream-release.jks" "%APP%\flutter\android\app\build.gradle" >nul || (echo [error] build.gradle standart anahtar yolu & pause & exit /b 1)
  findstr /c:"storeFile = releaseStoreFile" "%APP%\flutter\android\app\build.gradle" >nul || (echo [error] build.gradle storeFile baglantisi & pause & exit /b 1)
  findstr /c:"storeFile = file(keystoreProperties" "%APP%\flutter\android\app\build.gradle" >nul && (echo [error] build.gradle ham storeFile geri gelmis & pause & exit /b 1)
  findstr /c:"KS_DUZ" "%F2K%\keystore.bat" >nul || (echo [error] keystore.bat duz bolu donusumu & pause & exit /b 1)
  findstr /c:"storeFile=${KS//" "%F2K%\keystore.sh" >nul || (echo [error] keystore.sh duz bolu donusumu & pause & exit /b 1)
  findstr /c:"storeType=pkcs12" "%F2K%\keystore.bat" >nul || (echo [error] keystore.bat storeType & pause & exit /b 1)
  findstr /c:"storeType=pkcs12" "%F2K%\keystore.sh" >nul || (echo [error] keystore.sh storeType & pause & exit /b 1)
  :: --- /: 6. tur — Android HTTPS duzeltmesi (m3u/Xtream eklenmiyordu) ---
  :: V) reqwest'in platform sertifika dogrulayicisi Android'de baslatilmadigi
  :: icin panic atiyordu; FFI callback hic cagrilmiyor ve liste eklenmiyordu.
  :: Istemciler artik `crate::tls::client` uzerinden kurulur.
  findstr /c:"mod tls;" "%APP%\src\lib.rs" >nul || (echo [error] lib.rs tls modulu & pause & exit /b 1)
  findstr /c:"use_preconfigured_tls" "%APP%\src\tls.rs" >nul || (echo [error] tls.rs yapilandirmasi & pause & exit /b 1)
  findstr /c:"webpki_roots::TLS_SERVER_ROOTS" "%APP%\src\tls.rs" >nul || (echo [error] tls.rs kok sertifikalar & pause & exit /b 1)
  findstr /c:"crate::tls::client" "%APP%\src\m3u.rs" >nul || (echo [error] m3u.rs tls istemcisi & pause & exit /b 1)
  findstr /c:"crate::tls::client" "%APP%\src\xtream.rs" >nul || (echo [error] xtream.rs tls istemcisi & pause & exit /b 1)
  findstr /c:"webpki-roots" "%APP%\Cargo.toml" >nul || (echo [error] Cargo.toml webpki-roots & pause & exit /b 1)
  :: reqwest istemcisi DOGRUDAN kurulmamali (Android'de panic geri gelir)
  findstr /c:"Client::builder().user_agent" "%APP%\src\m3u.rs" >nul && (echo [error] m3u.rs platform dogrulayici geri gelmis & pause & exit /b 1)
  findstr /c:"Client::builder().user_agent" "%APP%\src\xtream.rs" >nul && (echo [error] xtream.rs platform dogrulayici geri gelmis & pause & exit /b 1)
  :: --- /: 7. tur — Hakkinda ekrani + guncelleme denetimi + yenilikler ---
  :: W) Uygulama ici guncelleme kontrolu GitHub Releases API'sinden yapilir;
  :: yenilikler penceresi surum degisince bir kez gosterilir.
  findstr /c:"class HStreamHakkinda" "%APP%\flutter\lib\hstream_hakkinda.dart" >nul || (echo [error] hakkinda ekrani & pause & exit /b 1)
  findstr /c:"guncellemeDialogGoster" "%APP%\flutter\lib\hstream_hakkinda.dart" >nul || (echo [error] guncelleme diyalogu & pause & exit /b 1)
  findstr /c:"yeniliklerDialogGoster" "%APP%\flutter\lib\hstream_hakkinda.dart" >nul || (echo [error] yenilikler diyalogu & pause & exit /b 1)
  findstr /c:"releases/latest" "%APP%\flutter\lib\hstream_surum.dart" >nul || (echo [error] surum denetimi adresi & pause & exit /b 1)
  findstr /c:"class HSurumNotlari" "%APP%\flutter\lib\hstream_surum_notlari.dart" >nul || (echo [error] gomulu surum notlari & pause & exit /b 1)
  findstr /c:"hstream_gorulen_surum" "%APP%\flutter\lib\hstream_surum.dart" >nul || (echo [error] yenilikler durumu & pause & exit /b 1)
  findstr /c:"HStreamHakkinda" "%APP%\flutter\lib\settings_view.dart" >nul || (echo [error] ayarlarda hakkinda satiri & pause & exit /b 1)
  findstr /c:"_acilisDenetimleri" "%APP%\flutter\lib\main.dart" >nul || (echo [error] acilis denetimleri & pause & exit /b 1)
  findstr /c:"hakkinda_tanitim" "%APP%\flutter\lib\l10n.dart" >nul || (echo [error] l10n hakkinda & pause & exit /b 1)
  findstr /c:"package_info_plus" "%APP%\flutter\lib\hstream_surum.dart" >nul || (echo [error] surum kaynagi package_info & pause & exit /b 1)
echo Overlay ready.
exit /b 0
