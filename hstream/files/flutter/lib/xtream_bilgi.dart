import 'dart:convert';
import 'dart:io';

import 'package:open_tv/l10n.dart';
import 'package:open_tv/models/source.dart';
import 'package:open_tv/models/source_type.dart';

/// : Xtream player_api user_info (kullanici adi + bitis tarihi).
class XtreamBilgi {
  final String? kullanici;
  final DateTime? bitis;
  const XtreamBilgi({this.kullanici, this.bitis});
}

DateTime? _expCoz(dynamic exp) {
  if (exp == null) return null;
  final s = exp.toString().trim();
  if (s.isEmpty || s == "null" || s == "0" || s == "-1" || s == "unlimited") {
    return null;
  }
  final n = int.tryParse(s);
  if (n != null) {
    // saniye veya milisaniye unix
    final ms = n > 9999999999 ? n : n * 1000;
    if (ms > 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    }
  }
  return DateTime.tryParse(s)?.toLocal();
}

List<String> _apiAdresleri(String ham) {
  var kok = ham.trim();
  if (kok.endsWith("/")) kok = kok.substring(0, kok.length - 1);
  final soru = kok.indexOf("?");
  if (soru >= 0) kok = kok.substring(0, soru);
  if (kok.contains("player_api.php")) {
    return [kok];
  }
  return ["$kok/player_api.php"];
}

Future<XtreamBilgi?> xtreamBilgiCek(Source kaynak) async {
  if (kaynak.sourceType != SourceType.xtream) return null;
  final ham = (kaynak.urlOrigin ?? kaynak.url ?? "").trim();
  final kullanici = kaynak.username ?? "";
  final sifre = kaynak.password ?? "";
  if (ham.isEmpty || kullanici.isEmpty) return null;
  final istemci = HttpClient();
  istemci.connectionTimeout = const Duration(seconds: 8);
  istemci.badCertificateCallback = (cert, host, port) => true;
  try {
    for (final adres in _apiAdresleri(ham)) {
      try {
        final uri = Uri.parse(adres).replace(
          queryParameters: {
            "username": kullanici,
            "password": sifre,
          },
        );
        final istek =
            await istemci.getUrl(uri).timeout(const Duration(seconds: 8));
        final cevap = await istek.close().timeout(const Duration(seconds: 10));
        if (cevap.statusCode < 200 || cevap.statusCode >= 300) continue;
        final govde = await cevap
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 10));
        final json = jsonDecode(govde);
        if (json is! Map) continue;
        final ui = json["user_info"];
        if (ui is! Map) continue;
        final ad = ui["username"]?.toString();
        return XtreamBilgi(
          kullanici: (ad != null && ad.isNotEmpty) ? ad : kullanici,
          bitis: _expCoz(ui["exp_date"]),
        );
      } catch (_) {
        continue;
      }
    }
    return null;
  } finally {
    istemci.close();
  }
}

String xtreamAltYazi(XtreamBilgi bilgi) {
  final parca = <String>[];
  if (bilgi.kullanici != null && bilgi.kullanici!.isNotEmpty) {
    parca.add("${L.t('kullanici')}: ${bilgi.kullanici}");
  }
  if (bilgi.bitis != null) {
    final d = bilgi.bitis!;
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    parca.add("${L.t('bitis')}: $dd.$mm.${d.year}");
  } else {
    parca.add("${L.t('bitis')}: ${L.t('sinirsiz')}");
  }
  return parca.join("  ·  ");
}
