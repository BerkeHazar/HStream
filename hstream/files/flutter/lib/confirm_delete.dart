import 'package:flutter/material.dart';
import 'package:open_tv/l10n.dart';

class ConfirmDelete extends StatelessWidget {
  const ConfirmDelete(
      {super.key,
      required this.name,
      required this.confirm,
      required this.type});
  final VoidCallback confirm;
  final String type;
  final String name;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(L.t("sil_onay")),
      content: Text.rich(TextSpan(children: [
        TextSpan(text: L.t("sil_govde")),
        TextSpan(
            text: name, style: const TextStyle(fontWeight: FontWeight.bold)),
        TextSpan(text: L.t("sil_emin")),
      ])),
      actions: [
        TextButton(
            autofocus: true,
            onPressed: () async {
              Navigator.of(context).pop();
              confirm();
            },
            child: Text(L.t("sil"))),
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(L.t("iptal")))
      ],
    );
  }
}
