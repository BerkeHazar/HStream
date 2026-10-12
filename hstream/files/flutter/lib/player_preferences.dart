import 'package:shared_preferences/shared_preferences.dart';

/// : Oynatıcı tercihleri — tampon (buffer), altyazı boyutu ve PiP.
///
/// Nsfw / SonIzlenen / HDil kalıbıyla aynı: ayarlar Rust protobuf'una
/// EKLENMEZ (o zaman sql.rs + mesaj şeması da değişirdi), bunun yerine
/// SharedPreferences'ta tutulur. Oynatıcı ve ayar ekranı AYNI kaynağı okur.
class PlayerPreferences {
  // ---- tampon (saniye) ----
  static const String _tamponAnahtar = 'hstream_tampon_sn';
  static const int tamponVarsayilan = 60;
  static const List<int> tamponSecenekler = [30, 60, 90];
  static const int tamponMin = 15;
  static const int tamponMax = 120;

  // ---- altyazı boyutu (sp) ----
  static const String _altyaziAnahtar = 'hstream_altyazi_sp';
  // : VARSAYILAN 24 -> 18 (kullanıcı isteği: hem TV hem mobilde 18).
  // Eski kurulumlarda 24 kayıtlı kaldığı için `yukle()` içinde tek
  // seferlik göç uygulanır; aksi halde değişiklik mevcut cihazlarda
  // hiç görünmezdi.
  static const int altyaziVarsayilan = 18;
  /// : göçün bir kez çalıştığını işaretler.
  static const String _altyaziGocAnahtar = 'hstream_altyazi_sp_goc';
  /// : değişiklikten önceki varsayılan — göç yalnızca bu değeri hedefler.
  static const int _altyaziEskiVarsayilan = 24;
  static const List<int> altyaziSecenekler = [18, 24, 30, 36];

  // ---- PiP tercihi ----
  static const String _pipAnahtar = 'hstream_pip_acik';
  static const bool pipVarsayilan = true;

  static int tamponSn = tamponVarsayilan;
  static int altyaziSp = altyaziVarsayilan;
  static bool pipAcik = pipVarsayilan;

  /// Uygulama açılışında bir kez çağrılır (main.dart, Future.wait ile).
  static Future<void> yukle() async {
    final p = await SharedPreferences.getInstance();
    tamponSn = (p.getInt(_tamponAnahtar) ?? tamponVarsayilan)
        .clamp(tamponMin, tamponMax);

    // : ALTYAZI VARSAYILANI GÖÇÜ (24 -> 18).
    // Yalnızca eski VARSAYILAN (24) kayıtlıysa 18'e çekilir. Kullanıcının
    // bilerek seçtiği 30/36 gibi değerlere DOKUNULMAZ — 24 de teorik olarak
    // bilinçli bir seçim olabilir ama pratikte eski varsayılandır ve
    // kullanıcı 18 istedi; bu yüzden göç tam olarak onu hedefler.
    // İşaretçi sayesinde göç yalnızca BİR kez çalışır: kullanıcı sonradan
    // 24'e dönerse bir daha 18'e çekilmez.
    final kayitliSp = p.getInt(_altyaziAnahtar);
    final gocTamam = p.getBool(_altyaziGocAnahtar) ?? false;
    if (gocTamam) {
      altyaziSp = kayitliSp ?? altyaziVarsayilan;
    } else {
      if (kayitliSp == _altyaziEskiVarsayilan) {
        altyaziSp = altyaziVarsayilan;
        await p.setInt(_altyaziAnahtar, altyaziSp);
      } else {
        altyaziSp = kayitliSp ?? altyaziVarsayilan;
      }
      await p.setBool(_altyaziGocAnahtar, true);
    }

    pipAcik = p.getBool(_pipAnahtar) ?? pipVarsayilan;
  }

  static Future<void> tamponAyarla(int sn) async {
    tamponSn = sn.clamp(tamponMin, tamponMax);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_tamponAnahtar, tamponSn);
  }

  static Future<void> altyaziAyarla(int sp) async {
    altyaziSp = sp;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_altyaziAnahtar, sp);
  }

  static Future<void> pipAyarla(bool acik) async {
    pipAcik = acik;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_pipAnahtar, acik);
  }
}
