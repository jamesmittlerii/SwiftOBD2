import 'package:shared_preferences/shared_preferences.dart';

class ConfigurationService {
  static const _connectionTypeKey = 'flutter_obd2.connection_type';

  Future<void> setConnectionTypeName(String typeName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_connectionTypeKey, typeName);
  }

  Future<String?> getConnectionTypeName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_connectionTypeKey);
  }
}
