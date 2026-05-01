import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

import '../decoders.dart';
import 'obd_command.dart';

class Commands {
  static const String _commandsAssetPackage =
      'packages/flutter_obd2/lib/src/data/commands.enriched.json';
  static const String _commandsAssetLocal = 'lib/src/data/commands.enriched.json';
  static const String _aliasesAssetPackage =
      'packages/flutter_obd2/lib/src/data/command_aliases.json';
  static const String _aliasesAssetLocal = 'lib/src/data/command_aliases.json';

  static final Map<String, ObdCommand> _allCommands = <String, ObdCommand>{};
  static final Map<String, String> _mode1AliasToCommandId = <String, String>{};
  static final Map<String, String> _gmMode22AliasToCommandId = <String, String>{};
  static final List<String> _pidGetterCommands = <String>[];
  static Future<void>? _initFuture;

  static Map<String, ObdCommand> get allCommands => _allCommands;
  static List<String> get pidGetterCommands => _pidGetterCommands;

  static Future<void> ensureInitialized() async {
    _initFuture ??= _load();
    await _initFuture;
  }

  static String resolveCommandId(String alias, {String? pidType}) {
    final trimmed = alias.trim();
    if (trimmed.isEmpty) return alias;

    final upper = trimmed.toUpperCase();
    if (_allCommands.containsKey(upper)) return upper;

    final normalized = trimmed.toLowerCase();
    if (pidType?.trim().toLowerCase() == 'gmmode22') {
      return _gmMode22AliasToCommandId[normalized] ?? upper;
    }
    return _mode1AliasToCommandId[normalized] ?? upper;
  }

  static Future<void> _load() async {
    WidgetsFlutterBinding.ensureInitialized();
    final aliasesRaw = await _loadAssetWithFallback(
      _aliasesAssetPackage,
      _aliasesAssetLocal,
    );
    final aliasesObj = jsonDecode(aliasesRaw) as Map<String, dynamic>;
    _populateAliasMap(_mode1AliasToCommandId, aliasesObj['mode1']);
    _populateAliasMap(_gmMode22AliasToCommandId, aliasesObj['GMmode22']);

    final commandsRaw = await _loadAssetWithFallback(
      _commandsAssetPackage,
      _commandsAssetLocal,
    );
    final rows = jsonDecode(commandsRaw) as List<dynamic>;
    for (final row in rows) {
      final cmd = row as Map<String, dynamic>;
      final command = (cmd['command'] as String).toUpperCase();
      final description = cmd['description'] as String;
      final bytes = (cmd['bytes'] as num).toInt();
      final live = (cmd['live'] as bool?) ?? false;
      final maxValue = (cmd['maxValue'] as num?)?.toDouble() ?? 100;
      final minValue = (cmd['minValue'] as num?)?.toDouble() ?? 0;
      final decoder = _decoderFromJson(
        (cmd['decoder'] as Map<String, dynamic>?) ?? const {},
      );

      _allCommands[command] = ObdCommand(
        CommandProperties(
          command,
          description,
          bytes,
          decoder,
          live: live,
          maxValue: maxValue,
          minValue: minValue,
        ),
      );

      final lowerDescription = description.toLowerCase();
      if (lowerDescription.startsWith('supported pids [') ||
          lowerDescription.startsWith('supported mids [')) {
        _pidGetterCommands.add(command);
      }
    }
  }

  static Future<String> _loadAssetWithFallback(String preferred, String fallback) async {
    try {
      return await rootBundle.loadString(preferred);
    } catch (_) {
      return rootBundle.loadString(fallback);
    }
  }

  static void _populateAliasMap(Map<String, String> target, dynamic source) {
    if (source is! Map<String, dynamic>) return;
    source.forEach((key, value) {
      if (value is String) {
        target[key.toLowerCase()] = value.toUpperCase();
      }
    });
  }

  static Decoder? _decoderFromJson(Map<String, dynamic> decoderJson) {
    if (decoderJson.isEmpty) return null;
    final key = decoderJson.keys.first;
    final payload = decoderJson[key];

    switch (key) {
      case 'none':
      case 'pid':
      case 'count':
      case 'cvn':
        return null;
      case 'status':
        return StatusDecoder();
      case 'singleDTC':
        return SingleDtcDecoder();
      case 'fuelStatus':
        return FuelStatusDecoder();
      case 'dtc':
        return DtcDecoder();
      case 'percent':
        return PercentDecoder();
      case 'percentCentered':
        return PercentCenteredDecoder();
      case 'temp':
        return TemperatureDecoder();
      case 'pressure':
        return PressureDecoder();
      case 'airStatus':
        return AirStatusDecoder();
      case 'o2Sensors':
        return O2SensorsDecoder();
      case 'o2SensorsAlt':
        return O2SensorsAltDecoder();
      case 'obdCompliance':
        return OBDComplianceDecoder();
      case 'sensorVoltage':
        return SensorVoltageDecoder();
      case 'sensorVoltageBig':
        return SensorVoltageBigDecoder();
      case 'evapPressure':
        return EvapPressureDecoder();
      case 'evapPressureAlt':
        return EvapPressureAltDecoder();
      case 'currentCentered':
        return CurrentCenteredDecoder();
      case 'timingAdvance':
        return TimingAdvanceDecoder();
      case 'injectTiming':
        return InjectTimingDecoder();
      case 'fuelRate':
        return FuelRateDecoder();
      case 'maxMaf':
        return MaxMafDecoder();
      case 'fuelType':
        return FuelTypeDecoder();
      case 'monitor':
        return MonitorDecoder();
      case 'encoded_string':
        return StringDecoder();
      case 'uas':
        final offset = payload is Map<String, dynamic>
            ? (payload['_0'] as num?)?.toInt() ?? 0
            : 0;
        return UasDecoder(offset);
      case 'GMoilPressure':
        return GMEngineOilPressureDecoder();
      case 'GMACPressure':
        return GMACPressureDecoder();
      default:
        return null;
    }
  }
}
