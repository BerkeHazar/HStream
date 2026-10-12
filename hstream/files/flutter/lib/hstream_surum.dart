import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// : SÜRÜM BİLGİSİ + GÜNCELLEME DENETİMİ.
///
/// Nereden okunur:
///  - Kurulu sürüm: `package_info_plus` (pubspec.yaml'daki `version:`).
///  - Yeni sürüm  : GitHub Releases API (`/releases/latest`).
///
/// Neden GitHub Releases: uygulama Play Store dışında, APK olarak dağıtılıyor;
/// "yeni sürüm var" bilgisinin tek güvenilir kaynağı yayın sayfasıdır.
///
/// Durum bilgisi (yenilikler gösterildi mi, hangi sürüm atlandı) SharedPreferences
/// içinde tutulur — `Nsfw` / `SonIzlenen` / `PlayerPreferences` ile aynı kalıp:
/// bu tür arayüz durumu Rust protobuf şemasına eklenmez.
class HGuncelleme {
  /// Sunucudaki sürüm adı, örn "1.0.1".
  final String surum;
  /// Yayın notu (GitHub release body). Boş olabilir.
  final String notlar;
  /// Yayın sayfası — kullanıcı buraya yönlendirilir.
  final String sayfa;
  /// Doğrudan APK adresi (yayında .apk eki varsa).
  final String? apk;

  const HGuncelleme({
    required this.surum,
    required this.notlar,
    required this.sayfa,
    this.apk,
  });

  /// İndirme için tercih edilen adres: varsa doğrudan APK, yoksa sayfa.
  String get indirmeAdresi => apk ?? sayfa;
}

class HSurum {
  static const String ad = "HStream";
  static const String depo = "BerkeHazar/HStream";
  static const String depoSayfasi = "https://github.com/$depo";
  static const String lisansAdi = "AGPL-3.0";
  static const String lisansSayfasi = "$depoSayfasi/blob/main/LICENSE";
  static const String _api =
      "https://api.github.com/repos/$depo/releases/latest";

  // ---- tercih anahtarları ----
  static const String _gorulenAnahtar = 'hstream_gorulen_surum';
  static const String _atlananAnahtar = 'hstream_atlanan_surum';
  static const String _sonDenetimAnahtar = 'hstream_son_guncelleme_denetimi';

  /// Kurulu sürüm adı ("1.0.0"). `yukle()` çağrılmadan boş kalır.
  static String surum = '';
  /// Kurulu build numarası ("1"), yalnız gösterim için.
  static String build = '';

  /// Uygulama açılışında bir kez çağrılır (main.dart, paralel blokta).
  static Future<void> yukle() async {
    try {
      final b = await PackageInfo.fromPlatform();
      surum = b.version;
      build = b.buildNumber;
    } catch (_) {
      // Sürüm okunamazsa güncelleme denetimi ve yenilikler sessizce atlanır.
    }
  }

  /// "Sürüm 1.0.0 (1)" — build numarası varsa parantezde.
  static String etiket() {
    if (surum.isEmpty) return '';
    return build.isEmpty ? surum : '$surum ($build)';
  }

  // ---------- güncelleme denetimi ----------

