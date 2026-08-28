import 'package:flutter/material.dart';
import 'package:open_tv/models/channel.dart';
import 'package:open_tv/models/id_data.dart';
import 'package:open_tv/select_dialog.dart';
import 'package:open_tv/l10n.dart';

///  — dikey paneldeki BÖLÜM ŞERİDİ (onaylı mockup).
/// "BÖLÜMLER" etiketi + sezon chip'i + kaydırılabilir numara kutuları.
/// Mor dolu kutu = izlenen bölüm; altında mor çizgi = daha önce izlenmiş.
/// Sezon chip'i SelectDialog ile sezon değiştirir (parent yeni listeyi yükler).
String sezonAdiTr(Channel sezon) {
  final ad = sezon.name.replaceAllMapped(
    RegExp(r'^\s*Season\s+(\d+)'),
    (m) => "${L.t('sezon_n')} ${m[1]}",
  );
  if (ad.trim().toLowerCase() == 'uncategorized') return L.t('kategorisiz');
  return ad.trim();
}

class HStreamBolumSeridi extends StatefulWidget {
  final List<Channel> sezonlar; // mediaType season (id = sezon satır kimliği)
  final List<Channel> bolumler; // aktif sezonun bölümleri (episode_num sıralı)
  final int? aktifSezonId;
  final int? seciliBolumId;
  final Set<int> izlenenIds;
  final void Function(Channel sezon) onSezonDegistir;
  final void Function(Channel bolum) onBolumSec;

  const HStreamBolumSeridi({
    super.key,
    required this.sezonlar,
    required this.bolumler,
    required this.aktifSezonId,
    required this.seciliBolumId,
    required this.izlenenIds,
    required this.onSezonDegistir,
    required this.onBolumSec,
  });

  @override
  State<HStreamBolumSeridi> createState() => _HStreamBolumSeridiState();
}

class _HStreamBolumSeridiState extends State<HStreamBolumSeridi> {
  late final ScrollController _kaydirici;

  @override
  void initState() {
    super.initState();
    final i = widget.bolumler.indexWhere(
      (b) => b.id == widget.seciliBolumId,
    );
    final baslangic = i > 1 ? (i - 1) * 40.0 : 0.0;
    _kaydirici = ScrollController(initialScrollOffset: baslangic);
  }

  @override
  void dispose() {
    _kaydirici.dispose();
    super.dispose();
  }

  void _sezonDialog() {
    final aktifIndex = widget.sezonlar.indexWhere(
      (s) => s.id == widget.aktifSezonId,
    );
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => SelectDialog(
        title: L.t("sezon_sec"),
        data: widget.sezonlar
            .asMap()
            .entries
            .map((e) => IdData(id: e.key, data: sezonAdiTr(e.value)))
            .toList(),
        action: (index) {
          Navigator.of(ctx).pop();
          if (widget.sezonlar[index].id != widget.aktifSezonId) {
            widget.onSezonDegistir(widget.sezonlar[index]);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Channel? aktifSezon;
    for (final s in widget.sezonlar) {
      if (s.id == widget.aktifSezonId) {
        aktifSezon = s;
        break;
      }
    }
    final cokSezon = widget.sezonlar.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          L.t('bolumler_baslik'),
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
            color: Color(0xFF8B93B5),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // Sezon chip'i (sezon bilgisi yoksa gizlenir)
            if (aktifSezon != null)
            Material(
              color: const Color(0xFF1D1F2F),
              borderRadius: BorderRadius.circular(9),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: cokSezon ? _sezonDialog : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: cokSezon
                      ? null
                      : null, // sabit panel rengi; ok isareti cok sezonluysa
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        sezonAdiTr(aktifSezon).toUpperCase(),
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFC9CFEA),
                        ),
                      ),
                      if (cokSezon) ...const [
                        SizedBox(width: 4),
                        Icon(
                          Icons.arrow_drop_down,
                          size: 13,
                          color: Color(0xFF9AA2C4),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Bölüm kutuları
            Expanded(
              child: SizedBox(
                height: 34,
                child: ListView.separated(
                  controller: _kaydirici,
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.bolumler.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, i) {
                    final bolum = widget.bolumler[i];
                    final secili = bolum.id == widget.seciliBolumId;
                    final izlendi =
                        !secili && widget.izlenenIds.contains(bolum.id);
                    final no =
                        bolum.episodeNum?.toString() ?? (i + 1).toString();
                    return _bolumKutusu(
                      no: no,
                      secili: secili,
                      izlendi: izlendi,
                      onTap: () => widget.onBolumSec(bolum),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _bolumKutusu({
    required String no,
    required bool secili,
    required bool izlendi,
    required VoidCallback onTap,
  }) {
    return Material(
      color: secili ? Colors.transparent : const Color(0xFF1D1F2F),
      borderRadius: BorderRadius.circular(9),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: secili
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF7A52E0), Color(0xFF5642D6)],
                  ),
                  boxShadow: const [
                    BoxShadow(color: Color(0x667A52E0), blurRadius: 10),
                  ],
                )
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: const Color(0xFF2C3344)),
                ),
          child: Stack(
            children: [
              Center(
                child: Text(
                  no,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: secili ? Colors.white : const Color(0xFFC9CFEA),
                  ),
                ),
              ),
              if (izlendi)
                Positioned(
                  left: 7,
                  right: 7,
                  bottom: 4,
                  child: Container(
                    height: 2.5,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF5642D6), Color(0xFFA78BFA)],
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
}

///  — BÖLÜM SONU KARTI (onaylı C):
/// "SIRADAKİ BÖLÜM" + 5 sn geri sayım; Şimdi oynat / İptal.
/// Geri sayım sıfırlanınca parent otomatik geçiş yapar.
class HStreamSonrakiKarti extends StatelessWidget {
  final Channel bolum;
  final String? altYazi;
  final int kalanSn;
  final VoidCallback onOynat;
  final VoidCallback onIptal;

  const HStreamSonrakiKarti({
    super.key,
    required this.bolum,
    this.altYazi,
    required this.kalanSn,
    required this.onOynat,
    required this.onIptal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF161826),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2C3344)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              "$kalanSn ${L.t('basliyor')}",
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF8B93B5)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            L.t('siradaki_bolum'),
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              color: Color(0xFFA78BFA),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            bolum.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 1.25,
            ),
          ),
          if (altYazi != null) ...[
            const SizedBox(height: 4),
            Text(
              altYazi!,
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF9AA2C4),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Material(
                  borderRadius: BorderRadius.circular(11),
                  clipBehavior: Clip.antiAlias,
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onOynat,
                    child: Ink(
                      height: 40,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF7A52E0), Color(0xFF5642D6)],
                        ),
                        borderRadius: BorderRadius.all(Radius.circular(11)),
                      ),
                      child: Center(
                        child: Text(
                          L.t('simdi_oynat'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Material(
                  color: const Color(0xFF1D1F2F),
                  borderRadius: BorderRadius.circular(11),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onIptal,
                    child: SizedBox(
                      height: 40,
                      child: Center(
                        child: Text(
                          L.t('iptal'),
                          style: const TextStyle(
                            color: Color(0xFFC9CFEA),
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
