import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Recovery for "Cannot open Environment: MdbxError (11): Try again".
///
/// audio_service destroys its Flutter engine when the media service stops,
/// but Android may keep the JARX process alive. The database stays opened by
/// the dead engine, so the next engine in the same process cannot open it.
/// Only a new process can, so the app restarts itself once.
class AppRestart {
  AppRestart._();

  static const _channel = MethodChannel('jarx/app');

  static bool isDatabaseLocked(Object error) =>
      error.toString().contains('MdbxError (11)');

  /// Restarts the app process when [error] is the database-lock error, unless
  /// it already restarted for it in the last 30 seconds (then the error is
  /// something a restart does not fix). Returns false when it does not restart.
  static Future<bool> restartIfDatabaseLocked(Object error) async {
    if (!Platform.isAndroid || !isDatabaseLocked(error)) return false;
    try {
      final marker =
          File('${(await getTemporaryDirectory()).path}/jarx_db_lock_restart');
      if (marker.existsSync() &&
          DateTime.now().difference(marker.lastModifiedSync()) <
              const Duration(seconds: 30)) {
        return false;
      }
      marker.writeAsStringSync('');
      await _channel.invokeMethod<void>('restart');
      return true;
    } catch (_) {
      return false;
    }
  }
}
