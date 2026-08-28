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
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
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

    private var ekranKapattiDurdurdu = false
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
        val PLAYBACK_SPEEDS = floatArrayOf(0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 2.0f)
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
        playerView.context.registerReceiver(
            ekranKapandi,
            android.content.IntentFilter().apply {
                addAction(android.content.Intent.ACTION_SCREEN_OFF)
                addAction(android.content.Intent.ACTION_SCREEN_ON)
            },
        )
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
        playerView.setShowSubtitleButton(true)
        playerView.setShowNextButton(false)
        playerView.setShowPreviousButton(false)
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
        val show = isBuffering && !playerView.isControllerFullyVisible
        bufferingView.visibility = if (show) View.VISIBLE else View.GONE
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
        playerView.findViewById<View>(R.id.zoom_button).setOnClickListener { toggleZoom() }
        // : tam ekran dugmesi -> Dart yonlendirir, ikon geri gelir
        playerView.findViewById<View>(R.id.hs_fullscreen_button).setOnClickListener {
            methodChannel.invokeMethod("toggleFullscreen", null)
        }
        // : SONRAKI BOLUM rozeti (yalniz dizi bolumu + sonraki varsa)
        val nextButton = playerView.findViewById<View>(R.id.hs_next_button)
        istenenNext = !isLive && hasNext
        nextButton.setOnClickListener { methodChannel.invokeMethod("nextEpisode", null) }
        // : hiz rozeti (yalniz film/dizi)
        val speedButton = playerView.findViewById<TextView>(R.id.hs_speed_button)
        if (!isLive) {
            speedButton.setOnClickListener { showSpeedDialog() }
            updateSpeedChip()
        }
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
        val dikey = playerView.context.resources.configuration.orientation ==
            android.content.res.Configuration.ORIENTATION_PORTRAIT
        val nextButton = playerView.findViewById<View?>(R.id.hs_next_button)
        nextButton?.visibility =
            if (!dikey && istenenNext && !isLive) View.VISIBLE else View.GONE
        val speedButton = playerView.findViewById<TextView?>(R.id.hs_speed_button)
        speedButton?.visibility = if (dikey || isLive) View.GONE else View.VISIBLE
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
                updateSpeedChip()
                dialog.dismiss()
            }
            .show()
    }

    private fun formatSpeedLabel(speed: Float): String = "${speed}x"

    private fun updateSpeedChip() {
        val speedButton = playerView.findViewById<TextView>(R.id.hs_speed_button) ?: return
        speedButton.text = formatSpeedLabel(currentSpeed)
        speedButton.setBackgroundResource(
            if (currentSpeed != 1.0f) R.drawable.hs_chip_mor else R.drawable.hs_chip
        )
    }

    private fun updateQualityText(height: Int) {
        val qualityText = playerView.findViewById<TextView>(R.id.hs_quality_text) ?: return
        if (height > 0) {
            qualityText.text = "${height}p"
            qualityText.visibility = View.VISIBLE
        }
    }

    private fun tolerantLoadControl(): LoadControl =
        DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                BUFFER_MIN_MS,
                BUFFER_MAX_MS,
                BUFFER_FOR_PLAYBACK_MS,
                BUFFER_RESUME_AFTER_REBUFFER_MS,
            )
            .build()

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

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                updateQualityText(videoSize.height)
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
            R.id.hs_speed_button,
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

    private fun audioTrackLabel(format: Format, fallbackIndex: Int): String {
        format.label?.let { return it }
        val lang = format.language
        if (!lang.isNullOrEmpty() && lang != "und") {
            val display = Locale(lang).displayLanguage
            return if (display.isNotEmpty()) display else lang
        }
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
        if (active === this) active = null
        methodChannel.setMethodCallHandler(null)
        handler.removeCallbacksAndMessages(null)
        playerView.player = null
        player.release()
    }
}
