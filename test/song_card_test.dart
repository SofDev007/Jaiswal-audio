// Song cards: language and mood guessed from song text (recommendations
// Layer 1). Titles are real ones seen on the test phone.

import 'package:Bloomee/services/recommendations/song_card.dart';
import 'package:Bloomee/src/rust/api/plugin/models.dart';
import 'package:flutter_test/flutter_test.dart';

Track _t(String title, List<String> artists, {String? album}) => Track(
      id: title,
      title: title,
      artists: [for (final a in artists) ArtistSummary(id: a, name: a)],
      album: album == null
          ? null
          : AlbumSummary(id: album, title: album, artists: const []),
      thumbnail: const Artwork(url: '', layout: ImageLayout.square),
      isExplicit: false,
    );

String _key(Track t) => t.title.toLowerCase();

void main() {
  test('language from script and from words in English letters', () {
    expect(languageOfText('तुम ही हो'), SongLanguage.hindi);
    expect(languageOfText('ਤੇਰੇ ਨਾਲ'), SongLanguage.punjabi);
    expect(languageOfText('Tum Hi Ho'), SongLanguage.hindi);
    expect(languageOfText('Kal Chaudhvin Ki Raat Thi'), SongLanguage.hindi);
    expect(
        languageOfText('Mainu Tere Naal Pyaar Ho Gaya'), SongLanguage.punjabi);
    expect(languageOfText('Closer (feat. Halsey)'), SongLanguage.english);
    expect(languageOfText('Shape of You'), SongLanguage.english);
    expect(languageOfText('Kinna Sona'), isNull);
    expect(languageOfText('Darkhaast (From "Shivaay")'), SongLanguage.hindi);
  });

  test('artists inherit the language of their clear songs', () {
    final langs = learnArtistLanguages([
      _t('Tum Hi Ho', ['Mithoon']),
      _t('Tera Mera Rishta', ['Mithoon']),
      _t('Shape of You', ['Ed Sheeran']),
    ]);
    expect(langs['mithoon'], SongLanguage.hindi);
    expect(langs.containsKey('ed sheeran'), isFalse); // one song only

    final reader = SongCardReader(
        artistLanguages: langs, songKey: (t) => t.title.toLowerCase());
    expect(reader.read(_t('Kinna Sona', ['Mithoon'])).language,
        SongLanguage.hindi);
  });

  test('moods from title words, and devotional songs are recognised', () {
    expect(moodsOfText('Shree Ram Dhun'), contains(Mood.devotional));
    expect(moodsOfText('Jai Radha Madhav'), contains(Mood.devotional));
    expect(moodsOfText('Hanuman Chalisa'), contains(Mood.devotional));
    expect(moodsOfText('Tum Hi Ho'), isNot(contains(Mood.devotional)));
    expect(moodsOfText('Bewafa Tera Masoom Chehra'), contains(Mood.sad));
    expect(moodsOfText('Lungi Dance'), contains(Mood.dance));
    expect(moodsOfText('Pyaar Ka Pehla Khat'), contains(Mood.romantic));
    expect(moodsOfText('Kali Kali Zulfon Ke Phande Nah Dalo'), isEmpty);
  });

  test('playlist names give their songs a mood', () {
    expect(moodsOfPlaylistName('Soothing'), {Mood.cozy});
    expect(moodsOfPlaylistName('Party Hits'), contains(Mood.dance));
    expect(moodsOfPlaylistName('Old is Gold💰'), isEmpty);

    final reader = SongCardReader(
      playlistMoods: {
        'kinna sona': {Mood.cozy}
      },
      songKey: (t) => t.title.toLowerCase(),
    );
    expect(reader.read(_t('Kinna Sona', ['Mithoon'])).moods, {Mood.cozy});
  });

  test("the listener's languages are learned from what they play", () {
    final hindi = [for (var i = 0; i < 7; i++) _t('Tum Hi Ho $i', ['A'])];
    final english = [for (var i = 0; i < 3; i++) _t('Shape of You $i', ['B'])];
    final tamil = [_t('நீ கவிதைகளா', ['C'])];

    // Too few clear songs yet: no preference.
    expect(learnUserLanguages(hindi.take(5), const {}), isEmpty);

    final langs = learnUserLanguages([...hindi, ...english, ...tamil], const {});
    expect(langs, {SongLanguage.hindi, SongLanguage.english});
    // 1 Tamil song of 11 is under 3 songs: not a language they listen to (yet).
    expect(langs, isNot(contains(SongLanguage.other)));
  });

  test('Punjabi from well-known singers and from playlist names', () {
    const reader = SongCardReader(songKey: _key);
    // English-looking titles by Punjabi singers are Punjabi.
    expect(reader.read(_t('Lover', ['Diljit Dosanjh'])).language,
        SongLanguage.punjabi);
    expect(reader.read(_t('Excuses', ['AP Dhillon', 'Gurinder Gill'])).language,
        SongLanguage.punjabi);
    // A Devanagari title still goes by its script.
    expect(reader.read(_t('तुम ही हो', ['Diljit Dosanjh'])).language,
        SongLanguage.hindi);

    expect(languageOfPlaylistName('Punjabi Hits'), SongLanguage.punjabi);
    expect(languageOfPlaylistName("My One's(अंग्रेज़ी)"), SongLanguage.english);
    expect(languageOfPlaylistName('Old is Gold'), isNull);

    final strong = strongArtistLanguages({
      'Punjabi Hits': [_t('Brown Rang', ['Some New Singer'])],
    });
    final r2 = SongCardReader(strongArtists: strong, songKey: _key);
    expect(r2.read(_t('Nights', ['Some New Singer'])).language,
        SongLanguage.punjabi);
  });

  test('a smaller language still counts when it is a real habit', () {
    final hindi = [for (var i = 0; i < 40; i++) _t('Tum Hi Ho $i', ['A'])];
    final punjabi = [
      for (var i = 0; i < 3; i++) _t('Softly $i', ['Karan Aujla'])
    ];
    expect(learnUserLanguages([...hindi, ...punjabi], const {}),
        {SongLanguage.hindi, SongLanguage.punjabi});
  });
}
