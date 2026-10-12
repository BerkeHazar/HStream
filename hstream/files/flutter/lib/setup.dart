import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:animations/animations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:loader_overlay/loader_overlay.dart';
import 'package:open_tv/correction_modal.dart';
import 'package:open_tv/home.dart';
import 'package:open_tv/models/filters.dart';
import 'package:open_tv/models/home_manager.dart';
import 'package:open_tv/models/source.dart';
import 'package:open_tv/models/source_type.dart';
import 'package:open_tv/models/steps.dart';
import 'package:open_tv/models/view_type.dart';
import 'package:open_tv/error.dart';
import 'package:open_tv/native_bridge.dart';
import 'package:open_tv/l10n.dart';

class Setup extends StatefulWidget {
  final bool showAppBar;
  final bool tvMode;
  const Setup({super.key, this.showAppBar = false, this.tvMode = false});

  @override
  State<Setup> createState() => _SetupState();
}

class _SetupState extends State<Setup> {
  Steps step = Steps.welcome;
  SourceType selectedSourceType = SourceType.xtream;
  bool isForward = true;
  bool formValid = false;
  bool loading = false;
  final Map<Steps, FocusNode> focusNodes = {
    Steps.name: FocusNode(),
    Steps.url: FocusNode(),
    Steps.username: FocusNode(),
    Steps.password: FocusNode(),
  };
  final formPages = {Steps.name, Steps.url, Steps.username, Steps.password};
  final _formKeys = {
    Steps.name: GlobalKey<FormBuilderState>(),
    Steps.url: GlobalKey<FormBuilderState>(),
    Steps.username: GlobalKey<FormBuilderState>(),
    Steps.password: GlobalKey<FormBuilderState>(),
  };
  final formValues = {
    Steps.name: "",
    Steps.url: "",
    Steps.username: "",
    Steps.password: "",
  };
  final nextButtonFocusNode = FocusNode();
  Set<String> existingSourceNames = {};

  static const int _androidFlagSoftKeyboard = 0x2;

  static const List<SourceType> _turSirasi = [
    SourceType.xtream,
    SourceType.m3uUrl,
    SourceType.m3u,
  ];
  static const List<IconData> _turIkonlari = [
    Icons.key_rounded,
    Icons.link_rounded,
    Icons.folder_open_rounded,
  ];
  List<String> get _turAciklamalari => [
    L.t("xtream_alt"),
    L.t("m3uurl_alt"),
    L.t("m3u_alt"),
  ];

  bool _isFromSoftKeyboard(RawKeyEvent event) {
    final data = event.data;
    return data is RawKeyEventDataAndroid &&
        (data.flags & _androidFlagSoftKeyboard) != 0;
  }

