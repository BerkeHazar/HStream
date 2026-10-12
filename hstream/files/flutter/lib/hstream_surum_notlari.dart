/// : SÜRÜM NOTLARI — uygulamanın İÇİNDE gösterilen "yenilikler" metinleri.
///
/// Kaynak: kök dizindeki `CHANGELOG.md`. Uygulama o dosyayı okuyamaz (APK'nın
/// içinde değil), bu yüzden her sürümün kısa notları buraya da yazılır.
///
/// KURAL: yeni sürüm yayınlarken
///   1. `CHANGELOG.md`'ye bölümü ekle (kullanıcıya giden tam metin),
///   2. aynı sürümün maddelerini buraya ekle (uygulama içi özet),
///   3. `hstream/files/flutter/pubspec.yaml` içindeki `version:` satırını artır.
/// Anahtar, `pubspec.yaml`'daki sürüm adıyla BİREBİR aynı olmalı ("1.0.1").
///
/// Notlar yalnızca Türkçe ve İngilizce tutulur; diğer diller İngilizce'ye
/// düşer (uzun metinleri beş dilde çevirmek bakım yükünü artırıyordu).
class HSurumNotlari {
  /// Sürüm adı → maddeler.
  static const Map<String, List<String>> _tr = {
    "1.0.1": [
      "ÖNEMLİ: Ağustos'taki sürümü kurduysan önce kaldırman gerekir — imza değişti. Bundan sonraki güncellemeler sorunsuz kurulur",
      "Resim içinde resim artık canlı yayınlarda da açılıyor; pencereden 10 sn geri/ileri sarabilirsin",
      "Son İzlenenler kartlarında kalınan dakika görünüyor",
      "Hakkında ekranı: sürüm, lisans, kaynak kodu ve güncelleme denetimi",
      "Yeni sürüm çıkınca uygulama haber veriyor ve notları gösteriyor",
      "HTTPS m3u listeleri ve HTTPS Xtream panelleri artık ekleniyor",
      "Dizi bölümü Son İzlenenler'de \"Bölüm N\" olarak görünüyor",
      "Oynatıcıdaki hız/altyazı/uyku/PiP çip satırı kaydırırken kasmıyor",
      "Kaldığın yer daha güvenilir kaydediliyor (bölüm geçişi ve arka plan dahil)",
    ],
    "1.0.0": [
      "Canlı TV, film ve diziler tek ekranda: Xtream, M3U linki veya yerel M3U dosyası",
      "Kaldığın yerden devam: film ve bölümler bıraktığın saniyeden açılır",
      "Beş dil: Türkçe, English, Español, Deutsch, Français",
    ],
  };

  static const Map<String, List<String>> _en = {
    "1.0.1": [
      "IMPORTANT: if you have the August build, uninstall it first — the signature changed. Future updates install normally",
      "Picture-in-picture now works on live channels too, with 10-second back/forward in the window",
      "Continue watching cards show the time you left off",
      "About screen: version, license, source code and an update check",
      "The app tells you when a new version is out and shows the release notes",
      "HTTPS M3U playlists and HTTPS Xtream panels can be added now",
      "An episode shows as \"Episode N\" in Continue watching",
      "The in-player speed/subtitle/sleep/PiP chip row no longer stutters",
      "Your place is saved more reliably (episode changes and background included)",
    ],
    "1.0.0": [
      "Live TV, movies and series in one place: Xtream, M3U URL or a local M3U file",
      "Resume where you left off: movies and episodes open at the last position",
      "Five languages: Turkish, English, Spanish, German, French",
    ],
  };

  /// Verilen sürümün notları. Dil yoksa İngilizce, o da yoksa boş liste.
  static List<String> al(String surum, String dil) {
    final kod = surum.trim();
    final secim = dil.toLowerCase().startsWith('tr') ? _tr : _en;
    return secim[kod] ?? _en[kod] ?? const <String>[];
  }

  /// Uygulamada notu bulunan sürümler (en yeniden en eskiye).
  static List<String> surumler() {
    final hepsi = <String>{..._tr.keys, ..._en.keys}.toList();
    hepsi.sort((a, b) => _karsilastir(b, a));
    return hepsi;
  }

  /// "1.0.10" > "1.0.9" (sayısal karşılaştırma; metin karşılaştırması yanlış olur).
  static int _karsilastir(String a, String b) {
    final x = a.split('.');
    final y = b.split('.');
    final n = x.length > y.length ? x.length : y.length;
    for (var i = 0; i < n; i++) {
      final xi = i < x.length ? (int.tryParse(x[i]) ?? 0) : 0;
      final yi = i < y.length ? (int.tryParse(y[i]) ?? 0) : 0;
      if (xi != yi) return xi.compareTo(yi);
    }
    return 0;
  }
}
