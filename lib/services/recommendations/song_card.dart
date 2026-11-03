/// What JARX knows about a song without asking anyone: its language and its
/// moods, guessed from the title, album and artists, and from the names of
/// the user's playlists it is in. Layer 1 of the recommendations plan
/// (docs/recommendations-v2-plan.md); an AI replaces the mood guess in V2.
///
/// Pure: no plugin calls, no database.
library song_card;

import 'package:Bloomee/core/models/track_signal.dart';
import 'package:Bloomee/services/recommendations/recommendation_ranker.dart'
    show scriptOf;
import 'package:Bloomee/src/rust/api/plugin/models.dart';

/// The languages a listener can pick in Settings; [other] is everything else.
enum SongLanguage { hindi, english, punjabi, other }

enum Mood {
  sad,
  romantic,
  happy,
  dance,
  cozy,
  moody,
  uplifting,
  energetic,
  devotional,
}

class SongCard {
  /// Null when there is nothing to go on.
  final SongLanguage? language;
  final Set<Mood> moods;
  const SongCard(this.language, this.moods);

  @override
  String toString() => 'SongCard($language, $moods)';
}

/// Builds [SongCard]s. [artistLanguages] is what JARX learned about artists
/// from the user's history (see [learnArtistLanguages]); [playlistMoods] maps
/// a song key to the moods of the playlists it is in.
class SongCardReader {
  final Map<String, SongLanguage> artistLanguages;

  /// Artists whose language is known for sure (see [strongArtistLanguages]).
  /// For titles in English letters they win over the word guess: "Lover"
  /// by Diljit Dosanjh is Punjabi, not English.
  final Map<String, SongLanguage> strongArtists;
  final Map<String, Set<Mood>> playlistMoods;
  final String Function(Track) songKey;

  const SongCardReader({
    this.artistLanguages = const {},
    this.strongArtists = const {},
    this.playlistMoods = const {},
    required this.songKey,
  });

  SongCard read(Track t) {
    final text = '${t.title} ${t.album?.title ?? ''}';
    final script = scriptOf(text);
    final strong = script == null || script == 'latin'
        ? _lookup(strongArtists, t) ?? _lookup(_knownArtistLanguages, t)
        : null;
    return SongCard(
      strong ?? languageOfText(text) ?? _artistLanguage(t),
      {...moodsOfText(text), ...?playlistMoods[songKey(t)]},
    );
  }

  static SongLanguage? _lookup(Map<String, SongLanguage> m, Track t) {
    for (final a in t.artists.take(2)) {
      final l = m[artistKeyOf(a.name)];
      if (l != null) return l;
    }
    return null;
  }

  SongLanguage? _artistLanguage(Track t) {
    for (final a in t.artists) {
      final l = artistLanguages[artistKeyOf(a.name)];
      if (l != null) return l;
    }
    return null;
  }
}

/// Artist key -> the language most of their songs in [tracks] are in, for
/// artists with at least 2 songs whose language is clear from the text.
Map<String, SongLanguage> learnArtistLanguages(Iterable<Track> tracks) {
  final votes = <String, Map<SongLanguage, int>>{};
  for (final t in tracks) {
    final l = languageOfText('${t.title} ${t.album?.title ?? ''}');
    if (l == null) continue;
    for (final a in t.artists.take(2)) {
      final m = votes.putIfAbsent(artistKeyOf(a.name), () => {});
      m[l] = (m[l] ?? 0) + 1;
    }
  }
  return {
    for (final e in votes.entries)
      if (e.value.values.fold<int>(0, (a, b) => a + b) >= 2)
        e.key: e.value.entries.reduce((a, b) => b.value > a.value ? b : a).key,
  };
}

/// Language from the script, or from common words when the title is written
/// in English letters ("Tum Hi Ho" is Hindi). Null when unclear.
SongLanguage? languageOfText(String text) {
  switch (scriptOf(text)) {
    case 'devanagari':
      return SongLanguage.hindi;
    case 'gurmukhi':
      return SongLanguage.punjabi;
    case null:
      return null;
    case 'latin':
      break;
    default:
      return SongLanguage.other;
  }
  final words = _words(text);
  var hi = 0, pa = 0, en = 0;
  for (final w in words) {
    if (_punjabiWords.contains(w)) pa += 2;
    if (_hindiWords.contains(w)) hi++;
    if (_englishWords.contains(w)) en++;
  }
  // Bollywood releases: "(From "Movie")".
  if (_fromFilm.hasMatch(text)) hi++;
  if (pa >= 2 && pa >= hi) return SongLanguage.punjabi;
  if (hi > en && hi >= 1) return SongLanguage.hindi;
  if (en > hi && en >= 1) return SongLanguage.english;
  return null;
}

