import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_tv/generated/generated_proto.pb.dart' as gen;
import 'package:open_tv/home.dart';
import 'package:open_tv/app_mode.dart';
import 'package:open_tv/models/custom_shortcut.dart';
import 'package:open_tv/models/device_detector.dart';
import 'package:open_tv/models/filters.dart';
import 'package:open_tv/models/home_manager.dart';
import 'package:open_tv/models/settings.dart';
import 'package:open_tv/utils.dart';
import 'package:open_tv/native_bridge.dart' as nb;
import 'package:open_tv/nsfw.dart';
import 'package:open_tv/player_preferences.dart';
import 'package:open_tv/son_izlenen.dart';
import 'package:open_tv/l10n.dart';
import 'package:open_tv/hstream_hub.dart';
import 'package:open_tv/hstream_hakkinda.dart';
import 'package:open_tv/hstream_surum.dart';
import 'package:open_tv/palet.dart';
import 'package:open_tv/setup.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_kit/media_kit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isAndroid) {
    MediaKit.ensureInitialized();
  }

  // PERFORMANS: Bağımsız işler aynı anda başlatılır.
  // Önceden 8 işlem sırayla bekleniyordu; bu, açılışta siyah ekranı uzatıyordu.
  // Artık yalnızca gerçekten birbirine bağlı olanlar sırayla çalışır.
  final appDirF = getApplicationSupportDirectory();
  final tempDirF = getApplicationCacheDirectory();
  final nsfwF = Nsfw.yukle();
  final sonIzlenenF = SonIzlenen.yukle();
  final dilF = HDil.yukle();
  // : oynatıcı tercihleri (tampon/altyazı/PiP) — diğer tercihlerle paralel
  final oynaticiF = PlayerPreferences.yukle();
  // : sürüm bilgisi (güncelleme denetimi + "yenilikler" için) — paralel
  final surumF = HSurum.yukle();
  final touchF = Utils.hasTouchScreen();
  final tvF = DeviceDetector.isTV();

  final appDir = await appDirF;
  final tempDir = await tempDirF;

  // Veritabanı: hasSources / getSettings bunu beklemek zorunda.
  try {
    await nb.NativeBridge.instance.initialize(
      gen.InitMessage(dbPath: appDir.path, tempPath: tempDir.path),
    );
  } catch (e, stack) {
    if (!e.toString().contains(appDir.path)) {
      developer.log(
        "Failed to initialize NativeBridge",
        error: e,
        stackTrace: stack,
        name: "dev.fredol.open-tv",
      );
    }
  }

  // DB hazır — bu ikisi birbirinden bağımsız, paralel çalışır.
  final hasSourcesF = nb.NativeBridge.instance.hasSources();
  final settingsF = nb.NativeBridge.instance.getSettings();

  await nsfwF;
  await sonIzlenenF;
  await dilF;
  await oynaticiF;
  await surumF;
  final hasSources = await hasSourcesF;
  final settings = await settingsF;
  final hasTouchScreen = await touchF;
  final isTV = await tvF;

  runApp(
    MyApp(
      skipSetup: hasSources,
      settings: settings,
      hasTouchScreen: hasTouchScreen,
      isTV: isTV,
    ),
  );

  // : AÇILIŞ DENETİMLERİ — ilk kare çizildikten SONRA çalışır; açılışı
  // bekletmez. Sıra: önce "yenilikler" (yalnızca sürüm değiştiyse), sonra
  // güncelleme denetimi. İkisi üst üste çıkmasın diye yenilikler
  // gösterildiyse güncelleme sorusu bu açılışta atlanır.
  WidgetsBinding.instance.addPostFrameCallback((_) => _acilisDenetimleri());
}

/// : Açılışta "yenilikler" penceresi ve sessiz güncelleme denetimi.
///
/// Her adım hata toleranslıdır: ağ yok / DB yok / API kotası dolu olsa bile
/// uygulama normal açılır. Hiçbir hata kullanıcıya gösterilmez — güncelleme
/// denetimi "olsa iyi olur" özelliğidir, açılışı riske atmaz.
Future<void> _acilisDenetimleri() async {
  // 1) YENİLİKLER — sürüm değiştiyse bir kez gösterilir.
  try {
    if (HSurum.surum.isNotEmpty && await HSurum.yenilikGosterilmeli()) {
      final ctx = MyApp.navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        // : önce işaretle — diyalog açılamazsa (ör. kurulum ekranı) bir
        // sonraki açılışta tekrar tekrar denenmesin.
        await HSurum.yenilikGoruldu();
        await yeniliklerDialogGoster(ctx, HSurum.surum);
      }
      return;
    }
  } catch (_) {}

  // 2) GÜNCELLEME — en fazla 6 saatte bir, yeni sürüm varsa sorulur.
  try {
    if (!await HSurum.acilistaDenetlenmeli()) return;
    final guncelleme = await HSurum.denetle();
    if (guncelleme == null) return;
    if (await HSurum.atlandi(guncelleme.surum)) return;
    final ctx = MyApp.navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await guncellemeDialogGoster(ctx, guncelleme);
  } catch (_) {}
}

class MyApp extends StatelessWidget {
  final bool skipSetup;
  final Settings settings;
  final bool hasTouchScreen;
  final bool isTV;
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  const MyApp({
    super.key,
    required this.skipSetup,
    required this.settings,
    required this.hasTouchScreen,
    required this.isTV,
  });

  bool get _isEditingText {
    final focus = FocusManager.instance.primaryFocus;
    return focus?.context?.findAncestorWidgetOfExactType<EditableText>() !=
        null;
  }

  bool get _showFocusOutline =>
      !hasTouchScreen ||
      Platform.isLinux ||
      Platform.isWindows ||
      Platform.isMacOS;

  bool get _isTvMode =>
      settings.forceTVMode ||
      isTV ||
      (!hasTouchScreen && (Platform.isAndroid || Platform.isIOS));

  @override
  Widget build(BuildContext context) {
    AppMode.isTv = _isTvMode;
    return ValueListenableBuilder<int>(
      valueListenable: HGorsel.nesil,
      builder: (context, _, __) {
    return MaterialApp(
      title: 'HStream',
      navigatorKey: navigatorKey,
      navigatorObservers: [hstreamRouteObserver],
      builder: (context, child) {
        return CallbackShortcuts(
          bindings: {
            const CustomShortcut(
              SingleActivator(LogicalKeyboardKey.escape),
            ): () {
              if (_isEditingText) return;
              navigatorKey.currentState?.maybePop();
            },
            const CustomShortcut(
              SingleActivator(LogicalKeyboardKey.backspace),
            ): () {
              if (_isEditingText) return;
              navigatorKey.currentState?.maybePop();
            },
          },
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: P.tema(showFocusOutline: _showFocusOutline),
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      home: skipSetup
          ? Home(
              // : TV de ayni Home + ayni birlesik hub
              tvMode: _isTvMode,
              firstLaunch: true,
              refresh: settings.refreshOnStart,
              home: HomeManager(
                filters: Filters(viewType: settings.defaultView),
              ),
            )
          : Setup(tvMode: _isTvMode),
    );
      },
    );
  }
}
