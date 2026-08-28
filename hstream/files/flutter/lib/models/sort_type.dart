import 'package:open_tv/l10n.dart';

enum SortType { alphabeticalAsc, alphabeticalDesc, provider }

String sortTypeToString(SortType sort) {
  switch (sort) {
    case SortType.alphabeticalAsc:
      return L.t("siralama_az");
    case SortType.alphabeticalDesc:
      return L.t("siralama_za");
    case SortType.provider:
      return L.t("siralama_saglayici");
  }
}
