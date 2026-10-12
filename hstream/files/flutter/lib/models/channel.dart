import 'package:open_tv/models/media_type.dart';

class Channel {
  int? id;
  String name;
  int? groupId;
  String? group;
  String? image;
  String? url;
  MediaType mediaType;
  int sourceId;
  bool favorite;
  int? seriesId;
  int? streamId;
  int? seasonId;
  int? episodeNum;

  Channel({
    this.id,
    required this.name,
    this.group,
    this.groupId,
    this.image,
    this.url,
    required this.mediaType,
    required this.sourceId,
    required this.favorite,
    this.seriesId,
    this.streamId,
    this.seasonId,
    this.episodeNum,
  });

  /// : KAPAK VAR MI — null VEYA BOS/BOSLUKLU metin "kapak yok" sayilir.
  ///
  /// Neden gerekli: Rust tarafi `image` alanini `Option<String>` olarak
  /// aktarir ve Xtream kaynaklarinda `stream_icon: ""` gelen kanallar
  /// `Some("")` olur — yani `null` DEGIL, BOS STRING. Yalnizca
  /// `image != null` kontrolu bu durumda TRUE doner ve her kart icin
  /// `CachedNetworkImage(imageUrl: "")` kurulur. Bos adres basarisiz
  /// oldugu icin onbellege alinmaz ve kart listede geri geldikce yukleme
  /// YENIDEN denenir → kapaği olmayan canli yayin listeleri tam da bu
  /// yuzden kaydirirken cok daha fazla kasıyordu.
  ///
  /// Tum cagri yerleri bu TEK kaynagi kullanmali; `image != null`
  /// karsilastirmasi bir daha dogrudan yazilmamali.
  bool get kapakVar => image != null && image!.trim().isNotEmpty;
}
