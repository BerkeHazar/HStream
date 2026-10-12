import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_tv/channel_tile.dart';
import 'package:open_tv/exo_player.dart';
import 'package:open_tv/hstream_detail.dart';
import 'package:open_tv/hstream_route.dart';
import 'package:open_tv/models/channel.dart';
import 'package:open_tv/models/filters.dart';
import 'package:open_tv/models/media_type.dart';
import 'package:open_tv/models/node.dart';
import 'package:open_tv/models/node_type.dart';
import 'package:open_tv/models/settings.dart';
import 'package:open_tv/models/view_type.dart';
import 'package:open_tv/native_bridge.dart';
import 'package:open_tv/palet.dart';
import 'package:open_tv/player.dart';
import 'package:open_tv/son_izlenen.dart';
import 'package:open_tv/l10n.dart';

/// Oynaticidan geri donunce hub'in tazelenmesi icin global gozlemci
final RouteObserver<PageRoute> hstreamRouteObserver = RouteObserver<PageRoute>();

/// HStream birlesik ana ekran hub'i.
///
/// Duzen:
/// - **Dikey (telefon):** kaydirilabilir hero karusel (son izlenenler) +
///   altinda 4 tam genislik satir. Gecmis kapaliysa hero kalkar ve satirlar
///   uzayip ekrani doldurur (bosluk kalmaz, oran bozulmaz).
/// - **Yatay (TV):** ustte hero, altinda 4 kart tek sirada.
///
/// Kural: **butonlar sabit, hero istege bagli.** Dikey dikdortgen buton yok —
/// butonlar her zaman eninden genis (yatay oran).
class HStreamHub extends StatefulWidget {
  final void Function(String hedef) onYonlendir;
  final void Function(Node node) setNode;
  final VoidCallback onAyar;
  final bool tvMode;
  const HStreamHub({
    super.key,
    required this.onYonlendir,
    required this.setNode,
    required this.onAyar,
    this.tvMode = false,
  });

  @override
  State<HStreamHub> createState() => _HStreamHubState();
}

/// Bolum tanimi — ana ekrandaki dort giris noktasi.
class _Bolum {
  final String hedef;
  final String baslik;
  final String alt;
  final Color dolgu;
  final Color ikonRenk;
  final IconData ikon;
  const _Bolum(
    this.hedef,
    this.baslik,
    this.alt,
    this.dolgu,
    this.ikonRenk,
    this.ikon,
  );
}

class _HStreamHubState extends State<HStreamHub> with RouteAware {
  List<Channel> _gecmis = [];
  bool _yuklendi = false;
  bool _kayitli = false;
  final PageController _heroCtrl = PageController(viewportFraction: 0.92);
  int _heroSayfa = 0;

