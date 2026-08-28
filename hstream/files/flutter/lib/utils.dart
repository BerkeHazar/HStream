import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';

class Utils {
  static Future<bool> hasTouchScreen() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      return androidInfo.systemFeatures.contains(
        'android.hardware.touchscreen',
      );
    }
    return true;
  }

  static Future<void> maybeShowWhatsNew(BuildContext context) async {}
}
