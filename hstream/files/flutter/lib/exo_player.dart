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
import 'package:open_tv/player_preferences.dart';

import 'package:open_tv/palet.dart';
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

class _ExoPlayerScreenState extends State<ExoPlayerScreen>
    with WidgetsBindingObserver {
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

  // : uyku zamanlayıcısı — süre DART tarafında sayılır, dolunca native
  // duraklatılır ve oynatıcıdan çıkılır. Durum ekranda kalan süre olarak
  // tutulur (native yalnızca seçimi iletir, geri sayım burada).
  //
  // : KASMA (STUTTER) DÜZELTMESİ — geri sayım ARTIK `setState` ÇAĞIRMAZ.
  // Önceden `Timer.periodic` her saniye geri sayımı azaltıp `setState`
  // çağırıyordu; bu, `_dikeyPanel()`'in TAMAMINI (bölüm şeridi, favori,
  // "sonraki bölüm" düğmesi, çipler) her saniye yeniden kuruyordu.
  // Dikey panel kaydırılırken saniyede bir tam rebuild = gözle görülür
  // kasma. Çözüm: sayacı `ValueNotifier`'a taşıdık; yalnızca uyku ÇİPİ
  // `ValueListenableBuilder` ile kendini tazeler, panelin geri kalanı
  // etkilenmez. `setState` yalnızca uyku BAŞLARKEN/BİTİRKEN çağrılır.
  Timer? _uykuSayac;
  final ValueNotifier<int> _uykuKalan = ValueNotifier<int>(0);
  int _uykuToplamDk = 0;
  // `_hizliIslemler()` canlı yayında çip üretmez; bunu panel dışında
  // hesaplamak tekrar derlemeyi ucuzlatır.
  bool get _uykuAktif => _uykuKalan.value > 0;

  // : oynatma hızı — dikey paneldeki hızlı işlem çipinden değiştirilir.
  // Native oynatıcıya "setSpeed" ile bildirilir; bölüm geçişinde korunur.
  double _oynatmaHizi = 1.0;

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
    // : KALINAN DAKİKA — yaşam döngüsü dinlenir ki uygulama arka plana
    // atılınca (PiP penceresi kapatılınca, home tuşu) konum kaydedilebilsin.
    // Aksi halde yalnızca "geri" tuşuna basılınca yazılıyordu ve Son
    // İzlenenler'deki rozet eski konumu gösteriyordu.
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _kartSayac?.cancel();
    _uykuSayac?.cancel();
    _konumSayac?.cancel();
    _uykuKalan.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // : KALINAN DAKİKA — uygulama öne/arkaya geçişleri. Yaşam döngüsü
  // olayları çok sık tetiklenir (diyalog, PiP geçişi, ekran kilidi), bu
  // yüzden yazım 5 saniyede bir ile sınırlanır.
  int _sonKonumKaydiMs = 0;
  // : KALINAN DAKİKA — düzenli aralıklı kayıt. Uygulama aniden sonlanırsa
  // (PiP penceresi kapatma, arka planda öldürülme) yaşam döngüsü olayı
  // gelmeyebilir; 20 saniyelik yazım rozeti en fazla 20 sn geride bırakır.
  Timer? _konumSayac;
  // Aynı değeri tekrar tekrar yazmayı önler (duraklatılmış videoda
  // saniyede bir FFI çağrısı yapılmasın).
  int _sonKaydedilenSn = -1;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.inactive &&
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden) {
      return;
    }
    final simdi = DateTime.now().millisecondsSinceEpoch;
    if (simdi - _sonKonumKaydiMs < 5000) return;
    _sonKonumKaydiMs = simdi;
    _konumKaydet();
  }

  // : konum yazımı — film ve bölümler `media_type = movie` olarak
  // saklandığı için ikisi de kapsanır; canlı yayında konum kavramı yok.
  // `await` EDİLMEZ: çağıran akışı (çıkış, bölüm geçişi) geciktirmemeli.
  Future<void> _konumKaydet() async {
    final id = _kanal.id;
    final ch = _channel;
    if (id == null || ch == null) return;
    if (_kanal.mediaType != MediaType.movie) return;
    try {
      final posMs = await ch.invokeMethod<int>("getPosition") ?? 0;
      final sn = posMs ~/ 1000;
      if (sn > 0 && sn != _sonKaydedilenSn) {
        _sonKaydedilenSn = sn;
        await NativeBridge.instance.setMoviePosition(id, sn);
      }
    } catch (_) {
      // konum yazılamadı — oynatmayı etkilemez
    }
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
        // : oynatıcı tercihleri (SharedPreferences) — native taraf bunları
        // kurulumda uygular: tampon süresi, altyazı boyutu, PiP izni
        "tamponSn": PlayerPreferences.tamponSn,
        "altyaziSp": PlayerPreferences.altyaziSp,
        "pipAcik": PlayerPreferences.pipAcik,
      };
      _ready = true;
    });
    // : KALINAN DAKİKA — film/bölüm izlenirken konum düzenli aralıklarla
    // yazılır (20 sn). Yalnızca film/bölümde çalışır; canlı yayında
    // konum kavramı olmadığı için sayaç hiç kurulmaz.
    if (_kanal.mediaType == MediaType.movie) {
      _konumSayac?.cancel();
      _konumSayac = Timer.periodic(
        const Duration(seconds: 20),
        (_) => _konumKaydet(),
      );
    }
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
      // : KALINAN DAKİKA — bölüm değişmeden ÖNCE, izlenmekte olan bölümün
      // konumu yazılır. Aksi halde Son İzlenenler'de o bölüm "baştan
      // başlanmamış" gibi görünüyordu (konum yalnızca oynatıcıdan tam
      // çıkışta kaydediliyordu).
      await _konumKaydet();
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
      // : KALINAN DAKİKA — yeni bölümün konumu henüz yazılmadı; "aynı
      // değeri tekrar yazma" koruması sıfırlanır.
      _sonKaydedilenSn = -1;
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

  // : uyku zamanlayıcısı — native menüden seçilen dakika ile başlar.
  // Süre DART'ta sayılır; dolunca yayın duraklatılır ve oynatıcıdan çıkılır.
  // 0 veya negatif değer = iptal.
  void _uykuBaslat(int dakika) {
    _uykuSayac?.cancel();
    if (dakika <= 0) {
      // : iptal — `setState` YALNIZCA burada (bir kerelik) gerekir, çünkü
      // çipin vurgu durumu ve panel yerleşimi değişir.
      _uykuKalan.value = 0;
      if (mounted) {
        setState(() => _uykuToplamDk = 0);
      }
      _channel?.invokeMethod("showToast", "Uyku zamanlayıcısı iptal edildi");
      return;
    }
    _uykuKalan.value = dakika * 60;
    if (mounted) {
      setState(() => _uykuToplamDk = dakika);
    }
    _channel?.invokeMethod(
      "showToast",
      "Uyku zamanlayıcısı: $dakika dakika",
    );
    // : her saniye yalnızca ValueNotifier güncellenir — panel YENİDEN
    // KURULMAZ. Kasma bu yüzden ortadan kalkar.
    _uykuSayac = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final kalan = _uykuKalan.value - 1;
      if (kalan <= 0) {
        t.cancel();
        _uykuKalan.value = 0;
        if (mounted) {
          setState(() => _uykuToplamDk = 0);
        }
        _uykuDoldu();
        return;
      }
      _uykuKalan.value = kalan;
    });
  }

  // : süre doldu — yayını duraklat, oynatıcıdan çık
  void _uykuDoldu() {
    _uykuSayac?.cancel();
    _uykuKalan.value = 0;
    _channel?.invokeMethod("pause", null);
    if (mounted) {
      _onExit();
    }
  }

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
        case "setSleepTimer":
          // native menüden seçilen dakika (int) buraya gelir
          final dk = (call.arguments as num?)?.toInt() ?? 0;
          _uykuBaslat(dk);
          return null;
        case "pipFailed":
          // PiP desteklenmiyorsa kullanıcı sessiz kalmasın
          _channel?.invokeMethod(
            "showToast",
            "Bu cihazda resim içinde resim kullanılamıyor",
          );
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
    // : KALINAN DAKİKA — film VE bölüm (ikisi de media_type=movie) konumu
    // yazılır; "Son İzlenenler" rozeti buradan beslenir.
    await _konumKaydet();
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
                  // : PLATFORM VIEW KATMAN IZOLASYONU —
                  // Video bir platform view (`initExpensiveAndroidView` =
                  // hybrid composition): kendi katmaninda kompozit edilir.
                  // `RepaintBoundary` ile cevrilince Flutter tarafi
                  // yeniden boyandiginda (ornegin alttaki panel kaydirilirken)
                  // video katmaninin boyama kaydi YENIDEN URETILMEZ; yalnizca
                  // var olan katman yeniden kullanilir. Kucuk ama bedava bir
                  // kazanc; davranisi DEGISTIRMEZ.
                  RepaintBoundary(
                    child: SizedBox(
                      width: double.infinity,
                      height: videoYukseklik,
                      child: _ready
                          ? _buildPlatformView()
                          : const SizedBox.shrink(),
                    ),
                  ),
                  if (!yatay) Expanded(child: _dikeyPanel()),
                ],
              ),
              if (_kartAcik && _sonrakiBolum != null)
                Positioned.fill(
                  child: Container(
                    color: P.playerScrim,
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

  // : DOKUNMA GERİ BİLDİRİMİ (ince haptic) — tek yardımcı nokta.
  // `selectionClick()` en hafif sistem titreşimidir: "klik" hissi verir,
  // ses/ritim üretmez. Oynatıcıda YALNIZCA tek büyük eylemde (bölüm
  // atlama) kullanılır; hız/altyazı menü satırları gibi sık dokunulan
  // yerler bilinçli olarak sessiz bırakıldı (dengeli, "az ama öz").
  // `onTapDown` değil `onTapUp`: parmak kaydırma niyetiyle basıldığında
  // boşa titreşmez ve `Navigator` ile yarışmaz.
  void _titre() {
    HapticFeedback.selectionClick();
  }

  // : HIZLI İŞLEM ÇİPLERİ (dikey panel). Native ⋯ menüsünün Dart
  // karşılığı: telefonda da hız / altyazı / uyku / PiP erişilebilir olur.
  // Boş kalırsa (canlı yayın + PiP kapalı) hiç yer kaplamaz.
  Widget _hizliIslemler() {
    final cipler = <Widget>[];
    // : native `pipKullanilabilir()` ile AYNI kosul — artik canli yayin
    // DA dahil. Eskiden `!_isLive` vardi ve canlida PiP cipi hic
    // gorunmuyordu; Android canli video icin de PiP destekler. Tek fark
    // native tarafta: canlida PiP'e 10 sn sarim eylemleri eklenmez.
    final pipVar = PlayerPreferences.pipAcik;
    if (!_isLive) {
      cipler.add(
        _cip(
          icon: Icons.speed_rounded,
          etiket: L.t("hiz"),
          onTap: _hizDialogGoster,
        ),
      );
      cipler.add(
        _cip(
          icon: Icons.subtitles_rounded,
          etiket: L.t("altyazi_boyut"),
          onTap: _altyaziDialogGoster,
        ),
      );
      cipler.add(
        // : UYKU ÇİPİ — saniyede bir YALNIZCA bu çip yeniden kurulur.
        // `ValueListenableBuilder` sayesinde `_dikeyPanel()` ve bölüm
        // şeridi saniyelik rebuild'den muaf kalır (kasma düzeltmesi).
        ValueListenableBuilder<int>(
          valueListenable: _uykuKalan,
          builder: (_, kalan, __) => _cip(
            icon: Icons.bedtime_rounded,
            etiket: kalan > 0 ? _uykuSuresiMetni(kalan) : L.t("uyku"),
            vurgu: kalan > 0,
            onTap: _uykuDialogGoster,
          ),
        ),
      );
    }
    if (pipVar) {
      cipler.add(
        _cip(
          icon: Icons.picture_in_picture_alt_rounded,
          etiket: L.t("pip"),
          onTap: _pipAc,
        ),
      );
    }
    if (cipler.isEmpty) return const SizedBox.shrink();
    // : KAYDIRMA KASMASI (STUTTER) DÜZELTMESİ —
    // Çip satırı yatay kaydırılırken kare başına yapılan iş minimuma
    // indirilir. Önceki hâlde satır bir `SingleChildScrollView` + `Row`
    // idi ve şu üç maliyet her karede ödeniyordu:
    //  1) `Row` tüm çipleri baştan yerleştiriyordu (sabit yükseklik yok),
    //  2) viewport kırpma katmanı (Clip.hardEdge) yeniden uygulanıyordu,
    //  3) Material 3'ün varsayılan **esneme (stretching) taşma efekti**
    //     satırın tamamını ölçekleyip yeniden boyuyordu.
    // Çözüm: sabit yükseklikli `ListView` (öğeler önceden kurulur,
    // `cacheExtent` ile kaydırma sırasında build olmaz), `ScrollConfiguration`
    // ile taşma efekti KAPALI ve katman dışarıdan `RepaintBoundary` ile
    // yalıtılır — kaydırma yalnızca bu katmanı etkiler, panel/bölüm
    // şeridi/video yeniden boyanmaz.
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: RepaintBoundary(
        child: SizedBox(
          height: 44,
          child: ScrollConfiguration(
            // : taşma (overscroll) efekti kapalı — esneme parıltısı/ölçekleme
            // yatay kaydırmada gereksiz kare üretiyordu.
            behavior: ScrollConfiguration.of(context).copyWith(
              overscroll: false,
              physics: const ClampingScrollPhysics(),
            ),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.zero,
              // : kaydırma sırasında çip KURULMASIN (build maliyeti sıfır).
              cacheExtent: 900,
              itemCount: cipler.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              // `Align`: çip doğal yüksekliğini korur (sabit 44'lük satıra
              // yayılıp şişmez), satır içinde dikeyde ortalanır.
              itemBuilder: (_, i) =>
                  Align(alignment: Alignment.centerLeft, child: cipler[i]),
            ),
          ),
        ),
      ),
    );
  }

  // tek çip: ikon + etiket; etkin durumda marka rengiyle vurgulanır
  Widget _cip({
    required IconData icon,
    required String etiket,
    required VoidCallback onTap,
    bool vurgu = false,
  }) {
    return Material(
      color: vurgu ? P.brandSoft : P.surfaceRaised,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: P.pressOverlay,
        highlightColor: P.pressOverlay,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: vurgu ? P.brandLight : P.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                etiket,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: vurgu ? P.brandLight : P.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // : kalan süre metni — değer parametre olarak gelir (notifier'ın
  // güncel değeri); çipin dışında hesaplanır ki rebuild dar kalsın.
  String _uykuSuresiMetni(int kalanSn) {
    final dk = kalanSn ~/ 60;
    final sn = kalanSn % 60;
    if (dk > 0) return '$dk:${sn.toString().padLeft(2, '0')}';
    return '$sn sn';
  }

  // 1.0 -> "1x", 1.25 -> "1.25x", 0.5 -> "0.5x"
  String _hizEtiketi(double h) =>
      h == h.truncateToDouble() ? '${h.toInt()}x' : '${h}x';

  // ---- çip eylemleri (native ⋯ menüsüne gerek kalmadan) ----

  // hız: 0.5x–3x. Native ile aynı aralık; seçim doğrudan kanala yazılır.
  Future<void> _hizDialogGoster() async {
    const hizlar = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
    final secim = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: P.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  L.t("oynatma_hizi"),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: P.textPrimary,
                  ),
                ),
              ),
            ),
            for (final h in hizlar)
              ListTile(
                dense: true,
                title: Text(
                  _hizEtiketi(h),
                  style: TextStyle(
                    color: h == _oynatmaHizi ? P.brandLight : P.textPrimary,
                    fontWeight: h == _oynatmaHizi
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                ),
                trailing: h == _oynatmaHizi
                    ? const Icon(Icons.check_rounded, color: P.brandLight, size: 20)
                    : null,
                onTap: () => Navigator.of(ctx).pop(h),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (secim == null || !mounted) return;
    setState(() => _oynatmaHizi = secim);
    await _channel?.invokeMethod("setSpeed", secim);
  }

  // altyazı boyutu: PlayerPreferences ile aynı seçenekler
  Future<void> _altyaziDialogGoster() async {
    const boyutlar = <int>[18, 24, 30, 36];
    final secim = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: P.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  L.t("altyazi_boyut"),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: P.textPrimary,
                  ),
                ),
              ),
            ),
            for (final b in boyutlar)
              ListTile(
                dense: true,
                title: Text(
                  L.t("altyazi_sp").replaceFirst('%s', '$b'),
                  style: TextStyle(
                    color: b == PlayerPreferences.altyaziSp
                        ? P.brandLight
                        : P.textPrimary,
                    fontWeight: b == PlayerPreferences.altyaziSp
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                ),
                trailing: b == PlayerPreferences.altyaziSp
                    ? const Icon(Icons.check_rounded, color: P.brandLight, size: 20)
                    : null,
                onTap: () => Navigator.of(ctx).pop(b),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (secim == null || !mounted) return;
    await PlayerPreferences.altyaziAyarla(secim);
    await _channel?.invokeMethod("setSubtitleSize", secim);
    if (mounted) setState(() {});
  }

  // uyku: dakika seç (0 = iptal). Süre Dart'ta sayılır, native duraklatır.
  Future<void> _uykuDialogGoster() async {
    const dakikalar = <int>[15, 30, 45, 60, 90];
    final secim = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: P.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    L.t("uyku"),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: P.textPrimary,
                    ),
                  ),
                ),
              ),
              for (final d in dakikalar)
                ListTile(
                  dense: true,
                  title: Text(
                    L.t("dakika_n").replaceFirst('%s', '$d'),
                    style: const TextStyle(
                      color: P.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () => Navigator.of(ctx).pop(d),
                ),
              if (_uykuAktif)
                ListTile(
                  dense: true,
                  title: Text(
                    L.t("uyku_iptal"),
                    style: const TextStyle(
                      color: P.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () => Navigator.of(ctx).pop(0),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (secim == null || !mounted) return;
    _uykuBaslat(secim);
  }

  // PiP: destek yoksa native "pipFailed" yollar, kullanıcı toast görür.
  Future<void> _pipAc() async {
    await _channel?.invokeMethod("enterPip");
  }

  Widget _dikeyPanel() {
    final sonraki = _sonrakiBolum;
    // : KAYDIRMA KASMASI (STUTTER) DÜZELTMESİ — panel artık gerçek bir
    // `ListView` içinde. Önceden `Column` + bir esnek dolgu öğesiydi: içerik
    // ekrana sığmadığında taşıyor, hiçbir şey kaydırılamıyordu ve çip
    // satırını kaydırmak üst katmanı yeniden boyamaya zorluyordu.
    // `ListView` + `RepaintBoundary` kombinasyonu:
    //  - içerik taşarsa doğal olarak kaydırılır (kırpılmaz),
    //  - her bölüm kendi RepaintBoundary'sinde kalır, kaydırma sırasında
    //    yalnız görünen katman boyanır.
    return Container(
      width: double.infinity,
      color: P.bg,
      // : PANEL KAYDIRMA KASMASI — Material 3'ün varsayılan **esneme
      // (stretching) taşma efekti** panelin tamamını (içindeki bölüm şeridi
      // ve çiplerle birlikte) ölçekleyip her karede yeniden boyatıyordu;
      // panelin üstündeki platform view (video) ile birlikte bu, kaydırma
      // sırasında gözle görülür takılmaya yol açıyordu. Taşma efekti
      // kapatılır ve fizik sabitlenir (yay animasyonu gereksiz kare üretmez).
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          overscroll: false,
          physics: const ClampingScrollPhysics(),
        ),
        child: ListView(
          // Klavye/fare ile de kaydırılabilir; telefonda parmak zaten çalışır.
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            12 + MediaQuery.of(context).padding.bottom,
          ),
          children: [
          // --- başlık + favori (kendi katmanı) ---
          RepaintBoundary(
            child: Row(
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
                          color: P.textSecondary,
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
          ),
          // --- hızlı işlem çipleri (kendi katmanı) ---
          // : HIZLI İŞLEM ÇİPLERİ — telefonda (dikey) uyku/PiP/altyazı
          // gibi özellikler yalnızca yatay ⋯ menüsünde kalıyordu; bu satır
          // onları doğrudan erişilebilir kılar. Canlı yayında yalnız PiP
          // gösterilir (hız/altyazı/uyku VOD'a özeldir).
          RepaintBoundary(child: _hizliIslemler()),
          // --- bölüm şeridi (kendi katmanı - en ağır parça) ---
          if (_bolumModu && !_seritHazir && !_seritHata) ...[
            const SizedBox(height: 10),
            Text(
              L.t('bolum_yukleniyor'),
              style: const TextStyle(fontSize: 12, color: P.textTertiary),
            ),
          ],
          if (_bolumModu && _seritHazir && _bolumler.isNotEmpty) ...[
            const SizedBox(height: 10),
            RepaintBoundary(
              child: HStreamBolumSeridi(
                key: ValueKey('serit_$_aktifSezonId'),
                sezonlar: _sezonlar,
                bolumler: _bolumler,
                aktifSezonId: _aktifSezonId,
                seciliBolumId: _kanal.id,
                izlenenIds: _izlenenIds,
                onSezonDegistir: _sezonDegistir,
                onBolumSec: _bolumSec,
              ),
            ),
          ],
          if (_bolumModu && !_seritHazir && _seritHata) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    L.t('bolum_yuklenemedi'),
                    style: const TextStyle(fontSize: 12, color: P.textSecondary),
                  ),
                ),
                TextButton(
                  onPressed: _bolumleriYukle,
                  child: Text(L.t('tekrar_dene')),
                ),
              ],
            ),
          ],
          // --- SONRAKİ BÖLÜM düğmesi ---
          if (_bolumModu && sonraki != null) ...[
            const SizedBox(height: 10),
            _sonrakiBolumDugmesi(sonraki),
          ],
          // : esnek dolgu öğesi KALDIRILDI — ListView sonsuz yükseklik varsayar,
          // böyle bir öğe orada hata verir/çöker. Onun yerine tam ekran düğmesi
          // içerikten sonra sabit bir boşlukla gelir.
          const SizedBox(height: 18),
          // Tam ekran: kucuk ve sakin bir aksiyon. Kilitli (dondurmesi kapali)
          // cihazlar icin gerekli, ama panelin tamamini kaplamasi gerekmiyor.
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  color: P.surfaceRaised,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _tamEkranDegistir,
                    splashColor: P.pressOverlay,
                    highlightColor: P.pressOverlay,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.screen_rotation_rounded,
                            color: P.brandLight,
                            size: 19,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            L.t("tam_ekran"),
                            style: const TextStyle(
                              color: P.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  L.t("yatay_cevir"),
                  style: const TextStyle(fontSize: 11, color: P.textTertiary),
                ),
              ],
            ),
          ),
          ],
        ),
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
        // : bölüm atlama — panelin en "ağır" eylemi, net bir onay hissi
        onTapUp: (_) => _titre(),
        child: Ink(
          width: double.infinity,
          height: 42,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [P.brand, P.brandDark],
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
                    color: P.brandLight,
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
        color: P.surfaceRaised,
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
              _kanal.favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 24,
              color: _kanal.favorite
                  ? P.favoriIkon
                  : P.textSecondary,
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
