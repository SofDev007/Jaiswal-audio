// The first-run flow, right after sign-in: song languages, then at least 3
// artists. Plugins install in the background meanwhile (no waiting screen
// unless they're still not done at the end). Home style, "bring your music"
// and "All set" follow on Home (home_layout_picker.dart).

import 'package:Bloomee/core/constants/setting_keys.dart';
import 'package:Bloomee/core/di/service_locator.dart';
import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:Bloomee/l10n/app_localizations.dart';
import 'package:Bloomee/plugins/services/plugin_repository_service.dart';
import 'package:Bloomee/services/db/dao/settings_dao.dart';
import 'package:Bloomee/services/db/db_provider.dart';
import 'package:Bloomee/services/first_run.dart';
import 'package:Bloomee/services/onboarding_service.dart';
import 'package:Bloomee/services/plugin_bootstrap_service.dart';
import 'package:Bloomee/services/recommendations/song_card.dart'
    show SongLanguage;
import 'package:Bloomee/utils/country_info.dart';
import 'package:flutter/material.dart';

class FirstRunFlow extends StatefulWidget {
  const FirstRunFlow({super.key, required this.onComplete});
  final VoidCallback onComplete;

  @override
  State<FirstRunFlow> createState() => _FirstRunFlowState();
}

class _FirstRunFlowState extends State<FirstRunFlow> {
  final _pages = PageController();
  int _step = 0;
  final _langs = <SongLanguage>{};
  final _artists = <String>[];
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _installPluginsInBackground();
    _search.addListener(() => setState(() {}));
  }

  Future<void> _installPluginsInBackground() async {
    if (PluginBootstrapService.bootstrapDone) return;
    final dao = SettingsDAO(DBProvider.db);
    try {
      final result = await PluginBootstrapService.run(
        pluginService: ServiceLocator.pluginService,
        repositoryService: PluginRepositoryService(settingsDao: dao),
        settingsDao: dao,
        onProgress: (_) {},
      );
      if (result.success) {
        await PluginBootstrapService.autoSelectPluginDefaults(
            ServiceLocator.pluginService, dao);
      }
    } catch (_) {
      // The setup screen after the flow tries again and shows what's wrong.
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    _search.dispose();
    super.dispose();
  }

  void _next() {
    setState(() => _step = 1);
    _pages.animateToPage(1,
        duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
  }

  Future<void> _finish({bool skipArtists = false}) async {
    final dao = SettingsDAO(DBProvider.db);
    // What the old welcome screen saved: phone's language, default region.
    await dao.putSettingBool(SettingKeys.autoGetCountry, false);
    await dao.putSettingStr(
        SettingKeys.countryCode, CountryInfoService.defaultCountryCode);
    await dao.putSettingStr(SettingKeys.languageCode, '');
    await FirstRunPicks(_langs, skipArtists ? const [] : _artists).save();
    await OnboardingService.markDone(dao);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: Default_Theme().defaultThemeData,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        backgroundColor: Default_Theme.themeColor,
        body: SafeArea(
          child: Column(children: [
            const SizedBox(height: 18),
            _Dots(step: _step),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                children: [_languagesPage(), _artistsPage()],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _languagesPage() => _Page(
        title: 'What do you listen to?',
        subtitle: 'Pick your languages. Bathroom-singing languages count too.',
        body: Column(
          children: [
            for (final e in firstRunLanguages.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _BigChoice(
                  label: e.value,
                  selected: _langs.contains(e.key),
                  onTap: () => setState(() => _langs.contains(e.key)
                      ? _langs.remove(e.key)
                      : _langs.add(e.key)),
                ),
              ),
          ],
        ),
        primary: 'Next',
        onPrimary: _langs.isEmpty ? null : _next,
        secondary: 'Skip',
        onSecondary: _next,
      );

  Widget _artistsPage() {
    final q = _search.text.trim();
    final all = artistsFor(_langs);
    final shown = [
      // Picked ones you typed in yourself stay visible.
      for (final a in _artists)
        if (!all.contains(a)) a,
      for (final a in all)
        if (q.isEmpty || a.toLowerCase().contains(q.toLowerCase())) a,
    ];
    final canAdd = q.length >= 2 &&
        !shown.any((a) => a.toLowerCase() == q.toLowerCase());
    final n = _artists.length;
    return _Page(
      title: 'Pick at least 3 artists',
      subtitle: 'JARX starts from them and learns the rest as you listen.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _search,
            style: const TextStyle(color: Default_Theme.primaryColor1),
            decoration: InputDecoration(
              hintText: 'Search or add an artist',
              hintStyle: TextStyle(
                  color: Default_Theme.primaryColor1.withValues(alpha: 0.4)),
              prefixIcon: const Icon(Icons.search_rounded,
                  color: Default_Theme.primaryColor2),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canAdd)
                ActionChip(
                  avatar: const Icon(Icons.add_rounded,
                      size: 18, color: Default_Theme.accentColor2),
                  label: Text('Add "$q"'),
                  onPressed: () => setState(() {
                    _artists.add(q);
                    _search.clear();
                  }),
                ),
              for (final a in shown)
                FilterChip(
                  label: Text(a),
                  selected: _artists.contains(a),
                  showCheckmark: false,
                  selectedColor: Default_Theme.accentColor2,
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  labelStyle: TextStyle(
                      color: _artists.contains(a)
                          ? Colors.white
                          : Default_Theme.primaryColor1,
                      fontWeight: FontWeight.w600),
                  side: BorderSide.none,
                  shape: const StadiumBorder(),
                  onSelected: (on) =>
                      setState(() => on ? _artists.add(a) : _artists.remove(a)),
                ),
            ],
          ),
        ],
      ),
      primary: n >= 3 ? 'Done' : 'Pick ${3 - n} more',
      onPrimary: n >= 3 ? _finish : null,
      secondary: 'Skip',
      onSecondary: () => _finish(skipArtists: true),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.title,
    required this.subtitle,
    required this.body,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
  });
  final String title, subtitle, primary, secondary;
  final Widget body;
  final VoidCallback? onPrimary;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Default_Theme.primaryColor1,
                      fontSize: 28,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(subtitle,
                  style: TextStyle(
                      color: Default_Theme.primaryColor2.withValues(alpha: 0.75),
                      fontSize: 15.5,
                      height: 1.4)),
              const SizedBox(height: 26),
              body,
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        child: Row(children: [
          TextButton(
            onPressed: onSecondary,
            child: Text(secondary,
                style: TextStyle(
                    color: Default_Theme.primaryColor2.withValues(alpha: 0.7),
                    fontSize: 15)),
          ),
          const Spacer(),
          FilledButton(
            onPressed: onPrimary,
            style: FilledButton.styleFrom(
              backgroundColor: Default_Theme.accentColor2,
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
              minimumSize: const Size(140, 50),
              shape: const StadiumBorder(),
            ),
            child: Text(primary,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    ]);
  }
}

class _BigChoice extends StatelessWidget {
  const _BigChoice(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: selected
              ? Default_Theme.accentColor2.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
              color: selected
                  ? Default_Theme.accentColor2
                  : Colors.white.withValues(alpha: 0.08),
              width: 1.5),
        ),
        child: Row(children: [
          Text(label,
              style: const TextStyle(
                  color: Default_Theme.primaryColor1,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          AnimatedScale(
            scale: selected ? 1 : 0,
            duration: const Duration(milliseconds: 260),
            curve: Curves.elasticOut,
            child: const Icon(Icons.check_circle_rounded,
                color: Default_Theme.accentColor2),
          ),
        ]),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 2; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == step ? 26 : 8,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: i == step
                    ? Default_Theme.accentColor2
                    : Colors.white.withValues(alpha: 0.2),
              ),
            ),
        ],
      );
}
