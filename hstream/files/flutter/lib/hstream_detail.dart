import 'dart:convert';
import 'dart:io' show HttpClient, Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:open_tv/app_mode.dart';
import 'package:open_tv/error.dart';
import 'package:open_tv/exo_player.dart';
import 'package:open_tv/memory.dart';
import 'package:open_tv/models/channel.dart';
import 'package:open_tv/models/media_type.dart';
import 'package:open_tv/models/node.dart';
import 'package:open_tv/models/node_type.dart';
import 'package:open_tv/models/source_type.dart';
import 'package:open_tv/native_bridge.dart';
import 'package:open_tv/palet.dart';
import 'package:open_tv/player.dart';
import 'package:open_tv/l10n.dart';
import 'package:open_tv/xtream_bilgi.dart';

///  — DETAY EKRANI (onaylı tasarım):
/// Film/Dizi kartına basınca önce burası açılır: büyük kapak, ad, bilgi
/// satırı, açıklama, ▶ Oynat kutusu ve favori düğmesi.
/// Canlı TV detaya girmez, direkt oynatılır (channel_tile / hstream_card).
///
/// Bilgi kaynağı:
/// - Xtream kaynağıysa player_api'den anlık çekilir (get_vod_info /
///   get_series_info): açıklama, yıl, tür, süre, puan, büyük kapak.
/// - M3U kaynağında API yoktur -> eldeki kapak + kategori gösterilir.
/// Bölümler (seriesId dolu kanallar) detaya girmez, direkt oynar.

class HStreamDetail extends StatefulWidget {
  final Channel channel;
  final Function(Node node) setNode;
  const HStreamDetail({
    super.key,
    required this.channel,
    required this.setNode,
  });

  @override
  State<HStreamDetail> createState() => _HStreamDetailState();
}

class _HStreamDetailState extends State<HStreamDetail> {
  bool _yukleniyor = true;
  Map<String, dynamic>? _bilgi;
  bool _oynatOdakli = false;
  final FocusNode _oynatFocus = FocusNode();

  bool get _dizi => widget.channel.mediaType == MediaType.serie;

  @override
  void initState() {
    super.initState();
    if (AppMode.isTv) _oynatFocus.requestFocus();
    _oynatFocus.addListener(() {
      if (mounted) {
        setState(() {
          _oynatOdakli = _oynatFocus.hasFocus;
        });
      }
    });
    _bilgiGetir();
  }

  @override
  void dispose() {
    _oynatFocus.dispose();
    super.dispose();
  }

  // ---------- Xtream bilgi çekme ----------

