import 'dart:async';
import 'dart:developer';

import 'package:Bloomee/core/models/app_notification.dart';
import 'package:Bloomee/services/app_updater.dart';
import 'package:Bloomee/services/bloomee_updater_tools.dart';
import 'package:Bloomee/services/db/dao/notification_dao.dart';
import 'package:Bloomee/services/db/global_db.dart' show NotificationsDB;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'notification_state.dart';

class NotificationCubit extends Cubit<NotificationState> {
  final NotificationDAO _notificationDao;
  StreamSubscription? _subscription;

  NotificationCubit({required NotificationDAO notificationDao})
      : _notificationDao = notificationDao,
        super(NotificationInitial()) {
    _refreshUpdateNotice();
    getNotification();
  }
  /// The build an update notice is for (its payload; older notices only
  /// say it in the title, "JARX 2.0.0 (39)"); 0 when unknown.
  static int _buildOf(NotificationsDB n) =>
      int.tryParse(n.payload ?? '') ??
      int.tryParse(RegExp(r'\((?:build )?(\d+)\)').firstMatch(n.title)?.group(1) ??
          '') ??
      0;

  /// At most one update notice, for the latest build; none once the user
  /// has it (so the bell's count goes away after updating).
  Future<void> _refreshUpdateNotice() async {
    const type = 'app_update';
    final info = await PackageInfo.fromPlatform();
    final current = (int.tryParse(info.buildNumber) ?? 0) % 1000;
    // Already installed (works offline too).
    await _notificationDao.removeType(type, (n) => _buildOf(n) <= current);
    getNotification();

    final value = await getLatestVersion();
    if (value['source'] != 'github') return; // offline: nothing new to say
    final latest = int.tryParse('${value['newBuild']}') ?? 0;
    if (value['results'] == true && latest > current) {
      final required = (value['requiredBuild'] as int? ?? 0) > 0;
      await _notificationDao.putNotification(
        title: 'JARX ${value['newVer']} (build $latest) is '
            '${required ? 'required' : 'available'}',
        body: (value['notes'] as String?)?.isNotEmpty == true
            ? value['notes']
            : 'A new version of JARX is ready to download.',
        type: type,
        url: value['download_url'],
        payload: '$latest',
        unique: true,
      );
    } else {
      await _notificationDao.removeType(type); // up to date
    }
    getNotification();
  }

  void getNotification() async {
    final dbNotifications = await _notificationDao.getNotifications();
    final notifications = dbNotifications
        .map(
          (n) => AppNotification(
            title: n.title,
            body: n.body,
            type: n.type,
            url: n.url,
            payload: n.payload,
          ),
        )
        .toList(growable: false);
    emit(NotificationState(notifications: notifications));
  }

  void clearNotification() {
    // ponytail: keeps every notice, not just the update, while one is
    // compulsory; the tour needs the update in the bell.
    if (UpdateGate.blocked) return;
    _notificationDao.clearNotifications();
    log("Notification Cleared");
    getNotification();
  }

  Future<void> watchNotification() async {
    _subscription =
        (await _notificationDao.watchNotification()).listen((event) {
      getNotification();
    });
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
