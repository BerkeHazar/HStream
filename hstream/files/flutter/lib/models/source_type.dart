import 'package:open_tv/l10n.dart';

enum SourceType { m3u, m3uUrl, xtream }

extension SourceTypeExtension on SourceType {
  String get label {
    switch (this) {
      case SourceType.m3u:
        return L.t("m3u_dosya");
      case SourceType.m3uUrl:
        return L.t("m3u_link");
      case SourceType.xtream:
        return L.t("xtream");
    }
  }
}