  /// GitHub'dan en son yayını sorar.
  ///
  /// `null` dönerse: ağ yok, kota doldu (403), yayın yok ya da sürüm aynı/eski.
  /// Bu metot ASLA hata fırlatmaz — açılış akışını bozmamalı.
  static Future<HGuncelleme?> denetle({
    Duration zamanAsimi = const Duration(seconds: 8),
  }) async {
    if (surum.isEmpty) return null;
    final istemci = HttpClient();
    istemci.connectionTimeout = zamanAsimi;
    try {
      final istek = await istemci
          .getUrl(Uri.parse(_api))
          .timeout(zamanAsimi);
      // : GitHub API bir User-Agent ister; Dart varsayılanı ("Dart/x.y")
      // kabul edilir ama açıkça yazmak daha güvenli.
      istek.headers.set(HttpHeaders.userAgentHeader, '$ad/$surum');
      istek.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final cevap = await istek.close().timeout(zamanAsimi);
      if (cevap.statusCode != 200) return null;
      final govde = await cevap
          .transform(utf8.decoder)
          .join()
          .timeout(zamanAsimi);
      final harita = jsonDecode(govde) as Map<String, dynamic>;
      await _sonDenetimiKaydet();
      final uzak = _temizle(
        (harita['tag_name'] ?? harita['name'] ?? '').toString(),
      );
      if (uzak.isEmpty) return null;
      if (!dahaYeni(uzak, surum)) return null;
      return HGuncelleme(
        surum: uzak,
        notlar: (harita['body'] ?? '').toString().trim(),
        sayfa: (harita['html_url'] ?? depoSayfasi).toString(),
        apk: _apkAdresi(harita['assets']),
      );
    } catch (_) {
      return null;
    } finally {
      istemci.close();
    }
  }

  /// Yayın ekleri arasından ilk .apk dosyasını seçer.
  static String? _apkAdresi(dynamic assets) {
    if (assets is! List) return null;
    for (final a in assets) {
      if (a is! Map) continue;
      final adres = (a['browser_download_url'] ?? '').toString();
      if (adres.toLowerCase().endsWith('.apk')) return adres;
    }
    return null;
  }

  /// "v1.0.1" / "1.0.1-beta" / "1.0.1+2" → "1.0.1"
  static String _temizle(String ham) {
    var s = ham.trim();
    if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
    for (final ayrac in ['-', '+', ' ']) {
      final i = s.indexOf(ayrac);
      if (i > 0) s = s.substring(0, i);
    }
    return s.trim();
  }

  /// "1.0.10" > "1.0.9" — sayısal karşılaştırma (metin karşılaştırması yanlış).
  static int karsilastir(String a, String b) {
    final x = a.split('.');
    final y = b.split('.');
    final n = x.length > y.length ? x.length : y.length;
    for (var i = 0; i < n; i++) {
      final xi = i < x.length ? (int.tryParse(x[i].trim()) ?? 0) : 0;
      final yi = i < y.length ? (int.tryParse(y[i].trim()) ?? 0) : 0;
      if (xi != yi) return xi.compareTo(yi);
    }
    return 0;
  }

  static bool dahaYeni(String aday, String mevcut) =>
      karsilastir(aday, mevcut) > 0;

  // ---------- "yenilikler" durumu ----------

  /// Sürüm değiştiyse (yani uygulama güncellendiyse) yenilikler gösterilmeli.
  static Future<bool> yenilikGosterilmeli() async {
    if (surum.isEmpty) return false;
    final p = await SharedPreferences.getInstance();
    return p.getString(_gorulenAnahtar) != surum;
  }

  /// Yenilikler gösterildi olarak işaretlenir (bir kez gösterilir).
  static Future<void> yenilikGoruldu() async {
    if (surum.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString(_gorulenAnahtar, surum);
  }

  // ---------- güncelleme hatırlatmasını erteleme ----------

  /// Kullanıcı "Sonra" dediyse aynı sürüm için tekrar sorulmaz.
  static Future<bool> atlandi(String surum) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_atlananAnahtar) == surum;
  }

  static Future<void> atla(String surum) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_atlananAnahtar, surum);
  }

  // ---------- denetim zamanı ----------

  /// Açılışta çok sık denetlememek için son denetim zamanı (ms).
  static Future<DateTime?> sonDenetim() async {
    final p = await SharedPreferences.getInstance();
    final ms = p.getInt(_sonDenetimAnahtar);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<void> _sonDenetimiKaydet() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(
      _sonDenetimAnahtar,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Açılışta otomatik denetim yapılmalı mı? (son denetimden 6 saat geçtiyse)
  static Future<bool> acilistaDenetlenmeli() async {
    final son = await sonDenetim();
    if (son == null) return true;
    return DateTime.now().difference(son) > const Duration(hours: 6);
  }
}
