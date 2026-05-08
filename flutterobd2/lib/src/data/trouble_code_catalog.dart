import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../decoders.dart';

class TroubleCodeCatalog {
  static final Map<String, TroubleCodeMetadata> _entries = {};
  static bool _loaded = false;

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    final raw = await _loadCatalogJson();
    final json = jsonDecode(raw) as Map<String, dynamic>;

    List<String> parseList(String key) =>
        (json[key] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList();

    final causes = parseList('causes');
    final remedies = parseList('remedies');
    final codes = json['codes'] as Map<String, dynamic>? ?? const {};

    _entries.clear();
    codes.forEach((code, value) {
      final info = value as Map<String, dynamic>;

      List<String> mapIndexes(String key, List<String> source) {
        final indexes =
            (info[key] as List<dynamic>? ?? const []).map((e) => e as int);
        return indexes
            .map((i) => i >= 0 && i < source.length ? source[i] : null)
            .whereType<String>()
            .toList();
      }

      _entries[code] = TroubleCodeMetadata(
        code: code,
        title: (info['title'] as String?) ?? '',
        description: (info['description'] as String?) ?? '',
        severity: severityFor(code),
        causes: mapIndexes('causeIndexes', causes),
        remedies: mapIndexes('remedyIndexes', remedies),
      );
    });
    _loaded = true;
  }

  static TroubleCodeMetadata? lookup(String code) => _entries[code];

  static String severityFor(String code) {
    const criticalCodes = {
      'P0087',
      'P0088',
      'P0217',
      'P0218',
      'P0219',
      'P0234',
      'P0606',
    };
    if (criticalCodes.contains(code) ||
        code.startsWith('P030') ||
        code.startsWith('P031')) {
      return 'Critical';
    }
    const highPrefixes = [
      'P017',
      'P032',
      'P033',
      'P034',
      'P035',
      'P036',
      'P039'
    ];
    const highCodes = {'U0121', 'U0151'};
    if (highCodes.contains(code) ||
        highPrefixes.any(code.startsWith) ||
        code.startsWith('P07') ||
        code.startsWith('P08')) {
      return 'High';
    }
    const lowPrefixes = ['P041', 'P042', 'P043', 'P044', 'P045', 'P049'];
    if (lowPrefixes.any(code.startsWith)) return 'Low';
    return 'Moderate';
  }

  static Future<String> _loadCatalogJson() async {
    const packagePath = 'packages/flutter_obd2/lib/src/data/codes.json';
    const localPath = 'lib/src/data/codes.json';
    try {
      return await rootBundle.loadString(packagePath);
    } catch (_) {
      return await rootBundle.loadString(localPath);
    }
  }
}
