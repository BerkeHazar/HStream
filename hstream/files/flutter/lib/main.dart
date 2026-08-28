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
import 'package:open_tv/son_izlenen.dart';
import 'package:open_tv/l10n.dart';
import 'package:open_tv/hstream_hub.dart';
import 'package:open_tv/setup.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_kit/media_kit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isAndroid) {
    MediaKit.ensureInitialized();
  }
  final appDir = await getApplicationSupportDirectory();
  final tempDir = await getApplicationCacheDirectory();
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
  await Nsfw.yukle();
  await SonIzlenen.yukle();
  await HDil.yukle();
  final hasSources = await nb.NativeBridge.instance.hasSources();
  final settings = await nb.NativeBridge.instance.getSettings();
  final hasTouchScreen = await Utils.hasTouchScreen();
  final isTV = await DeviceDetector.isTV();
  runApp(
    MyApp(
      skipSetup: hasSources,
      settings: settings,
      hasTouchScreen: hasTouchScreen,
      isTV: isTV,
    ),
  );
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
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7A52E0),
          surface: const Color(0xFF0A0A16),
          brightness: Brightness.dark,
          surfaceContainer: const Color(0xFF1D1F2F),
          surfaceContainerHighest: const Color(0xFF2C3344),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.focused) && _showFocusOutline) {
                return const BorderSide(
                  color: const Color(0xFFA78BFA), // HStream focus rengi
                  width: 4,
                );
              }
              return BorderSide.none;
            }),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.focused) && _showFocusOutline) {
                return const BorderSide(
                  color: const Color(0xFFA78BFA), // HStream focus rengi
                  width: 4,
                );
              }
              return null;
            }),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: ButtonStyle(
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.focused) && _showFocusOutline) {
                return const BorderSide(
                  color: const Color(0xFFA78BFA), // HStream focus rengi
                  width: 4,
                );
              }
              return null;
            }),
          ),
        ),
        switchTheme: SwitchThemeData(
          trackOutlineColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused) && _showFocusOutline) {
              return const Color(0xFFA78BFA);
            }
            return null;
          }),
          trackOutlineWidth: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused) && _showFocusOutline) {
              return 4;
            }
            return null;
          }),
        ),
        useMaterial3: true,
      ),
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
