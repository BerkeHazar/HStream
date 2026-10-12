package dev.fredol.open_tv

import android.app.AlertDialog
import android.content.Context
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.KeyEvent
import android.view.LayoutInflater
import android.view.View
import android.widget.FrameLayout
import android.widget.Toast
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.LoadControl
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.util.EventLogger
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.DefaultTimeBar
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import java.util.Locale

// HSTREAM : oynatici kontrolleri onayli mockup'a gore HStream dilinde.
// Degismeyen mantik: reconnect, tolerant load control, TV dpad focus,
// restricted player, HTTP header fabrikasi.  ekleri: favori kalbi,
// hiz diyalogu (yalniz VOD), kalite rozeti, CANLI rozeti + konum,
// bilgi satiri, 4 sn kontrol zaman asimi.
class ExoPlayerView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    params: Map<String, Any?>,
) : PlatformView, MethodChannel.MethodCallHandler {

    private val isLive = params["isLive"] as? Boolean ?: false
    private val url = params["url"] as String
    // : bolum gecisinde oynatilan adres degisir
    private var currentUrl: String = url
    private val startPositionMs = (params["startPositionMs"] as? Number)?.toLong() ?: 0L
    private val title = params["title"] as? String ?: ""
    private val meta = params["meta"] as? String
    private val positionLabel = params["positionLabel"] as? String
    // : oynatici tercihleri (Dart SharedPreferences'tan tasinir)
    // tampon saniye (15-120 arasi), altyazi sp (18/24/30/36), pip izni
    private val tamponSn = (params["tamponSn"] as? Number)?.toInt()
        ?.coerceIn(15, 120) ?: 60
    // : var - dikey paneldeki altyazi cipi "setSubtitleSize" ile degistirir
    // : varsayilan 24 -> 18 (Dart tarafiyla AYNI olmali; Dart her zaman
    // "altyaziSp" gonderir, bu yedek yalnizca parametre gelmezse devreye
    // girer - ama iki tarafin varsayilani ayrismamali).
    private var altyaziSp = (params["altyaziSp"] as? Number)?.toInt() ?: 18
    private val pipAcik = params["pipAcik"] as? Boolean ?: true
    private val debug = (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

    private val methodChannel = MethodChannel(messenger, "dev.fredol.open_tv/exoplayer_$viewId")
    private val handler = Handler(Looper.getMainLooper())

    // : asagidaki init bunlari KULLANIYOR - Kotlin'de ozellik
    // tanim satirindan ONCE kullanilamaz ("must be initialized" hatasi).
    // Bu yuzden BASA tasinmalar ('de sonda tanimliydi - derleme
    // hatasi verdigi tam olarak buydu).
    private val tvMi: Boolean by lazy {
        try {
            (playerView.context.getSystemService(android.content.Context.UI_MODE_SERVICE)
                as? android.app.UiModeManager)?.currentModeType ==
                android.content.res.Configuration.UI_MODE_TYPE_TELEVISION
        } catch (_: Exception) {
            false
        }
    }

    // : ekran kapanınca video arkada calmasin - DURUR (bkz. ekranKapandi)
    private var ekranKapattiDurdurdu = false

    // : PiP EYLEMLERI — resim-icinde-resim penceresindeki play/pause
    // dugmeleri. `player` henuz init'te olusmadigi icin `by lazy`
    // kullanilir (Kotlin ozellik tanim sirasi kurali - yukaridaki tvMi
    // ile ayni gerekce).
    private val pipEylemler: android.content.BroadcastReceiver by lazy {
        object : android.content.BroadcastReceiver() {
            override fun onReceive(ctx: android.content.Context?, intent: android.content.Intent?) {
                when (intent?.action) {
                    ACTION_PIP_OYNAT -> {
                        player.play()
                        guncellePipEylemleri()
                    }
                    ACTION_PIP_DURDUR -> {
                        player.pause()
                        guncellePipEylemleri()
                    }
                    // : PiP penceresinden 10 sn sarim. Normal kontrollerle
                    // ayni mantik: geri sararken 0'in altina inilmez.
                    ACTION_PIP_GERI -> {
                        val hedef = (player.currentPosition - PIP_SARIM_MS).coerceAtLeast(0)
                        player.seekTo(hedef)
                    }
                    ACTION_PIP_ILERI -> {
                        player.seekTo(player.currentPosition + PIP_SARIM_MS)
                    }
                }
            }
        }
    }
    private val ekranKapandi = object : android.content.BroadcastReceiver() {
        override fun onReceive(ctx: android.content.Context?, intent: android.content.Intent?) {
            when (intent?.action) {
                android.content.Intent.ACTION_SCREEN_OFF ->
                    // : yalniz OYNUYORKEN biz durduruyoruz; kullanici
                    // zaten durdurduysa dokunmuyoruz (acilinca da oyle kalsin)
                    if (player.isPlaying) {
                        ekranKapattiDurdurdu = true
                        player.pause()
                    }
                android.content.Intent.ACTION_SCREEN_ON ->
                    // : ekran geri acilinca kaldigi yerden DEVAM
                    // (bunu yalniz biz durdurduysak)
                    if (ekranKapattiDurdurdu) {
                        ekranKapattiDurdurdu = false
                        player.play()
                    }
            }
        }
    }
    private val player: ExoPlayer
    private val playerView: PlayerView
    private val root: FrameLayout

    private var zoomed = false
    private var reconnecting = false
    private var reconnectAttempts = 0
    private var favorite = params["favorite"] as? Boolean ?: false
    // : sonraki bolum var mi (kurucu parametresi metotlarda gorunmez)
    private val hasNext = params["hasNext"] as? Boolean ?: false
    private lateinit var bufferingView: View
    // : doner yalniz kontroller KAPALIYKEN gorunur (pause ile cakismasin)
    private var isBuffering = false
    // : PiP penceresi acikken HStream kontrol/bekleme katmanlari gizlenir —
    // 52dp'lik dugmeler ve 74dp'lik bekleme halkasi kucuk pencereyi
    // kapliyordu. PiP'te kontrol sistemin RemoteAction'lari ile saglanir.
    private var pipIcinde = false
    private var currentSpeed = 1.0f

    companion object {
        var active: ExoPlayerView? = null
        const val DIAG_TAG = "ExoPlayerDiag"
        const val SEEK_INCREMENT_MS = 10_000L
        val RECONNECT_DELAYS_MS = longArrayOf(1_000L, 3_000L, 5_000L)
        const val BUFFER_MIN_MS = 30_000
        const val BUFFER_MAX_MS = 60_000
        const val BUFFER_FOR_PLAYBACK_MS = 10_000
        const val BUFFER_RESUME_AFTER_REBUFFER_MS = 10_000
        const val HTTP_CONNECT_TIMEOUT_MS = 15_000
        const val HTTP_READ_TIMEOUT_MS = 60_000
        // : dikey panel cipiyle (Dart) AYNI liste - iki diyalog birebir olsun
        val PLAYBACK_SPEEDS = floatArrayOf(0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 2.0f, 3.0f)
        // : "daha fazla" menusu ogeleri (hiz, sonraki bolum, uyku, pip)
        const val MENU_HIZ = 0
        const val MENU_SONRAKI = 1
        const val MENU_UYKU = 2
        const val MENU_PIP = 3
        // uyku zamanlayici secenekleri (dakika)
        val UYKU_DAKIKA = intArrayOf(15, 30, 45, 60, 90)
        // : PiP penceresi eylemleri (package'e ozel - cakisma olmaz)
        const val ACTION_PIP_OYNAT = "dev.fredol.open_tv.PIP_OYNAT"
        const val ACTION_PIP_DURDUR = "dev.fredol.open_tv.PIP_DURDUR"
        // : PiP'ten 10 sn sarim (yalniz VOD - canlida anlamsiz)
        const val ACTION_PIP_GERI = "dev.fredol.open_tv.PIP_GERI"
        const val ACTION_PIP_ILERI = "dev.fredol.open_tv.PIP_ILERI"
        const val PIP_REQ_OYNAT = 8801
        const val PIP_REQ_DURDUR = 8802
        const val PIP_REQ_GERI = 8803
        const val PIP_REQ_ILERI = 8804
        // : PiP penceresinde 10 sn sarim miktari (normal kontrollerle AYNI)
        const val PIP_SARIM_MS = 10_000L
    }

    init {
        methodChannel.setMethodCallHandler(this)
        player = ExoPlayer.Builder(context)
            .setMediaSourceFactory(
                DefaultMediaSourceFactory(context)
                    .setDataSourceFactory(createHttpFactory(params))
                    .setLoadErrorHandlingPolicy(DefaultLoadErrorHandlingPolicy(999))
            )
            .setLoadControl(tolerantLoadControl())
            .setSeekBackIncrementMs(SEEK_INCREMENT_MS)
            .setSeekForwardIncrementMs(SEEK_INCREMENT_MS)
            .build()
        root = LayoutInflater.from(context)
            .inflate(R.layout.exo_player_container, null) as FrameLayout
        root.keepScreenOn = true
        playerView = root.findViewById(R.id.player_view)
        // : kontroller 3 sn sonra TOPLOP kaybolur - sure cubugu ve
        // dugmeler tek katmanda ayni anda (XML attribute media3'te yok,
        // AAPT linklemesi patladi; kod tarafindaki setter KESIN calisir)
        playerView.controllerShowTimeoutMs = 3000
        // : solma animasyonu KAPALI - kontrol katmani ANINDA acilip
        // kapanar; tum ogeler ayni anda (1sn/1.5sn kayma algisi biter).
        playerView.setControllerAnimationEnabled(false)
        if (debug) player.addAnalyticsListener(EventLogger(DIAG_TAG))
        attachPlayer()
        bindControls()
        observeForReconnect()
        active = this
        // : TV KUMANDASI - kok odak alir; dpad + medya kisayol
        // tuslari Flutter'a hic gitmeden burada yakalanir. (dispatchDpad
        // buraya kadar HICBIR YERDEN cagrilmiyordu - olmustu.)
        root.isFocusable = true
        root.isFocusableInTouchMode = true
        root.setOnKeyListener { _, keyCode, event -> kumandaTusu(keyCode, event) }
        root.post { if (playerView.isAttachedToWindow) root.requestFocus() }
        // : TV'de tam ekran dugmesi anlamsiz - gizlenir
        if (tvMi) playerView.findViewById<View?>(R.id.hs_fullscreen_button)?.visibility = View.GONE
        // : ekran kapaninca video arkada calmasin - DURUR
        // : ANDROID 14+ RECEIVER HATASI DUZELTMESI —
        // Onceden `context.registerReceiver(receiver, filter)` (2 argumanli,
        // artik kullanilmayan imza) cagriliyordu. Uygulamanin targetSdk'si 36
        // oldugu icin Android 14 (API 34) ve uzeri, sistem disi yayinlar icin
        // kayit sirasinda RECEIVER_EXPORTED / RECEIVER_NOT_EXPORTED bayragini
        // ZORUNLU tutuyor; bayrak verilmeyince SecurityException atiliyor.
        // Bu cagri try/catch icinde oldugu icin hata YUTULUYOR ve receiver
        // HIC KAYIT OLMUYORDU → "ekran kapaninca durdur" ve PiP dugmeleri
        // sessizce calismiyordu. `ContextCompat.registerReceiver` bayragi
        // API 33 oncesi icin kendisi uyarlar (tek dogru yol budur).
        // NOT_EXPORTED: yalnizca sistem ve kendi uygulamamiz yayin gonderebilir
        // — sistem yayinlari (SCREEN_OFF/ON) ve kendi PendingIntent'lerimiz
        // bu kapsamda gelir, yani ikisi de calisir.
        try {
            ContextCompat.registerReceiver(
                playerView.context,
                ekranKapandi,
                android.content.IntentFilter().apply {
                    addAction(android.content.Intent.ACTION_SCREEN_OFF)
                    addAction(android.content.Intent.ACTION_SCREEN_ON)
                },
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
        } catch (e: Exception) {
            Log.e(DIAG_TAG, "screen-off receiver register failed", e)
        }
        // : PiP penceresindeki play/pause dugmeleri (Android 12+; API 26-30
        // istemezse zararsiz).
        try {
            ContextCompat.registerReceiver(
                playerView.context,
                pipEylemler,
                android.content.IntentFilter().apply {
                    addAction(ACTION_PIP_OYNAT)
                    addAction(ACTION_PIP_DURDUR)
                    addAction(ACTION_PIP_GERI)
                    addAction(ACTION_PIP_ILERI)
                },
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
        } catch (e: Exception) {
            Log.e(DIAG_TAG, "pip receiver register failed", e)
        }
        startPlayback()
    }

    private fun createHttpFactory(params: Map<String, Any?>): DefaultHttpDataSource.Factory {
        val headers = HashMap<String, String>()
        (params["referer"] as? String)?.takeIf { it.isNotEmpty() }?.let { headers["Referer"] = it }
        (params["origin"] as? String)?.takeIf { it.isNotEmpty() }?.let { headers["Origin"] = it }
        val userAgent = params["userAgent"] as? String
        return DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(HTTP_CONNECT_TIMEOUT_MS)
            .setReadTimeoutMs(HTTP_READ_TIMEOUT_MS)
            .apply {
                if (headers.isNotEmpty()) setDefaultRequestProperties(headers)
                if (!userAgent.isNullOrEmpty()) setUserAgent(userAgent)
            }
    }

    private fun attachPlayer() {
        playerView.player = restrictedPlayer(player, isLive)
        // : ALTYAZI MENUSU (KOSE SORUNU) DUZELTMESI — media3'un kendi
        // altyazi dugmesi (exo_subtitle) TrackSelectionDialog'u EKRANIN
        // SAG ALT KOSESINE yakin bir yerde aciyordu ve HStream
        // gorunumuyle uyusmuyordu. Kendi dugmemizi baglariz:
        // `setShowSubtitleButton(false)` + `hs_subtitle_button`.
        playerView.setShowSubtitleButton(false)
        playerView.setShowNextButton(false)
        playerView.setShowPreviousButton(false)
        // : kullanici altyazi boyutu secimi (sp) - TV'de varsayilan
        // kocaman kaliyordu; sabit SP boyutu ile olcekten bagimsiz.
        applySubtitleSize()
        // : media3'un varsayilan gostergesi yerine ozel mor halka
        playerView.setShowBuffering(PlayerView.SHOW_BUFFERING_NEVER)
        // : kontroller ~4 sn sonra kaybolur (onayli tasarim)
        playerView.controllerShowTimeoutMs = 4000
        playerView.isFocusable = true
        makeSeekBarGranular()
        bufferingView = root.findViewById(R.id.hs_yukleniyor)
        syncControllerVisibility()
        if (isLive) hideLiveControls()
    }

    // : altyazi boyutu - SubtitleView sabit SP boyutu ile olceklenir.
    // (DEFAULT_TEXT_SIZE_TYPE_SP media3 1.4.1 API'sinde YOK; onun yerine
    // setFixedTextSize(unit, size) kullanilir - TypedValue.COMPLEX_UNIT_SP.)
    private fun applySubtitleSize() {
        try {
            val sv = playerView.subtitleView ?: return
            sv.setFixedTextSize(
                android.util.TypedValue.COMPLEX_UNIT_SP,
                altyaziSp.toFloat(),
            )
        } catch (e: Exception) {
            if (debug) Log.e(DIAG_TAG, "applySubtitleSize failed", e)
        }
    }

    private fun makeSeekBarGranular() {
        val timeBar = playerView.findViewById<View?>(androidx.media3.ui.R.id.exo_progress) as? DefaultTimeBar
        timeBar?.setKeyTimeIncrement(SEEK_INCREMENT_MS)
    }

    private fun syncControllerVisibility() {
        playerView.setControllerVisibilityListener(
            PlayerView.ControllerVisibilityListener { visibility ->
                if (isLive && visibility == View.VISIBLE) hideLiveControls()
                updateBufferingOverlay()
            }
        )
    }

    // : doner tek basina merkeze basmasin; kontroller acikken gizle
    private fun updateBufferingOverlay() {
        if (!::bufferingView.isInitialized) return
        // : PiP penceresinde doner GOSTERILMEZ — 74dp'lik halka kucuk
        // pencerenin neredeyse tamamini kapliyordu. Ayrica PiP'te kontrol
        // katmani zaten kapali oldugu icin "kontroller kapaliyken goster"
        // kosulu her zaman dogru cikip halkayi surekli acik tutuyordu.
        val show = isBuffering && !pipIcinde && !playerView.isControllerFullyVisible
        bufferingView.visibility = if (show) View.VISIBLE else View.GONE
    }

    // : PiP EN-BOY ORANI — gercek video boyutundan hesaplanir; boyut henuz
    // bilinmiyorsa (yayin yeni acildi) 16:9'a dusulur. Android orani
    // [1/2.39, 2.39] araligina zorlar; asiri deger
    // IllegalArgumentException firlatir ve PiP HIC ACILMAZ, bu yuzden
    // sinirlanir. Dondurulmus (portre) videolarda en/boy takas edilir.
    private fun pipOrani(): android.util.Rational {
        val vs = player.videoSize
        var w = vs.width
        var h = vs.height
        if (w <= 0 || h <= 0) return android.util.Rational(16, 9)
        if (vs.unappliedRotationDegrees == 90 || vs.unappliedRotationDegrees == 270) {
            val t = w
            w = h
            h = t
        }
        val oran = w.toFloat() / h.toFloat()
        return when {
            oran < 1f / 2.39f -> android.util.Rational(100, 239)
            oran > 2.39f -> android.util.Rational(239, 100)
            else -> android.util.Rational(w, h)
        }
    }

    private fun bindControls() {
        playerView.findViewById<TextView>(R.id.title_text).text = title
        // : ince bilgi satiri ("2024 - Bilim Kurgu - 2s 46dk")
        val metaText = playerView.findViewById<TextView>(R.id.hs_meta_text)
        if (!meta.isNullOrEmpty()) {
            metaText.text = meta
            metaText.visibility = View.VISIBLE
        } else {
            metaText.visibility = View.GONE
        }
        // : CANLI rozeti
        playerView.findViewById<View>(R.id.hs_canli_badge).visibility =
            if (isLive) View.VISIBLE else View.GONE
        // : favori kalbi (durum Dart'tan gelir, dokununca Dart'a sorulur)
        updateFavoriteIcon()
        playerView.findViewById<View>(R.id.hs_fav_button).setOnClickListener { toggleFavorite() }
        playerView.findViewById<View>(R.id.back_button).setOnClickListener {
            methodChannel.invokeMethod("onBack", null)
        }
        playerView.findViewById<View>(R.id.audio_button).setOnClickListener { showAudioTrackDialog() }
        // : OZEL ALTYAZI DUGMESI — media3'un kendi dugmesi kapatildi
        // (bkz. attachPlayer). Bu dugme ORTALANMIS diyalogu acar.
        playerView.findViewById<View?>(R.id.hs_subtitle_button)?.setOnClickListener {
            showSubtitleDialog()
        }
        playerView.findViewById<View>(R.id.zoom_button).setOnClickListener { toggleZoom() }
        // : tam ekran dugmesi -> Dart yonlendirir, ikon geri gelir
        playerView.findViewById<View>(R.id.hs_fullscreen_button).setOnClickListener {
            methodChannel.invokeMethod("toggleFullscreen", null)
        }
        // : "daha fazla" menusu (hiz/sonraki/uyku/pip buradan acilir)
        playerView.findViewById<View>(R.id.hs_more_button).setOnClickListener { showMoreMenu() }
        // : SONRAKI BOLUM rozeti (yalniz dizi bolumu + sonraki varsa)
        // Durum artik menude tutulur; alt satirda ayri dugme YOK.
        istenenNext = !isLive && hasNext
        // : canli kanal konumu ("4/118")
        val positionText = playerView.findViewById<TextView>(R.id.hs_position_text)
        if (!positionLabel.isNullOrEmpty()) {
            positionText.text = positionLabel
            positionText.visibility = View.VISIBLE
        }

        // : her yerlesim degisiminde YON + DELIK korunur.
        // ('nin inset dinleyicisi platform view icinde hic
        // tetiklenmiyordu - Flutter insetleri tuketiyor; artik dekorun
        // KOK insetlerinden okunuyor, tuketimden bagimsiz.)
        playerView.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            darEkranUygula()
            cutoutKoru()
            cutoutModuUygula()
        }
        darEkranUygula()
        cutoutKoru()
        cutoutModuUygula()
    }

    // : BARIYER KALDIRILDI (kullanici: video FIZIKSEL ekranin
    // ortasinda dursun). Pencere HER YONDE ALWAYS: tam full-bleed, video
    // fiziksel ekrana yayilip ortalanir; delik kenar siyah bantta kalir.
    // ('nin NEVER bariyeri videoyu guvenli alana sikistirip
    // ortalamayi bozuyordu.) Kontrolleri cutoutKoru() delikten korur.
    private fun cutoutModuUygula() {
        if (android.os.Build.VERSION.SDK_INT < 28) return
        val activity = playerView.context as? android.app.Activity ?: return
        val lp = activity.window.attributes
        if (lp.layoutInDisplayCutoutMode !=
            android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
        ) {
            lp.layoutInDisplayCutoutMode =
                android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            activity.window.attributes = lp
        }
    }

    // : kamera deligi korumasi - decor rootWindowInsets uzerinden
    // (setOnApplyWindowInsetsListener platform view'de calismiyordu)
    private fun cutoutKoru() {
        if (android.os.Build.VERSION.SDK_INT < 28) return
        val insets = (playerView.context as? android.app.Activity)
            ?.window?.decorView?.rootWindowInsets ?: return
        val c = insets.displayCutout ?: return
        val dp = playerView.resources.displayMetrics.density.toInt()
        playerView.findViewById<View?>(R.id.top_bar)?.setPadding(
            14 * dp + c.safeInsetLeft, 10 * dp + c.safeInsetTop,
            14 * dp + c.safeInsetRight, 10 * dp)
        playerView.findViewById<View?>(R.id.hs_alt_kutu)?.setPadding(
            14 * dp + c.safeInsetLeft, 0,
            14 * dp + c.safeInsetRight, 10 * dp + c.safeInsetBottom)
    }

    // : rozet isteği (setNextEnabled/ilk kurulumdan) burada uygulanir
    private var istenenNext = false

    // : dikey tespiti CIHAZ YONUNDEN.  gorunum boyutuna
    // bakıyordu; dikey mini playerin gorunum alani GENDIR (video 360x245)
    // ve yatay saniliyordu - kutucuklar bu yuzden hic gizlenmemisti.
    private fun darEkranUygula() {
        // : hiz ve sonraki bolum artik alt satirda DEGIL, "⋯" menusunde.
        // Bu yuzden burada gorunurluk ayarlanmaz (ayarlanirsa olu kod olur:
        // menu ogesi gorunurluk ile kontrol edilemez, icerikle kurulur).
    }

    // : favori kalbi Dart tarafina gider, sonuc geri gelir
    private fun toggleFavorite() {
        methodChannel.invokeMethod("toggleFavorite", null, object : MethodChannel.Result {
            override fun success(result: Any?) {
                favorite = (result as? Boolean) ?: return
                updateFavoriteIcon()
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}

            override fun notImplemented() {}
        })
    }

    // : tam ekran ikonu (girilecekse genisletme, cikilacaksa daraltma)
    private fun updateFullscreenIcon(enter: Boolean) {
        val btn = playerView.findViewById<android.widget.ImageButton>(R.id.hs_fullscreen_button) ?: return
        btn.setImageResource(if (enter) R.drawable.hs_fullscreen else R.drawable.hs_fullscreen_exit)
    }

    private fun updateFavoriteIcon() {
        val favButton = playerView.findViewById<android.widget.ImageButton>(R.id.hs_fav_button) ?: return
        favButton.setImageResource(if (favorite) R.drawable.hs_heart else R.drawable.hs_heart_off)
    }

    // : oynatma hizi diyalogu (VOD)
    private fun showSpeedDialog() {
        val labels = PLAYBACK_SPEEDS.map { formatSpeedLabel(it) }.toTypedArray()
        val checked = PLAYBACK_SPEEDS.indexOfFirst { it == currentSpeed }
        AlertDialog.Builder(playerView.context, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle(R.string.hs_hiz)
            .setSingleChoiceItems(labels, checked) { dialog, which ->
                currentSpeed = PLAYBACK_SPEEDS[which]
                player.playbackParameters = PlaybackParameters(currentSpeed)
                dialog.dismiss()
            }
            .show()
    }

    private fun formatSpeedLabel(speed: Float): String = "${speed}x"

    // : "daha fazla" menusu - satirdan cikarilan islemler burada.
    // Ogeler duruma gore kurulur: hiz (VOD), sonraki bolum (dizi), uyku
    // (VOD), pip (telefon + VOD). Bos kalan basliklar gosterilmez.
    private fun showMoreMenu() {
        val etiketler = ArrayList<String>()
        val kodlar = ArrayList<Int>()
        if (!isLive) {
            etiketler.add(playerView.context.getString(R.string.hs_hiz))
            kodlar.add(MENU_HIZ)
        }
        if (istenenNext && !isLive) {
            etiketler.add(playerView.context.getString(R.string.hs_sonraki_bolum))
            kodlar.add(MENU_SONRAKI)
        }
        if (!isLive) {
            etiketler.add(playerView.context.getString(R.string.hs_uyku))
            kodlar.add(MENU_UYKU)
        }
        if (pipKullanilabilir()) {
            etiketler.add(playerView.context.getString(R.string.hs_pip))
            kodlar.add(MENU_PIP)
        }
        AlertDialog.Builder(playerView.context, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle(R.string.hs_menu_baslik)
            .setItems(etiketler.toTypedArray()) { dialog, which ->
                when (kodlar[which]) {
                    MENU_HIZ -> showSpeedDialog()
                    MENU_SONRAKI -> methodChannel.invokeMethod("nextEpisode", null)
                    MENU_UYKU -> showSleepDialog()
                    MENU_PIP -> enterPip()
                }
                dialog.dismiss()
            }
            .show()
    }

    // : pip yalniz kullanici izin verdiyse + API 26+.
    // : dikey kisiti KALDIRILDI - telefon (dikey panel) de PiP cipi
    // kullanabilsin; Android 12+ dikeyde de PiP'e izin verir.
    // : CANLI KISITI DA KALDIRILDI — onceden `&& !isLive` vardi ve canli
    // yayinda PiP HICBIR SEKILDE acilamiyordu (ne cip ne ⋯ menusu ne de
    // native yol). Android canli video icin de PiP destekler; tek fark
    // sarim eylemlerinin gosterilmemesidir (bkz. pipEylemleri).
    private fun pipKullanilabilir(): Boolean =
        pipAcik &&
            android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O

    // : uyku zamanlayicisi - secenek diyalogu, sure DART tarafinda islenir.
    // Native yalnizca secimi Dart'a iletir (geri sayim + durdurma orada).
    private fun showSleepDialog() {
        val etiketler = UYKU_DAKIKA.map { "$it ${playerView.context.getString(R.string.hs_dakika)}" }.toTypedArray()
        AlertDialog.Builder(playerView.context, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle(R.string.hs_uyku)
            .setItems(etiketler) { dialog, which ->
                methodChannel.invokeMethod("setSleepTimer", UYKU_DAKIKA[which])
                dialog.dismiss()
            }
            .show()
    }

    // : PiP EYLEMLERI — resim-icinde-resim penceresi icin RemoteAction'lar.
    // Onceden `.setActions(...)` YOKTU; PiP penceresinde DURDURMA/BASLATMA
    // dugmesi hic gorunmuyordu (yalnizca sistemin varsayilan "kapat"
    // davranisi vardi). Bu metot:
    //  - VOD'da 10 sn geri / oynat-durdur / 10 sn ileri (en fazla 3 eylem;
    //    Android PiP zaten en fazla 3 destekler),
    //  - CANLIDA yalnizca oynat-durdur (sarim anlamsiz),
    //  - hepsi HStream ikonlarini (media3 degil) kullanir,
    //  - PendingIntent'ler package-scoped broadcast ile receiver'a gider.
    private fun pipEylemleri(): List<android.app.RemoteAction> {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.O) {
            return emptyList()
        }
        val oynuyor = player.isPlaying
        val eylemler = ArrayList<android.app.RemoteAction>(3)

        fun pendingIntent(action: String, req: Int): android.app.PendingIntent {
            val ni = android.content.Intent(action).setPackage(playerView.context.packageName)
            var bayrak = android.app.PendingIntent.FLAG_UPDATE_CURRENT
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                bayrak = bayrak or android.app.PendingIntent.FLAG_IMMUTABLE
            }
            return android.app.PendingIntent.getBroadcast(
                playerView.context,
                req,
                ni,
                bayrak,
            )
        }

        val playIkon = android.graphics.drawable.Icon.createWithResource(
            playerView.context,
            R.drawable.hs_pip_oynat,
        )
        val pauseIkon = android.graphics.drawable.Icon.createWithResource(
            playerView.context,
            R.drawable.hs_pip_durdur,
        )
        // : 10 sn sarim ikonlari — normal kontrollerdeki RAKAMSIZ oklarla
        // ayni (hs_geri_ok / hs_ileri_ok). Rakamlar ikonda degil, eylem
        // aciklamasinda (hs_pip_geri_10 / hs_pip_ileri_10) tasinir.
        val geriIkon = android.graphics.drawable.Icon.createWithResource(
            playerView.context,
            R.drawable.hs_geri_ok,
        )
        val ileriIkon = android.graphics.drawable.Icon.createWithResource(
            playerView.context,
            R.drawable.hs_ileri_ok,
        )

        // : SIRA ONEMLI — Android eylemleri soldan saga bu sirayla dizer,
        // play/pause ORTADA kalsin diye once geri, sonra oynat/durdur,
        // en son ileri eklenir.
        // : Sarim YALNIZ VOD'da. Canli yayinda seek anlamsiz/guvenilmez
        // oldugu icin canlida yalnizca oynat-durdur gosterilir.
        if (!isLive) {
            eylemler.add(
                android.app.RemoteAction(
                    geriIkon,
                    playerView.context.getString(R.string.hs_pip_geri_10),
                    ACTION_PIP_GERI,
                    pendingIntent(ACTION_PIP_GERI, PIP_REQ_GERI),
                )
            )
        }

        if (oynuyor) {
            eylemler.add(
                android.app.RemoteAction(
                    pauseIkon,
                    playerView.context.getString(R.string.hs_durdur),
                    ACTION_PIP_DURDUR,
                    pendingIntent(ACTION_PIP_DURDUR, PIP_REQ_DURDUR),
                )
            )
        } else {
            eylemler.add(
                android.app.RemoteAction(
                    playIkon,
                    playerView.context.getString(R.string.hs_oynat),
                    ACTION_PIP_OYNAT,
                    pendingIntent(ACTION_PIP_OYNAT, PIP_REQ_OYNAT),
                )
            )
        }

        if (!isLive) {
            eylemler.add(
                android.app.RemoteAction(
                    ileriIkon,
                    playerView.context.getString(R.string.hs_pip_ileri_10),
                    ACTION_PIP_ILERI,
                    pendingIntent(ACTION_PIP_ILERI, PIP_REQ_ILERI),
                )
            )
        }
        return eylemler
    }

    // : PiP penceresi gorunurken eylemleri (play/pause ikonu) tazeler.
    private fun guncellePipEylemleri() {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.O) return
        val activity = playerView.context as? android.app.Activity ?: return
        if (!activity.isInPictureInPictureMode) return
        try {
            val params = android.app.PictureInPictureParams.Builder()
                .setAspectRatio(pipOrani())
                .setActions(pipEylemleri())
                .build()
            activity.setPictureInPictureParams(params)
        } catch (e: Exception) {
            if (debug) Log.e(DIAG_TAG, "updatePipActions failed", e)
        }
    }

    // : MainActivity'den PiP durum degisimi gelir.
    // : PiP'TE HSTREAM KONTROL KATMANI KAPATILIR —
    // Onceden burada yalnizca eylemler tazeleniyordu. Sonuc: 52dp'lik
    // geri/oynat/ileri dugmeleri + alt bar, kucuk PiP penceresinin
    // TAMAMINI kapliyordu (duraklatinca kontroller zaten otomatik
    // gorunur oldugu icin ozellikle "durdurunca" barizdi).
    // `useController = false` media3'un kendi kontrol katmanini tamamen
    // kaldirir; PiP'te kontrol zaten sistemin RemoteAction'lari ile
    // saglanir. Cikista geri acilir.
    fun onPipDurumuDegisti(pipIcinde: Boolean) {
        this.pipIcinde = pipIcinde
        playerView.useController = !pipIcinde
        if (pipIcinde) {
            guncellePipEylemleri()
        } else {
            playerView.showController()
        }
        // : bekleme halkasi PiP'te gizli kalir; cikista durum yeniden hesaplanir
        updateBufferingOverlay()
    }

    // : resim icinde resim (API 26+). Desteklenmiyorsa sessizce cikar.
    // : CANLI YAYIN DA DAHIL — onceden `pipKullanilabilir()` canliyi
    // disliyordu ve canli yayinda PiP HICBIR SEKILDE acilamiyordu.
    // Android canli video icin de PiP destekler; tek fark PiP penceresinde
    // 10 sn sarim eylemlerinin gosterilmemesidir (bkz. pipEylemleri).
    private fun enterPip() {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.O) {
            methodChannel.invokeMethod("pipFailed", null)
            return
        }
        val activity = playerView.context as? android.app.Activity ?: run {
            methodChannel.invokeMethod("pipFailed", null)
            return
        }
        try {
            // : Kontrol katmani PENCEREYE GIRMEDEN once kapatilir; boylece
            // PiP acilisinda tek kare bile kaplama gorunmez.
            playerView.useController = false
            // : PiP penceresinde DURDURMA/OYNATMA (+ VOD'da 10 sn sarim)
            // dugmeleri gorunur. Oran gercek videodan hesaplanir.
            val params = android.app.PictureInPictureParams.Builder()
                .setAspectRatio(pipOrani())
                .setActions(pipEylemleri())
                .build()
            if (activity.enterPictureInPictureMode(params)) {
                pipIcinde = true
                updateBufferingOverlay()
            } else {
                // : giris basarisiz olduysa kontrolleri GERI AC.
                pipIcinde = false
                playerView.useController = true
                methodChannel.invokeMethod("pipFailed", null)
            }
        } catch (e: Exception) {
            if (debug) Log.e(DIAG_TAG, "enterPip failed", e)
            pipIcinde = false
            playerView.useController = true
            methodChannel.invokeMethod("pipFailed", null)
        }
    }

    private fun updateQualityText(height: Int) {
        val qualityText = playerView.findViewById<TextView>(R.id.hs_quality_text) ?: return
        if (height > 0) {
            qualityText.text = "${height}p"
            qualityText.visibility = View.VISIBLE
        }
    }

    // : kullanici tampon ayari (saniye) -> ms. Min = secilen surenin
    // yarisi (alt sinir 10sn), max = secilen sure. Boylece "60sn tampon"
    // secen kullanici en az 30sn dolmus tamponla baslar.
    private fun tolerantLoadControl(): LoadControl {
        val maxMs = tamponSn * 1000
        val minMs = (tamponSn * 500).coerceAtLeast(10_000)
        return DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                minMs,
                maxMs,
                BUFFER_FOR_PLAYBACK_MS,
                BUFFER_RESUME_AFTER_REBUFFER_MS,
            )
            .build()
    }

    private fun observeForReconnect() {
        player.addListener(object : Player.Listener {
            override fun onPlayerError(error: PlaybackException) {
                if (debug) Log.e(DIAG_TAG, "onPlayerError code=${error.errorCodeName} cause=${error.cause}", error)
                if (isLive) scheduleReconnect()
            }

            override fun onPlaybackStateChanged(state: Int) {
                if (debug) Log.i(DIAG_TAG, "onPlaybackStateChanged state=${stateName(state)}")
                // : doner yalniz kontroller kapaliyken (pause ile cakisma yok)
                isBuffering = state == Player.STATE_BUFFERING
                updateBufferingOverlay()
                when (state) {
                    Player.STATE_READY -> reconnectAttempts = 0
                    Player.STATE_ENDED -> {
                        if (isLive) {
                            scheduleReconnect()
                        } else {
                            // : bolum/film bitti -> Dart karti gosterir
                            methodChannel.invokeMethod("onEnded", null)
                        }
                    }
                }
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                // : PiP penceresi acikken oynat/durdur ikonunu guncel tutar.
                // Her durum degisiminde tek bir PiP parametre yazimi yapilir.
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    val activity = playerView.context as? android.app.Activity
                    if (activity?.isInPictureInPictureMode == true) {
                        guncellePipEylemleri()
                    }
                }
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                updateQualityText(videoSize.height)
                // : PiP acikken video boyutu ogrenilirse pencere orani
                // gercek olcuye guncellenir (yayin ilk saniyede boyut
                // bildirmemis olabilir; o anda 16:9 varsayilmisti).
                if (pipIcinde) guncellePipEylemleri()
            }
        })
    }

    private fun stateName(state: Int): String = when (state) {
        Player.STATE_IDLE -> "IDLE"
        Player.STATE_BUFFERING -> "BUFFERING"
        Player.STATE_READY -> "READY"
        Player.STATE_ENDED -> "ENDED"
        else -> "UNKNOWN($state)"
    }

    private fun startPlayback() {
        player.setMediaItem(MediaItem.fromUri(Uri.parse(currentUrl)))
        if (!isLive && startPositionMs > 0) player.seekTo(startPositionMs)
        player.playWhenReady = true
        player.prepare()
    }

    private fun restrictedPlayer(delegate: Player, isLive: Boolean): Player {
        val blocked = blockedCommands(isLive)
        return object : ForwardingPlayer(delegate) {
            override fun getAvailableCommands(): Player.Commands {
                val builder = super.getAvailableCommands().buildUpon()
                for (command in blocked) builder.remove(command)
                return builder.build()
            }

            override fun isCommandAvailable(command: Int): Boolean =
                command !in blocked && super.isCommandAvailable(command)
        }
    }

    private fun blockedCommands(isLive: Boolean): IntArray {
        // : hiz artik VOD'da ACIK (hiz rozeti); canlida yasak.
        val blocked = mutableListOf<Int>()
        if (isLive) {
            blocked += listOf(
                Player.COMMAND_SET_SPEED_AND_PITCH,
                Player.COMMAND_PLAY_PAUSE,
                Player.COMMAND_SEEK_BACK,
                Player.COMMAND_SEEK_FORWARD,
                Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM,
                Player.COMMAND_SEEK_TO_PREVIOUS,
                Player.COMMAND_SEEK_TO_NEXT,
                Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM,
                Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,
            )
        }
        return blocked.toIntArray()
    }

    private fun hideLiveControls() {
        intArrayOf(
            androidx.media3.ui.R.id.exo_progress,
            androidx.media3.ui.R.id.exo_time,
            androidx.media3.ui.R.id.exo_play_pause,
            androidx.media3.ui.R.id.exo_rew_with_amount,
            androidx.media3.ui.R.id.exo_ffwd_with_amount,
        ).forEach { id -> playerView.findViewById<View?>(id)?.visibility = View.GONE }
    }

    private fun showAudioTrackDialog() {
        val activePlayer = playerView.player ?: return
        val groups = activePlayer.currentTracks.groups.filter { it.type == C.TRACK_TYPE_AUDIO }
        if (groups.isEmpty()) return

        val labels = mutableListOf("Auto")
        val overrides = mutableListOf<TrackSelectionOverride?>(null)
        for (group in groups) {
            for (i in 0 until group.length) {
                if (!group.isTrackSupported(i)) continue
                val prefix = if (group.isTrackSelected(i)) "✓ " else ""
                labels.add(prefix + audioTrackLabel(group.getTrackFormat(i), overrides.size))
                overrides.add(TrackSelectionOverride(group.mediaTrackGroup, i))
            }
        }

        AlertDialog.Builder(playerView.context, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle(R.string.exo_audio)
            .setItems(labels.toTypedArray()) { dialog, which ->
                val params = activePlayer.trackSelectionParameters.buildUpon()
                    .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
                    .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
                overrides[which]?.let { params.addOverride(it) }
                activePlayer.trackSelectionParameters = params.build()
                dialog.dismiss()
            }
            .show()
    }

    // : ALTYAZI SECIMI — media3'un varsayilan TrackSelectionDialog'u
    // ekranin SAG ALT KOSESINE yaklasik konumda aciliyordu ve HStream
    // temasina uymuyordu. Bu diyalog:
    //  - ORTALANMIS bir pencere (kendi LinearLayout'u, gravity=center),
    //  - "Kapali" secenegi + cihazdaki tum metin (text) parcalari,
    //  - secili parca ✓ ile isaretlenir,
    //  - parca yoksa "Altyazi bulunamadi" bilgisi gosterilir.
    // Boylece altyazi menusu kornerde degil ekranin ortasinda acilir.
    private fun showSubtitleDialog() {
        val activePlayer = playerView.player ?: return
        val gruplar = activePlayer.currentTracks.groups.filter {
            it.type == C.TRACK_TYPE_TEXT
        }

        val satirlar = ArrayList<String>()
        val eylemler = ArrayList<(() -> Unit)?>()
        // 0. satir: KAPALI
        val metinKapaliMi = gruplar.none { g ->
            (0 until g.length).any { g.isTrackSelected(it) }
        }
        satirlar.add(
            (if (metinKapaliMi) "✓ " else "") +
                playerView.context.getString(R.string.hs_altyazi_kapali)
        )
        eylemler.add {
            val p = activePlayer.trackSelectionParameters.buildUpon()
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                .build()
            activePlayer.trackSelectionParameters = p
        }
        for (grup in gruplar) {
            for (i in 0 until grup.length) {
                if (!grup.isTrackSupported(i)) continue
                val secili = grup.isTrackSelected(i)
                val format = grup.getTrackFormat(i)
                satirlar.add(
                    (if (secili) "✓ " else "") + altyaziEtiketi(format, satirlar.size)
                )
                eylemler.add {
                    val p = activePlayer.trackSelectionParameters.buildUpon()
                        .clearOverridesOfType(C.TRACK_TYPE_TEXT)
                        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                        .addOverride(TrackSelectionOverride(grup.mediaTrackGroup, i))
                        .build()
                    activePlayer.trackSelectionParameters = p
                }
            }
        }

        if (gruplar.isEmpty()) {
            // parca yok: kullaniciya bos bir liste gostermek yerine bilgi ver
            AlertDialog.Builder(
                playerView.context,
                android.R.style.Theme_DeviceDefault_Dialog_Alert,
            )
                .setTitle(R.string.hs_altyazi)
                .setMessage(R.string.hs_altyazi_yok)
                .setPositiveButton(android.R.string.ok, null)
                .show()
            return
        }

        AlertDialog.Builder(
            playerView.context,
            android.R.style.Theme_DeviceDefault_Dialog_Alert,
        )
            .setTitle(R.string.hs_altyazi)
            .setItems(satirlar.toTypedArray()) { dialog, which ->
                eylemler.getOrNull(which)?.invoke()
                dialog.dismiss()
            }
            .setOnDismissListener {
                // : kullanici diyalogu kapatinca kontroller hemen
                // kaybolmasin (altyazi secimi ekranda kalsin).
                playerView.showController()
            }
            .show()
    }

    // : DIL ADI — ISO kodu (tr, en, deu, spa, pt-BR ...) okunabilir dile
    // cevrilir. Onceden `Locale(lang).displayLanguage` kullaniliyordu ve
    // bircok kod icin (3 harfli ISO 639-2: "deu", "spa", "tur"; bolge
    // ekli: "pt-BR") BOS donuyordu -> listede yalniz "Altyazi 1" gibi
    // anlamsiz etiketler kaliyordu. Bu fonksiyon ONCE Locale'i 2/3 harf
    // varyantlariyla dener, olmazsa yerlesik bir tabloya duser.
    private fun dilAdi(kod: String?): String {
        if (kod.isNullOrEmpty() || kod == "und") return ""
        val temiz = kod.trim()
        // 1) dogrudan dene
        var ad = dilAdiDene(temiz)
        if (ad.isNotEmpty()) return ad
        // 2) bolge ekini at ("pt-BR" -> "pt"), sonra tekrar dene
        val ana = temiz.split('-', '_').firstOrNull() ?: temiz
        if (ana != temiz) {
            ad = dilAdiDene(ana)
            if (ad.isNotEmpty()) return ad
        }
        // 3) 3 harfli ISO 639-2 -> 2 harfli eslemesi (yaygin diller)
        val iso3 = mapOf(
            "deu" to "de", "ger" to "de",
            "fra" to "fr", "fre" to "fr",
            "spa" to "es",
            "por" to "pt",
            "ita" to "it",
            "rus" to "ru",
            "ara" to "ar",
            "tur" to "tr",
            "nld" to "nl", "dut" to "nl",
            "ell" to "el", "gre" to "el",
            "jpn" to "ja",
            "kor" to "ko",
            "zho" to "zh", "chi" to "zh",
            "hin" to "hi",
            "pol" to "pl",
            "swe" to "sv",
            "ces" to "cs", "cze" to "cs",
            "dan" to "da",
            "fin" to "fi",
            "nor" to "no",
            "ron" to "ro", "rum" to "ro",
            "hun" to "hu",
            "ukr" to "uk",
            "heb" to "he",
            "fas" to "fa", "per" to "fa",
            "urd" to "ur",
            "ben" to "bn",
            "ind" to "id",
            "msa" to "ms",
            "tha" to "th",
            "vie" to "vi",
        )
        iso3[temiz.lowercase()]?.let { kisa ->
            val a = dilAdiDene(kisa)
            if (a.isNotEmpty()) return a
        }
        // 4) hicbiri olmadi: kodu buyuk harfle goster (bos birakmaktan iyi)
        return temiz.uppercase()
    }

    // tek bir kod icin Locale tabanli ceviri denemesi
    private fun dilAdiDene(kod: String): String {
        if (kod.isEmpty()) return ""
        // "en" -> Locale("en");  "pt" -> Locale("pt"); tam kod ise Locale.forLanguageTag
        val adaylar = ArrayList<Locale>(3)
        try {
            adaylar.add(Locale.forLanguageTag(kod))
        } catch (_: Exception) {
        }
        if (kod.length == 2) adaylar.add(Locale(kod))
        if (kod.length == 3) adaylar.add(Locale(kod))
        for (l in adaylar) {
            val d = try {
                l.getDisplayLanguage(l)
            } catch (_: Exception) {
                ""
            }
            if (!d.isNullOrEmpty() && d.lowercase() != kod.lowercase()) return d
        }
        return ""
    }

    // : ALTYAZI ETIKETI — artik HER ZAMAN dil adini da icerir.
    // Onceden `format.label` ("tr" gibi kisa bir kod olabiliyor) varsa
    // DOGRUDAN donduruluyor ve dil adi hic yazilmiyordu; kullanici
    // "sadece ismi yaziyor, dili de yazsin" dedi. Simdi:
    //   - etiket VAR + dil VAR ve etiket dil adini zaten iceriyorsa: etiket
    //   - etiket VAR + dil VAR ama etiket dil adini icermiyorsa: "etiket (Dil)"
    //   - etiket YOK + dil VAR: "Dil"
    //   - hicbiri yok: "Altyazi N"
    private fun altyaziEtiketi(format: Format, fallbackIndex: Int): String {
        val dil = dilAdi(format.language)
        val etiket = format.label?.takeIf { it.isNotEmpty() }
        if (etiket != null) {
            if (dil.isEmpty()) return etiket
            return if (etiket.contains(dil, ignoreCase = true)) {
                etiket
            } else {
                "$etiket ($dil)"
            }
        }
        if (dil.isNotEmpty()) return dil
        return "Altyazı $fallbackIndex"
    }

    // : SES PARCASI ETIKETI — ayni mantik (dil adi her zaman gorunur).
    private fun audioTrackLabel(format: Format, fallbackIndex: Int): String {
        val dil = dilAdi(format.language)
        val etiket = format.label?.takeIf { it.isNotEmpty() }
        if (etiket != null) {
            if (dil.isEmpty()) return etiket
            return if (etiket.contains(dil, ignoreCase = true)) {
                etiket
            } else {
                "$etiket ($dil)"
            }
        }
        if (dil.isNotEmpty()) return dil
        return when (format.channelCount) {
            1 -> "Mono"
            2 -> "Stereo"
            6 -> "5.1"
            8 -> "7.1"
            Format.NO_VALUE -> "Audio $fallbackIndex"
            else -> "${format.channelCount} channels"
        }
    }

    private fun toggleZoom() {
        zoomed = !zoomed
        playerView.resizeMode = if (zoomed) {
            AspectRatioFrameLayout.RESIZE_MODE_ZOOM
        } else {
            AspectRatioFrameLayout.RESIZE_MODE_FIT
        }
    }

    fun dispatchDpad(event: KeyEvent): Boolean {
        val keyCode = event.keyCode
        if (!isNavOrSelect(keyCode)) return false

        if (controlsNeedWaking()) {
            if (event.action == KeyEvent.ACTION_DOWN) wakeControls()
            return true
        }

        val focused = root.findFocus()!!
        if (focused.dispatchKeyEvent(event)) {
            playerView.showController()
            return true
        }
        if (event.action == KeyEvent.ACTION_DOWN && isDirection(keyCode)) {
            moveFocus(focused, keyCode)
        }
        return true
    }

    // : kumanda motoru - medya kisayollari + dpad navigasyonu
    private fun kumandaTusu(keyCode: Int, event: KeyEvent): Boolean {
        if (event.action != KeyEvent.ACTION_DOWN) return false
        when (keyCode) {
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            KeyEvent.KEYCODE_MEDIA_PLAY -> { oynatDuraklat(); return true }
            KeyEvent.KEYCODE_MEDIA_PAUSE -> { player.pause(); return true }
            KeyEvent.KEYCODE_MEDIA_REWIND,
            KeyEvent.KEYCODE_MEDIA_STEP_BACKWARD -> {
                player.seekTo((player.currentPosition - 10_000).coerceAtLeast(0))
                return true
            }
            KeyEvent.KEYCODE_MEDIA_FAST_FORWARD,
            KeyEvent.KEYCODE_MEDIA_STEP_FORWARD -> {
                player.seekTo(player.currentPosition + 10_000)
                return true
            }
        }
        if (!isNavOrSelect(keyCode)) return false
        if (controlsNeedWaking()) {
            wakeControls()
            return true
        }
        val focused = root.findFocus() ?: root
        if (focused !== root && focused.dispatchKeyEvent(event)) {
            playerView.showController()
            return true
        }
        if (focused === root &&
            (keyCode == KeyEvent.KEYCODE_DPAD_CENTER || keyCode == KeyEvent.KEYCODE_ENTER)
        ) {
            if (playerView.isControllerFullyVisible) {
                playerView.hideController()
            } else {
                playerView.showController()
            }
            return true
        }
        if (isDirection(keyCode)) moveFocus(focused, keyCode)
        return true
    }

    private fun oynatDuraklat() {
        if (player.isPlaying) player.pause() else player.play()
    }

    private fun controlsNeedWaking(): Boolean =
        !playerView.isControllerFullyVisible || root.findFocus() == null

    private fun wakeControls() {
        playerView.showController()
        focusDefaultControl()
    }

    private fun moveFocus(from: View, keyCode: Int) {
        val direction = directionFor(keyCode)
        from.focusSearch(direction)?.requestFocus(direction)
        playerView.showController()
    }

    private fun focusDefaultControl() {
        val candidates = listOfNotNull(
            playerView.findViewById<View?>(androidx.media3.ui.R.id.exo_play_pause),
            playerView.findViewById<View?>(R.id.audio_button),
            playerView.findViewById<View?>(R.id.zoom_button),
        )
        candidates.firstOrNull { it.isShown }?.requestFocus()
    }

    private fun isNavOrSelect(keyCode: Int): Boolean =
        isDirection(keyCode) ||
            keyCode == KeyEvent.KEYCODE_DPAD_CENTER ||
            keyCode == KeyEvent.KEYCODE_ENTER ||
            keyCode == KeyEvent.KEYCODE_NUMPAD_ENTER

    private fun isDirection(keyCode: Int): Boolean =
        keyCode == KeyEvent.KEYCODE_DPAD_UP ||
            keyCode == KeyEvent.KEYCODE_DPAD_DOWN ||
            keyCode == KeyEvent.KEYCODE_DPAD_LEFT ||
            keyCode == KeyEvent.KEYCODE_DPAD_RIGHT

    private fun directionFor(keyCode: Int): Int = when (keyCode) {
        KeyEvent.KEYCODE_DPAD_UP -> View.FOCUS_UP
        KeyEvent.KEYCODE_DPAD_DOWN -> View.FOCUS_DOWN
        KeyEvent.KEYCODE_DPAD_LEFT -> View.FOCUS_LEFT
        else -> View.FOCUS_RIGHT
    }

    private fun scheduleReconnect() {
        if (reconnecting) return
        reconnecting = true
        val delay = RECONNECT_DELAYS_MS[reconnectAttempts.coerceAtMost(RECONNECT_DELAYS_MS.lastIndex)]
        if (debug) Log.w(DIAG_TAG, "scheduleReconnect attempt=$reconnectAttempts delayMs=$delay")
        reconnectAttempts++
        handler.postDelayed({
            reconnecting = false
            player.setMediaItem(MediaItem.fromUri(Uri.parse(currentUrl)))
            player.playWhenReady = true
            player.prepare()
        }, delay)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "showToast" -> {
                // : teshis mesaji - yatayda da gorunur
                val msg = call.arguments as? String ?: ""
                if (msg.isNotEmpty()) {
                    Toast.makeText(playerView.context, msg, Toast.LENGTH_LONG).show()
                }
                result.success(null)
            }
            "getPosition" -> result.success(player.currentPosition)
            "pause" -> {
                // : uyku zamanlayicisi dolunca Dart buradan duraklatir
                player.playWhenReady = false
                result.success(null)
            }
            "setSpeed" -> {
                // : dikey paneldeki hiz cipinden gelir - native diyalogla
                // ayni davranis: currentSpeed guncellenir, bolum gecisinde korunur
                val hiz = (call.arguments as? Number)?.toFloat() ?: 1.0f
                currentSpeed = hiz
                player.playbackParameters = PlaybackParameters(currentSpeed)
                result.success(null)
            }
            "setSubtitleSize" -> {
                // : dikey paneldeki altyazi cipinden gelir; aninda uygulanir
                altyaziSp = (call.arguments as? Number)?.toInt() ?: altyaziSp
                applySubtitleSize()
                result.success(null)
            }
            "enterPip" -> {
                // : dikey paneldeki PiP cipi. Desteklenmezse pipFailed yollar.
                enterPip()
                result.success(null)
            }
            "updateFullscreenIcon" -> {
                updateFullscreenIcon(call.arguments as? Boolean ?: true)
                result.success(null)
            }
            "setNextEnabled" -> {
                // : sonraki bolum rozetinin gorunurlugu Dart'tan gelir
                // : istenek kaydedilir; darEkranUygula uygular
                // (dikey mini playerda chip gizli - panel butonu yeterli)
                istenenNext = call.arguments as? Boolean == true
                darEkranUygula()
                result.success(null)
            }
            "loadUrl" -> {
                // : ayni oynaticida yeni bolum yukle (cikis yok)
                val p = call.arguments as? Map<*, *>
                val yeniUrl = p?.get("url") as? String
                if (yeniUrl.isNullOrEmpty()) {
                    result.error("loadUrl", "url bos", null)
                    return
                }
                currentUrl = yeniUrl
                (p["title"] as? String)?.let {
                    playerView.findViewById<TextView>(R.id.title_text).text = it
                }
                val metaText = playerView.findViewById<TextView>(R.id.hs_meta_text)
                val meta = p["meta"] as? String
                if (!meta.isNullOrEmpty()) {
                    metaText.text = meta
                    metaText.visibility = View.VISIBLE
                } else {
                    metaText.visibility = View.GONE
                }
                favorite = p["favorite"] as? Boolean ?: false
                updateFavoriteIcon()
                playerView.findViewById<View?>(R.id.hs_quality_text)?.visibility = View.GONE
                val startMs = (p["startPositionMs"] as? Number)?.toLong() ?: 0L
                player.setMediaItem(MediaItem.fromUri(Uri.parse(currentUrl)))
                if (startMs > 0) player.seekTo(startMs)
                player.playWhenReady = true
                player.prepare()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun getView(): View = root

    override fun dispose() {
        // : oyuncu kapanirken cutout modu sifirlanir (uygulamanin
        // geri kalaninda siyah bar kalmasin)
        if (android.os.Build.VERSION.SDK_INT >= 28) {
            (playerView.context as? android.app.Activity)?.window?.let { w ->
                val lp = w.attributes
                if (lp.layoutInDisplayCutoutMode !=
                    android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                ) {
                    lp.layoutInDisplayCutoutMode =
                        android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                    w.attributes = lp
                }
            }
        }
        try { playerView.context.unregisterReceiver(ekranKapandi) } catch (_: Exception) {}
        // : PiP receiver'i da kayittan dusurulur. Onceden YALNIZ ekranKapandi
        // dusuruluyordu; pipEylemler kayitli kaliyor ve `player` uzerinden bu
        // gorunume referans tutuyordu → oynatici kapansa bile view GC'ye
        // gitmiyordu (bellek sizintisi + olu receiver'a yayin).
        try { playerView.context.unregisterReceiver(pipEylemler) } catch (_: Exception) {}
        if (active === this) active = null
        methodChannel.setMethodCallHandler(null)
        handler.removeCallbacksAndMessages(null)
        playerView.player = null
        player.release()
    }
}
