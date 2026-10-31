import 'dart:convert';
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

  static const String _keyCustomerActiveOrderId = 'mpm_customer_active_order_id';
  static const String _keyRiderActiveOrderId = 'mpm_rider_active_order_id';

  // Customer Active Order Persistence
  static Future<void> saveCustomerActiveOrderId(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCustomerActiveOrderId, orderId.trim());
  }

  static Future<String?> getCustomerActiveOrderId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCustomerActiveOrderId);
  }

  static Future<void> clearCustomerActiveOrderId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCustomerActiveOrderId);
  }

  // Rider Active Order Persistence
  static Future<void> saveRiderActiveOrderId(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRiderActiveOrderId, orderId.trim());
  }

  static Future<String?> getRiderActiveOrderId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyRiderActiveOrderId);
  }

  static Future<void> clearRiderActiveOrderId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyRiderActiveOrderId);
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
    await prefs.remove(_keyRiderActiveOrderId);
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

  // Rider Completed Deliveries History
  static Future<void> saveRiderCompletedTrip(String tripJson) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('mpm_rider_completed_trips') ?? [];
    list.insert(0, tripJson);
    await prefs.setStringList('mpm_rider_completed_trips', list);
  }

  static Future<List<String>> getRiderCompletedTrips() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('mpm_rider_completed_trips') ?? [];
  }

  static Future<void> clearRiderCompletedTrips() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('mpm_rider_completed_trips');
  }

  // Admin Session
  static const String _keyAdminSession = 'mpm_admin_session';

  static Future<void> saveAdminSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAdminSession, true);
  }

  static Future<bool> isAdminLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAdminSession) ?? false;
  }

  static Future<void> clearAdminSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAdminSession);
  }

  // Global Orders Store (for offline sync & live admin monitoring)
  static const String _keyGlobalOrders = 'mpm_global_all_orders';

  static Future<void> saveOrderToStore(Map<String, dynamic> orderJson) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyGlobalOrders) ?? [];
    final id = orderJson['_id'] ?? orderJson['id'] ?? orderJson['orderNumber'];

    int existingIdx = -1;
    for (int i = 0; i < list.length; i++) {
      try {
        final parsed = jsonDecode(list[i]);
        final parsedId = parsed['_id'] ?? parsed['id'] ?? parsed['orderNumber'];
        if (parsedId == id) {
          existingIdx = i;
          break;
        }
      } catch (_) {}
    }

    final encoded = jsonEncode(orderJson);
    if (existingIdx != -1) {
      list[existingIdx] = encoded;
    } else {
      list.insert(0, encoded);
    }
    await prefs.setStringList(_keyGlobalOrders, list);
  }

  static Future<List<Map<String, dynamic>>> getStoredOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyGlobalOrders) ?? [];
    final List<Map<String, dynamic>> result = [];
    for (final item in list) {
      try {
        final decoded = jsonDecode(item);
        if (decoded is Map<String, dynamic>) {
          result.add(decoded);
        }
      } catch (_) {}
    }
    return result;
  }
}

