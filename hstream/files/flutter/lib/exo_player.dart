import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:open_tv/l10n.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:open_tv/error.dart';
import 'package:open_tv/hstream_bolum.dart';
import 'package:open_tv/models/channel.dart';
import 'package:open_tv/models/channel_http_headers.dart';
import 'package:open_tv/models/filters.dart';
import 'package:open_tv/models/media_type.dart';
import 'package:open_tv/models/settings.dart';
import 'package:open_tv/models/sort_type.dart';
import 'package:open_tv/models/view_type.dart';
import 'package:open_tv/native_bridge.dart';

/// /10.9 — HStream oynatıcı ekranı (Android).
/// - YATAY: tam ekran video + HStream kontrolleri (native XML) + sağ altta
///   SONRAKİ BÖLÜM rozeti (yalnız dizi bölümü izlerken).
/// - DİKEY: video üstte 16:9; altındaki panelde başlık/bilgi + favori +
///   BÖLÜM ŞERİDİ (sezon chip'i + numaralı kutucuklar) + SONRAKİ BÖLÜM
///   düğmesi + L.t("tam_ekran") (onaylı mockup).
/// - BÖLÜM SONU: 5 sn geri sayımlı SIRADAKİ BÖLÜM kartı; onaylanmazsa
///   otomatik geçiş. Bölüm değişince oynatıcı KAPANMAZ, aynı görünüme
///   yeni adres yüklenir (native loadUrl).
/// - Saat: dikeyde görünür (video tavana dayanmaz), yatayda gizli.
class ExoPlayerScreen extends StatefulWidget {
  final Channel channel;
  final Settings settings;
  final String? meta;
  final String? konumEtiketi;
  // : dizi/sezon kimligi ACIKCA gelir - kanal nesnesinde seriestId
  // eksik/null olsa bile bolum gecisi calisir (listeyi getiren sorgudan)
  final int? diziId;
  final int? sezonId;
  // : bolum listesi EKRANDAN DOGRUDAN gelir (sorgu yok)
  final List<Channel>? bolumler;
  const ExoPlayerScreen({
    super.key,
    required this.channel,
    required this.settings,
    this.meta,
    this.konumEtiketi,
    this.diziId,
    this.sezonId,
    this.bolumler,
  });

  @override
  State<ExoPlayerScreen> createState() => _ExoPlayerScreenState();
}

class _ExoPlayerScreenState extends State<ExoPlayerScreen> {
  static const _viewType = "dev.fredol.open_tv/exoplayer";

  MethodChannel? _channel;
  bool _exiting = false;
  bool _ready = false;
  Map<String, dynamic> _creationParams = const {};

  // : oynatılan içerik bölüm geçişinde DEĞİŞEBİLİR
  late Channel _kanal = widget.channel;

  // bölüm şeridi durumu
  List<Channel> _sezonlar = [];
  List<Channel> _bolumler = [];
  int? _aktifSezonId;
  final Set<int> _izlenenIds = {};
  bool _seritHazir = false;
  bool _seritHata = false;  // : hata gorunur olsun (sessiz kalma yok)
  bool _gecisBasladi = false;

  // bölüm sonu kartı
  bool _kartAcik = false;
  int _kalanSn = 5;
  Timer? _kartSayac;

  // : son uygulanan yön (sistem çubuğu güncellemesi için)
  bool? _sonYatay;

  bool get _isLive => _kanal.mediaType == MediaType.livestream;

  /// Bölüm modu: bu kanal bir dizinin BÖLÜMÜ (seriesId dolu; mediaType movie
  /// olarak kayıtlı — upstream böyle saklar).
  bool get _bolumModu =>
      _kanal.seriesId != null || // : sql.rs artik series_id dondurur
      widget.diziId != null || // 
      (widget.bolumler?.isNotEmpty ?? false); // : ekrandan gelen liste

  // : rozet dizi bolumu izleniyorsa GOSTERILIR - liste yuklenene
  // kadar beklenmez (yatayda "hicbir sey yok" durumunu bitirir)
  bool get _bolumRozeti =>
      _bolumModu && (_bolumler.isEmpty || _sonrakiBolum != null);

