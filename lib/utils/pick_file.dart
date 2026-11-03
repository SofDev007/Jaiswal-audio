import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

/// Picks one file ending in one of [extensions] (lower case, no dot).
///
/// Android's picker filters by the type other apps give a file, not by its
/// name, so a CSV shared from Drive or WhatsApp as "spreadsheet" or "text"
/// would be greyed out. So every file is pickable and the ending is checked
/// here. A name with no ending at all is let through (some apps drop it), so
/// the importer's own parser decides. Returns null when cancelled; throws
/// [WrongFileType] for a file with another ending.
Future<String?> pickFileWithExtension(List<String> extensions,
    {String? dialogTitle}) async {
  final result = await FilePicker.platform
      .pickFiles(type: FileType.any, dialogTitle: dialogTitle);
  final path = result?.files.firstOrNull?.path;
  if (path == null) return null;
  final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
  if (ext.isNotEmpty && !extensions.contains(ext)) {
    throw WrongFileType(extensions);
  }
  return path;
}

class WrongFileType implements Exception {
  const WrongFileType(this.expected);
  final List<String> expected;

  /// "Please choose a .csv file" / "Please choose a .m3u or .m3u8 file".
  String get message =>
      'Please choose a ${expected.map((e) => '.$e').join(' or ')} file';

  @override
  String toString() => message;
}
