import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

bool isAndroid() {
  return Platform.isAndroid;
}

bool isIOS() {
  return Platform.isIOS;
}

bool isWindows() {
  return Platform.isWindows;
}

bool isLinux() {
  return Platform.isLinux;
}

bool isWeb() {
  return kIsWeb;
}

Future<String> getDownloadsDirectory() async {
  if (isAndroid()) {
    return '/storage/emulated/0/Download/RevEngi';
  } else if (isIOS()) {
    return await getApplicationDocumentsDirectory().then(
      (dir) => '${dir.path}/RevEngi',
    );
  } else if (isWindows()) {
    return '${Platform.environment['USERPROFILE']}\\Downloads\\RevEngi';
  } else if (isLinux()) {
    return '/home/${Platform.environment['USER']}/Downloads/RevEngi';
  } else {
    throw UnsupportedError('Unsupported platform');
  }
}

class DeviceInfo {
  static const platform = MethodChannel('flutter.native/helper');

  static Future<int> getSdkVersion() async {
    try {
      final Map<dynamic, dynamic> deviceInfo = await platform.invokeMethod(
        'getDeviceInfo',
      );
      return int.tryParse(deviceInfo['sdkVersion'] ?? '0') ?? 0;
    } on PlatformException {
      return 0;
    }
  }

  static Future<int> getTotalRAM() async {
    try {
      final int totalRAM = await platform.invokeMethod('getTotalRAM');
      return totalRAM;
    } on PlatformException {
      return 0;
    }
  }
}
