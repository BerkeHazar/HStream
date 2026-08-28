import 'package:shared_preferences/shared_preferences.dart';

/// : Ana ekrandaki Son Izlenenler bolumunu goster/gizle.
/// Varsayilan = ACIK. Kapatinca gecmis SILINMEZ; acilinca liste ayni doner.
class SonIzlenen {
  static const String _anahtar = 'hstream_son_izlenen_goster';
  static bool goster = true;

  /// Uygulama acilisinda bir kez cagrilir (main.dart).
  static Future<void> yukle() async {
    final p = await SharedPreferences.getInstance();
    goster = p.getBool(_anahtar) ?? true;
  }

  /// Ayarlar ekranindaki anahtar degistirince cagrilir.
  static Future<void> ayarla(bool value) async {
    goster = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_anahtar, value);
  }
}