  KeyEventResult _handleFormRawKey(FocusNode node, RawKeyEvent event) {
    if (_isFromSoftKeyboard(event)) {
      return KeyEventResult.ignored;
    }
    if (event is RawKeyDownEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.goBack) {
        bool moved = FocusScope.of(
          context,
        ).focusInDirection(TraversalDirection.left);
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
        bool moved = FocusScope.of(
          context,
        ).focusInDirection(TraversalDirection.right);
        if (moved) {
          return KeyEventResult.handled;
        }
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        bool moved = FocusScope.of(
          context,
        ).focusInDirection(TraversalDirection.left);
        if (moved) {
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> finish() async {
    loading = true;
    var result = await Error.tryAsync(
      () async {
        await NativeBridge.instance.processSource(
          Source(
            name: formValues[Steps.name]!,
            sourceType: selectedSourceType,
            url: selectedSourceType == SourceType.m3u
                ? formValues[Steps.url]!
                : await fixUrl(formValues[Steps.url]!),
            username: selectedSourceType == SourceType.xtream
                ? formValues[Steps.username]
                : null,
            password: selectedSourceType == SourceType.xtream
                ? formValues[Steps.password]
                : null,
          ),
        );
      },
      context,
      null,
      true,
      false,
    );
    loading = false;
    if (!result.success) {
      return;
    }
    setState(() {
      step = Steps.finish;
    });
  }

  Future<String> fixUrl(String url) async {
    var uri = Uri.parse(url);
    if (uri.scheme.isEmpty) {
      uri = Uri.parse("http://$uri");
    }
    if (uri.path == "/" || uri.path.isEmpty) {
      if (await showXtreamCorrectionModal()) {
        uri = uri.resolve("player_api.php");
      }
    }
    return uri.toString();
  }

  Future showXtreamCorrectionModal() async {
    return await showDialog(
      context: context,
      builder: (context) => const CorrectionModal(),
    );
  }

  bool _focusNext() {
    return FocusScope.of(context).focusInDirection(TraversalDirection.right);
  }

  @override
  void initState() {
    super.initState();
    nextButtonFocusNode.requestFocus();
    for (var node in focusNodes.values) {
      node.onKey = _handleFormRawKey;
    }
  }

  @override
  void dispose() {
    for (var focus in focusNodes.values) {
      focus.dispose();
    }
    nextButtonFocusNode.dispose();
    super.dispose();
  }

  Future<bool> selectFile() async {
    var path = (await FilePicker.platform.pickFiles())?.files.single.path;
    if (path == null) return false;
    // : yanlis dosya (ornegin fotograf) secilince sonsuz yukleme
    // oluyordu -> uzanti + icerik dogrulamasi, gecersizse Turkce hata.
    final lower = path.toLowerCase();
    final uzantiTamam = lower.endsWith('.m3u') ||
        lower.endsWith('.m3u8') ||
        lower.endsWith('.txt');
    if (!uzantiTamam) {
      _dosyaHatasi(L.t('dosya_uzanti'));
      return false;
    }
    try {
      final file = File(path);
      final bytes = await file
          .openRead(0, 4096)
          .fold<List<int>>(<int>[], (onceki, parca) => onceki..addAll(parca));
      final bas = utf8.decode(bytes, allowMalformed: true);
      final listeVar = bas.contains('#EXTM3U') ||
          bas.contains('http://') ||
          bas.contains('https://');
      if (!listeVar) {
        _dosyaHatasi(L.t('dosya_gecersiz'));
        return false;
      }
    } catch (_) {
      _dosyaHatasi(L.t('dosya_okunamadi'));
      return false;
    }
    formValues[Steps.url] = path;
    return true;
  }

  void _dosyaHatasi(String mesaj) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red[700],
        content: Text(mesaj, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  void prevStep() {
    if (loading) return;
    isForward = false;
    if (formPages.contains(step)) {
      formValues[step] =
          _formKeys[step]?.currentState?.fields[step.name]?.value;
    }
    setState(() {
      step = Steps.values[step.index - 1];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        formValid = _formKeys[step]?.currentState?.isValid == true;
      });
      if (formPages.contains(step)) focusNodes[step]?.requestFocus();
      if (step == Steps.welcome) {
        nextButtonFocusNode.requestFocus();
      }
    });
  }

  Future<void> handleNext() async {
    if (loading) return;
    isForward = true;
    if (formPages.contains(step)) {
      formValues[step] =
          _formKeys[step]?.currentState?.fields[step.name]?.value;
    }
    if (step == Steps.name) {
      var sourceName = formValues[step]!;
      if (await NativeBridge.instance.sourceNameExists(sourceName)) {
        existingSourceNames.add(sourceName);
        _formKeys[step]?.currentState?.validate();
        return;
      }
    }
    if (step == Steps.name && selectedSourceType == SourceType.m3u) {
      if (!await selectFile()) return;
      finish();
    } else if ((selectedSourceType == SourceType.m3uUrl && step == Steps.url) ||
        step == Steps.password) {
      finish();
    } else if (step == Steps.finish) {
      navigateToHome();
    } else {
      setState(() {
        step = Steps.values[step.index + 1];
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          if (formValues[step]?.isNotEmpty == true) {
            _formKeys[step]?.currentState?.validate();
          }
          formValid = _formKeys[step]?.currentState?.isValid == true;
        });
        if (formPages.contains(step)) focusNodes[step]?.requestFocus();
      });
    }
  }

