# HStream

Android ve Android TV için IPTV oynatıcısı.

Xtream Codes, M3U bağlantısı veya yerel M3U listesi ile canlı yayın, film ve dizi izlenir. Telefon, tablet ve kumandalı televizyon aynı arayüzü paylaşır.

## Özellikler

- Canlı TV, filmler, diziler ve favoriler — tek hub
- Üç kaynak türü: Xtream, M3U bağlantısı, yerel M3U
- Oynatıcı: bölüm geçişi, kumanda, ekran girintisi, tam ekran
- Beş dil: Türkçe, English, Español, Deutsch, Français
- Ayarlar: NSFW gizleme, Son İzlenenler
- Xtream kaynaklarında kullanıcı adı ve bitiş tarihi

## Derleme

HStream, [Fred TV](https://github.com/Fredolx/fred-tv-mobile) kaynak ağacının üzerine bir overlay uygular. Overlay `hstream/files` içindedir.

### Windows (taşınabilir ortam)

`app` klasörünün bulunduğu kökte:

```bat
hstream\build.bat
```

Açılan menüde **[2]** (derle), bitince **[4]** (çıkış). APK: `output\HStream.apk`

İlk kurulumda aynı kökte `setup.bat` → **[1]** ile araçlar ve Fred TV kaynağı iner.

### Linux / macOS

İlk kurulum (araçlar `tools/` altına iner, sisteme kurulmaz):

```bash
chmod +x setup.sh hstream/build.sh
./setup.sh
```

Menüde **[1]**. Sonraki derlemeler:

```bash
./hstream/build.sh
```

Flutter ve Rust zaten sistemdeyse Fred TV kaynağını `app/` olarak klonlayıp doğrudan `hstream/build.sh` yeter. `HSTREAM_APP` ile kaynak yolunu değiştirebilirsiniz.

### Elle

Gerekenler: Flutter, Android NDK, Rust, [cargo-ndk](https://github.com/bbqsrc/cargo-ndk).

```bash
git clone --depth 1 https://github.com/Fredolx/fred-tv-mobile.git app
cp -R hstream/files/flutter/. app/flutter/
cp hstream/files/rust/src/sql.rs app/src/sql.rs
cp hstream/files/rust/src/lib.rs app/src/lib.rs
cp hstream/files/rust/Cargo.toml app/Cargo.toml

cd app
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 --platform 24 \
  -o flutter/android/app/src/main/jniLibs build --release

cd flutter
flutter pub get
flutter build apk --release
```

APK: `app/flutter/build/app/outputs/flutter-apk/app-release.apk`

Play Store dışından yüklenen APK’larda Play Protect uyarısı görülebilir.

## Kaynak

HStream, [Fred TV](https://github.com/Fredolx/fred-tv-mobile) temel alınarak geliştirilmiştir. Arayüz ve sonraki özelliklerin bir bölümü yapay zeka desteğiyle yazılmıştır.

---

# HStream (English)

IPTV player for Android and Android TV.

Watch live TV, movies, and series from Xtream Codes, an M3U URL, or a local M3U file. Phone, tablet, and remote-driven TV use the same interface.

## Features

- Live TV, movies, series, and favorites — single hub
- Three source types: Xtream, M3U URL, local M3U
- Player: episode strip, D-pad, display cutout, fullscreen
- Five languages: Turkish, English, Spanish, German, French
- Settings: hide NSFW, continue watching
- Xtream sources show username and expiry date

## Build

HStream is an overlay on [Fred TV](https://github.com/Fredolx/fred-tv-mobile). Files live in `hstream/files`.

### Windows (portable toolchain)

From the directory that contains `app`:

```bat
hstream\build.bat
```

In the menu choose **[2]** (build), then **[4]** (quit). APK: `output\HStream.apk`

First-time setup: `setup.bat` → **[1]**.

### Linux / macOS

First-time setup (toolchain under `tools/`, nothing system-wide):

```bash
chmod +x setup.sh hstream/build.sh
./setup.sh
```

Choose **[1]**. Later builds: `./hstream/build.sh`

If Flutter and Rust are already installed, clone Fred TV at `app/` and run `hstream/build.sh` directly. Override the checkout path with `HSTREAM_APP`.

### Manual

Requires Flutter, Android NDK, Rust, and cargo-ndk. Same commands as in the Turkish section above.

Sideloaded APKs may trigger a Play Protect warning.

## Credits

HStream is based on [Fred TV](https://github.com/Fredolx/fred-tv-mobile). Portions of the interface and later features were written with AI assistance.

---

## Ekran görüntüsü / Screenshot

![HStream](docs/screenshots/hub.png)
