import 'package:crypto/crypto.dart' as crypto;
import 'package:Bloomee/utils/country_info.dart';

class RemotePluginModel {
  final String assetName;
  final String description;
  final String id;
  final String name;
  final String manifestVersion;
  final String type;
  final String version;
  final String downloadUrl;
  final String? thumbnailUrl;
  final String? publisherName;
  final List<String> countryAllowlist;
  final DateTime? lastUpdated;

  /// SHA-256 of the plugin file, from the plugin list (hex). Empty when the
  /// list doesn't give one.
  final String sha256Hex;

  RemotePluginModel({
    required this.assetName,
    required this.description,
    required this.id,
    required this.name,
    required this.manifestVersion,
    required this.type,
    required this.version,
    required this.downloadUrl,
    this.thumbnailUrl,
    this.publisherName,
    this.countryAllowlist = const [],
    this.lastUpdated,
    this.sha256Hex = '',
  });

  /// Refuses a downloaded plugin file that isn't the one the list
  /// describes (swapped, corrupted or cut-off download). Plugins run code
  /// inside JARX, so this is checked before every install.
  ///
  /// ponytail: the hash comes from the same list as the download link, so
  /// this can't stop someone who controls that list. Upgrade path: sign the
  /// list with a key kept off GitHub and check the signature in the app.
  void verifyFile(List<int> bytes) {
    final want = sha256Hex.trim().toLowerCase();
    if (want.isEmpty) return; // older lists have no hashes yet
    final got = crypto.sha256.convert(bytes).toString();
    if (got != want) {
      throw PluginFileMismatch(name.isEmpty ? id : name);
    }
  }

  factory RemotePluginModel.fromJson(Map<String, dynamic> json) {
    return RemotePluginModel(
      assetName: json['asset_name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      manifestVersion: json['manifest_version']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      version: json['version']?.toString() ?? '',
      downloadUrl: json['download_url']?.toString() ?? '',
      thumbnailUrl: json['thumbnail_url']?.toString(),
      publisherName: json['publisher'] != null
          ? json['publisher']['name']?.toString()
          : null,
      countryAllowlist:
          (json['country_allowlist'] as List<dynamic>? ?? const [])
              .map((value) =>
                  CountryInfoService.normalizeCountryCode(value?.toString()))
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList()
            ..sort(),
      lastUpdated: json['last_updated'] != null
          ? DateTime.tryParse(json['last_updated'].toString())
          : null,
      sha256Hex: json['sha256']?.toString() ?? '',
    );
  }

  bool isAllowedInCountry(String countryCode) {
    if (countryAllowlist.isEmpty) {
      return true;
    }
    final normalized = CountryInfoService.normalizeCountryCode(countryCode);
    return normalized.isNotEmpty && countryAllowlist.contains(normalized);
  }
}

class PluginRepositoryModel {
  final String url;
  final String schemaVersion;
  final String name;
  final String description;
  final String? thumbnailUrl;
  final List<RemotePluginModel> plugins;
  final DateTime? generatedAt;

  PluginRepositoryModel({
    required this.url,
    required this.schemaVersion,
    required this.name,
    required this.description,
    this.thumbnailUrl,
    required this.plugins,
    this.generatedAt,
  });

  factory PluginRepositoryModel.fromJson(
      String url, Map<String, dynamic> json) {
    return PluginRepositoryModel(
      url: url,
      schemaVersion: json['schema_version']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown Repository',
      description: json['description']?.toString() ?? '',
      thumbnailUrl: json['thumbnail_url']?.toString(),
      plugins: (json['plugins'] as List?)
              ?.map((p) =>
                  RemotePluginModel.fromJson(Map<String, dynamic>.from(p)))
              .toList() ??
          [],
      generatedAt: json['generated_at'] != null
          ? DateTime.tryParse(json['generated_at'].toString())
          : null,
    );
  }
}

/// A downloaded plugin file doesn't match the fingerprint in the plugin list.
class PluginFileMismatch implements Exception {
  PluginFileMismatch(this.plugin);
  final String plugin;

  @override
  String toString() =>
      'The downloaded "$plugin" plugin did not match its fingerprint, so it '
      'was not installed. Try again later.';
}
