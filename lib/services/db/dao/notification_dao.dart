import 'package:Bloomee/services/db/global_db.dart';
import 'package:isar_community/isar.dart';

/// DAO for in-app notifications.
class NotificationDAO {
  final Future<Isar> _db;

  const NotificationDAO(this._db);

  Future<void> putNotification({
    required String title,
    required String body,
    required String type,
    String? url,
    String? payload,
    bool unique = false,
  }) async {
    final isarDB = await _db;

    // Every older notice of this type goes (it used to remove only the
    // first one, so old update notices piled up in the bell).
    if (unique) await removeType(type);

    await isarDB.writeTxn(
      () async => isarDB.notificationsDBs.put(
        NotificationsDB(
          title: title,
          body: body,
          time: DateTime.now(),
          type: type,
          url: url,
          payload: payload,
        ),
      ),
    );
  }

  Future<List<NotificationsDB>> getNotifications() async {
    final isarDB = await _db;
    return isarDB.notificationsDBs.where().sortByTimeDesc().findAll();
  }

  /// Removes every notice of [type] that [test] picks (all by default).
  Future<void> removeType(String type,
      [bool Function(NotificationsDB n)? test]) async {
    final isarDB = await _db;
    final all =
        await isarDB.notificationsDBs.filter().typeEqualTo(type).findAll();
    final ids = [
      for (final n in all)
        if (test == null || test(n)) n.id
    ];
    if (ids.isEmpty) return;
    await isarDB.writeTxn(() => isarDB.notificationsDBs.deleteAll(ids));
  }

  Future<void> clearNotifications() async {
    final isarDB = await _db;
    await isarDB.writeTxn(
      () async => isarDB.notificationsDBs.where().deleteAll(),
    );
  }

  Future<Stream<void>> watchNotification() async {
    Isar isarDB = await _db;
    return isarDB.notificationsDBs.watchLazy();
  }
}
