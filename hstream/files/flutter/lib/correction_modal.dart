import 'package:flutter/material.dart';
import 'package:open_tv/l10n.dart';

class CorrectionModal extends StatelessWidget {
  const CorrectionModal({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(L.t("adres_dogru")),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(L.t("yine_devam")),
        ),
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context, true),
          child: Text(L.t("otomatik_duzelt")),
        ),
      ],
      content: Text(L.t("adres_aciklama")),
    );
  }
}
