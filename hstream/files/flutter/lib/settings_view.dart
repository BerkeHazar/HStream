import 'package:flutter/material.dart';
import 'package:open_tv/native_bridge.dart';
import 'package:open_tv/nsfw.dart';
import 'package:open_tv/player_preferences.dart';
import 'package:open_tv/son_izlenen.dart';
import 'package:open_tv/l10n.dart';
import 'package:open_tv/xtream_bilgi.dart';
import 'package:open_tv/confirm_delete.dart';
import 'package:open_tv/select_dialog.dart';
import 'package:open_tv/edit_dialog.dart';
import 'package:open_tv/loading.dart';
import 'package:open_tv/models/id_data.dart';
import 'package:open_tv/models/settings.dart';
import 'package:open_tv/models/source.dart';
import 'package:open_tv/models/source_type.dart';
import 'package:open_tv/models/sort_type.dart';
import 'package:open_tv/error.dart';
// : Hakkında ekranı (sürüm / lisans / kaynak / yenilikler / güncelleme)
import 'package:open_tv/hstream_hakkinda.dart';
import 'package:open_tv/hstream_route.dart';
// : kaynak satırındaki kompakt aksiyon düğmeleri marka rengini kullanır
import 'package:open_tv/palet.dart';
import 'package:open_tv/setup.dart';
import 'package:url_launcher/url_launcher.dart';

/// : Ayarlar — alt bar/rail yok; AppBar'daki ← hub'a dondurur.
/// NSFW bolumu eklendi (varsayilan: her sey gorunur; anahtar acilinca
/// yetiskin icerik ad + kategori bazli gizlenir).
class SettingsView extends StatefulWidget {
  final bool tvMode;

  const SettingsView({super.key, this.tvMode = false});

