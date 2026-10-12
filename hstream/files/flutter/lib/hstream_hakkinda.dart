import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:open_tv/hstream_surum.dart';
import 'package:open_tv/hstream_surum_notlari.dart';
import 'package:open_tv/l10n.dart';
import 'package:open_tv/palet.dart';

/// : HAKKINDA EKRANI — sürüm, lisans, kaynak kodu, yenilikler ve
/// güncelleme denetimi tek yerde.
///
/// Neden ayrı ekran: Ayarlar listesi uzuyordu ve "Hakkında" bilgileri
/// (lisans metni, sürüm notları) satır içine sığmıyordu. TV kumandasıyla
/// gezilebilmesi için her satır gerçek bir `ListTile` (odaklanabilir).
class HStreamHakkinda extends StatefulWidget {
  const HStreamHakkinda({super.key});

  @override
  State<HStreamHakkinda> createState() => _HStreamHakkindaState();
}

class _HStreamHakkindaState extends State<HStreamHakkinda> {
  bool _denetleniyor = false;

  // : sürüm notları — kurulu sürümün maddeleri (dil yoksa İngilizce).
  List<String> get _notlar =>
      HSurumNotlari.al(HSurum.surum, HDil.aktif());

  Future<void> _baglantiAc(String adres) async {
    try {
      await launchUrl(
        Uri.parse(adres),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L.t('tarayici_yok')),
          duration: const Duration(milliseconds: 900),
        ),
      );
    }
  }

  /// Güncellemeyi elle denetler. Sonuç her durumda kullanıcıya bildirilir
  /// (sessiz kalmaz): yeni sürüm varsa diyalog, yoksa kısa bilgi mesajı.
  Future<void> _denetle() async {
    if (_denetleniyor) return;
    setState(() => _denetleniyor = true);
    final g = await HSurum.denetle();
    if (!mounted) return;
    setState(() => _denetleniyor = false);
    if (g != null) {
      await guncellemeDialogGoster(context, g);
      return;
    }
    // : `denetle()` hata ile "güncel" durumunu ayırt etmiyor; ikisi de null.
    // Kullanıcıya "en son sürüm" demek yanıltıcı olmasın diye sonuç metni
    // güncel sürümü vurgular, ağ hatası ayrıntısı istenmez.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(L.t('guncelleme_yok')),
        duration: const Duration(milliseconds: 1600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notlar = _notlar;
    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          L.t('hakkinda'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _baslik(),
            const SizedBox(height: 18),
            _kart([
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(L.t('surum')),
                subtitle: Text(HSurum.etiket().isEmpty ? '—' : HSurum.etiket()),
              ),
              ListTile(
                leading: const Icon(Icons.gavel_rounded),
                title: Text(L.t('lisans')),
                subtitle: const Text(HSurum.lisansAdi),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: () => _baglantiAc(HSurum.lisansSayfasi),
              ),
              ListTile(
                leading: const Icon(Icons.code_rounded),
                title: Text(L.t('kaynak_kodu')),
                subtitle: Text(HSurum.depo),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: () => _baglantiAc(HSurum.depoSayfasi),
              ),
            ]),
            const SizedBox(height: 14),
            // ---- güncelleme ----
            _kart([
              ListTile(
                leading: _denetleniyor
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Icon(Icons.system_update_alt_rounded),
                title: Text(
                  _denetleniyor
                      ? L.t('guncelleme_denetleniyor')
                      : L.t('guncelleme_denetle'),
                ),
                subtitle: Text(HSurum.etiket().isEmpty ? '' : HSurum.etiket()),
                onTap: _denetleniyor ? null : _denetle,
              ),
            ]),
            const SizedBox(height: 18),
            _bolumBasligi(L.t('yenilikler')),
            const SizedBox(height: 8),
            if (notlar.isEmpty)
              _kart([
                ListTile(
                  leading: const Icon(Icons.notes_rounded),
                  title: Text(L.t('yenilikler_bos')),
                ),
              ])
            else
              _kart([
                for (var i = 0; i < notlar.length; i++)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      i == 0 ? 12 : 6,
                      16,
                      i == notlar.length - 1 ? 14 : 6,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 6, right: 8),
                          child: Icon(
                            Icons.circle,
                            size: 6,
                            color: P.brandLight,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            notlar[i],
                            style: const TextStyle(
                              fontSize: 13.5,
                              height: 1.45,
                              color: P.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ]),
            const SizedBox(height: 20),
            Center(
              child: Text(
                '${HSurum.ad} · ${HSurum.lisansAdi}',
                style: const TextStyle(fontSize: 11.5, color: P.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _baslik() {
    return Row(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: P.brandGrad,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(
            child: Icon(
              Icons.play_arrow_rounded,
              size: 36,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: const [
                    TextSpan(
                      text: 'H',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: P.textPrimary,
                      ),
                    ),
                    TextSpan(
                      text: 'Stream',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: P.brandLight,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                L.t('hakkinda_tanitim'),
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: P.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bolumBasligi(String metin) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        metin.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: .6,
          color: P.textTertiary,
        ),
      ),
    );
  }

  Widget _kart(List<Widget> cocuklar) {
    return Container(
      decoration: BoxDecoration(
        color: P.surfaceRaised,
        borderRadius: BorderRadius.circular(P.radiusPanel),
        border: Border.all(color: P.outline, width: P.outlineWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: cocuklar,
      ),
    );
  }
}

/// : YENİ SÜRÜM BULUNDU — sürüm notuyla birlikte gösterilir; "İndir"
/// doğrudan APK'ya (varsa) ya da yayın sayfasına gider.
Future<void> guncellemeDialogGoster(
  BuildContext context,
  HGuncelleme guncelleme,
) async {
  final indir = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      backgroundColor: P.surfaceRaised,
      title: Row(
        children: [
          const Icon(Icons.system_update_alt_rounded, color: P.brandLight),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              L.t('guncelleme_var'),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: P.textPrimary,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 300),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${HSurum.etiket()} → ${guncelleme.surum}',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: P.brandLight,
                ),
              ),
              const SizedBox(height: 12),
              if (guncelleme.notlar.isEmpty)
                Text(
                  L.t('yenilikler_bos'),
                  style: const TextStyle(
                    fontSize: 13,
                    color: P.textTertiary,
                  ),
                )
              else
                Text(
                  guncelleme.notlar,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: P.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(L.t('sonra')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(L.t('guncelleme_indir')),
        ),
      ],
    ),
  );
  if (indir != true) {
    // : "Sonra" — aynı sürüm için bir daha sorulmaz (açılışta rahatsız etmesin).
    await HSurum.atla(guncelleme.surum);
    return;
  }
  await _acil(context, guncelleme.indirmeAdresi);
}

/// : YENİLİKLER — uygulama güncellendiğinde bir kez gösterilir.
Future<void> yeniliklerDialogGoster(BuildContext context, String surum) async {
  final notlar = HSurumNotlari.al(surum, HDil.aktif());
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      backgroundColor: P.surfaceRaised,
      title: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded, color: P.brandLight),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              L.t('yenilikler'),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: P.textPrimary,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 320),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${L.t('surum')} $surum',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: P.brandLight,
                ),
              ),
              const SizedBox(height: 12),
              if (notlar.isEmpty)
                Text(
                  L.t('yenilikler_bos'),
                  style: const TextStyle(
                    fontSize: 13,
                    color: P.textTertiary,
                  ),
                )
              else
                for (final n in notlar)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 6, right: 8),
                          child: Icon(
                            Icons.circle,
                            size: 6,
                            color: P.brandLight,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            n,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: P.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(L.t('kapat')),
        ),
      ],
    ),
  );
}

Future<void> _acil(BuildContext context, String adres) async {
  try {
    await launchUrl(
      Uri.parse(adres),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(L.t('tarayici_yok')),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }
}