  Channel? get _sonrakiBolum {
    if (!_bolumModu) return null;
    final i = _bolumler.indexWhere((b) => b.id == _kanal.id);
    if (i < 0 || i + 1 >= _bolumler.length) return null;
    return _bolumler[i + 1];
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _kartSayac?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _init() async {
    _bolumleriYukle(); // paralel; şerit hazır olunca panel kendini günceller
    final ChannelHttpHeaders? headers = (await Error.tryAsyncNoLoading(() async {
      return await NativeBridge.instance.getChannelHeaders(_kanal.id!);
    }, context)).data;
    final seconds = _kanal.mediaType == MediaType.movie
        ? (await Error.tryAsyncNoLoading(() async {
            return await NativeBridge.instance.getMoviePosition(_kanal.id!);
          }, context)).data
        : null;
    if (!mounted) return;
    setState(() {
      _creationParams = {
        "url": _kanal.url,
        "isLive": _isLive,
        "startPositionMs": (seconds ?? 0) * 1000,
        "title": _kanal.name,
        "referer": headers?.referrer,
        "origin": headers?.httpOrigin,
        "userAgent": headers?.userAgent,
        "favorite": _kanal.favorite,
        "channelId": _kanal.id,
        "meta": widget.meta,
        "positionLabel": widget.konumEtiketi,
        "hasNext": _sonrakiBolum != null,
      };
      _ready = true;
    });
  }

  // ---------- bölüm verisi ----------

  Future<void> _bolumleriYukle() async {
    if (!_bolumModu) return;

    //  - BIRINCI KAYNAK: ekrandan dogrudan tasinan bolum listesi.
    // Senin sectigin bolum bu listedeyse serit ANINDA hazirdir; veritabani
    // sorgusu, kimlik tasma, bekleme YOK. (Liste arayuzu degil - sadece veri.)
    final tasinan = widget.bolumler;
    if (tasinan != null && tasinan.isNotEmpty) {
      var listede = false;
      for (final b in tasinan) {
        if (b.id == _kanal.id) {
          listede = true;
          break;
        }
      }
      if (listede && mounted) {
        setState(() {
          _bolumler = tasinan;
          _seritHazir = true;
          _seritHata = false;
          if (_kanal.id != null) _izlenenIds.add(_kanal.id!);
        });
        _channel?.invokeMethod("setNextEnabled", _bolumRozeti);
        return;
      }
    }

    // IKINCI KAYNAK (fallback): veritabani sorgusu - eski yontem
    final diziId = _kanal.seriesId ?? widget.diziId!;
    final baslangicSezon = _kanal.seasonId ?? widget.sezonId;
    try {
      final sourceIds = await NativeBridge.instance.getEnabledSourcesMinimal();
      if (!mounted) return;

      // 1. sezon listesi - search_series: seriesId dolu, season bos
      final sezonFiltre = Filters(
        viewType: ViewType.all,
        sourceIds: sourceIds,
        mediaTypes: const [
          MediaType.livestream,
          MediaType.movie,
          MediaType.serie,
        ],
        sort: SortType.provider,
      );
      sezonFiltre.seriesId = diziId;
      final sezonlar = await NativeBridge.instance.getChannels(sezonFiltre);
      if (!mounted) return;

      _sezonlar = sezonlar;
      _aktifSezonId = baslangicSezon ??
          (sezonlar.isNotEmpty ? sezonlar.first.id : null);
      if (_aktifSezonId != null) {
        await _sezonBolumleriYukle(diziId, _aktifSezonId!);
      } else if (_bolumler.isEmpty) {
        // : sezon kaydi yoksa bile mevcut sezonun bolumlerini cek
        await _sezonBolumleriYukle(diziId, -1);
      }

      // 2. izilenmis isaretleri - gecmisten bu dizinin bolumleri
      final gecmisFiltre = Filters(
        viewType: ViewType.history,
        sourceIds: sourceIds,
        mediaTypes: const [
          MediaType.livestream,
          MediaType.movie,
          MediaType.serie,
        ],
        sort: SortType.provider,
      );
      final gecmis = await NativeBridge.instance.getChannels(gecmisFiltre);
      if (!mounted) return;
      _izlenenIds
        ..clear()
        ..addAll(
          gecmis.where((c) => c.seriesId == diziId).map((c) => c.id!),
        );
      _izlenenIds.add(_kanal.id!);

      // : bolum listesi bos donduyse bu da sorundur - sessiz kalma
      // yok, "Bolumler yuklenemedi" satiri cikar (nedeni gormek icin).
      if (_bolumler.isEmpty) {
        setState(() {
          _seritHazir = false;
          _seritHata = true;
        });
        _channel?.invokeMethod(
          "showToast",
          "Bölüm listesi boş (dizi kodu: " + diziId.toString() + ")",
        );
      } else {
        setState(() {
          _seritHazir = true;
          _seritHata = false;
        });
      }
      _channel?.invokeMethod("setNextEnabled", _bolumRozeti);
    } catch (e) {
      // şerit çıkamazsa oynatma etkilenmez; hata EKRANA toast olarak gelir
      // ( - yatayda da gorunur, artik tahmin yok)
      debugPrint('bolum seridi yuklenemedi: ' + e.toString());
      if (mounted) {
        setState(() {
          _seritHazir = false;
          _seritHata = true;
        });
        _channel?.invokeMethod(
          "showToast",
          "Bölümler yüklenemedi: " + e.toString(),
        );
      }
    }
  }

  Future<void> _sezonBolumleriYukle(int diziId, int sezonId) async {
    final sourceIds = await NativeBridge.instance.getEnabledSourcesMinimal();
    // -1 = sezon satiri yok: bolumu zaten izlenen kanalin sezon_id'sinden al
    final hedefSezon = sezonId == -1 ? _kanal.seasonId : sezonId;
    if (hedefSezon == null) return;
    final filtre = Filters(
      viewType: ViewType.all,
      sourceIds: sourceIds,
      mediaTypes: const [
        MediaType.livestream,
        MediaType.movie,
        MediaType.serie,
      ],
      sort: SortType.provider,
    );
    filtre.seriesId = diziId;
    filtre.seasonId = hedefSezon;
    final bolumler = await NativeBridge.instance.getChannels(filtre);
    if (!mounted) return;
    setState(() => _bolumler = bolumler);
  }

  Future<void> _sezonDegistir(Channel sezon) async {
    final diziId = _kanal.seriesId;
    final sezonId = sezon.id;
    if (diziId == null || sezonId == null) return;
    setState(() {
      _aktifSezonId = sezonId;
      _bolumler = [];
    });
    try {
      await _sezonBolumleriYukle(diziId, sezonId);
    } catch (_) {}
    _channel?.invokeMethod("setNextEnabled", _bolumRozeti);
  }

  // ---------- bölüm geçişi (oynatıcı KAPANMAZ) ----------

  String? _bolumMeta(Channel bolum) {
    Channel? sezon;
    for (final s in _sezonlar) {
      if (s.id == _aktifSezonId) {
        sezon = s;
        break;
      }
    }
    final parcalar = <String>[
      if (sezon != null) sezonAdiTr(sezon),
      if (bolum.episodeNum != null) "${L.t('bolum_n')} ${bolum.episodeNum}",
    ];
    return parcalar.isEmpty ? null : parcalar.join(' · ');
  }

  Future<void> _bolumSec(Channel bolum) {
    if (bolum.id == _kanal.id) return Future.value();
    return _bolumDegistir(bolum);
  }

  Future<void> _bolumDegistir(Channel bolum) async {
    if (_gecisBasladi || bolum.id == null || bolum.url == null) return;
    _gecisBasladi = true;
    try {
      // daha önce yarıda kalan bölüme kaldığı yerden devam (episodes = movie)
      final sn =
          (await Error.tryAsyncNoLoading(() async {
            return await NativeBridge.instance.getMoviePosition(bolum.id!);
          }, context)).data ??
          0;
      await NativeBridge.instance.addLastWatched(bolum.id!);
      if (!mounted) return;
      _kartKapat();
      setState(() {
        _kanal = bolum;
        _izlenenIds.add(bolum.id!);
      });
      _channel?.invokeMethod("loadUrl", {
        "url": bolum.url,
        "title": bolum.name,
        "startPositionMs": sn * 1000,
        "favorite": bolum.favorite,
        "meta": _bolumMeta(bolum),
      });
      _channel?.invokeMethod("setNextEnabled", _bolumRozeti);
    } catch (_) {
    } finally {
      _gecisBasladi = false;
    }
  }

  // ---------- bölüm sonu kartı ----------

  void _bolumBitti() {
    final sonraki = _sonrakiBolum;
    if (sonraki == null || _kartAcik || !mounted) return;
    setState(() {
      _kartAcik = true;
      _kalanSn = 5;
    });
    _kartSayac?.cancel();
    _kartSayac = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_kalanSn <= 1) {
        t.cancel();
        _kartKapat();
        _bolumDegistir(sonraki);
      } else {
        setState(() => _kalanSn--);
      }
    });
  }

  void _kartKapat() {
    _kartSayac?.cancel();
    _kartSayac = null;
    if (_kartAcik && mounted) setState(() => _kartAcik = false);
  }

  // ---------- platform kanalı ----------

  void _onPlatformViewCreated(int id) {
    _channel = MethodChannel("dev.fredol.open_tv/exoplayer_$id");
    // : rozet kanal dogar dogmaz ayarlanir - diger kontrollerle
    // AYNI ANDA gorunur (gecikmeli pop-in YOK)
    _channel!.invokeMethod("setNextEnabled", _bolumRozeti);
    _channel!.setMethodCallHandler((call) async {
      switch (call.method) {
        case "onBack":
          _onExit();
          return null;
        case "toggleFullscreen":
          _tamEkranDegistir();
          return null;
        case "nextEpisode":
          final sonraki = _sonrakiBolum;
          if (sonraki != null) {
            _bolumDegistir(sonraki);
          } else {
            // liste henuz hazir degil: tekrar dene + kullaniciya soyle
            _bolumleriYukle();
            _channel?.invokeMethod(
              "showToast",
              "Bölüm listesi hazırlanıyor, tekrar deneyin",
            );
          }
          return null;
        case "onEnded":
          _bolumBitti();
          return null;
        case "toggleFavorite":
          final id = _kanal.id;
          if (id != null) {
            try {
              await NativeBridge.instance.favorite(id, !_kanal.favorite);
              if (mounted) {
                setState(() => _kanal.favorite = !_kanal.favorite);
              }
            } catch (_) {}
          }
          return _kanal.favorite;
      }
      return null;
    });
    // görünüm sonradan oluşturulduysa rozeti güncelle (: gecikmeli
    // ikinci deneme - bolum listesi view'dan SONRA biterse rozet yine gelsin)
    _channel?.invokeMethod("setNextEnabled", _bolumRozeti);
    Timer(const Duration(milliseconds: 600), () {
      _channel?.invokeMethod("setNextEnabled", _bolumRozeti);
    });
    // : 2 sn'lik gec deneme KALDIRILDI - rozet kanal dogar dogmaz
    // senkronlanir (yukarida); kontrollerle AYNI ANDA gorunur.
  }

  Future<void> _onExit() async {
    if (_exiting) return;
    _exiting = true;
    _kartKapat();
    if (_kanal.mediaType == MediaType.movie && _channel != null) {
      try {
        final posMs = await _channel!.invokeMethod<int>("getPosition") ?? 0;
        await NativeBridge.instance.setMoviePosition(_kanal.id!, posMs ~/ 1000);
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // ---------- tam ekran ----------

  void _tamEkranDegistir() {
    final boyut = MediaQuery.of(context).size;
    final yatay = boyut.width > boyut.height;
    if (yatay) {
      // tam ekrandan cik: dikey panele ACIKCA don (kilit acmak yetmiyordu -
      // telefon yatay tutulunca ekranda hicbir sey degismiyordu)
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      _channel?.invokeMethod("updateFullscreenIcon", true);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      _channel?.invokeMethod("updateFullscreenIcon", false);
    }
  }

  // ---------- arayüz ----------

  @override
  Widget build(BuildContext context) {
    final boyut = MediaQuery.of(context).size;
    final yatay = boyut.width > boyut.height;
    if (_sonYatay != yatay) {
      _sonYatay = yatay;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        SystemChrome.setEnabledSystemUIMode(
          yatay ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
        );
        // : telefonu ceirince tam ekran ikonu da duruma gecsin
        _channel?.invokeMethod("updateFullscreenIcon", !yatay);
      });
    }
    final videoYukseklik = yatay ? boyut.height : boyut.width * 0.68;  // : dikeyde player alani buyudu
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _onExit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          // : SafeArea sol/sagi VARSAYILAN olarak kirpar -
          // delik tarafi videodan catir catir yedigi icin video hicbir
          // modda ortalanmiyordu. Yanlar artik ACIK: video tam fiziksel
          // ekrana yayilir ve ortalanir; delik kenar siyah bantta kalir.
          // : ust de ACILDI - video tepedeki olu alana buyur,
          // fiziksel ekranin en tepesinden baslar (saat video ustune biner,
          // gorunur kalir). Butonlarin kullanmadigi bosluk kapanir.
          left: false,
          right: false,
          top: false,
          bottom: false,
          child: Stack(
            children: [
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: videoYukseklik,
                    child: _ready
                        ? _buildPlatformView()
                        : const SizedBox.shrink(),
                  ),
                  if (!yatay) Expanded(child: _dikeyPanel()),
                ],
              ),
              if (_kartAcik && _sonrakiBolum != null)
                Positioned.fill(
                  child: Container(
                    color: const Color(0xD90A0A16),
                    child: Center(
                      child: HStreamSonrakiKarti(
                        bolum: _sonrakiBolum!,
                        altYazi: _bolumMeta(_sonrakiBolum!),
                        kalanSn: _kalanSn,
                        onOynat: () => _bolumDegistir(_sonrakiBolum!),
                        onIptal: _kartKapat,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dikeyPanel() {
    final sonraki = _sonrakiBolum;
    return Container(
      width: double.infinity,
      color: const Color(0xFF0A0A16),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _kanal.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _bolumModu
                          ? (_bolumMeta(_kanal) ?? widget.meta ?? '')
                          : (widget.meta ?? ''),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF9AA2C4),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _favoriDugmesi(),
            ],
          ),
          // BÖLÜM ŞERİDİ (yalnız dizi bölümlerinde)
          if (_bolumModu && !_seritHazir && !_seritHata) ...[
            const SizedBox(height: 10),
            Text(
              L.t('bolum_yukleniyor'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF8B93B5)),
            ),
          ],
          if (_bolumModu && _seritHazir && _bolumler.isNotEmpty) ...[
            const SizedBox(height: 10),
            HStreamBolumSeridi(
              key: ValueKey('serit_$_aktifSezonId'),
              sezonlar: _sezonlar,
              bolumler: _bolumler,
              aktifSezonId: _aktifSezonId,
              seciliBolumId: _kanal.id,
              izlenenIds: _izlenenIds,
              onSezonDegistir: _sezonDegistir,
              onBolumSec: _bolumSec,
            ),
          ],
          if (_bolumModu && !_seritHazir && _seritHata) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    L.t('bolum_yuklenemedi'),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF9AA2C4)),
                  ),
                ),
                TextButton(
                  onPressed: _bolumleriYukle,
                  child: Text(L.t('tekrar_dene')),
                ),
              ],
            ),
          ],
          // SONRAKİ BÖLÜM düğmesi
          if (_bolumModu && sonraki != null) ...[
            const SizedBox(height: 10),
            _sonrakiBolumDugmesi(sonraki),
          ],
          const Spacer(),
          Center(
            child: Column(
              children: [
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _tamEkranDegistir,
                    child: Ink(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 11,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF5642D6), Color(0xFF7A52E0)],
                        ),
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.screen_rotation,
                            color: Colors.white,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            L.t("tam_ekran"),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  L.t("yatay_cevir"),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF8B93B5)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sonrakiBolumDugmesi(Channel sonraki) {
    final etiket = sonraki.episodeNum != null
        ? '${L.t("bolum_n")} ${sonraki.episodeNum}'
        : sonraki.name;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _bolumDegistir(sonraki),
        child: Ink(
          width: double.infinity,
          height: 42,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7A52E0), Color(0xFF5642D6)],
            ),
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.skip_next_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  L.t('sonraki_bolum'),
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    letterSpacing: .4,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  etiket,
                  style: const TextStyle(
                    color: Color(0xFFD8CDFF),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _favoriDugmesi() {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: const Color(0xFF1D1F2F),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            final id = _kanal.id;
            if (id == null) return;
            try {
              await NativeBridge.instance.favorite(id, !_kanal.favorite);
            } catch (_) {}
            if (mounted) {
              setState(() => _kanal.favorite = !_kanal.favorite);
            }
          },
          child: Center(
            child: Icon(
              _kanal.favorite ? Icons.favorite : Icons.favorite_border,
              size: 24,
              color: _kanal.favorite
                  ? const Color(0xFFF472B6)
                  : const Color(0xFF9AA2C4),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlatformView() {
    return PlatformViewLink(
      viewType: _viewType,
      surfaceFactory: (context, controller) {
        return AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        );
      },
      onCreatePlatformView: (params) {
        final controller = PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: _viewType,
          layoutDirection: TextDirection.ltr,
          creationParams: _creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () => params.onFocusChanged(true),
        );
        controller.addOnPlatformViewCreatedListener(params.onPlatformViewCreated);
        controller.addOnPlatformViewCreatedListener(_onPlatformViewCreated);
        controller.create();
        return controller;
      },
    );
  }
}
