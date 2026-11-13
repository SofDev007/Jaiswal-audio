// Nothing in JARX opens until the phone is signed in: this gate shows the
// sign-in, banned or "connect to confirm" screen instead of the app.

import 'dart:async';
import 'dart:io';

import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:Bloomee/services/account/account.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AccountGate extends StatelessWidget {
  const AccountGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // ponytail: Android only (the only JARX release); Google sign-in isn't
    // set up for the desktop builds.
    if (!Platform.isAndroid) return child;
    return ValueListenableBuilder<AccountState>(
      valueListenable: Account.instance.state,
      builder: (context, s, _) => s.status == AccountStatus.signedIn
          ? child
          : MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData.dark(useMaterial3: true).copyWith(
                  scaffoldBackgroundColor: Default_Theme.themeColor),
              home: _LockedScreen(state: s),
            ),
    );
  }
}

class _LockedScreen extends StatefulWidget {
  const _LockedScreen({required this.state});
  final AccountState state;

  @override
  State<_LockedScreen> createState() => _LockedScreenState();
}

class _LockedScreenState extends State<_LockedScreen> {
  bool _busy = false;
  String? _error;

  /// While waiting for approval, ask again every 20 s.
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (widget.state.status == AccountStatus.pending) Account.instance.check();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await action();
    if (mounted) {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final (title, text, button) = switch (s.status) {
      AccountStatus.banned => (
          "This account can't use JARX",
          s.reason.isEmpty
              ? 'The owner of JARX has blocked this Google account.'
              : 'The owner of JARX has blocked this Google account:\n"${s.reason}"',
          'Use another Google account',
        ),
      AccountStatus.pending => (
          'Waiting for approval',
          'The owner of JARX needs to approve ${s.user?.email ?? 'your account'}. '
              'JARX opens by itself as soon as they do.',
          'Check again',
        ),
      AccountStatus.needsOnline => (
          'Connect to confirm your account',
          'JARX works offline for up to 10 days. Connect to the internet once '
              'so JARX can confirm ${s.user?.email ?? 'your account'}.',
          'Try again',
        ),
      _ => (
          'Welcome to JARX',
          'Sign in to keep your playlists, Liked songs and taste on every '
              'phone. Your music on this phone stays as it is.',
          'Continue with Google',
        ),
    };
    final isRetry = s.status == AccountStatus.needsOnline ||
        s.status == AccountStatus.pending;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset('assets/icons/jarx/icon_android.png',
                        width: 96, height: 96),
                  ),
                  const SizedBox(height: 28),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontFamily: 'Gilroy',
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: Default_Theme.primaryColor1)),
                  const SizedBox(height: 12),
                  Text(text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 15,
                          height: 1.45,
                          color: Default_Theme.primaryColor1
                              .withValues(alpha: 0.75))),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Default_Theme.accentColor2,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26)),
                      ),
                      onPressed: _busy
                          ? null
                          : () => _run(isRetry
                              ? () async {
                                  await Account.instance.check();
                                  final now = Account.instance.state.value;
                                  return now.status == AccountStatus.signedIn ||
                                          now.status == AccountStatus.pending
                                      ? null
                                      : 'Could not reach JARX. Connect and try again.';
                                }
                              : Account.instance.signIn),
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Icon(isRetry ? Icons.refresh_rounded : Icons.login),
                      label: Text(button,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  if (isRetry) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy ? null : Account.instance.signOut,
                      child: const Text('Sign out'),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.redAccent)),
                  ],
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () => launchUrl(Uri.parse(jarxPrivacyUrl),
                        mode: LaunchMode.externalApplication),
                    child: Text('Privacy policy',
                        style: TextStyle(
                            color: Default_Theme.primaryColor1
                                .withValues(alpha: 0.6))),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
