// The JARX account: Google sign-in checked by the JARX server
// (server/src/index.js). Signing in is required to use JARX; the server can
// ban an account. The session token lives in Android's secure storage
// (Keystore). Once signed in, JARX works offline for [offlineGrace] since it
// last reached the server.

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:math' show Random;

import 'package:Bloomee/services/account/spaces.dart';
import 'package:Bloomee/services/db/db_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

const jarxServer = 'https://jarx.jarx-backend.workers.dev';
const jarxPrivacyUrl = '$jarxServer/privacy';

/// The "JARX server" web client: Google signs tokens for it, the server
/// accepts only those. Public by design.
const _webClientId =
    '269249413715-d5fb6ac76r9jngrmfadrk4oausldiv22.apps.googleusercontent.com';
const offlineGrace = Duration(days: 10);
const _checkEvery = Duration(hours: 4);
const _timeout = Duration(seconds: 20);

class JarxUser {
  const JarxUser(this.id, this.email, this.name, this.photo);
  final String id, email, name, photo;

  factory JarxUser.fromJson(Map j) => JarxUser(
        j['id']?.toString() ?? '',
        j['email']?.toString() ?? '',
        j['name']?.toString() ?? '',
        j['photo']?.toString() ?? '',
      );
  Map<String, String> toJson() =>
      {'id': id, 'email': email, 'name': name, 'photo': photo};
}

enum AccountStatus { signedOut, signedIn, pending, banned, needsOnline }

class AccountState {
  const AccountState(this.status, {this.user, this.reason = ''});
  final AccountStatus status;
  final JarxUser? user;

  /// Why the account was banned (set by the owner).
  final String reason;
}

/// Whether a phone that last reached the server at [lastOk] may still be
/// used offline at [now]. A clock moved far back counts as too long too.
bool withinGrace(DateTime? lastOk, DateTime now) =>
    lastOk != null && now.difference(lastOk).abs() < offlineGrace;

class Account {
  Account._();
  static final instance = Account._();

  final state = ValueNotifier(const AccountState(AccountStatus.signedOut));
  static const _store = FlutterSecureStorage();
  // Each space (account) on this phone keeps its own sign-in.
  static String get _kSession => Spaces.key('jarxSession');
  static String get _kUser => Spaces.key('jarxUser');
  static String get _kLastOk => Spaces.key('jarxLastOk');

  String? _token;
  DateTime? _lastOk;
  Timer? _timer;
  bool _googleReady = false;

  JarxUser? get user => state.value.user;
  bool get signedIn => state.value.status == AccountStatus.signedIn;

  /// Reads the saved sign-in (quick, no network), then confirms it with the
  /// server in the background and every few hours after.
  Future<void> start() async {
    try {
      _token = await _store.read(key: _kSession);
      final userJson = await _store.read(key: _kUser);
      final lastOk = int.tryParse(await _store.read(key: _kLastOk) ?? '');
      _lastOk =
          lastOk == null ? null : DateTime.fromMillisecondsSinceEpoch(lastOk);
      if (_token != null && userJson != null) {
        final user = JarxUser.fromJson(jsonDecode(userJson) as Map);
        // Signed in before spaces existed: this space is theirs.
        if (Spaces.ownerOf(Spaces.active) == null) Spaces.own(user);
        state.value = AccountState(
            _lastOk == null // signed in, never let in yet: waiting for approval
                ? AccountStatus.pending
                : withinGrace(_lastOk, DateTime.now())
                    ? AccountStatus.signedIn
                    : AccountStatus.needsOnline,
            user: user);
      }
    } catch (e) {
      log('Reading the saved sign-in failed: $e', name: 'Account');
    }
    _timer ??= Timer.periodic(_checkEvery, (_) => check());
    unawaited(check());
  }