  Future<void> _bilgiGetir() async {
    try {
      final kaynaklar = await NativeBridge.instance.getSources();
      dynamic kaynak;
      for (final k in kaynaklar) {
        if (k.id == widget.channel.sourceId) {
          kaynak = k;
          break;
        }
      }
      if (kaynak == null) throw "kaynak yok";
      if (kaynak.sourceType != SourceType.xtream) throw "api yok";
      final kok = (kaynak.urlOrigin ?? kaynak.url ?? "").trim();
      final kullanici = kaynak.username ?? "";
      final sifre = kaynak.password ?? "";
      if (kok.isEmpty || kullanici.isEmpty) throw "kimlik yok";

      // DUZELTME: Dizilerde kimlik `url` icinde degil `seriesId` alanindadir.
      // Onceden url sayiya cevrilmeye calisiliyordu; url bir yayin adresi
      // oldugu icin her zaman -1 donup "id yok" firlatiliyordu → dizi
      // aciklamalari hic yuklenmiyordu.
      late final int icerikId;
      if (_dizi) {
        icerikId =
            widget.channel.seriesId ??
            int.tryParse(widget.channel.url ?? "") ??
            -1;
      } else {
        icerikId = widget.channel.streamId ?? -1;
      }
      if (icerikId < 0) throw "id yok";

      // DUZELTME: Adres elle birlestirilmiyor. Kaynak zaten player_api.php
      // iceriyorsa ".../player_api.php/player_api.php" olusup 404 veriyordu.
      final adresler = xtreamApiAdresleri(kok);
      final eylem = _dizi ? "get_series_info" : "get_vod_info";
      final idAnahtar = _dizi ? "series_id" : "vod_id";
      final uri = Uri.parse(adresler.first).replace(
        queryParameters: {
          "username": kullanici,
          "password": sifre,
          "action": eylem,
          idAnahtar: "$icerikId",
        },
      );
      final cevap = await _httpJson(uri.toString());
      final bilgi = cevap["info"];
      if (bilgi is! Map) throw "bilgi yok";
      if (mounted) {
        setState(() {
          _bilgi = bilgi.cast<String, dynamic>();
          _yukleniyor = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _bilgi = null;
          _yukleniyor = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>> _httpJson(String url) async {
    final istemci = HttpClient();
    istemci.connectionTimeout = const Duration(seconds: 8);
    // DUZELTME: IPTV panellerinin cogu ozel veya suresi dolmus sertifika
    // kullanir. Bu satir olmadan istek patlar ve aciklama hic yuklenmez.
    // (xtream_bilgi.dart'ta zaten vardi; burada unutulmustu.)
    istemci.badCertificateCallback = (cert, host, port) => true;
    try {
      final istek = await istemci
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      final cevap = await istek.close().timeout(const Duration(seconds: 10));
      // Durum kodu kontrolu: hata sayfasi (HTML) JSON sanilip cozulmeye
      // calisilmasin.
      if (cevap.statusCode < 200 || cevap.statusCode >= 300) {
        throw "HTTP ${cevap.statusCode}";
      }
      final govde = await cevap
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      return jsonDecode(govde) as Map<String, dynamic>;
    } finally {
      istemci.close();
    }
  }

  // ---------- bilgi yardımcıları ----------

  String? _metin(dynamic deger) {
    final s = deger?.toString().trim();
    if (s == null || s.isEmpty || s == "null" || s == "0" || s == "0000") {
      return null;
    }
    return s;
  }

  String? get _yil {
    final ham = _metin(
          _bilgi?[_dizi ? "releaseDate" : "year"] ?? _bilgi?["releaseDate"],
        ) ??
        _metin(_bilgi?["year"]);
    if (ham == null) return null;
    final eslesme = RegExp(r"\d{4}").firstMatch(ham);
    return eslesme?.group(0);
  }

  String? get _tur {
    final ham = _metin(_bilgi?["genre"]);
    if (ham == null) return null;
    return ham.split(",").map((e) => e.trim()).take(2).join(", ");
  }

  String? get _sure {
    if (_dizi) return null;
    final sn = int.tryParse(_metin(_bilgi?["duration"]) ?? "");
    if (sn == null || sn <= 0) return null;
    final saat = sn ~/ 3600;
    final dk = (sn % 3600) ~/ 60;
    return saat > 0 ? "$saat s $dk dk" : "$dk dk";
  }

  String? get _puan {
    final p = double.tryParse(_metin(_bilgi?["rating"]) ?? "");
    if (p == null || p <= 0) return null;
    return "★ ${p.toStringAsFixed(1)}";
  }

  String? get _aciklama => _metin(_bilgi?["plot"] ?? _bilgi?["description"]);

  String? get _kapak =>
      _metin(_bilgi?["movie_image"] ?? _bilgi?["cover"]) ??
      widget.channel.image;

  String get _metaYazi {
    final parcalar = <String>[
      if (_yil != null) _yil!,
      if (_tur != null) _tur!,
      if (_sure != null) _sure!,
      if (_puan != null) _puan!,
    ];
    if (parcalar.isEmpty && widget.channel.group != null) {
      parcalar.add(widget.channel.group!);
    }
    return parcalar.join("  ·  ");
  }

  // ---------- eylemler ----------

  Future<void> _oynat() async {
    final kanal = widget.channel;
    if (kanal.id == null) return;
    if (_dizi) {
      await _bolumlereGit();
      return;
    }
    try {
      final ayarlar = await NativeBridge.instance.getSettings();
      await NativeBridge.instance.addLastWatched(kanal.id!);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Platform.isAndroid
              ? ExoPlayerScreen(
                  channel: kanal,
                  settings: ayarlar,
                  meta: _metaYazi,
                )
              : Player(channel: kanal, settings: ayarlar),
        ),
      );
    } catch (e) {
      if (mounted) Error.handleError(context, e.toString());
    }
  }

  Future<void> _bolumlereGit() async {
    final kanal = widget.channel;
    final diziId = int.tryParse(kanal.url ?? "");
    if (diziId == null) {
      if (mounted) {
        Error.handleError(context, L.t("gecersiz_dizi"));
      }
      return;
    }
    await Error.tryAsync(
      () async {
        await NativeBridge.instance.getEpisodes(
          diziId,
          kanal.sourceId,
          kanal.image,
        );
        refreshedSeries.add(diziId);
      },
      context,
      null,
      true,
      false,
    );
    if (!mounted) return;
    widget.setNode(
      Node(
        id: diziId,
        name: kanal.name,
        type: fromMediaType(MediaType.serie),
      ),
    );
  }

  Future<void> _favoriDegistir() async {
    final id = widget.channel.id;
    if (id == null) return;
    await Error.tryAsyncNoLoading(() async {
      await NativeBridge.instance.favorite(id, !widget.channel.favorite);
      if (!mounted) return;
      setState(() {
        widget.channel.favorite = !widget.channel.favorite;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L.t("fav_guncellendi")),
          duration: Duration(milliseconds: 500),
        ),
      );
    }, context);
  }

  // ---------- arayüz ----------

  Widget _kapakKutusu(double genislik) {
    final kapak = _kapak;
    return Container(
      width: genislik,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: P.shadowSoft, blurRadius: 24, spreadRadius: 2),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: kapak != null
              ? CachedNetworkImage(
                  imageUrl: kapak,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _kapakYedek(),
                )
              : _kapakYedek(),
        ),
      ),
    );
  }

  Widget _kapakYedek() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: P.placeholderGrad,
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.movie_rounded,
          size: 54,
          color: Colors.white24,
        ),
      ),
    );
  }

  Widget _bilgiAlani() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.channel.name,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        if (_yukleniyor)
          Text(
            L.t("bilgi_yukleniyor"),
            style: TextStyle(fontSize: 12.5, color: P.textTertiary),
          )
        else if (_metaYazi.isNotEmpty)
          Text(
            _metaYazi,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: P.textSecondary,
            ),
          ),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: _aciklama != null
                ? Text(
                    _aciklama!,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.55,
                      color: P.textSecondary,
                    ),
                  )
                : Text(
                    _dizi
                        ? L.t("aciklama_dizi")
                        : L.t("aciklama_film"),
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: P.textTertiary,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        _duymeSatiri(),
      ],
    );
  }

  Widget _duymeSatiri() {
    final odak = _oynatOdakli;
    return Row(
      children: [
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            // PERFORMANS: Animasyonlu blur'lu gölge kaldırıldı (her karede
            // yeniden hesaplanıyordu → takılma). Odak artık kenarlıkla.
            // foregroundDecoration + sabit kalınlık → düzen kaymaz.
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: odak ? P.brandLight : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                focusNode: _oynatFocus,
                autofocus: AppMode.isTv,
                onTap: _oynat,
                child: Ink(
                  height: 52,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [P.brandDark, P.brand],
                    ),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _dizi ? L.t("bolumler") : L.t("oynat"),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 52,
          height: 52,
          child: Material(
            color: P.surfaceRaised,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _favoriDegistir,
              child: Center(
                child: Icon(
                  widget.channel.favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 26,
                  color: widget.channel.favorite
                      ? P.favoriIkon
                      : P.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final yatay =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _dizi ? L.t("dizi_detay") : L.t("film_detay"),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, kisitlar) {
            if (yatay) {
              final kapakGenislik =
                  (kisitlar.maxWidth * 0.24).clamp(150.0, 300.0).toDouble();
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _kapakKutusu(kapakGenislik),
                    const SizedBox(width: 26),
                    Expanded(child: _bilgiAlani()),
                  ],
                ),
              );
            }
            final ekranYukseklik = kisitlar.maxHeight;
            final posterAlani = (ekranYukseklik * 0.42).clamp(160.0, 340.0).toDouble();
            // Kapak 2:3 oranli: hem genislige hem poster alanina sigdir.
            final genislikSiniri = (posterAlani / 1.5).clamp(140.0, 260.0).toDouble();
            final kapakGenislik = kisitlar.maxWidth * 0.52 < genislikSiniri
                ? kisitlar.maxWidth * 0.52
                : genislikSiniri;
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Column(
                children: [
                  SizedBox(
                    height: posterAlani,
                    child: Center(child: _kapakKutusu(kapakGenislik)),
                  ),
                  const SizedBox(height: 16),
                  Expanded(child: _bilgiAlani()),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
