import 'dart:io';

import 'package:catcher_2/catcher_2.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

/// Logger utility that wraps Catcher2 for centralized error handling.
class Logger {
  /// Initializes the logger with Catcher2 handlers.
  /// Returns a tuple of (debugConfig, releaseConfig).
  ///
  /// **Mobile/Desktop (non-web):**
  /// - Debug: ConsoleHandler + FileHandler
  /// - Release: FileHandler only
  ///
  /// **Web:**
  /// - Both debug and release: ConsoleHandler only (FileHandler not supported)
  static Future<(Catcher2Options?, Catcher2Options?)> initialize() async {
    if (kIsWeb) {
      final config = Catcher2Options(SilentReportMode(), [
        ConsoleHandler(enableStackTrace: true, enableCustomParameters: true),
      ]);
      return (config, config);
    }

    final dir = await getExternalStorageDirectory();
    final logFile = File('${dir!.path}/logs.txt');

    if (!await logFile.exists()) {
      await logFile.create(recursive: true);
    }

    final fileHandler = FileHandler(
      logFile,
      enableStackTrace: true,
      enableCustomParameters: true,
      printLogs: false,
    );

    final debugConfig = Catcher2Options(SilentReportMode(), [
      ConsoleHandler(enableStackTrace: true, enableCustomParameters: true),
      fileHandler,
    ]);

    final releaseConfig = Catcher2Options(SilentReportMode(), [fileHandler]);

    return (debugConfig, releaseConfig);
  }

  /// Reports an error that was caught in a try-catch block.
  /// Use this to manually report errors to the log file.
  static void reportError(dynamic error, StackTrace? stackTrace) {
    try {
      Catcher2.reportCheckedError(error, stackTrace);
    } catch (e) {
      if (kIsWeb) {
        // ignore: avoid_print
        print('[ERROR] $error');
        if (stackTrace != null) {
          // ignore: avoid_print
          print(stackTrace);
        }
      } else {
        stderr.writeln('[ERROR] $error');
        if (stackTrace != null) {
          stderr.writeln(stackTrace);
        }
      }
    }
  }
}
