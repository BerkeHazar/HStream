# Geliştirme notları

HStream'in mimarisi ve geliştirme sırasında dikkat edilmesi gereken noktalar.  
Kurulum ve derleme adımları için [README](README.md) dosyasına bakın.

## Mimari

HStream bağımsız bir Flutter projesi değildir. [Fred TV](https://github.com/Fredolx/fred-tv-mobile)  
kaynak ağacının üzerine **overlay** uygulanarak derlenir.

| Dizin                    | Hedef              | İçerik                                    |
| ------------------------ | ------------------ | ----------------------------------------- |
| `hstream/files/flutter/` | Fred TV `flutter/` | Arayüz, Android yapılandırması, varlıklar |
| `hstream/files/rust/`    | Fred TV `src/`     | SQLite köprüsü + HTTP istemcisi           |

Overlay'in sahip olduğu Rust dosyaları: `lib.rs`, `sql.rs`, `m3u.rs`,  
`xtream.rs`, `tls.rs` ve `Cargo.toml`. `xtream.rs` ve `tls.rs` şu yüzden  
overlay'e alındı: HTTPS istemcisi tek bir yerden (`tls.rs`) kurulmalı, aksi  
halde Android'de aşağıdaki panic hatası geri gelir. Bu dosyalar upstream'de  
değişirse elle karşılaştırmak gerekir.

Overlay'de bulunmayan dosyalar Fred TV deposundan gelir. `models/settings.dart`,  
`models/source.dart`, `select_dialog.dart`, `loading.dart` ve `models/home_manager.dart`  
bu depoda yer almaz. Yeni dosya eklerken bu ayrım gözetilmelidir.

### Tanımlayıcılar

| Alan              | Değer                                |
| ----------------- | ------------------------------------ |
| Android paket adı | `io.github.berkehazar.hstream`       |
| Flutter paket adı | `open_tv`                            |
| Sürüm             | `hstream/files/flutter/pubspec.yaml` |

`namespace` değeri Fred TV ile aynı (`dev.fredol.open_tv`) bırakılmıştır. R sınıfı ve  
manifest içindeki `.MainActivity` referansı bu değere bağlıdır; değiştirilmesi derlemeyi  
bozar. Kullanıcıya görünen uygulama kimliği `applicationId` alanından yönetilir.

`open_tv` paket adı tüm `import` ifadelerinde geçtiği için değiştirilmemelidir.

## Geliştirme sırasında dikkat edilecekler

### Overlay doğrulaması

`hstream/apply.bat`, overlay uygulandıktan sonra dosyaların beklenen içeriği taşıdığını  
`findstr` ile doğrular. Doğrulama başarısız olursa derleme kasıtlı olarak durur. Bir  
dosya değiştirildiğinde ilgili doğrulama satırı da güncellenmelidir.

`pubspec.yaml` kontrolü **sürüme bağlı değildir**: yalnızca dosyanın HStream'e ait  
olduğu (`name: open_tv` + `description`) ve bir `version:` satırı taşıdığı doğrulanır.  
Sürüm numarasını serbestçe artırabilirsin; ek bir satır güncellemek gerekmez.

Doğrulama satırı yazarken iki kural:

- **Negatif kontrol** (`geri gelmemeli`) ararken metnin dosyada **başka yerde de  
  geçmediğinden emin ol.** Örnek: `SingleChildScrollView` bir zamanlar çip satırı  
  için yasak sanıldı, ama uyku diyaloğunda da kullanılıyordu; kontrol yanlış alarm  
  verip derlemeyi durdurdu. Bunun yerine o yapıya özgü bir metin ara  
  (`i < cipler.length` gibi).
- Doğrulamayı `%APP%` altındaki **kopyalar** üzerinde yap; `%HS%` yalnızca  
  `build.bat` içinde tanımlıdır, `setup.bat` yolunda boş kalır. apply.bat içinde  
  overlay yolu için `%F2K%` kullan.

### Batch dosyalarında yorum tuzağı

`apply.bat` içinde `( ... )` bloğu **içine** `::` yorum satırı yazma. Cmd bunları  
etiket gibi ayrıştırır ve blok kapanırken `Sistem belirtilen sürücüyü bulamıyor.`  
hatası basar (işlem yine de çalışır, ama çıktı yanıltıcı olur). Blok içinde  
yorum gerekiyorsa `rem` kullan; ya da yorumu bloğun dışına taşı.

### HTTPS istemcisi (Android'de panic tuzağı)

**reqwest istemcisi doğrudan kurulmaz.** `reqwest::Client::builder()` her  
çağrıldığında reqwest 0.13'ün `rustls` özelliği sertifika doğrulaması için  
`rustls-platform-verifier` kullanır; o doğrulayıcı Android'de açıkça  
başlatılmadığı için **panic atar** (`Expect rustls-platform-verifier to be
initialized`). Panic tokio görevi içinde oluştuğu için FFI geri çağrısı hiç  
çalışmaz: Dart tarafındaki `await` sonsuza kadar bekler ve kullanıcı  
"liste eklenmiyor" görür. Masaüstünde aynı adres çalışır (orada doğrulayıcı  
işletim sisteminin deposunu kullanır), bu yüzden hata yalnızca Android'de ve  
yalnızca **HTTPS** adreslerde görünür — HTTP panelleri etkilenmez.

Kural: yeni bir HTTP çağrısı eklerken `crate::tls::client(&user_agent)` kullan.  
Kök sertifikalar Mozilla listesinden gelir (`webpki-roots`), yani doğrulama  
açık kalır ve hiçbir platform başlatma adımı gerekmez. Ayrıntılı gerekçe  
`hstream/files/rust/src/tls.rs` başında yazılıdır; `apply.bat` doğrudan  
`Client::builder().user_agent` kullanımının geri gelmemesini denetler.

### Dosya adları ve uzantılar

Overlay dosyaları, Fred TV'de aynı ada sahip dosyaların yerini alır. Bir dosyanın adı  
veya uzantısı değiştirilirse her iki dosya aynı anda mevcut olur ve Android  
`duplicate resource` hatası verir. Ad ve uzantı korunmalıdır.

### Android TV banner

`android:banner` görselinin boyutu 320×180 dp olmalıdır. Yoğunluk dizinleri 2× ölçek  
kullandığı için `drawable-xhdpi` içindeki dosya 640×360 piksel olmalıdır. Beklenen  
boyutun altındaki bir görsel TV arayüzünde büyütülerek bulanık görünür.

### Adaptive icon

`ic_launcher_foreground` görseli 108 dp tuval içinde ortadaki 72 dp'lik güvenli alanda  
kalmalıdır. Bu alanın dışına taşan içerik maskelenir.

### .gitignore kuralları

`/keys/` ve `/app/` kuralları kök dizine sabitlenmiştir. Baştaki `/` kaldırılırsa git  
bu isimdeki tüm dizinleri yok sayar; overlay altındaki `android/app/` dosyaları  
sessizce depo dışında kalır.

### İmzalama

Release derlemeleri `keys/` dizinindeki anahtarla imzalanır. Bu dizin `.gitignore`  
kapsamındadır ve depoya dahil edilmemelidir. Ayrıntılar için [README](README.md)  
dosyasının "İmzalama" bölümüne bakın.

**`key.properties` bir Java `.properties` dosyasıdır** ve orada ters bölü (`\`)  
kaçış karakteridir. `storeFile` değeri tek ters bölü ile yazılırsa yol okunurken  
bozulur:

```
yazılan : storeFile=C:\Users\Berke\...\keys\hstream-release.jks
okunan  : C:UsersBerke...keyshstream-release.jks      ← tüm \ yutuldu
```

Sonuç: `validateSigningRelease` görevi  
`Keystore file '...' not found for signing config 'release'` diyerek derlemeyi  
durdurur. Bu yüzden:

- `keystore.bat` / `keystore.sh` yolu **düz bölü** (`/`) ile yazar,
- `build.gradle` yolu yine de normalize eder ve bulunamazsa proje kökündeki  
  standart konuma (`keys/hstream-release.jks`) düşer,
- `apply.bat` bu üç davranışın geri gelmemesini denetler.

## Doğrulama (tam derleme olmadan)

Tam APK derlemesi uzun sürer; küçük bir değişiklikten sonra hatayı erken
yakalamak için derleyicileri doğrudan çağırmak yeterlidir. Ayrıca bu ortamda
`flutter` aracı bazen hiç çalışmaz (Dart alt süreç açamazsa
`All pipe instances are busy` hatası verir) — o durumda tek yol budur.

**Dart tip kontrolü** (tüm uygulama, hızlı):

```bash
D=tools/flutter/bin/cache/dart-sdk/bin
FS=tools/flutter/bin/cache/artifacts/engine/common/flutter_patched_sdk/platform_strong.dill
"$D/dartaotruntime.exe" "$D/snapshots/gen_kernel_aot.dart.snapshot" \
  --platform="$FS" --packages=app/flutter/.dart_tool/package_config.json \
  --target=flutter --output=/tmp/check.dill app/flutter/lib/main.dart
```

Çıktı **boşsa hata yoktur**. Uyarılar görünmez, yalnızca gerçek hatalar basılır.

**Rust testleri:** `app` dizininde `cargo test`. Host (Windows) derlemesi için
PATH'te `tools/perl/c/bin` (MinGW `gcc`/`dlltool`), `CARGO_HOME` ve
`RUSTUP_HOME` gerekir; aksi halde `dlltool.exe: program not found` veya
`ld: cannot find crt2.o` hataları çıkar.

**Batch doğrulaması:** `apply.bat` tek başına çalıştırılabilir; `ROOT` ve `APP`
ortam değişkenlerini vermek yeterlidir:

```bat
set "ROOT=%CD%" & set "APP=%CD%\app" & hstream\apply.bat
```

**Groovy/Gradle:** `build.gradle` değiştiğinde Gradle'ı çalıştırmadan
sözdizimi denetlenebilir — Gradle dağıtımındaki `groovy-*.jar` ile
`new GroovyShell().parse(new File('.../build.gradle'))`.

## Sıradaki sürüm — kısa kontrol listesi

1. `hstream/files/flutter/pubspec.yaml` → `version:` artır (build numarası **her
   yayında** artmalı; Android aksi halde güncellemeyi reddeder).
2. `CHANGELOG.md` → en üste yeni `## <sürüm>` bölümü (kullanıcıya giden metin).
3. `hstream/files/flutter/lib/hstream_surum_notlari.dart` → aynı sürüm için kısa
   maddeler (uygulama içi "Yenilikler"). Anahtar `pubspec.yaml` ile birebir aynı.
4. `hstream\build.bat` → **[2]**.
5. İmzayı doğrula: `apksigner verify --print-certs` → `CN=HStream` görünmeli.
6. GitHub'da yayınla: etiket sürümle aynı, açıklama = sürüm notu, APK ek olarak
   yüklenmeli. **Pre-release işaretleme** — `releases/latest` uç noktası
   pre-release ve taslakları atlar, uygulama içi güncelleme görmez.
7. İndirme sayfası (`docs/index.html`) sürümü, APK bağlantısını ve notu
   GitHub'dan kendi çeker; **sayfada elle güncellenecek bir şey yoktur.**
   Yalnızca özellik listesi değiştiyse o satırlar elle eklenir.

## Yol haritası

- [x] Arayüz performans iyileştirmeleri
- [x] Uygulama içi güncelleme kontrolü ve "Hakkında" ekranı
      (`hstream_hakkinda.dart`, `hstream_surum.dart` — GitHub Releases API)
- [x] LICENSE — AGPL-3.0 (Fred TV ile aynı; kök dizindeki `LICENSE`)
- [x] Sürüm notlarını uygulama içinde gösterme (`hstream_surum_notlari.dart`;
      sürüm değişince bir kez "Yenilikler" penceresi)
- [ ] README ekran görüntüleri (PiP, Son İzlenenler, Hakkında ekranı)

## Uygulama içi güncelleme (GitHub Releases)

| Dosya | Görev |
|---|---|
| `hstream_surum.dart` | kurulu sürüm, GitHub denetimi, atlama/hatırlatma durumu |
| `hstream_surum_notlari.dart` | uygulama içi "yenilikler" metinleri (gömülü) |
| `hstream_hakkinda.dart` | Hakkında ekranı + güncelleme/yenilikler pencereleri |

- Kurulu sürüm `package_info_plus` ile okunur (`pubspec.yaml` → `version:`).
- Yeni sürüm `api.github.com/repos/BerkeHazar/HStream/releases/latest`
  adresinden sorulur. Kimlik doğrulama yoktur; IP başına saatte 60 istek
  sınırı olduğu için açılışta **en fazla 6 saatte bir** denetlenir.
- Sürüm karşılaştırması sayısaldır ("1.0.10" > "1.0.9"); etiketteki `v` öneki
  ve `-`/`+` sonrası yok sayılır.
- **Sürüm notları iki yerde tutulur:** `CHANGELOG.md` (kullanıcıya giden tam
  metin, yayın sayfasına yapıştırılır) ve `hstream_surum_notlari.dart`
  (uygulama içi kısa özet). Anahtar, `pubspec.yaml`'daki sürüm adıyla birebir
  aynı olmalı ("1.0.0").
- GitHub yayınında **etiket sürümle aynı olmalı** ve **APK ek (asset) olarak
  yüklenmeli**; "İndir" düğmesi varsa doğrudan APK'yı, yoksa yayın sayfasını
  açar.
- Ağ yok / kota doldu / yayın yok → denetim sessizce atlanır, hiçbir hata
  kullanıcıya gösterilmez; açılış akışı etkilenmez.
- Durum bilgisi SharedPreferences'ta tutulur (`Nsfw`, `SonIzlenen`,
  `PlayerPreferences` ile aynı kalıp). Rust tarafındaki
  `should_show_whats_new` köprüsü kullanılmadı: DB'ye bağlı olduğu için
  açılışta ek bir FFI çağrısı gerektiriyordu.

## Yayınlama

Adım adım yayınlama (imzalama, sürüm yükseltme, APK doğrulama, dağıtım)  
[README](README.md) içindedir. Sürüm notları `CHANGELOG.md`'de tutulur;  
her yayında oraya bir bölüm eklenir ve aynı metin dağıtım sayfasına kopyalanır.

Sürüm numarası yalnızca `hstream/files/flutter/pubspec.yaml` içinde değiştirilir;  
`apply.bat` sürüm dizesini doğrulamaz (sürüme bağlı kontrol kaldırıldı).