/// Moods named or strongly hinted at by the words in [text].
Set<Mood> moodsOfText(String text) {
  final words = _words(text);
  final joined = ' ${words.join(' ')} ';
  return {
    for (final e in _moodWords.entries)
      if (e.value.any(
          (w) => w.contains(' ') ? joined.contains(' $w ') : words.contains(w)))
        e.key,
  };
}

/// Moods suggested by a playlist's name ("Soothing" -> cozy).
Set<Mood> moodsOfPlaylistName(String name) => {
      ...moodsOfText(name),
      for (final e in _playlistMoodWords.entries)
        if (_words(name).any(e.value.contains)) e.key,
    };

final _fromFilm = RegExp(r'\(\s*from\s', caseSensitive: false);
final _nonWord = RegExp(r"[^a-z0-9ऀ-੿']+");

List<String> _words(String text) =>
    text.toLowerCase().split(_nonWord).where((w) => w.isNotEmpty).toList();

// Common words in Hindi/Urdu song titles written in English letters.
const _hindiWords = {
  'hai',
  'hain',
  'ho',
  'hoon',
  'hun',
  'tum',
  'tu',
  'tujhe',
  'tujhko',
  'tera',
  'teri',
  'tere',
  'mera',
  'meri',
  'mere',
  'main',
  'mein',
  'mujhe',
  'mujhko',
  'hum',
  'humko',
  'humein',
  'dil',
  'pyaar',
  'pyar',
  'ishq',
  'mohabbat',
  'sanam',
  'zindagi',
  'kabhi',
  'saath',
  'jaan',
  'jaana',
  'yaad',
  'aankhein',
  'ankhon',
  'raat',
  'kya',
  'kyun',
  'kaise',
  'koi',
  'nahi',
  'nahin',
  'na',
  'ki',
  'ka',
  'ke',
  'ko',
  'se',
  'ye',
  'yeh',
  'wo',
  'woh',
  'aaj',
  'kal',
  'dekha',
  'dekho',
  'chal',
  'chalo',
  'bina',
  'bin',
  'sajna',
  'saiyaan',
  'piya',
  'balam',
  'tujhse',
  'humse',
  'jaise',
  'aisa',
  'wala',
  'wali',
  'dard',
  'judaai',
  'tanha',
  'bewafa',
  'khuda',
  'rabba',
  'mahi',
  'yaara',
  'dilbar',
  'chand',
  'baarish',
  'sawan',
  'gaana',
  'geet',
  'dekhne',
  'walon',
};

// Words that are much more Punjabi than Hindi; worth two votes.
final _punjabiWords = {
  'nu',
  'ni',
  'mainu',
  'tainu',
  'sanu',
  'tuhanu',
  'kudi',
  'kudiye',
  'munda',
  'jatt',
  'jatti',
  'sohneya',
  'sohni',
  'kithe',
  'nal',
  'naal',
  'gal',
  'di',
  'da',
  'de',
  've',
  'vi',
  'dil',
  'tere',
  'pind',
  'yaaran',
  'akhiyan',
  'bhangra',
  'gabru',
  'patiala',
  'peg',
  'lalkaara',
  'shona',
  'jind',
  'mahiya',
  'hun',
}.difference(_hindiWords);

const _englishWords = {
  'the',
  'you',
  'your',
  'love',
  'me',
  'my',
  'i',
  'we',
  'it',
  'is',
  'are',
  'baby',
  'night',
  'heart',
  'don\'t',
  'dont',
  'all',
  'of',
  'to',
  'in',
  'on',
  'and',
  'for',
  'with',
  'what',
  'when',
  'like',
  'just',
  'one',
  'time',
  'girl',
  'boy',
  'feel',
  'feat',
  'shape',
  'stay',
  'closer',
  'faded',
  'happy',
  'dance',
  'party',
  'never',
  'forever',
  'say',
  'want',
  'need',
  'let',
  'go',
};