  void navigateToHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => Home(
          // : TV de ayni birlesik Home
          tvMode: widget.tvMode,
          home: HomeManager(filters: Filters(viewType: ViewType.all)),
        ),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: step == Steps.welcome,
      onPopInvokedWithResult: (didPop, result) {
        if (step == Steps.finish || loading) return;
        if (!didPop) prevStep();
      },
      child: Scaffold(
        appBar: widget.showAppBar ? AppBar() : null,
        body: SafeArea(
          child: LoaderOverlay(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 16,
                  ),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: 0,
                      end: (step.index + 1) / Steps.values.length,
                    ),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOut,
                    builder: (context, value, child) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: value,
                          minHeight: 6,
                        ),
                      );
                    },
                  ),
                ),
                Expanded(
                  child: PageTransitionSwitcher(
                    duration: const Duration(milliseconds: 400),
                    reverse: !isForward,
                    transitionBuilder:
                        (child, primaryAnimation, secondaryAnimation) {
                          return SharedAxisTransition(
                            animation: primaryAnimation,
                            secondaryAnimation: secondaryAnimation,
                            transitionType: SharedAxisTransitionType.horizontal,
                            child: child,
                          );
                        },
                    child: currentPage,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: FocusTraversalGroup(
                    policy: OrderedTraversalPolicy(),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        AnimatedOpacity(
                          opacity: step != Steps.welcome && step != Steps.finish
                              ? 1
                              : 0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          child: IgnorePointer(
                            ignoring:
                                step == Steps.welcome || step == Steps.finish,
                            child: FocusTraversalOrder(
                              order: const NumericFocusOrder(2.0),
                              child: FilledButton.tonal(
                                onPressed: prevStep,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 16,
                                  ),
                                ),
                                child: Text(
                                  L.t("geri"),
                                  style: const TextStyle(fontSize: 18),
                                ),
                              ),
                            ),
                          ),
                        ),
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(1.0),
                          child: FilledButton(
                            focusNode: nextButtonFocusNode,
                            onPressed: !formPages.contains(step) || formValid
                                ? handleNext
                                : null,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                            ),
                            child: Text(
                              step == Steps.name &&
                                      selectedSourceType == SourceType.m3u
                                  ? L.t("dosya_sec")
                                  : step == Steps.finish
                                  ? L.t("bitti")
                                  : L.t("ileri"),
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget get currentPage {
    switch (step) {
      case Steps.welcome:
        return getPage(
          L.t("hosgeldin"),
          widget.showAppBar ? L.t("yeni_kaynak") : L.t("ilk_kaynak"),
          null,
          header: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset(
              "assets/icon.png",
              width: 96,
              height: 96,
              fit: BoxFit.cover,
            ),
          ),
        );
      case Steps.sourceType:
        return getPage(
          L.t("tur_sec"),
          null,
          List.generate(_turSirasi.length, (i) {
            final tip = _turSirasi[i];
            final isLast = i == _turSirasi.length - 1;
            final secili = selectedSourceType == tip;
            final card = Card(
              color: secili
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: secili
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              elevation: 2,
              child: ListTile(
                leading: Icon(_turIkonlari[i], size: 30),
                title: Text(
                  tip.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                subtitle: Text(_turAciklamalari[i]),
                trailing: secili
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: () {
                  setState(() {
                    formValues[Steps.url] = "";
                    selectedSourceType = tip;
                  });
                },
              ),
            );
            if (isLast) {
              return Focus(
                canRequestFocus: false,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    nextButtonFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: card,
              );
            }
            return card;
          }),
        );
      case Steps.name:
        return getPage(L.t("isim_ver"), null, [
          FormBuilder(
            onChanged: () {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setState(() {
                  formValid =
                      _formKeys[Steps.name]!.currentState?.isValid == true;
                });
              });
            },
            initialValue: {Steps.name.name: formValues[Steps.name]},
            key: _formKeys[Steps.name],
            child: FormBuilderTextField(
              autocorrect: false,
              focusNode: focusNodes[Steps.name],
              decoration: const InputDecoration(
                labelText: "İsim (örn. Salon TV)",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.label_outline_rounded),
              ),
              textInputAction: TextInputAction.next,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: FormBuilderValidators.compose([
                FormBuilderValidators.required(),
                (value) {
                  var trimmed = value?.trim();
                  if (trimmed == null || trimmed.isEmpty) {
                    return null;
                  }
                  if (existingSourceNames.contains(trimmed)) {
                    return L.t("isim_var");
                  }
                  return null;
                },
              ]),
              name: 'name',
            ),
          ),
        ]);
      case Steps.url:
        return getPage(L.t("sunucu_nedir"), null, [
          FormBuilder(
            onChanged: () {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setState(() {
                  formValid =
                      _formKeys[Steps.url]!.currentState?.isValid == true;
                });
              });
            },
            initialValue: {Steps.url.name: formValues[Steps.url]},
            key: _formKeys[Steps.url],
            child: FormBuilderTextField(
              autocorrect: false,
              focusNode: focusNodes[Steps.url],
              decoration: const InputDecoration(
                labelText: "Sunucu Adresi (http://...:port)",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link_rounded),
              ),
              textInputAction: TextInputAction.next,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: FormBuilderValidators.required(),
              name: 'url',
            ),
          ),
        ]);
      case Steps.username:
        return getPage(L.t("kullanici_nedir"), null, [
          FormBuilder(
            onChanged: () {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setState(() {
                  formValid =
                      _formKeys[Steps.username]!.currentState?.isValid == true;
                });
              });
            },
            initialValue: {Steps.username.name: formValues[Steps.username]},
            key: _formKeys[Steps.username],
            child: FormBuilderTextField(
              autocorrect: false,
              focusNode: focusNodes[Steps.username],
              decoration: const InputDecoration(
                labelText: "Kullanıcı Adı",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_rounded),
              ),
              textInputAction: TextInputAction.next,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: FormBuilderValidators.required(),
              name: 'username',
            ),
          ),
        ]);
      case Steps.password:
        return getPage(L.t("sifre_nedir"), null, [
          FormBuilder(
            initialValue: {Steps.password.name: formValues[Steps.password]},
            onChanged: () {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setState(() {
                  formValid =
                      _formKeys[Steps.password]!.currentState?.isValid == true;
                });
              });
            },
            key: _formKeys[Steps.password],
            child: FormBuilderTextField(
              autocorrect: false,
              obscureText: true,
              focusNode: focusNodes[Steps.password],
              decoration: const InputDecoration(
                labelText: "Şifre",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.password_rounded),
              ),
              textInputAction: TextInputAction.next,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: FormBuilderValidators.required(),
              name: 'password',
            ),
          ),
        ]);
      case Steps.finish:
        return getPage(L.t("hazir"), L.t("her_sey_tamam"), null);
    }
  }

  Widget getPage(
    String title,
    String? subtitle,
    List<Widget>? content, {
    Widget? header,
  }) {
    return Center(
      key: ValueKey(title),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (header != null) ...[header, const SizedBox(height: 20)],
            Text(
              title,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 12),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 20),
                textAlign: TextAlign.center,
              ),
            ],
            if (content != null) ...[const SizedBox(height: 24), ...content],
          ],
        ),
      ),
    );
  }
}
