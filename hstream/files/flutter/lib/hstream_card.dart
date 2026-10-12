import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_tv/memory.dart';
import 'package:open_tv/app_mode.dart';
import 'package:open_tv/models/channel.dart';
import 'package:open_tv/error.dart';
import 'package:open_tv/models/media_type.dart';
import 'package:open_tv/models/node.dart';
import 'package:open_tv/models/node_type.dart';
import 'package:open_tv/native_bridge.dart';
import 'package:open_tv/palet.dart';
import 'package:open_tv/player.dart';
import 'package:open_tv/exo_player.dart';
import 'package:open_tv/hstream_detail.dart';
import 'package:open_tv/hstream_route.dart';
import 'dart:io' show Platform;
import 'package:open_tv/l10n.dart';

/// HStream kompakt kapak karti ( - onayli birlesik tasarim).
/// Kanal/film/dizi listesini kucuk poster kartlari olarak gosterir.
/// Oynatma/favori mantigi ChannelTile ile birebir aynidir;
/// uzun bas (veya kumandada OK'a basili tut) = favori.
class HStreamCard extends StatefulWidget {
  final Channel channel;
  final BuildContext parentContext;
  final Function(Node node) setNode;
  final VoidCallback? onFocusNavbar;
  final VoidCallback onSelect;
  final bool autofocus;
  // : canli yayinda oynaticida "4/118" konum rozeti (bos = rozet yok)
  final String? konumEtiketi;
  // : dizi/sezon kimligi ACIKCA gelir (bolum gecisinin garanti kaynagi)
  final int? diziId;
  final int? sezonId;
  // : bolum listesi EKRANDAN direkt gelir
  final List<Channel>? bolumler;
  const HStreamCard({
    super.key,
    required this.channel,
    required this.setNode,
    required this.parentContext,
    required this.onSelect,
    this.onFocusNavbar,
    this.autofocus = false,
    this.konumEtiketi,
    this.diziId,
    this.sezonId,
    this.bolumler,
  });

  @override
  State<HStreamCard> createState() => _HStreamCardState();
}