// Single words, or two-word phrases (matched as a phrase).
const Map<Mood, Set<String>> _moodWords = {
  Mood.sad: {
    'sad',
    'broken',
    'alone',
    'lonely',
    'cry',
    'crying',
    'tears',
    'goodbye',
    'dard',
    'judaai',
    'judai',
    'tanha',
    'tanhai',
    'bewafa',
    'rona',
    'aansu',
    'ansoo',
    'virah',
    'bichhad',
    'tootey',
    'toota',
    'dukh',
  },
  Mood.romantic: {
    'love',
    'romantic',
    'pyaar',
    'pyar',
    'ishq',
    'mohabbat',
    'sanam',
    'dilbar',
    'mehboob',
    'jaanam',
    'humsafar',
    'valentine',
    'kiss',
  },
  Mood.happy: {'happy', 'smile', 'muskura', 'khushi', 'sunshine', 'good vibes'},
  Mood.dance: {
    'dance',
    'party',
    'club',
    'nachde',
    'nach',
    'naach',
    'thumka',
    'bhangra',
    'disco',
    'dj',
    'groove',
    'lungi',
    'garba',
    'dandiya',
  },
  Mood.cozy: {
    'lofi',
    'lo-fi',
    'chill',
    'unplugged',
    'acoustic',
    'lullaby',
    'rain',
    'baarish',
    'sukoon',
    'soft',
    'sleep',
  },
  Mood.moody: {'moody', 'midnight', 'dark', 'raat', 'shaam', 'yaad'},
  Mood.uplifting: {
    'rise',
    'fly',
    'dream',
    'hope',
    'zinda',
    'jeet',
    'believe',
    'unstoppable',
    'chak de',
    'motivation',
  },
  Mood.energetic: {'workout', 'gym', 'power', 'beast', 'fire', 'hype', 'rap'},
  Mood.devotional: {
    'bhajan',
    'aarti',
    'arti',
    'mantra',
    'chalisa',
    'bhakti',
    'satsang',
    'shabad',
    'gurbani',
    'kirtan',
    'stuti',
    'stotram',
    'shloka',
    'ram dhun',
    'shree ram',
    'shri ram',
    'jai shree',
    'hare krishna',
    'om namah',
    'jai radha',
    'radha madhav',
    'shiv',
    'shiva',
    'hanuman',
    'ganesh',
    'bhole',
  },
};

// Extra playlist-name words (playlists are named by feeling, not lyrics).
const Map<Mood, Set<String>> _playlistMoodWords = {
  Mood.cozy: {'soothing', 'calm', 'relax', 'peaceful', 'chill', 'sukoon'},
  Mood.sad: {'heartbreak', 'emotional'},
  Mood.dance: {'gym', 'weekend', 'roadtrip', 'drive'},
  Mood.romantic: {'romance', 'crush', 'date'},
  Mood.uplifting: {'motivation', 'morning', 'focus'},
  Mood.moody: {'night', 'late', 'drive'},
};

/// Share of each language among the songs in [tracks] whose language is
/// clear (0..1), and how many such songs there were.
({Map<SongLanguage, double> shares, int total}) languageShares(
    Iterable<Track> tracks, Map<String, SongLanguage> artistLanguages,
    {Map<String, SongLanguage> strongArtists = const {}}) {
  final reader = SongCardReader(
      artistLanguages: artistLanguages,
      strongArtists: strongArtists,
      songKey: (t) => t.id);
  final counts = <SongLanguage, int>{};
  for (final t in tracks) {
    final l = reader.read(t).language;
    if (l != null) counts[l] = (counts[l] ?? 0) + 1;
  }
  final total = counts.values.fold<int>(0, (a, b) => a + b);
  return (
    shares: {
      for (final e in counts.entries) e.key: total == 0 ? 0 : e.value / total
    },
    total: total,
  );
}

/// The languages this listener actually plays: each language that is at
/// least 5% of the songs in [tracks] whose language is clear, and at least
/// 3 songs (a few Punjabi songs among many Hindi ones still count). Empty
/// (no preference) until at least 8 such songs, so a new listener isn't
/// boxed in.
Set<SongLanguage> learnUserLanguages(
    Iterable<Track> tracks, Map<String, SongLanguage> artistLanguages,
    {Map<String, SongLanguage> strongArtists = const {}}) {
  final list = tracks.toList();
  final r =
      languageShares(list, artistLanguages, strongArtists: strongArtists);
  if (r.total < 8) return const {};
  return {
    for (final e in r.shares.entries)
      if (e.value >= 0.05 && e.value * r.total >= 2.5) e.key,
  };
}

