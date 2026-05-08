import 'dart:io';
import 'package:flutter/foundation.dart';

typedef ObdLogHandler = void Function(String message, {String level, String category});

class ObdLog {
  static ObdLogHandler? _handler;
  static bool enableConsoleOutput = !Platform.environment.containsKey('FLUTTER_TEST');

  static void setHandler(ObdLogHandler handler) {
    _handler = handler;
  }

  static void info(String message, {String category = 'Communication'}) {
    _log(message, level: 'info', category: category);
  }

  static void debug(String message, {String category = 'Communication'}) {
    _log(message, level: 'debug', category: category);
  }

  static void warning(String message, {String category = 'Communication'}) {
    _log(message, level: 'warning', category: category);
  }

  static void error(String message, {String category = 'Communication'}) {
    _log(message, level: 'error', category: category);
  }

  static void _log(String message, {required String level, required String category}) {
    if (_handler != null) {
      _handler!(message, level: level, category: category);
    } else if (enableConsoleOutput) {
      debugPrint('[$level $category] $message');
    }
  }
}