  @override
  State<SettingsView> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsView> {
  Settings settings = Settings();
  List<Source> sources = [];
  bool loading = true;
  bool nsfwHide = Nsfw.hide;
  bool sonIzlenenGoster = SonIzlenen.goster;
  final Map<int, XtreamBilgi> xtreamBilgiler = {};

  @override
  void initState() {
    super.initState();
    initAsync();
  }

  Future<void> initAsync() async {
    var results = await Future.wait([
      NativeBridge.instance.getSettings(),
      NativeBridge.instance.getSources(),
    ]);
    setState(() {
      settings = results[0] as Settings;
      sources = results[1] as List<Source>;
      loading = false;
    });
    _xtreamCek();
  }

  Future<void> _xtreamCek() async {
    final hedefler = sources
        .where((k) => k.sourceType == SourceType.xtream && k.id != null)
        .toList();
    if (hedefler.isEmpty) return;
    // PERFORMANS: Önceden her kaynak için SIRAYLA istek atılıyordu (N kaynak =
    // N kez bekleme) ve her sonuçta ayrı setState çağrılıyordu (N kez tam
    // yeniden çizim). Artık istekler paralel, tek setState.
    final sonuclar = await Future.wait(
      hedefler.map((k) async => MapEntry(k.id!, await xtreamBilgiCek(k))),
    );
    if (!mounted) return;
    setState(() {
      for (final s in sonuclar) {
        if (s.value != null) xtreamBilgiler[s.key] = s.value!;
      }
    });
  }

  String _dilEtiket() {
    switch (HDil.secim) {
      case 'tr':
        return 'Türkçe';
      case 'en':
        return 'English';
      case 'es':
        return 'Español';
      case 'de':
        return 'Deutsch';
      case 'fr':
        return 'Français';
      default:
        return L.t('dil_auto');
    }
  }

  Future<void> _dilSec(BuildContext context) async {
    final kodlar = ['auto', 'tr', 'en', 'es', 'de', 'fr'];
    final adlar = [
      L.t('dil_auto'),
      'Türkçe',
      'English',
      'Español',
      'Deutsch',
      'Français',
    ];
    await showDialog<void>(
      barrierDismissible: true,
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(L.t('dil')),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < kodlar.length; i++)
                  ListTile(
                    autofocus: i == 0,
                    title: Text(adlar[i]),
                    selected: HDil.secim == kodlar[i],
                    onTap: () {
                      Navigator.of(ctx).pop();
                      HDil.ayarla(kodlar[i]);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // : tampon (buffer) süresi seçimi — donan IPTV yayınları için.
  Future<void> _tamponSec(BuildContext context) async {
    final secenekler = PlayerPreferences.tamponSecenekler;
    await showDialog<void>(
      barrierDismissible: true,
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(L.t('tampon')),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final sn in secenekler)
                  ListTile(
                    title: Text(
                      L.t('tampon_sn').replaceFirst('%s', sn.toString()),
                    ),
                    selected: PlayerPreferences.tamponSn == sn,
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await PlayerPreferences.tamponAyarla(sn);
                      if (!mounted) return;
                      setState(() {});
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // : altyazı boyutu seçimi — TV'de varsayılan kocaman kalıyordu.
  Future<void> _altyaziBoyutSec(BuildContext context) async {
    final secenekler = PlayerPreferences.altyaziSecenekler;
    await showDialog<void>(
      barrierDismissible: true,
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(L.t('altyazi_boyut')),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final sp in secenekler)
                  ListTile(
                    title: Text(
                      L.t('altyazi_sp').replaceFirst('%s', sp.toString()),
                    ),
                    selected: PlayerPreferences.altyaziSp == sp,
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await PlayerPreferences.altyaziAyarla(sp);
                      if (!mounted) return;
                      setState(() {});
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> showEditDialog(BuildContext context, Source source) async {
    await showDialog(
      barrierDismissible: true,
      context: context,
      builder: (builder) => EditDialog(
        source: source,
        afterSave: reloadSources,
        parentContext: context,
      ),
    );
  }

  Future<void> _showDefaultSortDialog(BuildContext context) async {
    showDialog(
      barrierDismissible: true,
      context: context,
      builder: (BuildContext context) {
        return SelectDialog(
          title: L.t("varsayilan_siralama"),
          data: SortType.values
              .map((x) => IdData(id: x.index, data: sortTypeToString(x)))
              .toList(),
          action: (sort) {
            setState(() {
              settings.defaultSort = SortType.values[sort];
              updateSettings();
            });
            Navigator.of(context).pop();
          },
        );
      },
    );
  }

  Future<void> toggleSource(Source source) async {
    await Error.tryAsyncNoLoading(
      () async => await NativeBridge.instance.setSourceEnabled(
        source.id!,
        !source.enabled,
      ),
      context,
    );
    await reloadSources();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(!source.enabled ? L.t("kaynak_acildi") : L.t("kaynak_kapatildi")),
        duration: const Duration(milliseconds: 500),
      ),
    );
  }

  Widget getSource(Source source) {
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      elevation: 5,
      child: ListTile(
        // : KAYNAK SATIRI DARLIĞI DÜZELTMESİ —
        // Önceden burada üç adet VARSAYILAN `IconButton` vardı. Her biri
        // 48dp dokunma alanı + 8dp iç boşluk = ~64dp ister; üçü birlikte
        // ~192dp'yi yalnızca sağ tarafta tüketiyordu. Dar telefonlarda
        // başlık/alt başlık ezilip "…" oluyor, satır sıkışmış görünüyordu.
        // Çözüm: özel `_kaynakAksiyon` düğmesi (36dp dokunma alanı,
        // 4dp boşluk → ~40dp/adet). Üç düğme ~120dp'ye iner ve başlığa
        // ~70dp daha fazla yer kalır. `tvMode`da zaten en çok iki düğme
        // göründüğü için her iki düzen de rahatlar.
        leading: Icon(source.enabled ? Icons.tv_rounded : Icons.tv_off_rounded),
        horizontalTitleGap: 16,
        onLongPress: () => toggleSource(source),
        contentPadding: const EdgeInsets.only(left: 16, right: 4),
        title: Text(source.name),
        subtitle: Text(
          [
            source.sourceType.label,
            if (source.id != null && xtreamBilgiler[source.id!] != null)
              xtreamAltYazi(xtreamBilgiler[source.id!]!),
          ].join(" · "),
        ),
        trailing: Row(
          mainAxisSize:
              MainAxisSize.min, // Ensures the row takes up minimal space
          children: [
            Offstage(
              offstage: source.sourceType == SourceType.m3u,
              child: _kaynakAksiyon(
                ikon: Icons.refresh_rounded,
                ipucu: L.t("kaynak_yenilendi"),
                onTap: () async {
                  await Error.tryAsync(
                    () async {
                      await NativeBridge.instance.refreshSource(source);
                    },
                    context,
                    L.t("kaynak_yenilendi"),
                  );
                },
              ),
            ),
            Offstage(
              offstage:
                  source.sourceType == SourceType.m3u || widget.tvMode,
              child: _kaynakAksiyon(
                ikon: Icons.edit_rounded,
                ipucu: L.t("kaynak_duzenle"),
                onTap: () async => await showEditDialog(context, source),
              ),
            ),
            _kaynakAksiyon(
              ikon: Icons.delete_rounded,
              ipucu: L.t("sil"),
              tehlike: true,
              onTap: () async => await showConfirmDeleteDialog(source),
            ),
          ],
        ),
      ),
    );
  }

  // : Kaynak satırındaki kompakt aksiyon düğmesi.
  // `IconButton`ın varsayılan dokunma alanı 48dp + 8dp iç boşluk = ~64dp;
  // üçü birlikte sağdan ~192dp yiyordu ve dar telefonlarda başlığı
  // "…" hâline getiriyordu. 36dp hâlâ ergonomik (Material'ın önerdiği en
  // küçük hedef 36dp) ve üç düğmeyi ~120dp'ye indirir. Renk de nötr beyaz
  // yerine markaya çekildi: satır artık tekdüze bir ikon yığını gibi
  // görünmüyor, hiyerarşi net (sil = soluk, diğerleri = vurgulu).
  Widget _kaynakAksiyon({
    required IconData ikon,
    required String ipucu,
    required VoidCallback onTap,
    bool tehlike = false,
  }) {
    return Tooltip(
      message: ipucu,
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            ikon,
            size: 20,
            color: tehlike ? P.textTertiary : P.brandLight,
          ),
        ),
      ),
    );
  }

  Future<void> showConfirmDeleteDialog(Source source) async {
    await showDialog(
      barrierDismissible: true,
      context: context,
      builder: (builder) => ConfirmDelete(
        type: "source",
        name: source.name,
        confirm: () async {
          await Error.tryAsync(
            () async => await NativeBridge.instance.deleteSource(source.id!),
            context,
            L.t("kaynak_silindi"),
          );
          await reloadSources();
          if (!mounted) return;
          if (sources.isEmpty) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) => Setup(tvMode: widget.tvMode),
              ),
              (route) => false,
            );
          }
        },
      ),
    );
  }

  Future<void> reloadSources() async {
    await Error.tryAsyncNoLoading(
      () async => sources = await NativeBridge.instance.getSources(),
      context,
    );
    setState(() {
      sources;
    });
    _xtreamCek();
  }

  Future<void> updateSettings() async {
    await Error.tryAsyncNoLoading(
      () async => await NativeBridge.instance.updateSettings(settings),
      context,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget govde = Visibility(
      visible: !loading,
      child: Loading(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(vertical: 10),
            child: ListView(
              children: [
                const SizedBox(height: 6),
                ListTile(
                  title: Text(L.t("varsayilan_siralama")),
                  subtitle: Text(sortTypeToString(settings.defaultSort)),
                  onTap: () async => await _showDefaultSortDialog(context),
                ),
                ListTile(
                  title: Text(L.t("tv_modu")),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: settings.forceTVMode,
                        onChanged: (bool value) {
                          setState(() {
                            settings.forceTVMode = value;
                          });
                          updateSettings();
                        },
                      ),
                    ],
                  ),
                ),
                ListTile(
                  title: Text(L.t("dusuk_gecikme")),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: settings.lowLatency,
                        onChanged: (bool value) {
                          setState(() {
                            settings.lowLatency = value;
                          });
                          updateSettings();
                        },
                      ),
                    ],
                  ),
                ),
                ListTile(
                  title: Text(L.t("acilis_yenile")),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: settings.refreshOnStart,
                        onChanged: (bool value) {
                          setState(() {
                            settings.refreshOnStart = value;
                          });
                          updateSettings();
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                  child: Text(
                    L.t('gorunum'),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.language_rounded),
                  title: Text(L.t("dil")),
                  subtitle: Text(_dilEtiket()),
                  onTap: () => _dilSec(context),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                  child: Text(
                    L.t('icerik'),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.history_rounded),
                  title: Text(L.t("son_izlenenler")),
                  subtitle: Text(L.t("son_izlenenler_sub")),
                  value: sonIzlenenGoster,
                  onChanged: (bool value) async {
                    await SonIzlenen.ayarla(value);
                    if (!mounted) return;
                    setState(() {
                      sonIzlenenGoster = value;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          value
                              ? L.t("son_izlenen_on")
                              : L.t("son_izlenen_off"),
                        ),
                        duration: const Duration(milliseconds: 700),
                      ),
                    );
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.no_adult_content_rounded),
                  title: Text(L.t("nsfw")),
                  subtitle: Text(L.t("nsfw_sub")),
                  value: nsfwHide,
                  onChanged: (bool value) async {
                    await Nsfw.ayarla(value);
                    if (!mounted) return;
                    setState(() {
                      nsfwHide = value;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          value
                              ? L.t("nsfw_on")
                              : L.t("nsfw_off"),
                        ),
                        duration: const Duration(milliseconds: 700),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_rounded),
                  title: Text(L.t("gecmis_temizle")),
                  subtitle: Text(L.t("gecmis_temizle_sub")),
                  onTap: () async {
                    final onay = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(L.t("gecmis_temizle")),
                        content: Text(L.t("gecmis_temizle_q")),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(L.t("vazgec")),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(L.t("temizle")),
                          ),
                        ],
                      ),
                    );
                    if (onay != true) return;
                    await NativeBridge.instance.clearHistory();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(L.t("gecmis_temizlendi")),
                        duration: Duration(milliseconds: 900),
                      ),
                    );
                  },
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                  child: Text(
                    L.t('oynatici'),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.memory_rounded),
                  title: Text(L.t("tampon")),
                  subtitle: Text(
                    L.t("tampon_sub").replaceFirst(
                      '%s',
                      PlayerPreferences.tamponSn.toString(),
                    ),
                  ),
                  onTap: () => _tamponSec(context),
                ),
                ListTile(
                  leading: const Icon(Icons.subtitles_rounded),
                  title: Text(L.t("altyazi_boyut")),
                  subtitle: Text(
                    L.t("altyazi_boyut_sub").replaceFirst(
                      '%s',
                      PlayerPreferences.altyaziSp.toString(),
                    ),
                  ),
                  onTap: () => _altyaziBoyutSec(context),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.picture_in_picture_alt_rounded),
                  title: Text(L.t("pip")),
                  subtitle: Text(L.t("pip_sub")),
                  value: PlayerPreferences.pipAcik,
                  onChanged: (bool value) async {
                    await PlayerPreferences.pipAyarla(value);
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: Text(
                        L.t('kaynaklar'),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () async => await Error.tryAsync(
                            () async =>
                                await NativeBridge.instance.refreshAll(),
                            context,
                            L.t("kaynaklar_yenilendi"),
                          ),
                          icon: const Icon(Icons.refresh_rounded),
                          tooltip: L.t('tumunu_yenile'),
                        ),
                        IconButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => Setup(
                                showAppBar: true,
                                tvMode: widget.tvMode,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.add_rounded),
                          tooltip: L.t('kaynak_ekle'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...sources.map(getSource),
                const Divider(),
                // : HAKKINDA — sürüm, lisans, kaynak kodu, yenilikler ve
                // güncelleme denetimi. GitHub satırından ÖNCE gelir çünkü
                // kullanıcı önce "hangi sürümdeyim / güncelleme var mı"
                // sorusunun cevabını arar.
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: Text(L.t("hakkinda")),
                  subtitle: Text(L.t("hakkinda_sub")),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(
                    context,
                    HStreamPageRoute(
                      builder: (_) => const HStreamHakkinda(),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.code_rounded),
                  title: Text(L.t("github")),
                  subtitle: Text(L.t("github_sub")),
                  onTap: () async {
                    try {
                      await launchUrl(
                        Uri.parse("https://github.com/BerkeHazar/HStream"),
                        mode: LaunchMode.externalApplication,
                      );
                    } catch (_) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(L.t("tarayici_yok")),
                            duration: Duration(milliseconds: 900),
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          L.t('ayarlar'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: L.t('geri'),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: govde,
    );
  }
}
