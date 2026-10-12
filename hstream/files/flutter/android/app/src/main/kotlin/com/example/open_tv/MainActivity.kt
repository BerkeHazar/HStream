package dev.fredol.open_tv

import android.content.res.Configuration
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

// HSTREAM : Flutter kok aktivitesi. Overlay'in bir parcasi.
//  - exoplayer platform view fabrikasi burada kaydedilir
//  - TV kumandasi tuslari oynaticiya yonlendirilir
//  - PiP (resim icinde resim) durum degisimi oynaticiya bildirilir:
//    pencereye girince play/pause eylemleri tazelenir, cikinca
//    tam ekran kontroller geri gelir.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "dev.fredol.open_tv/exoplayer",
            ExoPlayerViewFactory(flutterEngine.dartExecutor.binaryMessenger),
        )
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (ExoPlayerView.active?.dispatchDpad(event) == true) {
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    // : PiP penceresine girince/çıkınca oynatıcıya haber ver.
    // `active` null olabilir (oynatıcı kapanmış) - guvenli kontrol.
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        ExoPlayerView.active?.onPipDurumuDegisti(isInPictureInPictureMode)
    }
}
