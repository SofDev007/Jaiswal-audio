import 'dart:async';
import 'dart:developer';

import 'package:Bloomee/core/models/app_notification.dart';
import 'package:Bloomee/services/app_updater.dart';
import 'package:Bloomee/services/bloomee_updater_tools.dart';
import 'package:Bloomee/services/db/dao/notification_dao.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'notification_state.dart';

class NotificationCubit extends Cubit<NotificationState> {
  final NotificationDAO _notificationDao;
  StreamSubscription? _subscription;

  NotificationCubit({required NotificationDAO notificationDao})
      : _notificationDao = notificationDao,
        super(NotificationInitial()) {
    getLatestVersion().then((value) {
      if (value["results"]) {
        if (int.parse(value["currBuild"]) < int.parse(value["newBuild"])) {
          _notificationDao.putNotification(
            title: (value["requiredBuild"] as int? ?? 0) > 0
                ? "JARX ${value["newVer"]} (${value["newBuild"]}) is required"
                : "JARX ${value["newVer"]} (${value["newBuild"]}) is available",
            body: (value["notes"] as String?)?.isNotEmpty == true
                ? value["notes"]
                : "A new version of JARX is ready to download.",
            type: "app_update",
            url: value["download_url"],
            unique: true,
          ).then((_) => getNotification());
        }
      }
    });
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