  // : KALINAN DAKİKA — kanal kimliği → kayıtlı konum (saniye).
  // Yalnızca film/dizi/bölüm için doldurulur; canlı yayında konum
  // anlamsız olduğu için hiç sorgulanmaz. Geçmiş listesi en fazla 10
  // öğe olduğu için konumlar paralel olarak tek seferde çekilir
  // (Rust/protobuf değişikliği GEREKMEZ — mevcut `getMoviePosition`
  // tek kanal için çalışır).
  Map<int, int> _konumlar = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_kayitli) {
      _kayitli = true;
      final rota = ModalRoute.of(context);
      if (rota is PageRoute) hstreamRouteObserver.subscribe(this, rota);
    }
  }

  @override
  void dispose() {
    hstreamRouteObserver.unsubscribe(this);
    _heroCtrl.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    // PERFORMANS: Bu metot her geri donuste (oynatici, detay, ayarlar) calisir.
    // Gecmis bolumu kapaliysa sorgu yapmanin anlami yok.
    if (!SonIzlenen.goster) {
      if (mounted && _gecmis.isNotEmpty) {
        setState(() => _gecmis = []);
      }
      return;
    }
    _gecmisYukle();
  }

  @override
  void initState() {
    super.initState();
    _gecmisYukle();
  }

  Future<void> _gecmisYukle() async {
    try {
      final filtre = Filters(viewType: ViewType.history);
      filtre.sourceIds = await NativeBridge.instance.getEnabledSourcesMinimal();
      // KOKLU DUZELTME: mediaTypes bos giderse Rust tarafinda "media_type IN ()"
      // diye bozuk SQL olusur ve sorgu her zaman patlar.
      filtre.mediaTypes = const [
        MediaType.livestream,
        MediaType.movie,
        MediaType.serie,
      ];
      final g = await NativeBridge.instance.getChannels(filtre);
      if (!mounted) return;
      final liste = g.take(10).toList();
      // : KALINAN DAKİKA — film/dizi/bölüm için kayıtlı konum çekilir.
      // Canlı yayın atlanır (konum kavramı yok). Her öğe için ayrı bir
      // hafif sorgu; PARALEL çalıştırılır ki ana ekran açılışı uzamasın.
      // Hata olursa rozet gösterilmez, akış bozulmaz.
      final konumlar = <int, int>{};
      await Future.wait(
        liste.map((k) async {
          final id = k.id;
          if (id == null || k.mediaType == MediaType.livestream) return;
          try {
            final sn = await NativeBridge.instance.getMoviePosition(id);
            if (sn != null && sn > 0) konumlar[id] = sn;
          } catch (_) {
            // konum okunamadı — rozet gösterilmez
          }
        }),
      );
      if (!mounted) return;
      setState(() {
        _gecmis = liste;
        _konumlar = konumlar;
        _yuklendi = true;
        if (_heroSayfa >= _gecmis.length) _heroSayfa = 0;
      });
    } catch (_) {
      if (mounted) setState(() => _yuklendi = true);
    }
  }

  /// : BUTON LİSTESİ ÖNBELLEĞİ — `_bolumler` önceden bir **getter**'dı ve
  /// her `build()` çağrısında 4 `_Bolum` nesnesi + 8 `L.t()` çevirisi
  /// yeniden üretiliyordu. `L.t()` her çağrıda `HDil.aktif()` → cihaz
  /// yerelini okur; ana ekranda her dokunuş/rebuild bu maliyeti ödüyordu.
  /// Artık liste BİR KEZ üretilip tutulur, dil değişince tazelenir.
  List<_Bolum>? _bolumlerCache;
  String? _bolumlerDil;

  List<_Bolum> get _bolumler {
    final dil = HDil.aktif();
    final mevcut = _bolumlerCache;
    if (mevcut != null && _bolumlerDil == dil) return mevcut;
    final yeni = <_Bolum>[
      _Bolum(
        'canli',
        L.t('canli_tv'),
        L.t('canli_alt'),
        P.canliDolgu,
        P.canliIkon,
        Icons.live_tv_rounded,
      ),
      _Bolum(
        'film',
        L.t('filmler'),
        L.t('film_alt'),
        P.filmDolgu,
        P.filmIkon,
        Icons.movie_rounded,
      ),
      _Bolum(
        'dizi',
        L.t('diziler'),
        L.t('dizi_alt'),
        P.diziDolgu,
        P.diziIkon,
        Icons.smart_display_rounded,
      ),
      _Bolum(
        'favori',
        L.t('favoriler'),
        L.t('favori_alt'),
        P.favoriDolgu,
        P.favoriIkon,
        Icons.favorite_rounded,
      ),
    ];
    _bolumlerCache = yeni;
    _bolumlerDil = dil;
    return yeni;
  }

  @override
  Widget build(BuildContext context) {
    final bool yatay =
        widget.tvMode ||
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (yatay) return _yatayDuzen();
    return _dikeyDuzen();
  }

  // ==================== DIKEY (telefon) ====================
  Widget _dikeyDuzen() {
    final goster = SonIzlenen.goster;
    // Getter her cagrildiginda yeni liste uretir; dongude tekrar tekrar
    // cagirmamak icin bir kez yerel degiskene alinir.
    final bolumler = _bolumler;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ustBar(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              const ara = 12.0;
              const heroY = 190.0;
              const baslikY = 26.0;
              // Hero varsa satirlar sabit yukseklikte; yoksa uzayip ekrani
              // doldururlar (yine de eninden genis kalirlar).
              final ust = goster ? heroY + baslikY + ara * 2 : 0.0;
              final satirY = goster
                  ? 82.0
                  : ((c.maxHeight - ust - 34 - ara * 3) / 4).clamp(72.0, 168.0);
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (goster) ...[
                      _bolumEtiketi(),
                      const SizedBox(height: ara),
                      SizedBox(height: heroY, child: _heroKarusel()),
                      const SizedBox(height: ara),
                    ],
                    for (var i = 0; i < bolumler.length; i++) ...[
                      if (i > 0) const SizedBox(height: ara),
                      // : her satır kendi boyama katmanında — bir satırın
                      // baskı animasyonu diğerlerini yeniden boyamaz.
                      RepaintBoundary(
                        child: SizedBox(
                          height: satirY,
                          child: _Basma(
                            onTap: () => widget.onYonlendir(bolumler[i].hedef),
                            child: _satirIcerik(bolumler[i]),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ==================== YATAY (telefon yatay + TV) ====================
  //
  // : SIKIŞMA (CRAMPING) DÜZELTMESİ — telefonda yatay modda üst bar +
  // hero (150dp) + 4 kart tek satırda kalıyordu ve ekran yüksekliği
  // çoğu telefonda ~360-410dp olduğu için kartlara yalnızca ~120dp
  // kalıyordu; üstelik hero sabit 150dp olduğu için KISA ekranlarda
  // (küçük telefon / yatay) taşma ve sıkışma oluyordu. Artık hero
  // yüksekliği mevcut alana göre ÖLÇEKLENİR ve LayoutBuilder ile
  // gerçek yükseklik ölçülür — sabit sayı yok.
  Widget _yatayDuzen() {
    final goster = SonIzlenen.goster;
    final bolumler = _bolumler;
    return LayoutBuilder(
      builder: (context, c) {
        // Üst bar (~52) + boşluklar + sayfa alt boşluğu düşülünce kalan
        const ustBarY = 52.0;
        const ara = 12.0;
        final kalan = c.maxHeight - ustBarY - ara;
        // Hero: kalan alanın %38'i, 110-150 arası sınırlanır. Kısa ekranda
        // küçülür (kartlara yer kalır), uzun ekranda 150'de durur.
        final heroY = goster ? (kalan * 0.38).clamp(104.0, 150.0) : 0.0;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [Expanded(child: _selamlama(compact: true)), _disli()]),
              const SizedBox(height: ara),
              if (goster) ...[
                SizedBox(height: heroY, child: _heroKarusel()),
                const SizedBox(height: ara),
              ],
              // Kartlar: kalan tüm alanı kaplar, tek satırda eşit genişlik.
              // Kısa ekranda da taşmaz çünkü hero yukarıda küçültüldü.
              Expanded(
                child: Row(
                  children: [
                    for (var i = 0; i < bolumler.length; i++) ...[
                      if (i > 0) const SizedBox(width: ara),
                      Expanded(
                        child: _Basma(
                          onTap: () => widget.onYonlendir(bolumler[i].hedef),
                          child: _kartIcerik(bolumler[i]),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==================== HERO KARUSEL ====================
  Widget _heroKarusel() {
    if (!_yuklendi) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (_gecmis.isEmpty) return _davetKarti();
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _heroCtrl,
            onPageChanged: (i) => setState(() => _heroSayfa = i),
            itemCount: _gecmis.length,
            itemBuilder: (context, i) {
              final kanal = _gecmis[i];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _heroKart(kanal),
              );
            },
          ),
        ),
        if (_gecmis.length > 1) ...[
          const SizedBox(height: 8),
          _noktalar(_gecmis.length, _heroSayfa),
        ],
      ],
    );
  }

  // : HERO KARTI - tam genislik kaplar.
  // Onceden burada ChannelTile kullaniliyordu; o bilesen bir LISTE SATIRI
  // icin tasarlandigi (Row + kare kapak + AspectRatio) icin 190dp'lik
  // karusel yuksekliginde yatayda sadece icerigi kadar yer kapliyor ve
  // kart ORTADA KUCUK bir serit gibi kaliyordu. Bu kart tum alani doldurur:
  // solda kapak (16:9 hissi), sagda baslik + tur etiketi.
  Widget _heroKart(Channel kanal) {
    final turEtiket = _turEtiketi(kanal);
    // : kalınan yer — yalnız kaydı olan film/dizi/bölüm için dolu.
    final konumSn = kanal.id != null ? _konumlar[kanal.id] : null;
    return _Basma(
      onTap: () => _gecmisAc(kanal),
      onLongPress: () => _gecmisSecenekleri(kanal),
      child: Container(
        decoration: BoxDecoration(
          color: P.surfaceRaised,
          borderRadius: BorderRadius.circular(P.radiusPanel),
          border: Border.all(color: P.outline, width: P.outlineWidth),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kapak: yukseklige gore kare, tasma yok
            // : `kapakVar` — bos string de "kapak yok" sayilir (bkz.
            // models/channel.dart). Aksi halde bos URL'li gorsel
            // yukleyicisi kuruluyordu.
            AspectRatio(
              aspectRatio: 1,
              child: kanal.kapakVar
                  ? CachedNetworkImage(
                      imageUrl: kanal.image!,
                      fit: BoxFit.cover,
                      memCacheHeight: 400,
                      memCacheWidth: 400,
                      // : fadeIn KAPALI + placeholder — önceden görsel
                      // geldiğinde 500ms yumuşak geçişle "pop" yapıyordu;
                      // yükleme sırasında boş alan kalıyordu. Yer tutucu
                      // ile geçiş anı görünmez olur, algılanan gecikme düşer.
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      placeholder: (_, __) => _kapakYedek(),
                      errorWidget: (_, __, ___) => _kapakYedek(),
                    )
                  : _kapakYedek(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      kanal.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: P.textPrimary,
                        height: 1.22,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Tur etiketi (Canli / Film / Dizi / Bolum N)
                    // : KALINAN DAKİKA ROZETİ — kayitli konum varsa
                    // (film/dizi/bolum; canli yayinda konum kavrami yok)
                    // tur etiketinin yaninda "▶ 42:15" rozeti cikar.
                    // `Wrap` kullanilir: dar kartta iki rozet alt satira
                    // inebilir, boylece tasma/sikisma olmaz.
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _rozet(turEtiket, P.brandSoft, P.brandLight),
                        if (konumSn != null)
                          _rozet(
                            _konumMetni(konumSn),
                            P.surfaceHigh,
                            P.textPrimary,
                            ikon: Icons.play_arrow_rounded,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // : kucuk etiket rozeti — tur etiketi ve "kalinan yer" ayni dili kullanir.
  // Ikon istege bagli; metin dili bagimsizdir (yalnizca sayi/zaman).
  Widget _rozet(
    String metin,
    Color dolgu,
    Color renk, {
    IconData? ikon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: dolgu,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ikon != null) ...[
            Icon(ikon, size: 13, color: renk),
            const SizedBox(width: 3),
          ],
          Text(
            metin,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: renk,
            ),
          ),
        ],
      ),
    );
  }

  // kapak yoksa / yuklenemezse gosterilen sade yer tutucu
  Widget _kapakYedek() {
    return Container(
      color: P.surfaceHigh,
      child: const Center(
        child: Icon(Icons.movie_creation_rounded, size: 34, color: P.textTertiary),
      ),
    );
  }

  // kanal turune gore kisa etiket (dil destekli, kucuk harfli hero etiketi)
  String _turEtiketi(Channel kanal) {
    // : BOLUM ETIKETI DUZELTMESI —
    // Bir dizinin bolumu Rust tarafinda `media_type = MOVIE` + `series_id`
    // dolu olarak saklanir (bkz. xtream.rs `episode_to_channel`). Bu yuzden
    // asagidaki `movie` dali bolumleri "Film" olarak etiketliyordu.
    //
    // : IKINCI TUR DUZELTMESI — `episode_num` HER saglayicida dolu
    // gelmiyor: bazi Xtream panelleri bu alani hic gondermiyor, o zaman
    // `episodeNum != null` kontrolu de yetmiyor ve bolum YINE "Film"
    // gorunuyordu. Bolumler icin HER ZAMAN dolu olan alan `series_id`dir
    // (upstream `episode_to_channel` garanti eder) — asil sinyal odur.
    // Bolum numarasi biliniyorsa "Bolum N", bilinmiyorsa "Dizi" yazilir;
    // hicbir durumda "Film" cikmaz.
    if (kanal.seriesId != null || kanal.episodeNum != null) {
      return kanal.episodeNum != null
          ? '${L.t('bolum_n')} ${kanal.episodeNum}'
          : L.t('tur_dizi');
    }
    switch (kanal.mediaType) {
      case MediaType.livestream:
        return L.t('tur_canli');
      case MediaType.movie:
        return L.t('tur_film');
      default:
        return L.t('tur_dizi');
    }
  }

  // : KALINAN DAKİKA METNİ — saniyeyi okunur bir zaman damgasına çevirir.
  // Saat varsa "1:05:30", yoksa "42:15". Dil bağımsızdır; rozetin yanındaki
  // oynat ikonu "buradan devam et" anlamını taşır.
  String _konumMetni(int sn) {
    final saat = sn ~/ 3600;
    final dk = (sn % 3600) ~/ 60;
    final sn2 = sn % 60;
    final iki = (int v) => v.toString().padLeft(2, '0');
    if (saat > 0) return '$saat:${iki(dk)}:${iki(sn2)}';
    return '$dk:${iki(sn2)}';
  }

  // hero karta dokununca: ChannelTile.play() ile AYNI davranis
  // (film/dizi -> detay ekrani; canli -> dogrudan oynatici)
  //
  // : GEÇİŞ GECİKMESİ (LAG) DÜZELTMESİ — canlı yayında önceden önce
  // `await getSettings()` bekleniyor, SONRA rota açılıyordu. Bu await
  // platform kanalına gidip döndüğü için dokunuşla ekranın açılması
  // arasında gözle görülür bir gecikme oluşuyordu. Artık `getSettings()`
  // ile rota açılışı PARALEL yürür: Navigator HEMEN push edilir, ayarlar
  // geldiğinde oynatıcıya iletilir (bir `FutureBuilder` ile).
  Future<void> _gecmisAc(Channel kanal) async {
    final mt = kanal.mediaType;
    if ((mt == MediaType.movie && kanal.seriesId == null) ||
        mt == MediaType.serie) {
      if (!mounted) return;
      await Navigator.push(
        context,
        HStreamPageRoute(
          builder: (_) => HStreamDetail(
            channel: kanal,
            setNode: widget.setNode,
          ),
        ),
      );
      return;
    }
    if (mt == MediaType.group || mt == MediaType.season) {
      widget.setNode(
        Node(
          id: kanal.id!,
          name: kanal.name,
          type: fromMediaType(mt),
        ),
      );
      return;
    }
    if (!mounted) return;
    // : geçmiş kaydı ve ayar çekme AYNI ANDA başlar; rota bunları BEKLEMEZ.
    final id = kanal.id;
    if (id != null) {
      NativeBridge.instance.addLastWatched(id);
    }
    final ayarGelecek = NativeBridge.instance.getSettings();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FutureBuilder<Settings>(
          future: ayarGelecek,
          builder: (ctx, snap) {
            if (!snap.hasData) {
              // : ayarlar gelene kadar siyah ekran yerine sade bir
              // yüklenme göstergesi; geçiş animasyonu biter bitmez
              // içerik hazır olur.
              return const Scaffold(
                backgroundColor: Colors.black,
                body: Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              );
            }
            return Platform.isAndroid
                ? ExoPlayerScreen(
                    channel: kanal,
                    settings: snap.data!,
                    // : BOLUM GECMISI — kayitli oge bir dizi bolumu ise
                    // (`series_id` dolu) dizi/sezon kimligi oynaticiya
                    // TASINIR. Aksi halde bolum tek basina "ciplak film"
                    // gibi aciliyor, bolum seridi ve "sonraki bolum"
                    // dugmesi hic olusmuyordu (gecmisten devam ederken
                    // dizi ici gecis imkansizdi).
                    diziId: kanal.seriesId,
                    sezonId: kanal.seasonId,
                  )
                : Player(channel: kanal, settings: snap.data!);
          },
        ),
      ),
    );
  }

  Widget _noktalar(int adet, int aktif) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < adet && i < 10; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == aktif ? 16 : 6,
            height: 4,
            decoration: BoxDecoration(
              color: i == aktif ? P.brandLight : P.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }

  /// Gecmis yokken hero yerine gosterilen davet karti.
  Widget _davetKarti() {
    return _Basma(
      onTap: () => widget.onYonlendir('canli'),
      child: Container(
        decoration: BoxDecoration(
          color: P.surfaceRaised,
          borderRadius: BorderRadius.circular(P.radiusPanel),
          border: Border.all(color: P.outline, width: P.outlineWidth),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: P.surfaceHigh,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: P.textTertiary,
                size: 24,
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                L.t('son_izlenen_bos'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: P.textSecondary,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== BOLUM BUTONLARI ====================

  /// Tam genislik satir — telefon icin (yatay oran).
  Widget _satirIcerik(_Bolum b) {
    return Container(
      decoration: BoxDecoration(
        color: b.dolgu,
        borderRadius: BorderRadius.circular(P.radiusPanel),
        border: Border.all(color: P.outline, width: P.outlineWidth),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Icon(b.ikon, color: b.ikonRenk, size: 26),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b.baslik,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: P.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    letterSpacing: .4,
                  ),
                ),
                if (b.alt.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    b.alt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: P.textTertiary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Kart — TV/yatay için (tek sırada dört eşit kart).
  ///
  /// : SIKIŞMA DÜZELTMESİ — ikon (30) + başlık (15) + alt satır (11.5)
  /// sabit boyuttaydı; telefonda yatay modda kart yüksekliği ~110dp'ye
  /// düşünce içerik taşıp sıkışıyordu. `LayoutBuilder` ile kartın GERÇEK
  /// yüksekliği ölçülür ve ikon/metin boyutları buna göre küçültülür
  /// (küçük kart = küçük ikon/yazı, taşma yok).
  Widget _kartIcerik(_Bolum b) {
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight;
        // Yüksekliğe göre ölçek: 150dp+ tam boy, 100dp'de ~%72
        final kucuk = h < 132;
        final ikonBoy = kucuk ? 24.0 : 30.0;
        final baslikBoy = kucuk ? 13.0 : 15.0;
        final altBoy = kucuk ? 10.5 : 11.5;
        final dikeyBosluk = kucuk ? 5.0 : 9.0;
        return Container(
          decoration: BoxDecoration(
            color: b.dolgu,
            borderRadius: BorderRadius.circular(P.radiusPanel),
            border: Border.all(color: P.outline, width: P.outlineWidth),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(b.ikon, color: b.ikonRenk, size: ikonBoy),
              SizedBox(height: dikeyBosluk),
              Text(
                b.baslik,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: P.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: baslikBoy,
                  letterSpacing: .4,
                ),
              ),
              if (b.alt.isNotEmpty && !kucuk) ...[
                // : alt satır yalnız yeterli yer varsa gösterilir;
                // kısa kartta gizlemek taşmayı kökten engeller.
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    b.alt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: P.textTertiary, fontSize: altBoy),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ==================== ORTAK PARCALAR ====================

  Widget _selamlama({bool compact = false}) {
    if (widget.tvMode) {
      return const Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'H',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: P.textPrimary,
              ),
            ),
            TextSpan(
              text: 'Stream',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: P.brandLight,
              ),
            ),
          ],
        ),
      );
    }
    if (compact) {
      return Text(
        L.t('iyi_seyirler'),
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          L.t('iyi_seyirler'),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 1),
        Text(
          L.t('hub_alt'),
          style: const TextStyle(fontSize: 11, color: P.textTertiary),
        ),
      ],
    );
  }

  Widget _disli() {
    return IconButton(
      onPressed: widget.onAyar,
      iconSize: 22,
      style: IconButton.styleFrom(
        backgroundColor: P.surfaceRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: const Icon(Icons.settings_rounded, color: P.brandLight),
      tooltip: L.t('ayarlar'),
    );
  }

  Widget _ustBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 4),
      child: Row(children: [Expanded(child: _selamlama()), _disli()]),
    );
  }

  Widget _bolumEtiketi() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 16, 0),
      child: Text(
        L.t('son_izlenenler_baslik'),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: .5,
          color: P.textTertiary,
        ),
      ),
    );
  }

  // : Son Izlenenler'de basili tut -> favorilere ekle/cikar +
  // gecmisten cikar.
  void _gecmisSecenekleri(Channel kanal) {
    showModalBottomSheet(
      context: context,
      backgroundColor: P.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  kanal.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: P.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              ListTile(
                leading: Icon(
                  kanal.favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: P.brandLight,
                ),
                title: Text(
                  kanal.favorite ? L.t("fav_cikar") : L.t("fav_ekle"),
                  style: const TextStyle(color: P.textPrimary),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final id = kanal.id;
                  if (id == null) return;
                  await NativeBridge.instance.favorite(id, !kanal.favorite);
                  kanal.favorite = !kanal.favorite;
                  if (mounted) setState(() {});
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.history_toggle_off_rounded,
                  color: P.brandLight,
                ),
                title: Text(
                  L.t("gecmisten_cikar"),
                  style: const TextStyle(color: P.textPrimary),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final id = kanal.id;
                  if (id == null) return;
                  await NativeBridge.instance.clearHistoryItem(id);
                  await _gecmisYukle();
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }
}

/// Basma geri bildirimi sarmalayicisi.
///
/// Basinca hafifce kucultur; odak/parlama efektini blur'lu golge yerine
/// kenarlikla gosterir (blur her animasyon karesinde yeniden hesaplanir →
/// takilmaya yol acar). Kenarlik kalinligi SABIT, yalnizca renk degisir;
/// boylece duzen kaymaz.
class _Basma extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double yaricap;
  final double olcek;

  const _Basma({
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.yaricap = P.radiusPanel,
    this.olcek = .97,
  });

  @override
  State<_Basma> createState() => _BasmaState();
}

class _BasmaState extends State<_Basma> {
  final _durum = WidgetStatesController();

  @override
  void dispose() {
    _durum.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<WidgetState>>(
      valueListenable: _durum,
      builder: (context, d, _) {
        final basili = d.contains(WidgetState.pressed);
        final odakli = d.contains(WidgetState.focused);
        return AnimatedScale(
          scale: basili ? widget.olcek : 1.0,
          // : 90ms yerine 70ms — dokunuş geri bildirimi daha çevik
          // hissedilir (algılanan gecikme düşer).
          duration: const Duration(milliseconds: 70),
          curve: Curves.easeOut,
          child: Container(
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.yaricap),
              border: Border.all(
                color: odakli ? P.brandLight : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(widget.yaricap),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                statesController: _durum,
                onTap: widget.onTap,
                onLongPress: widget.onLongPress,
                // YUMUSAK HIS: belirgin overlay + haptik + %97 olcek.
                splashColor: P.pressOverlay,
                highlightColor: P.pressOverlay,
                focusColor: P.pressOverlay,
                // : GEÇİŞ LAG'I DÜZELTMESİ — haptik önceden `onTapDown`
                // içindeydi, yani parmak ekrana DEĞDİĞİ ANDA platform
                // kanalına gidiyordu (kaydırma niyetinde bile). Bu,
                // Navigator.push ile aynı karede yarışıp geçişi
                // geciktiriyordu. Artık `onTap` (gerçek dokunuş onayı)
                // içinde tetiklenir; kaydırmada hiç çalışmaz.
                onTapUp: (_) => HapticFeedback.selectionClick(),
                child: widget.child,
              ),
            ),
          ),
        );
      },
    );
  }
}
