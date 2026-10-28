import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static const String _keyCustomerName = 'mpm_customer_name';
  static const String _keyCustomerPhone = 'mpm_customer_phone';
  static const String _keyRiderId = 'mpm_rider_id';
  static const String _keyRiderName = 'mpm_rider_name';
  static const String _keyRiderPhone = 'mpm_rider_phone';
  static const String _keyFcmToken = 'mpm_fcm_token';

  // Guest Customer Profile
  static Future<void> saveCustomerProfile(String name, String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCustomerName, name.trim());
    await prefs.setString(_keyCustomerPhone, phone.trim());
  }

  static Future<Map<String, String?>> getCustomerProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'name': prefs.getString(_keyCustomerName),
      'phone': prefs.getString(_keyCustomerPhone),
    };
  }

  static Future<bool> hasCustomerProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_keyCustomerPhone) &&
        (prefs.getString(_keyCustomerPhone)?.isNotEmpty ?? false);
  }

  // Rider Session
  static Future<void> saveRiderSession({
    required String id,
    required String name,
    required String phone,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRiderId, id);
    await prefs.setString(_keyRiderName, name);
    await prefs.setString(_keyRiderPhone, phone);
  }

  static Future<Map<String, String?>> getRiderSession() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'id': prefs.getString(_keyRiderId),
      'name': prefs.getString(_keyRiderName),
      'phone': prefs.getString(_keyRiderPhone),
    };
  }

  static Future<void> clearRiderSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyRiderId);
    await prefs.remove(_keyRiderName);
    await prefs.remove(_keyRiderPhone);
  }

  // FCM Token Cache
  static Future<void> saveFcmToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFcmToken, token);
  }

  static Future<String?> getFcmToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyFcmToken);
  }
}
