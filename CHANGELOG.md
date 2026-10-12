# Sürüm notları / Release notes

Bu dosya **kullanıcıya gösterilecek** güncelleme notlarını tutar. Her sürüm
yayınlanmadan önce buraya bir bölüm eklenir ve aynı metin dağıtım sayfasına
(GitHub release, web sitesi, mağaza açıklaması) kopyalanır.

**Nasıl eklenir:** en üste, `## ` başlığıyla yeni sürümü yaz. Sürüm numarası
`hstream/files/flutter/pubspec.yaml` içindeki `version:` ile **birebir aynı**
olmalı (örn. `version: 1.0.1+2` → başlık `## 1.0.1`). Yeni bölüm en üste gelir,
eskiler aşağıda kalır.

Not yazarken kullanıcının dilinden konuş: "şu düzeltildi" değil,
"artık şöyle çalışıyor". Teknik ayrıntı (dosya adı, sınıf adı) yazma.

---

## 1.0.1

**ÖNEMLİ — yeniden kurulum gerekiyor.** Bu sürüm ilk kez kalıcı bir imzalama
anahtarıyla imzalandı. Ağustos'taki 1.0.0 sürümünü kurduysan Android, imzası
farklı olan yeni sürümü eskisinin üstüne kuramaz: önce eski uygulamayı
kaldırman, sonra bu APK'yı kurman gerekir. Kaynaklarını ve ayarlarını yeniden
girmen gerekecek. **Bundan sonraki güncellemeler sorunsuz kurulur** — anahtar
artık sabit.

Düzeltmeler

- Canlı yayınlarda resim içinde resim hiç açılmıyordu.
- PiP penceresini HStream'in düğmeleri kaplıyordu; artık pencere tamamen video.
- PiP penceresinden 10 saniye geri/ileri sarılabiliyor (film ve dizilerde).
- Bir dizinin bölümü Son İzlenenler'de "Film" olarak görünüyordu.
- `https://` ile gelen M3U listeleri ve HTTPS Xtream panelleri Android'de
  eklenemiyordu — büyük listeler dahil (örn. iptv-org index).
- Oynatıcıdaki hız / altyazı / uyku / PiP çip satırı kaydırılırken kasıyordu.
- Son İzlenenler'den bir bölüme girince bölüm şeridi ve "sonraki bölüm"
  çalışmıyordu.

Yenilikler

- Son İzlenenler kartlarında **kalınan dakika** rozeti.
- **Hakkında ekranı:** sürüm, lisans, kaynak kodu ve güncelleme denetimi.
- **Uygulama içi güncelleme:** yeni sürüm çıkınca haber verir, sürüm notlarını
  gösterir ve indirmeye yönlendirir.
- Güncellemeden sonra ilk açılışta **"Yenilikler"** özeti.
- Kaldığın yer artık daha güvenilir kaydediliyor (bölüm geçişinde ve uygulama
  arka plana atıldığında da).

---

## 1.0.1 (English)

**IMPORTANT — reinstall required.** This is the first build signed with a
permanent key. If you installed 1.0.0 from August, Android cannot install this
over it because the signature differs: uninstall the old app first, then install
this APK. You will need to add your sources again. **Future updates will install
normally** — the key is stable from here on.

Fixes

- Picture-in-picture never opened on live channels.
- HStream's own buttons covered the PiP window; the window is all video now.
- PiP supports 10-second back/forward for movies and series.
- An episode of a series showed up as a "Movie" in Continue watching.
- M3U playlists served over `https://` and HTTPS Xtream panels could not be
  added on Android — including large lists such as the iptv-org index.
- The speed / subtitle / sleep / PiP chip row stuttered while scrolling.
- Opening an episode from Continue watching lost the episode strip and the
  "next episode" button.

New

- **Time you left off** badge on Continue watching cards.
- **About screen:** version, license, source code and an update check.
- **In-app updates:** tells you when a new version is out, shows the release
  notes and takes you to the download.
- A **"What's new"** summary on the first launch after an update.
- Your place is now saved more reliably (also on episode changes and when the
  app goes to the background).

---

## 1.0.0

İlk sürüm: canlı TV, filmler ve diziler tek ekranda. Xtream Codes, M3U
bağlantısı ve cihazdaki M3U dosyası desteği. Beş dil.

## 1.0.0 (English)

First release: live TV, movies and series in one screen. Xtream Codes, an M3U
URL and a local M3U file. Five languages.
