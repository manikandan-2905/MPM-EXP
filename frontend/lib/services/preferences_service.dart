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

  // Last View Mode (Persistent Role: 'customer' or 'rider')
  static const String _keyLastViewMode = 'mpm_last_view_mode';

  static Future<void> saveLastViewMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastViewMode, mode);
  }

  static Future<String?> getLastViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastViewMode);
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
    await prefs.setString(_keyLastViewMode, 'rider');
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
    await prefs.setString(_keyLastViewMode, 'customer');
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

  static Future<void> setRiderCompletedTrips(List<String> trips) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('mpm_rider_completed_trips', trips);
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

  static Future<void> removeOrderFromStore(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyGlobalOrders) ?? [];
    list.removeWhere((item) {
      try {
        final parsed = jsonDecode(item);
        final id = parsed['_id'] ?? parsed['id'] ?? parsed['orderNumber'];
        return id == orderId;
      } catch (_) {
        return false;
      }
    });
    await prefs.setStringList(_keyGlobalOrders, list);
  }

  static Future<void> clearStoredOrders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyGlobalOrders);
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

  static const String _keyInAppNotifications = 'mpm_in_app_notifications';
  static const String _keyDismissedBroadcastIds = 'mpm_dismissed_broadcast_ids';

  /// Save received notification to local inbox (keeps max 20)
  static Future<void> saveInAppNotification({
    required String title,
    required String body,
    String? type,
    String? orderId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyInAppNotifications) ?? [];
    // Prevent duplicate entries within short interval
    final isDuplicate = list.any((item) {
      try {
        final d = jsonDecode(item);
        return d['title'] == title && d['body'] == body;
      } catch (_) {
        return false;
      }
    });
    if (isDuplicate) return;

    final notifMap = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'title': title,
      'body': body,
      'type': type ?? 'ANNOUNCEMENT',
      'orderId': orderId ?? '',
      'timestamp': DateTime.now().toIso8601String(),
      'isRead': false,
    };
    list.insert(0, jsonEncode(notifMap));
    if (list.length > 30) list.removeRange(30, list.length);
    await prefs.setStringList(_keyInAppNotifications, list);
  }

  /// Mark all notifications as read (removes active fill color from bell icon)
  static Future<void> markNotificationsAsRead() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyInAppNotifications) ?? [];
    final List<String> updated = [];
    for (final item in list) {
      try {
        final d = jsonDecode(item) as Map<String, dynamic>;
        d['isRead'] = true;
        updated.add(jsonEncode(d));
      } catch (_) {
        updated.add(item);
      }
    }
    await prefs.setStringList(_keyInAppNotifications, updated);
  }

  /// Check if there are any unread notifications
  static Future<bool> hasUnreadNotifications() async {
    final notifs = await getInAppNotifications();
    return notifs.any((n) => n['isRead'] == false || n['isRead'] == null);
  }

  /// Sync remote MongoDB broadcasts into local inbox so users never miss announcements
  /// Checks permanently dismissed IDs so deleted broadcasts are NEVER re-added for the user
  static Future<void> syncRemoteBroadcasts(List<Map<String, dynamic>> broadcasts) async {
    if (broadcasts.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyInAppNotifications) ?? [];
    final dismissed = prefs.getStringList(_keyDismissedBroadcastIds) ?? [];

    for (final b in broadcasts) {
      final bId = b['_id']?.toString() ?? '';
      // If permanently deleted by this user, never re-add
      if (bId.isNotEmpty && dismissed.contains(bId)) {
        continue;
      }

      final title = b['title']?.toString() ?? 'ZIPPO Announcement';
      final body = b['message']?.toString() ?? '';
      if (body.isEmpty) continue;

      final alreadyExists = list.any((item) {
        try {
          final d = jsonDecode(item);
          return d['id'] == bId || (d['title'] == title && d['body'] == body);
        } catch (_) {
          return false;
        }
      });

      if (!alreadyExists) {
        final notifMap = {
          'id': bId.isNotEmpty ? bId : DateTime.now().millisecondsSinceEpoch.toString(),
          'title': title,
          'body': body,
          'type': b['type']?.toString() ?? 'ANNOUNCEMENT',
          'orderId': '',
          'timestamp': b['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
          'isRead': false,
        };
        list.insert(0, jsonEncode(notifMap));
      }
    }

    if (list.length > 30) list.removeRange(30, list.length);
    await prefs.setStringList(_keyInAppNotifications, list);
  }

  /// Get received in-app notifications
  static Future<List<Map<String, dynamic>>> getInAppNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyInAppNotifications) ?? [];
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

  /// Clear in-app notifications (marks all as permanently dismissed so remote sync won't restore them)
  static Future<void> clearInAppNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyInAppNotifications) ?? [];
    final dismissed = prefs.getStringList(_keyDismissedBroadcastIds) ?? [];
    for (final item in list) {
      try {
        final d = jsonDecode(item);
        final id = d['id']?.toString();
        if (id != null && !dismissed.contains(id)) {
          dismissed.add(id);
        }
      } catch (_) {}
    }
    await prefs.setStringList(_keyDismissedBroadcastIds, dismissed);
    await prefs.remove(_keyInAppNotifications);
  }

  /// Remove single notification from in-app inbox and mark permanently dismissed
  static Future<void> removeInAppNotification(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyInAppNotifications) ?? [];
    list.removeWhere((item) {
      try {
        final decoded = jsonDecode(item);
        return decoded['id']?.toString() == id;
      } catch (_) {
        return false;
      }
    });
    await prefs.setStringList(_keyInAppNotifications, list);

    // Save to permanently dismissed list so remote sync never re-adds it
    final dismissed = prefs.getStringList(_keyDismissedBroadcastIds) ?? [];
    if (!dismissed.contains(id)) {
      dismissed.add(id);
      await prefs.setStringList(_keyDismissedBroadcastIds, dismissed);
    }
  }

  /// Restore undone notification
  static Future<void> restoreInAppNotification(Map<String, dynamic> notif) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyInAppNotifications) ?? [];
    final dismissed = prefs.getStringList(_keyDismissedBroadcastIds) ?? [];
    final notifId = notif['id']?.toString();
    if (notifId != null) {
      dismissed.remove(notifId);
      await prefs.setStringList(_keyDismissedBroadcastIds, dismissed);
    }
    list.insert(0, jsonEncode(notif));
    await prefs.setStringList(_keyInAppNotifications, list);
  }
}
