import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_tv/native_bridge.dart';
import 'package:open_tv/hstream_card.dart';
import 'package:open_tv/hstream_hub.dart';
import 'package:open_tv/hstream_route.dart';
import 'package:open_tv/loading.dart';
import 'package:open_tv/models/channel.dart';
import 'package:open_tv/models/filters.dart';
import 'package:open_tv/models/home_manager.dart';
import 'package:open_tv/models/media_type.dart';
import 'package:open_tv/models/id_data.dart';
import 'package:open_tv/models/node.dart';
import 'package:open_tv/models/node_type.dart';
import 'package:open_tv/models/sort_type.dart';
import 'package:open_tv/models/view_type.dart';
import 'package:open_tv/select_dialog.dart';
import 'package:open_tv/settings_view.dart';
import 'package:open_tv/error.dart';
import 'package:open_tv/utils.dart';
import 'package:open_tv/l10n.dart';

///  — BİRLEŞİK TASARIM v3 (onaylı):
/// - Alt bar / sol rail YOK. Menü = hub kutuları.
/// - Hub = kök ekran; bölümler (Canlı/Film/Dizi/Favori) hub'ın ÜSTÜNE
///   HStreamPageRoute ile yumuşak animasyonla PUSH edilir ( animasyon fix).
/// - Bölümde ← veya sistem geri tuşu → hub.
/// - Kategoriler: Canlı/Film/Dizi kutuları kategori kapaklarını açar
///   (); 'Tümü' kartı kategorisiz tam listeye götürür.
/// - Grid kompakt kapaklar: dikey 4 / yatay 6 / TV 7 sütun.
/// - TV de aynı Home(tvMode: true) + aynı hub.
class Home extends StatefulWidget {
  final HomeManager home;
  final bool refresh;
  final bool firstLaunch;
  final bool tvMode;
  const Home({
    super.key,
    required this.home,
    this.refresh = false,
    this.firstLaunch = false,
    this.tvMode = false,
  });
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  Timer? _debounce;
  bool reachedMax = false;
  final int pageSize = 36;
  List<Channel> channels = [];
  TextEditingController searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _keywordsFocusNode = FocusNode(skipTraversal: true);
  final FocusNode _sortFocusNode = FocusNode(skipTraversal: true);
  final ScrollController _scrollController = ScrollController();
  int currentlyFocusedChannel = 0;
  bool isLoading = false;
  bool blockSettings = false;
  bool scrolledDeepEnough = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    _searchFocusNode.onKey = _handleSearchRawKey;
    _keywordsFocusNode.onKeyEvent = _handleKeywordsKeyEvent;
    _sortFocusNode.onKeyEvent = _handleSortKeyEvent;
    initializeAsync();
  }

  Future<void> initializeAsync() async {
    if (widget.home.filters.sourceIds == null) {
      final sources = await NativeBridge.instance.getEnabledSourcesMinimal();
      widget.home.filters.sourceIds = sources;
    }
    if (widget.home.filters.mediaTypes == null) {
      final settings = await NativeBridge.instance.getSettings();
      widget.home.filters.mediaTypes = const [
        MediaType.livestream,
        MediaType.movie,
        MediaType.serie,
      ];
      widget.home.filters.sort = settings.defaultSort;
    }
    await load();
    if (!mounted) return;
    if (widget.firstLaunch) {
      await Utils.maybeShowWhatsNew(context);
    }
    if (!mounted) return;
    if (widget.refresh) {
      Error.tryAsyncNoLoading(
        () async {
          setState(() {
            blockSettings = true;
          });
          await NativeBridge.instance.refreshAll();
        },
        context,
        true,
        L.t("kaynaklar_yenilendi"),
      );
      setState(() {
        blockSettings = false;
      });
    }
  }

  void showSortDialog() {
    showDialog(
      barrierDismissible: true,
      context: context,
      builder: (context) => SelectDialog(
        title: L.t("siralama"),
        data: SortType.values
            .map((x) => IdData(id: x.index, data: sortTypeToString(x)))
            .toList(),
        action: (sort) {
          setState(() {
            widget.home.filters.sort = SortType.values[sort];
          });
          Navigator.of(context).pop();
          load(false);
          _varsayilaniGuncelle(SortType.values[sort]);
        },
      ),
    );
  }

  void scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  // : bolum icinde siralama degistirince VARSAYILAN da guncellenir.
  // ("providera geciremiyorum" kok neden: ekranda secilen siralama geri
  // donunce kayboluyor, ayarlardaki varsayilan devreye giriyordu.)
  Future<void> _varsayilaniGuncelle(SortType yeni) async {
    try {
      final ayarlar = await NativeBridge.instance.getSettings();
      ayarlar.defaultSort = yeni;
      await NativeBridge.instance.updateSettings(ayarlar);
    } catch (_) {}
  }

  Future<void> load([bool more = false]) async {
    if (more) {
      widget.home.filters.page++;
    } else {
      widget.home.filters.page = 1;
    }
    await Error.tryAsyncNoLoading(() async {
      List<Channel> channels = await NativeBridge.instance.getChannels(
        widget.home.filters,
      );
      // /10.7: ust listelerde ismi TAM ayni icerikten tek tane.
      // ONEMLI: sayfalama karari HAM sayiya gore verilir (ayiklama sonrasi
      // uzunluk kullanirsak sayfa kisalir ve liste ERKEN KESILIRDI).
      final hamSayi = channels.length;
      if (widget.home.node == null) {
        final gorulen = <String>{};
        if (more) {
          gorulen.addAll(this.channels.map((c) => c.name));
        }
        channels = channels.where((c) => gorulen.add(c.name)).toList();
      }
      if (!more) {
        setState(() {
          this.channels = channels;
        });
      } else {
        setState(() {
          this.channels.addAll(channels);
        });
      }
      reachedMax = hamSayi < pageSize;
      // : ayiklama/ksa sayfa yuzunden ızgara ekrana SIĞMADIYSA
      // (kaydirma olusmadiysa) sonraki sayfayı kendiliğinden cek -
      // yoksa liste kisa kalir ve gerisi HIC gelmezdi.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || reachedMax || isLoading) return;
        final sc = _scrollController;
        if (sc.hasClients && sc.position.maxScrollExtent <= 0) {
          load(true);
        }
      });
    }, context);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _debounce?.cancel();
    _searchFocusNode.dispose();
    _keywordsFocusNode.dispose();
    _sortFocusNode.dispose();
    super.dispose();
  }

  void _scrollListener() async {
    final bool shouldShow = _scrollController.offset > 200;

    if (scrolledDeepEnough != shouldShow) {
      setState(() => scrolledDeepEnough = shouldShow);
    }

    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent * 0.75 &&
        !isLoading &&
        !reachedMax) {
      setState(() {
        isLoading = true;
      });
      await load(true);
      setState(() {
        isLoading = false;
      });
    }
  }

  // ---------- TV kumanda / klavye odak yonetimi ----------
  bool _focusChannelsBelow() {
    return FocusScope.of(context).focusInDirection(TraversalDirection.down);
  }

  static const int _androidFlagSoftKeyboard = 0x2;

  bool _isFromSoftKeyboard(RawKeyEvent event) {
    final data = event.data;
    return data is RawKeyEventDataAndroid &&
        (data.flags & _androidFlagSoftKeyboard) != 0;
  }

  KeyEventResult _handleSearchRawKey(FocusNode node, RawKeyEvent event) {
    if (_isFromSoftKeyboard(event)) {
      return KeyEventResult.ignored;
    }
    if (event is RawKeyDownEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.goBack) {
        bool moved = FocusScope.of(
          context,
        ).focusInDirection(TraversalDirection.down);
        if (!moved) {
          node.unfocus();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        bool moved = FocusScope.of(
          context,
        ).focusInDirection(TraversalDirection.down);
        if (moved) {
          return KeyEventResult.handled;
        }
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        _keywordsFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleKeywordsKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowLeft) {
        _searchFocusNode.requestFocus();
        searchController.selection = TextSelection.fromPosition(
          TextPosition(offset: searchController.text.length),
        );
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        _sortFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        bool moved = FocusScope.of(
          context,
        ).focusInDirection(TraversalDirection.down);
        if (moved) {
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleSortKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowLeft) {
        _keywordsFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        bool moved = FocusScope.of(
          context,
        ).focusInDirection(TraversalDirection.down);
        if (moved) {
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  // ---------- GEZINME (: push + yumusak animasyon) ----------
  void updateViewMode(ViewType type, [List<MediaType>? mediaTypes]) {
    Navigator.of(context).push(
      HStreamPageRoute(
        builder: (context) => Home(
          tvMode: widget.tvMode,
          home: HomeManager(
            filters: Filters(
              viewType: type,
              mediaTypes: mediaTypes ?? widget.home.filters.mediaTypes,
              sourceIds: widget.home.filters.sourceIds,
              // FIX (): siralama devralinir -> "Saglayici" her yerde
              sort: widget.home.filters.sort,
            ),
          ),
        ),
      ),
    );
  }

  void setNode(Node node) {
    final home = HomeManager(
      node: node,
      filters: Filters(
        viewType: ViewType.all,
        mediaTypes: widget.home.filters.mediaTypes,
        sourceIds: widget.home.filters.sourceIds,
        sort: widget.home.filters.sort,
      ),
    );
    if (widget.home.filters.groupId != null) {
      home.filters.groupId = widget.home.filters.groupId;
    } else if (node.type == NodeType.category) {
      home.filters.groupId = node.id;
    }
    if (node.type == NodeType.series) home.filters.seriesId = node.id;
    if (node.type == NodeType.season) {
      home.filters.seriesId = widget.home.filters.seriesId;
      home.filters.seasonId = node.id;
    }
    Navigator.of(context).push(
      HStreamPageRoute(
        builder: (context) => Home(home: home, tvMode: widget.tvMode),
      ),
    );
  }

  Future<void> hubYonlendir(String hedef) async {
    // : Ayarlar'daki varsayilan siralama her bolum acilisinda TAZE
    // okunur (eski kod acilis degerini ezberliyordu -> ayar ise yaramazdi).
    SortType siralama = widget.home.filters.sort;
    try {
      final ayarlar = await NativeBridge.instance.getSettings();
      siralama = ayarlar.defaultSort;
      widget.home.filters.sort = siralama;
    } catch (_) {}
    switch (hedef) {
      case 'canli':
        updateViewMode(ViewType.categories, const [MediaType.livestream]);
      case 'film':
        updateViewMode(ViewType.categories, const [MediaType.movie]);
      case 'dizi':
        updateViewMode(ViewType.categories, const [MediaType.serie]);
      case 'favori':
        updateViewMode(ViewType.favorites, const [
          MediaType.livestream,
          MediaType.movie,
          MediaType.serie,
        ]);
    }
  }

  void ayarlariAc() {
    Navigator.of(context).push(
      HStreamPageRoute(
        builder: (context) => SettingsView(tvMode: widget.tvMode),
      ),
    );
  }

  bool get _kategoriModu =>
      widget.home.filters.viewType == ViewType.categories &&
      widget.home.filters.groupId == null &&
      widget.home.filters.seriesId == null;

  Widget _tumuKarti() {
    return Material(
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        splashColor: Colors.white24,
        onTap: () => updateViewMode(
          ViewType.all,
          widget.home.filters.mediaTypes,
        ),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF5642D6), Color(0xFF7A52E0)],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.grid_view_rounded, size: 28, color: Colors.white),
              SizedBox(height: 4),
              Text(
                L.t('tumu'),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _hubModu =>
      widget.home.node == null &&
      widget.home.filters.viewType == ViewType.all &&
      (widget.home.filters.mediaTypes == null ||
          widget.home.filters.mediaTypes!.length >= 3);

  String get _bolumAdi {
    if (widget.home.node != null) return widget.home.node.toString();
    if (widget.home.filters.viewType == ViewType.favorites) {
      return L.t('favoriler_baslik');
    }
    final mt = widget.home.filters.mediaTypes;
    if (mt != null && mt.length == 1) {
      if (mt.first == MediaType.livestream) return L.t('canli_tv_baslik');
      if (mt.first == MediaType.movie) return L.t('filmler_baslik');
      if (mt.first == MediaType.serie) return L.t('diziler_baslik');
    }
    return 'HStream';
  }

  @override
  Widget build(BuildContext context) {
    final Widget govde = Loading(
      child: SafeArea(
        child: _hubModu
            ? HStreamHub(
                onYonlendir: hubYonlendir,
                setNode: setNode,
                onAyar: ayarlariAc,
                tvMode: widget.tvMode,
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final double width = constraints.maxWidth;
                  // Onayli tasarim: dikey 4 / yatay 6 / TV 7 sira kompakt kapak
                  final int crossAxisCount = width < 480
                      ? 4
                      : (width < 760 ? 6 : 7);
                  return CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          child: Center(
                            child: TextField(
                              focusNode: _searchFocusNode,
                              style: TextStyle(
                                fontSize: Theme.of(
                                  context,
                                ).textTheme.titleMedium?.fontSize!,
                              ),
                              controller: searchController,
                              textInputAction: TextInputAction.search,
                              onEditingComplete: _focusChannelsBelow,
                              onChanged: (query) {
                                _debounce?.cancel();
                                _debounce = Timer(
                                  const Duration(milliseconds: 500),
                                  () {
                                    widget.home.filters.query = query;
                                    load(false);
                                  },
                                );
                              },
                              decoration: InputDecoration(
                                hintText: L.t("ara"),
                                hintStyle: TextStyle(
                                  fontSize: Theme.of(
                                    context,
                                  ).textTheme.titleMedium?.fontSize!,
                                ),
                                prefixIcon: const Icon(Icons.search),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      focusNode: _keywordsFocusNode,
                                      onPressed: () {
                                        widget.home.filters.useKeywords =
                                            !widget.home.filters.useKeywords;
                                        load(false);
                                      },
                                      icon: Icon(
                                        widget.home.filters.useKeywords
                                            ? Icons.label
                                            : Icons.label_outline,
                                      ),
                                      tooltip: L.t('kelime_ara'),
                                    ),
                                    IconButton(
                                      focusNode: _sortFocusNode,
                                      onPressed: showSortDialog,
                                      icon: const Icon(Icons.sort),
                                      tooltip: L.t('siralama'),
                                    ),
                                  ],
                                ),
                                filled: true,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                        sliver: SliverGrid(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            if (_kategoriModu && index == 0) {
                              return _tumuKarti();
                            }
                            final channel =
                                channels[_kategoriModu ? index - 1 : index];
                            return HStreamCard(
                              channel: channel,
                              parentContext: context,
                              setNode: setNode,
                              autofocus: index == currentlyFocusedChannel,
                              onSelect: () => currentlyFocusedChannel = index,
                              // : BOLUM LISTESI EKRANDAN DOGRUDAN TASINIR.
                              // Ekranda gorunen liste = oynaticidaki serit.
                              // (Yeniden sorgu/kimlik tasima YOK - risk sifir)
                              diziId: widget.home.filters.seriesId,
                              sezonId: widget.home.filters.seasonId,
                              bolumler: widget.home.filters.seasonId != null
                                  ? channels
                                  : null,
                              // : canli kanal oynaticida konum rozeti
                              konumEtiketi: (channel.mediaType ==
                                          MediaType.livestream &&
                                      reachedMax)
                                  ? "${_kategoriModu ? index : index + 1}"
                                      "/${channels.length}"
                                  : null,
                            );
                          }, childCount: channels.length + (_kategoriModu ? 1 : 0)),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                childAspectRatio: 0.72,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                              ),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
    return Scaffold(
      appBar: _hubModu
          ? null
          : AppBar(
              title: Text(
                _bolumAdi,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              automaticallyImplyLeading: !widget.tvMode,
              leading: !widget.tvMode
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: L.t('geri'),
                      onPressed: () => Navigator.of(context).pop(),
                    )
                  : null,
            ),
      body: govde,
      floatingActionButton: !_hubModu && !widget.tvMode
          ? IgnorePointer(
              ignoring: !scrolledDeepEnough,
              child: AnimatedOpacity(
                opacity: scrolledDeepEnough ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: FloatingActionButton(
                  onPressed: scrollToTop,
                  shape: const CircleBorder(),
                  tooltip: L.t('yukari'),
                  child: const Icon(Icons.arrow_upward),
                ),
              ),
            )
          : null,
    );
  }
}