class _HStreamCardState extends State<HStreamCard> {
  static final _selectionKeys = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
  };

  final FocusNode _focusNode = FocusNode();
  final _statesController = WidgetStatesController();
  Timer? _longPressTimer;
  bool _longPressTriggered = false;
  bool _selectKeyDown = false;
  InteractiveInkFeature? _inkFeature;
  BuildContext? _innerContext;

  @override
  void initState() {
    super.initState();
    _focusNode.onKeyEvent = _handleKeyEvent;
    _focusNode.addListener(_handleFocusChange);
  }

  void _showSplash() {
    final context = _innerContext;
    if (context == null) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    _inkFeature?.cancel();

    final theme = Theme.of(context);
    final splashFactory = theme.splashFactory;

    _inkFeature = splashFactory.create(
      controller: Material.of(context),
      referenceBox: renderBox,
      position: renderBox.size.center(Offset.zero),
      color: P.pressOverlay,
      textDirection: Directionality.of(context),
      containedInkWell: true,
      rectCallback: () => Offset.zero & renderBox.size,
      borderRadius: BorderRadius.circular(10),
    );
  }

  void _confirmSplash() {
    _inkFeature?.confirm();
    _inkFeature = null;
  }

  void _cancelSplash() {
    _inkFeature?.cancel();
    _inkFeature = null;
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      _longPressTimer?.cancel();
      _longPressTriggered = false;
      _selectKeyDown = false;
      _cancelSplash();
      _statesController.update(WidgetState.pressed, false);
    }
    // : ODAK KASMASI DUZELTMESI — burada `setState(() {})` VARDI.
    // Odak kenarligi zaten `_statesController` uzerinden
    // `ValueListenableBuilder` ile tazeleniyor (InkWell focus durumunu
    // controller'a yazar). Dolayisiyla `setState` GEREKSIZDI ve her odak
    // degisiminde TUM kart alt agacini (Material + Ink + Stack + gorsel)
    // yeniden kuruyordu. TV'de kumanda ile gezinirken bu, kare basina
    // tam rebuild demekti. Artik yalnizca ilgili builder tazelenir.
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (!FocusScope.of(context).focusInDirection(TraversalDirection.right)) {
        widget.onFocusNavbar?.call();
      }
      return KeyEventResult.handled;
    }

    if (_selectionKeys.contains(event.logicalKey)) {
      if (event is KeyDownEvent) {
        _selectKeyDown = true;
        _longPressTimer?.cancel();
        _statesController.update(WidgetState.pressed, true);
        _showSplash();
        _longPressTimer = Timer(const Duration(milliseconds: 500), () {
          _longPressTriggered = true;
          _confirmSplash();
          _statesController.update(WidgetState.pressed, false);
          favorite();
        });
      } else if (event is KeyUpEvent) {
        if (!_selectKeyDown) {
          return KeyEventResult.handled;
        }
        _selectKeyDown = false;
        _longPressTimer?.cancel();
        _statesController.update(WidgetState.pressed, false);
        _confirmSplash();
        if (!_longPressTriggered) {
          play();
        }
        _longPressTriggered = false;
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _cancelSplash();
    _statesController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> favorite() async {
    if (widget.channel.mediaType == MediaType.group) return;
    await Error.tryAsyncNoLoading(() async {
      await NativeBridge.instance.favorite(
        widget.channel.id!,
        !widget.channel.favorite,
      );
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

  Future<int?> _handleSeries() async {
    if (widget.channel.url?.isEmpty == true) {
      if (context.mounted) {
        Error.handleError(context, L.t("gecersiz_dizi"));
      }
      return null;
    }
    final seriesId = int.tryParse(widget.channel.url!);
    if (seriesId == null) {
      if (context.mounted) {
        Error.handleError(
          context,
          L.t("gecersiz_dizi"),
        );
      }
      return null;
    }
    await Error.tryAsync(
      () async {
        await NativeBridge.instance.getEpisodes(
          seriesId,
          widget.channel.sourceId,
          widget.channel.image,
        );
        refreshedSeries.add(seriesId);
      },
      widget.parentContext,
      null,
      true,
      false,
    );
    return seriesId;
  }

  Future<void> play() async {
    widget.onSelect();
    // : film / dizi karti once DETAY ekranina gider (onayli tasarim).
    // Bolumler (seriesId dolu) ve canli kanallar direkt oynar.
    // : BOLUM EKRANINDA (sezon kimligi/listesi elimizde) dokunulan
    // kanal KESINLIKLE bolumdur - detay atlanir, direkt oynatici. Rust eski
    // surumlerde series_id dondurmedigi icin bolumler "film" sanilip detaya
    // yollaniyordu ve oynatici ciplak aciliyordu (seri ici gecis imkansizdi).
    final bolumEkrani =
        widget.sezonId != null || widget.bolumler != null;
    final mt = widget.channel.mediaType;
    if (((mt == MediaType.movie && widget.channel.seriesId == null) ||
            mt == MediaType.serie) &&
        !bolumEkrani) {
      if (!mounted) return;
      await Navigator.push(
        context,
        HStreamPageRoute(
          builder: (_) => HStreamDetail(
            channel: widget.channel,
            setNode: widget.setNode,
          ),
        ),
      );
      if (mounted) _focusNode.requestFocus();
      return;
    }
    late final int? seriesId;
    if (widget.channel.mediaType == MediaType.serie) {
      seriesId = await _handleSeries();
      if (seriesId == null) return;
    }

    if (widget.channel.mediaType == MediaType.group ||
        widget.channel.mediaType == MediaType.serie ||
        widget.channel.mediaType == MediaType.season) {
      widget.setNode(
        Node(
          id:
              widget.channel.mediaType == MediaType.group ||
                  widget.channel.mediaType == MediaType.season
              ? widget.channel.id!
              : seriesId!,
          name: widget.channel.name,
          type: fromMediaType(widget.channel.mediaType),
        ),
      );
    } else {
      var settings = await NativeBridge.instance.getSettings();
      NativeBridge.instance.addLastWatched(widget.channel.id!);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Platform.isAndroid
              ? ExoPlayerScreen(
                  channel: widget.channel,
                  settings: settings,
                  konumEtiketi: widget.konumEtiketi,
                  diziId: widget.diziId,
                  sezonId: widget.sezonId,
                  bolumler: widget.bolumler,
                )
              : Player(channel: widget.channel, settings: settings),
        ),
      );
      if (mounted) _focusNode.requestFocus();
    }
  }

  // Tur bazli yedek gradyan (kapak gorseli yoksa)
  /// Görsel yüklenene kadar kullanılan yer tutucu gradyanı.
  /// Tüm medya türleri için aynı — palet tek kaynaktan yönetilir.
  List<Color> _yedekRenkler() => P.placeholderGrad;

  IconData _yedekIkon() {
    switch (widget.channel.mediaType) {
      case MediaType.movie:
        return Icons.movie_rounded;
      case MediaType.serie:
      case MediaType.season:
        return Icons.smart_display_rounded;
      case MediaType.livestream:
        return Icons.live_tv_rounded;
      default:
        return Icons.video_library_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final yedek = _yedekRenkler();
    // PERFORMANS: Blur'lu gölge kaldırıldı — her animasyon karesinde yeniden
    // hesaplanıyordu ve takılmaya yol açıyordu. Odak parlaması artık kenarlıkla.
    // GERİ BİLDİRİM: Basma efekti artık telefonda da çalışır (önce yalnızca TV
    // modundaydı) ve karta %97 ölçek ekler.
    return ValueListenableBuilder<Set<WidgetState>>(
      valueListenable: _statesController,
      builder: (context, durumlar, _) {
        final basili = durumlar.contains(WidgetState.pressed);
        final odakli = durumlar.contains(WidgetState.focused) && AppMode.isTv;
        return AnimatedScale(
          scale: basili ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            // foregroundDecoration: kenarlık çizilirken düzeni kaydırmaz.
            // Kalınlık sabit (2.5), yalnızca RENK animasyonlanır → hem kayma
            // yok hem de blur'lu gölge yok.
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: odakli ? P.brandLight : Colors.transparent,
                width: 2.5,
              ),
            ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: Builder(
          builder: (innerContext) {
            _innerContext = innerContext;
            return InkWell(
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              statesController: _statesController,
              borderRadius: BorderRadius.circular(10),
              // YUMUSAK HIS: belirgin overlay + haptik geri bildirim.
              splashColor: P.pressOverlay,
              highlightColor: P.pressOverlay,
              focusColor: P.pressOverlay,
              // : KAYDIRMA HAPTIGI DUZELTMESI — onceden `onTapDown` idi,
              // yani parmak ekrana DEGDIGI ANDA platform kanalina gidiyordu;
              // kaydirmaya baslarken bile tetikleniyor ve listede gezinirken
              // gereksiz titresim + kare gecikmesi uretiyordu. `onTapUp`
              // gercek dokunus onayini bekler (ayni duzeltme hstream_hub ve
              // oynaticida da yapildi).
              onTapUp: (_) => HapticFeedback.selectionClick(),
              onLongPress: favorite,
              onTap: () async => await play(),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: yedek,
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Kapak gorseli (varsa)
                    // : `kapakVar` kullanilir — `image != null` DEGIL.
                    // Bos string (`stream_icon: ""`) kapak YOK demektir;
                    // aksi halde bos URL'li CachedNetworkImage kurulup
                    // kaydirma sirasinda tekrar tekrar basarisiz yukleme
                    // denenirdi (canli yayin kasmasinin ana sebebi).
                    if (widget.channel.kapakVar)
                      CachedNetworkImage(
                        imageUrl: widget.channel.image!,
                        memCacheWidth: 320,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Center(
                          child: Icon(
                            _yedekIkon(),
                            size: 30,
                            color: Colors.white24,
                          ),
                        ),
                      )
                    else
                      Center(
                        child: Icon(
                          _yedekIkon(),
                          size: 30,
                          color: Colors.white24,
                        ),
                      ),
                    // Favori yildizi
                    if (widget.channel.favorite)
                      const Positioned(
                        top: 5,
                        right: 5,
                        child: Icon(Icons.star_rounded, size: 15, color: Colors.amber),
                      ),
                    // Alt baslik seridi
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(6, 10, 6, 5),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: P.scrimGrad,
                          ),
                        ),
                        child: Text(
                          widget.channel.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          // : METIN GOLGESI KALDIRILDI (blurRadius 3).
                          // Kart basina her metin icin ayri bulaniklik
                          // gecisi (blur pass) hesaplaniyordu; gorunur
                          // kartlarin sayisiyla carpilinca kaydirma
                          // sirasinda olculebilir maliyet olusturuyordu.
                          // Okunabilirlik zaten alttaki `P.scrimGrad`
                          // perdesinden geliyor - gorsel fark yok denecek
                          // kadar az, maliyet sifir.
                          style: const TextStyle(
                            fontSize: 10,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
            ),
          );
      },
    );
  }
}
