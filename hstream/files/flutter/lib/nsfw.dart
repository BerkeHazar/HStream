import 'package:shared_preferences/shared_preferences.dart';

/// : NSFW gizleme anahtari.
/// Varsayilan = KAPALI (her sey gorunur; kullanici karari).
/// PIN yok (kullanici istemedi). Filtreleme Rust tarafinda:
/// native_bridge, anahtar acikken sorgu sort degerini +3 gonderir;
/// Rust sort%3 ile siralamayi korur, nsfw_flag ile ad+kategori eler.
class Nsfw {
  static const String _anahtar = 'hstream_nsfw_gizle';
  static bool hide = false;

  /// Uygulama acilisinda bir kez cagrilir (main.dart).
  static Future<void> yukle() async {
    final p = await SharedPreferences.getInstance();
    hide = p.getBool(_anahtar) ?? false;
  }

  /// Ayarlar ekranindaki anahtar degistirince cagrilir.
  static Future<void> ayarla(bool value) async {
    hide = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_anahtar, value);
  }
}
