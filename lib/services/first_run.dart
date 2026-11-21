// What a new user picked in the first-run flow: song languages and at least
// 3 artists. Recommendations start from these until JARX has learned from
// what they actually play (see RecommendationRanker.buildTaste).

import 'dart:convert';

import 'package:Bloomee/services/db/dao/settings_dao.dart';
import 'package:Bloomee/services/db/db_provider.dart';
import 'package:Bloomee/services/recommendations/song_card.dart'
    show SongLanguage;

/// Popular artists per language, built in so the picker shows at once
/// (no network). The search box adds anyone else.
const firstRunArtists = <SongLanguage, List<String>>{
  SongLanguage.hindi: [
    'Arijit Singh', 'Shreya Ghoshal', 'Jubin Nautiyal', 'Atif Aslam', //
    'Pritam', 'A. R. Rahman', 'Sonu Nigam', 'KK', 'Vishal Mishra',
    'Darshan Raval', 'Neha Kakkar', 'Badshah', 'Armaan Malik', 'Anuv Jain',
    'Prateek Kuhad', 'Sachet Tandon', 'Rahat Fateh Ali Khan',
    'Sunidhi Chauhan', 'Kishore Kumar', 'Lata Mangeshkar', 'Mohammed Rafi',
    'Udit Narayan', 'Alka Yagnik', 'Shaan',
  ],
  SongLanguage.english: [
    'Taylor Swift', 'Ed Sheeran', 'The Weeknd', 'Billie Eilish', //
    'Coldplay', 'Dua Lipa', 'Justin Bieber', 'Imagine Dragons', 'Bruno Mars',
    'Ariana Grande', 'Post Malone', 'Drake', 'Eminem', 'Maroon 5',
    'Shawn Mendes', 'Olivia Rodrigo', 'Arctic Monkeys', 'Sabrina Carpenter',
  ],
  SongLanguage.punjabi: [
    'AP Dhillon', 'Diljit Dosanjh', 'Sidhu Moose Wala', 'Karan Aujla', //
    'Shubh', 'Guru Randhawa', 'Harrdy Sandhu', 'B Praak', 'Ammy Virk',
    'Jasmine Sandlas', 'Satinder Sartaaj', 'Gurdas Maan', 'Arjan Dhillon',
  ],
};

/// The languages a new user can pick, with their names.
const firstRunLanguages = <SongLanguage, String>{
  SongLanguage.hindi: 'Hindi',
  SongLanguage.english: 'English',
  SongLanguage.punjabi: 'Punjabi',
};

/// The artists to offer for [langs] (all languages when none is picked),
/// in list order, each once.
List<String> artistsFor(Set<SongLanguage> langs) => {
      for (final e in firstRunArtists.entries)
        if (langs.isEmpty || langs.contains(e.key)) ...e.value,
    }.toList();

class FirstRunPicks {
  const FirstRunPicks(this.languages, this.artists);
  final Set<SongLanguage> languages;
  final List<String> artists;

  static const _key = 'firstRunPicks1';
  static const none = FirstRunPicks({}, []);

  Map<String, dynamic> toJson() => {
        'langs': [for (final l in languages) l.name],
        'artists': artists,
      };

  static FirstRunPicks fromJson(Map j) => FirstRunPicks(
        {
          for (final n in j['langs'] as List? ?? const [])
            for (final l in SongLanguage.values)
              if (l.name == n) l
        },
        [for (final a in j['artists'] as List? ?? const []) '$a'],
      );

  static Future<FirstRunPicks> load() async {
    try {
      final raw = await SettingsDAO(DBProvider.db).getSettingStr(_key);
      if (raw != null) return fromJson(jsonDecode(raw) as Map);
    } catch (_) {}
    return none;
  }

  Future<void> save() =>
      SettingsDAO(DBProvider.db).putSettingStr(_key, jsonEncode(toJson()));
}
