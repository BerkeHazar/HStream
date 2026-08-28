import 'package:flutter/material.dart';
import 'package:open_tv/channel_tile.dart';
import 'package:open_tv/models/channel.dart';
import 'package:open_tv/models/filters.dart';
import 'package:open_tv/models/media_type.dart';
import 'package:open_tv/models/node.dart';
import 'package:open_tv/models/view_type.dart';
import 'package:open_tv/native_bridge.dart';
import 'package:open_tv/son_izlenen.dart';
import 'package:open_tv/l10n.dart';

/// Oynaticidan geri donunce hub'in tazelenmesi icin global gozlemci
final RouteObserver<PageRoute> hstreamRouteObserver = RouteObserver<PageRoute>();

/// HStream BIRLESIK ana ekran hub'i ( duzeni):
/// - DİKEY: kaydirilabilir, SABIT ve cömert kutu yukseklikleri
///   (kutular asla ufalmaz) + alt bol bosluk.
/// - YATAY + TV: solda SON İZLENENLER dikey kolonu,
///   sağda 2x2 TAMAMEN ESIT dort kutu (Canli/Film/Dizi/Favori).
/// - Basinca hissedilir geri bildirim: dalga + hafif parlama.
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

class _HStreamHubState extends State<HStreamHub> with RouteAware {
  List<Channel> _gecmis = [];
  bool _yuklendi = false;
  bool _kayitli = false;

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
    super.dispose();
  }

  @override
  void didPopNext() {
    _gecmisYukle();
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _gecmisYukle();
  }

  Future<void> _gecmisYukle() async {
    try {
      final filtre = Filters(viewType: ViewType.history);
      filtre.sourceIds =
          await NativeBridge.instance.getEnabledSourcesMinimal();
      // KÖKLÜ DÜZELTME (): mediaTypes boş giderse Rust tarafında
      // "media_type IN ()" diye bozuk SQL oluşur ve sorgu HER ZAMAN patlar.
      filtre.mediaTypes = const [
        MediaType.livestream,
        MediaType.movie,
        MediaType.serie,
      ];
      final g = await NativeBridge.instance.getChannels(filtre);
      if (!mounted) return;
      setState(() {
        _gecmis = g.take(10).toList();
        _yuklendi = true;
      });
    } catch (_) {
      if (mounted) setState(() => _yuklendi = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool yatay =
        widget.tvMode ||
        MediaQuery.of(context).orientation == Orientation.landscape;
    if (yatay) return _yatayDuzen();
    return _dikeyDuzen();
  }

  // ================= DİKEY: kaydırılabilir, sabit yükseklikler =================
  Widget _dikeyDuzen() {
    final bool goster = SonIzlenen.goster;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ustBar(),
        if (goster) ...[
          _bolumEtiketi(),
          SizedBox(height: 104, child: _devamSeridiYatay()),
        ],
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
            child: Column(
              children: [
                SizedBox(
                  height: 190,
                  width: double.infinity,
                  child: _kutu(
                    L.t('canli_tv'),
                    L.t('canli_alt'),
                    const [Color(0xFF23263A), Color(0xFF161824)],
                    Icons.live_tv_rounded,
                    'canli',
                    ikonBoyut: 42,
                    yaziBoyut: 21,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 124,
                  child: Row(
                    children: [
                      Expanded(
                        child: _kutu(
                          L.t('filmler'),
                          L.t('film_alt'),
                          const [Color(0xFFDB6150), Color(0xFFB23F31)],
                          Icons.movie_rounded,
                          'film',
                          ikonBoyut: 28,
                          yaziBoyut: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _kutu(
                          L.t('diziler'),
                          L.t('dizi_alt'),
                          const [Color(0xFF7A63B3), Color(0xFF5A4390)],
                          Icons.smart_display_rounded,
                          'dizi',
                          ikonBoyut: 28,
                          yaziBoyut: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 56,
                  width: double.infinity,
                  child: _kutu(
                    L.t('favoriler'),
                    '',
                    const [Color(0xFF8E7196), Color(0xFF6B5273)],
                    Icons.favorite_rounded,
                    'favori',
                    yatayCubuk: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ============ YATAY + TV: solda geçmiş kolonu, sağda 2x2 eşit kutu ============
  // : Son Izlenenler kapaliysa sol kolon kalkar, 2x2 AYNI boyutta
  // kalir ve ekran ortasina alinir (dev kart yok).
  Widget _yatayDuzen() {
    final bool goster = SonIzlenen.goster;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: goster
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 224,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: _selamlama(compact: true)),
                          _disli(),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _bolumEtiketi(sifirBosluk: true),
                      const SizedBox(height: 6),
                      Expanded(child: _devamSeridiDikey()),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: _ikiIkiKutular()),
              ],
            )
          : Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _selamlama(compact: true)),
                    _disli(),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Row(
                    children: [
                      const SizedBox(width: 118),
                      Expanded(child: _ikiIkiKutular()),
                      const SizedBox(width: 118),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _ikiIkiKutular() {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _kutu(
                  L.t('canli_tv'),
                  L.t('canli_alt'),
                  const [Color(0xFF23263A), Color(0xFF161824)],
                  Icons.live_tv_rounded,
                  'canli',
                  ikonBoyut: 30,
                  yaziBoyut: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _kutu(
                  L.t('filmler'),
                  L.t('film_alt'),
                  const [Color(0xFFDB6150), Color(0xFFB23F31)],
                  Icons.movie_rounded,
                  'film',
                  ikonBoyut: 28,
                  yaziBoyut: 16,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _kutu(
                  L.t('diziler'),
                  L.t('dizi_alt'),
                  const [Color(0xFF7A63B3), Color(0xFF5A4390)],
                  Icons.smart_display_rounded,
                  'dizi',
                  ikonBoyut: 28,
                  yaziBoyut: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _kutu(
                  L.t('favoriler'),
                  L.t('favori_alt'),
                  const [Color(0xFF8E7196), Color(0xFF6B5273)],
                  Icons.favorite_rounded,
                  'favori',
                  ikonBoyut: 28,
                  yaziBoyut: 16,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------- ortak parçalar ----------
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
                color: Colors.white,
              ),
            ),
            TextSpan(
              text: 'Stream',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: Color(0xFFA78BFA),
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
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _disli() {
    return IconButton(
      onPressed: widget.onAyar,
      iconSize: 21,
      style: IconButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: const Icon(Icons.settings_rounded, color: Color(0xFFA78BFA)),
      tooltip: L.t('ayarlar'),
    );
  }

  Widget _ustBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 4),
      child: Row(
        children: [Expanded(child: _selamlama()), _disli()],
      ),
    );
  }

  Widget _bolumEtiketi({bool sifirBosluk = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(sifirBosluk ? 0 : 16, 4, 16, 6),
      child: Text(
        L.t('son_izlenenler_baslik'),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: .5,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _bosDurum() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Text(
        L.t('son_izlenen_bos'),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 11.5,
        ),
      ),
    );
  }

  Widget _devamSeridiYatay() {
    if (!_yuklendi) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (_gecmis.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _bosDurum(),
      );
    }
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _gecmis.length,
      separatorBuilder: (_, __) => const SizedBox(width: 5),
      itemBuilder: (context, i) {
        final kanal = _gecmis[i];
        return SizedBox(
          width: 250,
          child: GestureDetector(
            onLongPress: () => _gecmisSecenekleri(kanal),
            child: ChannelTile(
              channel: kanal,
              parentContext: context,
              setNode: widget.setNode,
              onSelect: () {},
            ),
          ),
        );
      },
    );
  }

  Widget _devamSeridiDikey() {
    if (!_yuklendi) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (_gecmis.isEmpty) return _bosDurum();
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _gecmis.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final kanal = _gecmis[i];
        return SizedBox(
          height: 78,
          child: GestureDetector(
            onLongPress: () => _gecmisSecenekleri(kanal),
            child: ChannelTile(
              channel: kanal,
              parentContext: context,
              setNode: widget.setNode,
              onSelect: () {},
            ),
          ),
        );
      },
    );
  }

  // : Son Izlenenler'de basili tut -> favorilere ekle/cikar +
  // gecmisten cikar (kullanicinin istedigi ozellik).
  void _gecmisSecenekleri(Channel kanal) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16182A),
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
                  style: TextStyle(
                    color: Colors.white,
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
                  color: const Color(0xFFA78BFA),
                ),
                title: Text(
                  kanal.favorite ? L.t("fav_cikar") : L.t("fav_ekle"),
                  style: const TextStyle(color: Colors.white),
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
                  color: Color(0xFFA78BFA),
                ),
                title: Text(
                  L.t("gecmisten_cikar"),
                  style: const TextStyle(color: Colors.white),
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

  Widget _kutu(
    String baslik,
    String alt,
    List<Color> renkler,
    IconData ikon,
    String hedef, {
    bool yatayCubuk = false,
    double ikonBoyut = 32,
    double yaziBoyut = 19,
  }) {
    // FIX (): InkWell, Ink gradyaninin DISINDA -> dalga efekti
    // artik gorunur; basinca hissedilir geri bildirim.
    return Material(
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onYonlendir(hedef),
        splashColor: Colors.white24,
        highlightColor: Colors.white10,
        focusColor: Colors.white24,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: renkler,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: yatayCubuk
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(ikon, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      baslik,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: .5,
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(ikon, color: Colors.white70, size: ikonBoyut),
                    const SizedBox(height: 8),
                    Flexible(
                      child: Text(
                        baslik,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: yaziBoyut,
                          shadows: const [
                            Shadow(
                              color: Colors.black45,
                              offset: Offset(0, 2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (alt.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        alt,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