/// The language a playlist's name says its songs are in: "Punjabi Hits",
/// "Bollywood Party", "My One's(अंग्रेज़ी)". Null when it doesn't say.
SongLanguage? languageOfPlaylistName(String name) {
  final n = name.toLowerCase();
  if (n.contains('punjabi') || n.contains('ਪੰਜਾਬੀ') || n.contains('पंजाबी')) {
    return SongLanguage.punjabi;
  }
  if (n.contains('english') || n.contains('अंग्रेज़ी') || n.contains('अंग्रेजी')) {
    return SongLanguage.english;
  }
  if (n.contains('hindi') || n.contains('bollywood') || n.contains('हिंदी')) {
    return SongLanguage.hindi;
  }
  return null;
}

/// Artists whose language the user's own playlists name: everyone in
/// "Punjabi Hits" is Punjabi. When an artist is in playlists of different
/// languages, the one with most songs wins.
Map<String, SongLanguage> strongArtistLanguages(
    Map<String, List<Track>> playlists) {
  final votes = <String, Map<SongLanguage, int>>{};
  for (final e in playlists.entries) {
    final l = languageOfPlaylistName(e.key);
    if (l == null) continue;
    for (final t in e.value) {
      for (final a in t.artists.take(2)) {
        final k = artistKeyOf(a.name);
        if (k.isEmpty) continue;
        final m = votes.putIfAbsent(k, () => {});
        m[l] = (m[l] ?? 0) + 1;
      }
    }
  }
  return {
    for (final e in votes.entries)
      e.key: e.value.entries.reduce((a, b) => b.value > a.value ? b : a).key,
  };
}

/// Well-known Punjabi singers, so their songs count as Punjabi even when the
/// title is in English letters ("Excuses", "Softly", "295"). Checked against
/// Spotify India's yearly most-streamed lists; singers who mostly sing in
/// Hindi (Badshah, Mika Singh, Yo Yo Honey Singh) are left out.
final Map<String, SongLanguage> _knownArtistLanguages = {
  for (final name in const [
    'Diljit Dosanjh', 'AP Dhillon', 'Karan Aujla', 'Sidhu Moose Wala',
    'Shubh', 'Guru Randhawa', 'Jasmine Sandlas', 'Gurinder Gill',
    'Ammy Virk', 'Harrdy Sandhu', 'Jassie Gill', 'Jaani', 'Gippy Grewal',
    'Sharry Mann', 'Amrinder Gill', 'Satinder Sartaaj', 'Mankirt Aulakh',
    'Parmish Verma', 'Garry Sandhu', 'Nimrat Khaira', 'Sunanda Sharma',
    'Jass Manak', 'Arjan Dhillon', 'Gurnam Bhullar', 'R Nait', 'Prem Dhillon',
    'Sukh-E Muzical Doctorz', 'Bohemia', 'Kaka', 'Tegi Pannu', 'Cheema Y',
    'Gur Sidhu', 'Navaan Sandhu', 'Jordan Sandhu', 'Gurlez Akhtar',
    'Afsana Khan', 'Karan Randhawa', 'Jazzy B', 'Sukshinder Shinda',
    'Malkit Singh', 'Kuldeep Manak', 'Surjit Bindrakhia', 'Rajvir Jawanda',
    'Babbu Maan', 'Gurdas Maan', 'Kulwinder Billa', 'Ninja', 'Dilpreet Dhillon',
    'Mickey Singh', 'Sukhbir', 'Daler Mehndi', 'Hustinder', 'Simar Doraha',
    'Amrit Maan', 'Jass Bajwa', 'Gulab Sidhu', 'Veer Davinder',
    'Bir', 'Talwiinder', 'Sabba', 'Harkirat Sangha', 'Jassa Dhillon',
    'Ranjit Bawa', 'Kamal Heer', 'Manmohan Waris', 'Laddi Chahal',
    'Imran Khan', 'Gurshabad', 'Hunarr', 'Fateh', 'Kambi Rajpuria',
    'Shree Brar', 'Inderpal Moga',
  ])
    artistKeyOf(name): SongLanguage.punjabi,
};
