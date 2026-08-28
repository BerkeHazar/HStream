import 'package:flutter/material.dart';

/// HStream sayfa gecisi — : kullanicinin "cok kasiyor" geri
/// bildirimi sonrasi sadelestirildi: sadece yumusak solma, 200ms.
/// PageRoute oldugu icin hstreamRouteObserver — Son Izlenenler
/// tazeleme — aynen calisir.
class HStreamPageRoute<T> extends PageRouteBuilder<T> {
  HStreamPageRoute({required WidgetBuilder builder})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 160),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
              reverseCurve: Curves.easeIn,
            ),
            child: child,
          );
        },
      );
}