  /// Asks the server whether this account may still use JARX.
  Future<void> check() async {
    final token = _token;
    if (token == null) return;
    try {
      final res = await http
          .get(Uri.parse('$jarxServer/me'), headers: await _headers(token))
          .timeout(_timeout);
      if (res.statusCode == 200) {
        await _confirmed(JarxUser.fromJson(
            (jsonDecode(res.body) as Map)['user'] as Map));
        return;
      }
      if (res.statusCode == 403) {
        if (_errorOf(res.body) == 'pending') {
          state.value = AccountState(AccountStatus.pending, user: user);
          return;
        }
        return _banned(_reasonOf(res.body));
      }
      if (res.statusCode == 401) {
        // The session ended (signed out elsewhere, expired, account deleted).
        await _forget();
        return;
      }
      log('Account check: HTTP ${res.statusCode}', name: 'Account');
    } catch (e) {
      log('Account check failed (offline?): $e', name: 'Account');
    }
    // Server not reached: fine until the offline grace runs out.
    if (signedIn && !withinGrace(_lastOk, DateTime.now())) {
      state.value = AccountState(AccountStatus.needsOnline, user: user);
    }
  }

  /// Google's account picker, then the JARX server. Returns a message to
  /// show when it failed, null when signed in (or the user backed out).
  ///
  /// Another account than this space's owner restarts JARX into that
  /// account's own space. When this space has music but no owner yet,
  /// [isThisYours] decides whether it joins the account (true), stays
  /// apart (false) or the sign-in stops (null).
  Future<String?> signIn(
      {Future<bool?> Function(int playlists, int liked, int plays)?
          isThisYours}) async {
    try {
      if (!_googleReady) {
        await GoogleSignIn.instance.initialize(serverClientId: _webClientId);
        _googleReady = true;
      } else {
        // Always show the picker (adding another account).
        await GoogleSignIn.instance.signOut();
      }
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) return 'Google did not finish the sign-in. Try again.';
      final res = await http
          .post(Uri.parse('$jarxServer/auth/google'),
              headers: {'content-type': 'application/json'},
              body: jsonEncode({
                'idToken': idToken,
                'device': await _device(),
                'appVersion': await _version(),
              }))
          .timeout(_timeout);
      if (res.statusCode == 403) {
        await _banned(_reasonOf(res.body));
        return null;
      }
      if (res.statusCode != 200) {
        return 'JARX could not sign you in (error ${res.statusCode}). Try again.';
      }
      final body = jsonDecode(res.body) as Map;
      final user = JarxUser.fromJson(body['user'] as Map);
      final pending = (body['user'] as Map)['status'] == 'pending';
      final space = await _spaceFor(user, isThisYours);
      if (space == null) return null;
      if (space != Spaces.active) {
        await _store.write(
            key: Spaces.key('jarxSession', space), value: body['token']);
        await _store.write(
            key: Spaces.key('jarxUser', space),
            value: jsonEncode(user.toJson()));
        if (!pending) {
          await _store.write(
              key: Spaces.key('jarxLastOk', space),
              value: '${DateTime.now().millisecondsSinceEpoch}');
        }
        await Spaces.switchTo(space);
        return null;
      }
      _token = body['token'] as String;
      await _store.write(key: _kSession, value: _token);
      if (pending) {
        // New account: the owner has to approve it first.
        await _store.write(key: _kUser, value: jsonEncode(user.toJson()));
        state.value = AccountState(AccountStatus.pending, user: user);
        return null;
      }
      await _confirmed(user);
      return null;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      return 'Google sign-in failed: ${e.description ?? e.code.name}';
    } on TimeoutException {
      return 'The JARX server did not answer. Check your internet and try again.';
    } on SocketException {
      return 'No internet connection. Connect and try again.';
    } catch (e) {
      return 'Sign-in failed: $e';
    }
  }

  /// The space [user] signs into: theirs if this phone has one, else this
  /// one if it's nobody's and (when it has music) they say it's theirs,
  /// else a new one. Null: they backed out.
  Future<String?> _spaceFor(JarxUser user,
      Future<bool?> Function(int, int, int)? isThisYours) async {
    final theirs = Spaces.spaceOf(user.id);
    if (theirs != null) return theirs;
    final isar = await DBProvider.db;
    if (Spaces.ownerOf(Spaces.active) == null) {
      final (lists, liked, plays) = await Spaces.music(isar);
      final bool? yours = lists + liked + plays == 0
          ? true
          : isThisYours == null
              ? false
              : await isThisYours(lists, liked, plays);
      if (yours == null) return null;
      if (yours) {
        Spaces.own(user);
        return Spaces.active;
      }
    }
    return Spaces.create(isar, user);
  }

  /// Ends this phone's sign-in. The music on the phone stays.
  Future<void> signOut() async {
    final token = _token;
    if (token != null) {
      try {
        await http
            .post(Uri.parse('$jarxServer/signout'),
                headers: await _headers(token))
            .timeout(const Duration(seconds: 5));
      } catch (_) {} // the session expires on the server anyway
    }
    await _forget();
  }

  /// Takes another account off this phone: ends its sign-in and deletes its
  /// space. Its music stays in the account.
  static Future<void> removeSpace(String space) async {
    final token = await _store.read(key: Spaces.key('jarxSession', space));
    if (token != null) {
      try {
        await http
            .post(Uri.parse('$jarxServer/signout'),
                headers: await _headers(token))
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    for (final k in ['jarxSession', 'jarxUser', 'jarxLastOk']) {
      try {
        await _store.delete(key: Spaces.key(k, space));
      } catch (_) {}
    }
    Spaces.remove(space);
  }

  /// Deletes the account and everything the server keeps about it.
  /// Returns a message when it failed.
  Future<String?> deleteAccount() async {
    final token = _token;
    if (token == null) return 'Not signed in.';
    try {
      final res = await http
          .delete(Uri.parse('$jarxServer/me'), headers: await _headers(token))
          .timeout(_timeout);
      if (res.statusCode != 200) {
        return 'Could not delete the account (error ${res.statusCode}).';
      }
    } catch (_) {
      return 'No connection to the JARX server. Try again when online.';
    }
    Spaces.own(null); // the music here is nobody's now
    await _forget();
    return null;
  }

  Future<void> _confirmed(JarxUser user) async {
    _lastOk = DateTime.now();
    await _store.write(key: _kUser, value: jsonEncode(user.toJson()));
    await _store.write(
        key: _kLastOk, value: '${_lastOk!.millisecondsSinceEpoch}');
    state.value = AccountState(AccountStatus.signedIn, user: user);
  }

  Future<void> _banned(String reason) async {
    await _clear();
    state.value = AccountState(AccountStatus.banned, reason: reason);
  }

  Future<void> _forget() async {
    await _clear();
    state.value = const AccountState(AccountStatus.signedOut);
  }

  Future<void> _clear() async {
    _token = null;
    _lastOk = null;
    for (final k in [_kSession, _kUser, _kLastOk]) {
      try {
        await _store.delete(key: k);
      } catch (_) {}
    }
    // So the next sign-in shows the account picker again.
    if (_googleReady) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
  }

  /// A request to the JARX server as this account (null: not signed in or
  /// no connection).
  Future<http.Response?> api(String method, String path,
      {Map<String, String>? query, Object? body}) async {
    final token = _token;
    if (token == null) return null;
    final req = http.Request(method,
        Uri.parse('$jarxServer$path').replace(queryParameters: query))
      ..headers.addAll(await _headers(token));
    if (body != null) {
      req.headers['content-type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    try {
      return await http.Response.fromStream(
          await req.send().timeout(const Duration(seconds: 60)));
    } catch (e) {
      log('$method $path failed: $e', name: 'Account');
      return null;
    }
  }

  /// A random id for this phone, kept across sign-outs (its listening time
  /// is stored under it).
  static Future<String> deviceId() async {
    const key = 'jarxDevice';
    var id = await _store.read(key: key);
    if (id == null) {
      final r = Random.secure();
      id = [for (var i = 0; i < 16; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0')]
          .join();
      await _store.write(key: key, value: id);
    }
    return id;
  }

  static String _errorOf(String body) {
    try {
      return (jsonDecode(body) as Map)['error']?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  static String _reasonOf(String body) {
    try {
      return (jsonDecode(body) as Map)['reason']?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<Map<String, String>> _headers(String token) async =>
      {'authorization': 'Bearer $token', 'x-jarx-version': await _version()};

  static String? _versionCache;
  static Future<String> _version() async {
    if (_versionCache != null) return _versionCache!;
    final p = await PackageInfo.fromPlatform();
    return _versionCache = '${p.version}+${p.buildNumber}';
  }

  static Future<String> _device() async {
    try {
      if (Platform.isAndroid) {
        final a = await DeviceInfoPlugin().androidInfo;
        return '${a.brand} ${a.model}';
      }
    } catch (_) {}
    return Platform.operatingSystem;
  }
}
