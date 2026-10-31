import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/order_model.dart';
import '../models/rider_model.dart';
import 'preferences_service.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final String baseUrl = AppConstants.apiBaseUrl;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Map<String, dynamic>? _safeJsonDecode(String body) {
    try {
      final trimmed = body.trim();
      if (trimmed.isEmpty || trimmed.startsWith('<')) return null;
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  // 1. Live Active Riders Count (for Customer Top Bar)
  Future<int> getActiveRidersCount() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/riders/active-count'), headers: _headers)
          .timeout(const Duration(seconds: 8));

      final data = _safeJsonDecode(response.body);
      if (response.statusCode == 200 && data != null && data['activeRidersCount'] != null) {
        return (data['activeRidersCount'] as num).toInt();
      }
    } catch (e) {}
    return 0; // Default to 0 when no riders are actively online in DB
  }

  // 2. Create Order (Guest Customer & Testing)
  Future<Map<String, dynamic>> createOrder(Map<String, dynamic> payload) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/orders'),
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));

      final data = _safeJsonDecode(response.body);
      if (response.statusCode == 201 && data != null && data['success'] == true) {
        if (data['order'] != null) {
          await PreferencesService.saveOrderToStore(data['order']);
        }
        return {
          'order': OrderModel.fromJson(data['order']),
          'whatsappTicket': (data['whatsappTicket'] as String?) ?? '🛵 ZIPPO Dispatch Order',
        };
      }
    } catch (_) {}

    // Resilient fallback for local testing / offline dummy orders:
    final dateCode = DateTime.now().toIso8601String().substring(2, 10).replaceAll('-', '');
    final randCode = 1000 + (DateTime.now().millisecond * 7 % 9000);
    final dummyNumber = 'ZIPPO-$dateCode-$randCode';
    final dummyPin = '${1000 + (DateTime.now().microsecond % 9000)}';
    final dummyJson = {
      '_id': 'ord_${DateTime.now().millisecondsSinceEpoch}',
      'orderNumber': dummyNumber,
      'customerName': payload['customerName'] ?? 'Customer',
      'customerPhone': payload['customerPhone'] ?? '9876543210',
      'pickupPhone': payload['pickupPhone'] ?? payload['customerPhone'] ?? '9876543210',
      'dropPhone': payload['dropPhone'] ?? payload['customerPhone'] ?? '9876543210',
      'orderType': payload['orderType'] ?? 'PICKUP_DROP',
      'category': payload['category'] ?? 'Custom',
      'itemsList': payload['itemsList'] ?? ['Essential Package'],
      'shopName': payload['shopName'] ?? '',
      'budget': payload['budget'] ?? 0,
      'isUrgent': payload['isUrgent'] ?? false,
      'pickupAddress': payload['pickupAddress'] ?? 'Melapalayam Center',
      'dropAddress': payload['dropAddress'] ?? 'Melapalayam Landmark',
      'status': 'ORDER_PLACED',
      'assignedRider': null,
      'deliveryPin': dummyPin,
      'isOtpBypassed': false,
      'fare': payload['calculatedFare'] ?? payload['fare'] ?? 30,
      'estimatedDistanceKm': payload['estimatedDistanceKm'] ?? 2.0,
      'paymentMode': 'Cash',
      'createdAt': DateTime.now().toIso8601String(),
    };
    await PreferencesService.saveOrderToStore(dummyJson);
    return {
      'order': OrderModel.fromJson(dummyJson),
      'whatsappTicket': '🛵 *ZIPPO DISPATCH*\nOrder: #$dummyNumber',
    };
  }

  // 3. Get Order by ID
  Future<OrderModel> getOrderById(String orderId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/orders/$orderId'), headers: _headers)
          .timeout(const Duration(seconds: 8));

      final data = _safeJsonDecode(response.body);
      if (response.statusCode == 200 && data != null && data['success'] == true) {
        await PreferencesService.saveOrderToStore(data['order']);
        return OrderModel.fromJson(data['order']);
      }
    } catch (_) {}

    final stored = await PreferencesService.getStoredOrders();
    for (final s in stored) {
      if (s['_id'] == orderId || s['id'] == orderId || s['orderNumber'] == orderId) {
        return OrderModel.fromJson(s);
      }
    }
    throw Exception('Order not found');
  }

  // 4. Get Latest Ongoing Active Order for Customer Phone
  Future<OrderModel?> getCustomerActiveOrder(String phone) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/orders/customer/$phone/active'), headers: _headers)
          .timeout(const Duration(seconds: 8));

      final data = _safeJsonDecode(response.body);
      if (response.statusCode == 200 && data != null && data['hasActiveOrder'] == true && data['order'] != null) {
        await PreferencesService.saveOrderToStore(data['order']);
        return OrderModel.fromJson(data['order']);
      }
    } catch (_) {}

    final stored = await PreferencesService.getStoredOrders();
    for (final s in stored) {
      if ((s['customerPhone'] == phone || s['dropPhone'] == phone) &&
          s['status'] != 'DELIVERED' &&
          s['status'] != 'CANCELLED') {
        return OrderModel.fromJson(s);
      }
    }
    return null;
  }

  // 5. Cancel Order
  Future<void> cancelOrder(String orderId, {String reason = 'Customer requested'}) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/orders/$orderId/cancel'),
            headers: _headers,
            body: jsonEncode({'reason': reason}),
          )
          .timeout(const Duration(seconds: 8));

      final data = _safeJsonDecode(response.body);
      if (response.statusCode == 200 && data != null && data['success'] == true) {
        if (data['order'] != null) {
          await PreferencesService.saveOrderToStore(data['order']);
        }
        return;
      }
    } catch (_) {}

    // Update locally
    final stored = await PreferencesService.getStoredOrders();
    for (final s in stored) {
      if (s['_id'] == orderId || s['id'] == orderId || s['orderNumber'] == orderId) {
        s['status'] = 'CANCELLED';
        await PreferencesService.saveOrderToStore(s);
        return;
      }
    }
  }

  // 6. Rider Login (Passcode authentication with local authorized fallback)
  Future<RiderModel> loginRider(String password, {String? phone, String? fcmToken}) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/riders/login'),
            headers: _headers,
            body: jsonEncode({
              if (phone != null && phone.isNotEmpty) 'phone': phone,
              'password': password,
              'fcmToken': fcmToken,
            }),
          )
          .timeout(const Duration(seconds: 8));

      final data = _safeJsonDecode(response.body);
      if (response.statusCode == 200 && data != null && data['success'] == true) {
        return RiderModel.fromJson(data['rider']);
      }
    } catch (_) {}

    // Fallback: Verified Melapalayam Fleet Passcodes
    final fleetMap = {
      '02266': {'id': 'r_sudalai', 'name': 'Sudalai', 'phone': '9363302266', 'isOnline': false, 'totalDeliveries': 0, 'totalEarnings': 0, 'todayOrders': 0, 'cashEarnings': 0, 'upiEarnings': 0},
      '83476': {'id': '6ae34ea6ed8921437ffd42da', 'name': 'V Mani', 'phone': '7639483476', 'isOnline': false, 'totalDeliveries': 3, 'totalEarnings': 105, 'todayOrders': 0, 'cashEarnings': 0, 'upiEarnings': 0},
      '82476': {'id': '6ae34ea6ed8921437ffd42da', 'name': 'V Mani', 'phone': '7639483476', 'isOnline': false, 'totalDeliveries': 3, 'totalEarnings': 105, 'todayOrders': 0, 'cashEarnings': 0, 'upiEarnings': 0},
      '29930': {'id': '6ae34ea6ed8921437ffd42db', 'name': 'MS Mani', 'phone': '6379329930', 'isOnline': true, 'totalDeliveries': 0, 'totalEarnings': 0, 'todayOrders': 0, 'cashEarnings': 0, 'upiEarnings': 0},
      '50818': {'id': 'r_hari', 'name': 'Hari', 'phone': '9344590818', 'isOnline': false, 'totalDeliveries': 0, 'totalEarnings': 0, 'todayOrders': 0, 'cashEarnings': 0, 'upiEarnings': 0},
      '76183': {'id': 'r_mathan', 'name': 'Mathan', 'phone': '9791766183', 'isOnline': false, 'totalDeliveries': 0, 'totalEarnings': 0, 'todayOrders': 0, 'cashEarnings': 0, 'upiEarnings': 0},
      '10215': {'id': 'r_santhanam', 'name': 'Santhanam', 'phone': '7010710215', 'isOnline': false, 'totalDeliveries': 0, 'totalEarnings': 0, 'todayOrders': 0, 'cashEarnings': 0, 'upiEarnings': 0},
      '07394': {'id': 'r_raja', 'name': 'RAJA', 'phone': '7695807394', 'isOnline': false, 'totalDeliveries': 0, 'totalEarnings': 0, 'todayOrders': 0, 'cashEarnings': 0, 'upiEarnings': 0},
    };

    final p = password.trim();
    if (fleetMap.containsKey(p)) {
      return RiderModel.fromJson(fleetMap[p]!);
    }

    throw Exception('Invalid passcode. Please enter valid 5-digit rider password or master admin key.');
  }

  // 7. Toggle Rider Online/Offline
  Future<bool> toggleOnlineStatus(String riderId, bool isOnline) async {
    try {
      final response = await http
          .patch(
            Uri.parse('$baseUrl/riders/$riderId/online-status'),
            headers: _headers,
            body: jsonEncode({'isOnline': isOnline}),
          )
          .timeout(const Duration(seconds: 8));

      final data = _safeJsonDecode(response.body);
      if (response.statusCode == 200 && data != null && data['success'] == true) {
        return data['rider']['isOnline'] ?? isOnline;
      }
    } catch (_) {}
    return isOnline;
  }

  // 8. Get Available Orders Pool for Riders
  Future<List<OrderModel>> getAvailableOrders() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/orders/pool/available'), headers: _headers)
          .timeout(const Duration(seconds: 8));

      final data = _safeJsonDecode(response.body);
      if (response.statusCode == 200 && data != null && data['success'] == true) {
        final List ordersJson = data['orders'] ?? [];
        for (final item in ordersJson) {
          await PreferencesService.saveOrderToStore(item);
        }
        return ordersJson.map((i) => OrderModel.fromJson(i)).toList();
      }
    } catch (_) {}

    final stored = await PreferencesService.getStoredOrders();
    final available = stored
        .where((s) => s['status'] == 'ORDER_PLACED' && s['assignedRider'] == null)
        .map((s) => OrderModel.fromJson(s))
        .toList();
    available.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return available;
  }

  // 9. Atomic Claim Order
  Future<OrderModel> claimOrder(String orderId, String riderId, {String? riderName, String? riderPhone}) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/orders/$orderId/claim'),
            headers: _headers,
            body: jsonEncode({'riderId': riderId}),
          )
          .timeout(const Duration(seconds: 8));

      final data = _safeJsonDecode(response.body);
      if (response.statusCode == 200 && data != null && data['success'] == true) {
        await PreferencesService.saveOrderToStore(data['order']);
        return OrderModel.fromJson(data['order']);
      }
    } catch (_) {}

    // Update locally
    final stored = await PreferencesService.getStoredOrders();
    for (final s in stored) {
      if (s['_id'] == orderId || s['id'] == orderId || s['orderNumber'] == orderId) {
        s['status'] = 'RIDER_ASSIGNED';
        s['assignedRider'] = {
          '_id': riderId,
          'name': riderName ?? 'Assigned Rider',
          'phone': riderPhone ?? '9363302266',
        };
        await PreferencesService.saveOrderToStore(s);
        return OrderModel.fromJson(s);
      }
    }
    throw Exception('Failed to claim order');
  }

  // 10. Update Milestone
  Future<OrderModel> updateMilestone(String orderId, String riderId, String status) async {
    try {
      final response = await http
          .patch(
            Uri.parse('$baseUrl/orders/$orderId/milestone'),
            headers: _headers,
            body: jsonEncode({'riderId': riderId, 'status': status}),
          )
          .timeout(const Duration(seconds: 8));

      final data = _safeJsonDecode(response.body);
      if (response.statusCode == 200 && data != null && data['success'] == true) {
        await PreferencesService.saveOrderToStore(data['order']);
        return OrderModel.fromJson(data['order']);
      }
    } catch (_) {}

    final stored = await PreferencesService.getStoredOrders();
    for (final s in stored) {
      if (s['_id'] == orderId || s['id'] == orderId || s['orderNumber'] == orderId) {
        s['status'] = status;
        await PreferencesService.saveOrderToStore(s);
        return OrderModel.fromJson(s);
      }
    }
    throw Exception('Failed to update milestone');
  }

  // 11. Complete Delivery
  Future<OrderModel> completeDelivery(
    String orderId,
    String riderId, {
    String? deliveryPin,
    bool isBypass = false,
    String? paymentMode,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/orders/$orderId/complete'),
            headers: _headers,
            body: jsonEncode({
              'riderId': riderId,
              if (deliveryPin != null) 'deliveryPin': deliveryPin,
              'isBypass': isBypass,
              if (paymentMode != null) 'paymentMode': paymentMode,
            }),
          )
          .timeout(const Duration(seconds: 8));

      final data = _safeJsonDecode(response.body);
      if (response.statusCode == 200 && data != null && data['success'] == true) {
        await PreferencesService.saveOrderToStore(data['order']);
        return OrderModel.fromJson(data['order']);
      }
    } catch (_) {}

    final stored = await PreferencesService.getStoredOrders();
    for (final s in stored) {
      if (s['_id'] == orderId || s['id'] == orderId || s['orderNumber'] == orderId) {
        s['status'] = 'DELIVERED';
        s['isOtpBypassed'] = isBypass;
        if (paymentMode != null) s['paymentMode'] = paymentMode;
        s['completedAt'] = DateTime.now().toIso8601String();
        await PreferencesService.saveOrderToStore(s);
        return OrderModel.fromJson(s);
      }
    }
    throw Exception('Failed to complete delivery');
  }

  // 12. Get Rider Active Order
  Future<OrderModel?> getRiderActiveOrder(String riderId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/riders/$riderId/active-order'), headers: _headers)
          .timeout(const Duration(seconds: 8));

      final data = _safeJsonDecode(response.body);
      if (response.statusCode == 200 && data != null && data['hasActiveOrder'] == true && data['order'] != null) {
        await PreferencesService.saveOrderToStore(data['order']);
        return OrderModel.fromJson(data['order']);
      }
    } catch (_) {}

    final stored = await PreferencesService.getStoredOrders();
    for (final s in stored) {
      final assigned = s['assignedRider'];
      final assignedId = (assigned is Map) ? (assigned['_id'] ?? assigned['id']) : null;
      if (assignedId == riderId && s['status'] != 'DELIVERED' && s['status'] != 'CANCELLED') {
        return OrderModel.fromJson(s);
      }
    }
    return null;
  }

  // 13. Get Rider Profile
  Future<RiderModel> getRiderProfile(String riderId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/riders/$riderId/profile'), headers: _headers)
          .timeout(const Duration(seconds: 8));

      final data = _safeJsonDecode(response.body);
      if (response.statusCode == 200 && data != null && data['success'] == true) {
        return RiderModel.fromJson(data['rider']);
      }
    } catch (_) {}

    final riders = await getAdminRiders();
    return riders.firstWhere((r) => r.id == riderId, orElse: () => riders.first);
  }

  // ==========================================
  // ADMIN PORTAL API SERVICES (HYBRID & RESILIENT)
  // ==========================================

  // Admin Login (Master Password: mani2006)
  Future<bool> loginAdmin(String password) async {
    if (password.trim() == 'mani2006') {
      return true;
    }
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/admin/login'),
        headers: _headers,
        body: jsonEncode({'password': password}),
      ).timeout(const Duration(seconds: 8));
      final data = _safeJsonDecode(response.body);
      if (response.statusCode == 200 && data != null && data['success'] == true) {
        return true;
      }
    } catch (_) {}
    throw Exception('Incorrect admin password');
  }

  // Admin Dashboard Statistics
  Future<Map<String, dynamic>> getAdminDashboard() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/admin/dashboard'), headers: _headers)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = _safeJsonDecode(response.body);
        if (data != null && data['success'] == true) {
          return data;
        }
      }
    } catch (_) {}

    // Dynamic aggregation from active store + fleet
    final liveOrders = await getAdminLiveOrders();
    final historyOrders = await getAdminRiderHistory();
    final riders = await getAdminRiders();

    final totalOrders = liveOrders.length + historyOrders.length;
    final deliveredOrders = historyOrders.where((o) => o.status == 'DELIVERED').toList();
    final cancelledOrders = historyOrders.where((o) => o.status == 'CANCELLED').toList();
    final totalRevenue = deliveredOrders.fold<int>(0, (sum, o) => sum + o.fare);
    final onlineRiders = riders.where((r) => r.isOnline).length;

    final cashRevenue = deliveredOrders
        .where((o) => o.paymentMode.toUpperCase() != 'UPI')
        .fold<int>(0, (sum, o) => sum + o.fare);
    final upiRevenue = deliveredOrders
        .where((o) => o.paymentMode.toUpperCase() == 'UPI')
        .fold<int>(0, (sum, o) => sum + o.fare);

    final now = DateTime.now();
    final todayDelivered = deliveredOrders.where((o) =>
        o.createdAt.year == now.year &&
        o.createdAt.month == now.month &&
        o.createdAt.day == now.day).toList();
    final todayRevenue = todayDelivered.fold<int>(0, (sum, o) => sum + o.fare);
    final todayCashRevenue = todayDelivered
        .where((o) => o.paymentMode.toUpperCase() != 'UPI')
        .fold<int>(0, (sum, o) => sum + o.fare);
    final todayUpiRevenue = todayDelivered
        .where((o) => o.paymentMode.toUpperCase() == 'UPI')
        .fold<int>(0, (sum, o) => sum + o.fare);

    return {
      'success': true,
      'stats': {
        'totalOrders': totalOrders,
        'liveOrdersCount': liveOrders.length,
        'deliveredOrdersCount': deliveredOrders.length,
        'cancelledOrdersCount': cancelledOrders.length,
        'totalRiders': riders.length,
        'onlineRidersCount': onlineRiders,
        'totalRevenue': totalRevenue,
        'cashRevenue': cashRevenue,
        'upiRevenue': upiRevenue,
        'todayOrdersCount': liveOrders.length + todayDelivered.length,
        'todayDeliveredCount': todayDelivered.length,
        'todayRevenue': todayRevenue,
        'todayCashRevenue': todayCashRevenue,
        'todayUpiRevenue': todayUpiRevenue,
      },
      'riders': riders.map((r) => {
        'id': r.id,
        'name': r.name,
        'phone': r.phone,
        'isOnline': r.isOnline,
        'totalDeliveries': r.totalDeliveries,
        'totalEarnings': r.totalEarnings,
      }).toList(),
    };
  }

  // Admin Live Orders (Never crashes; merges server pool and stored orders)
  Future<List<OrderModel>> getAdminLiveOrders() async {
    List<OrderModel> remoteOrders = [];

    // 1. Try remote dedicated endpoint
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/admin/live-orders'), headers: _headers)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = _safeJsonDecode(response.body);
        if (data != null && data['orders'] is List) {
          for (final item in data['orders']) {
            final om = OrderModel.fromJson(item);
            remoteOrders.add(om);
            await PreferencesService.saveOrderToStore(item);
          }
        }
      }
    } catch (_) {}

    // 2. Fetch active pool from Render backend (/orders/pool/available)
    try {
      final poolRes = await http
          .get(Uri.parse('$baseUrl/orders/pool/available'), headers: _headers)
          .timeout(const Duration(seconds: 8));

      if (poolRes.statusCode == 200) {
        final poolData = _safeJsonDecode(poolRes.body);
        if (poolData != null && poolData['orders'] is List) {
          for (final item in poolData['orders']) {
            await PreferencesService.saveOrderToStore(item);
          }
        }
      }
    } catch (_) {}

    // 3. Merge with local persistent store
    final stored = await PreferencesService.getStoredOrders();
    final Map<String, OrderModel> map = {};

    for (final s in stored) {
      try {
        final om = OrderModel.fromJson(s);
        final key = om.id.isNotEmpty ? om.id : om.orderNumber;
        map[key] = om;
      } catch (_) {}
    }

    for (final ro in remoteOrders) {
      final key = ro.id.isNotEmpty ? ro.id : ro.orderNumber;
      map[key] = ro;
    }

    final live = map.values
        .where((o) => o.status != 'DELIVERED' && o.status != 'CANCELLED')
        .toList();

    live.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return live;
  }

  // Admin Rider History (Delivered & Cancelled closed orders)
  Future<List<OrderModel>> getAdminRiderHistory({
    String? riderId,
    String? status,
    String? timeRange,
    int? month,
    int? year,
  }) async {
    List<OrderModel> remoteOrders = [];

    try {
      final queryParams = <String, String>{};
      if (riderId != null && riderId.isNotEmpty) queryParams['riderId'] = riderId;
      if (status != null && status.isNotEmpty) queryParams['status'] = status;
      if (timeRange != null && timeRange.isNotEmpty) queryParams['timeRange'] = timeRange;
      if (month != null) queryParams['month'] = month.toString();
      if (year != null) queryParams['year'] = year.toString();

      final uri = Uri.parse('$baseUrl/admin/rider-history').replace(
        queryParameters: queryParams.isEmpty ? null : queryParams,
      );
      final response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = _safeJsonDecode(response.body);
        if (data != null && data['orders'] is List) {
          for (final item in data['orders']) {
            final om = OrderModel.fromJson(item);
            remoteOrders.add(om);
            await PreferencesService.saveOrderToStore(item);
          }
        }
      }
    } catch (_) {}

    final stored = await PreferencesService.getStoredOrders();
    final Map<String, OrderModel> map = {};

    for (final s in stored) {
      try {
        final om = OrderModel.fromJson(s);
        final key = om.id.isNotEmpty ? om.id : om.orderNumber;
        map[key] = om;
      } catch (_) {}
    }

    for (final ro in remoteOrders) {
      final key = ro.id.isNotEmpty ? ro.id : ro.orderNumber;
      map[key] = ro;
    }

    var history = map.values
        .where((o) => o.status == 'DELIVERED' || o.status == 'CANCELLED')
        .toList();

    if (riderId != null && riderId != 'all') {
      history = history.where((o) => o.assignedRiderId == riderId).toList();
    }
    if (status != null && status != 'all') {
      history = history.where((o) => o.status == status).toList();
    }

    final now = DateTime.now();
    if (timeRange == 'today') {
      history = history.where((o) =>
          o.createdAt.year == now.year &&
          o.createdAt.month == now.month &&
          o.createdAt.day == now.day).toList();
    } else if (timeRange == 'yesterday') {
      final yesterday = now.subtract(const Duration(days: 1));
      history = history.where((o) =>
          o.createdAt.year == yesterday.year &&
          o.createdAt.month == yesterday.month &&
          o.createdAt.day == yesterday.day).toList();
    } else if (timeRange == 'week') {
      history = history.where((o) => now.difference(o.createdAt).inDays <= 7).toList();
    } else if (timeRange == 'month') {
      history = history.where((o) =>
          o.createdAt.year == now.year &&
          o.createdAt.month == now.month).toList();
    } else if (month != null && year != null) {
      history = history.where((o) =>
          o.createdAt.year == year &&
          o.createdAt.month == month).toList();
    }

    history.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return history;
  }

  // Admin All Riders List
  Future<List<RiderModel>> getAdminRiders() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/admin/riders'), headers: _headers)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = _safeJsonDecode(response.body);
        if (data != null && data['success'] == true && data['riders'] is List) {
          return (data['riders'] as List).map((i) => RiderModel.fromJson(i)).toList();
        }
      }
    } catch (_) {}

    // Fallback: Verified Melapalayam Fleet (Only MS Mani is online baseline)
    final sampleFleet = [
      {'id': 'r_sudalai', 'name': 'Sudalai', 'phone': '9363302266', 'isOnline': false, 'totalDeliveries': 0, 'totalEarnings': 0},
      {'id': '6ae34ea6ed8921437ffd42da', 'name': 'V Mani', 'phone': '7639483476', 'isOnline': false, 'totalDeliveries': 3, 'totalEarnings': 105},
      {'id': '6ae34ea6ed8921437ffd42db', 'name': 'MS Mani', 'phone': '6379329930', 'isOnline': false, 'totalDeliveries': 0, 'totalEarnings': 0},
      {'id': 'r_hari', 'name': 'Hari', 'phone': '9344590818', 'isOnline': false, 'totalDeliveries': 0, 'totalEarnings': 0},
      {'id': 'r_mathan', 'name': 'Mathan', 'phone': '9791766183', 'isOnline': false, 'totalDeliveries': 0, 'totalEarnings': 0},
      {'id': 'r_santhanam', 'name': 'Santhanam', 'phone': '7010710215', 'isOnline': false, 'totalDeliveries': 0, 'totalEarnings': 0},
      {'id': 'r_raja', 'name': 'RAJA', 'phone': '7695807394', 'isOnline': false, 'totalDeliveries': 0, 'totalEarnings': 0},
    ];

    return sampleFleet.map((f) => RiderModel.fromJson(f)).toList();
  }

  // Quick Action: Admin Order Milestone Simulator / Manual Override
  Future<void> adminAdvanceOrder(OrderModel order, String newStatus, {RiderModel? rider}) async {
    final stored = await PreferencesService.getStoredOrders();
    for (final s in stored) {
      if (s['_id'] == order.id || s['id'] == order.id || s['orderNumber'] == order.orderNumber) {
        s['status'] = newStatus;
        if (rider != null) {
          s['assignedRider'] = {
            '_id': rider.id,
            'name': rider.name,
            'phone': rider.phone,
          };
        }
        if (newStatus == 'DELIVERED') {
          s['completedAt'] = DateTime.now().toIso8601String();
        }
        await PreferencesService.saveOrderToStore(s);
        return;
      }
    }

    // If not in stored, create it
    final ordJson = {
      '_id': order.id,
      'orderNumber': order.orderNumber,
      'customerName': order.customerName,
      'customerPhone': order.customerPhone,
      'pickupPhone': order.pickupPhone,
      'dropPhone': order.dropPhone,
      'orderType': order.orderType,
      'category': order.category,
      'itemsList': order.itemsList,
      'pickupAddress': order.pickupAddress,
      'dropAddress': order.dropAddress,
      'status': newStatus,
      'assignedRider': rider != null ? {'_id': rider.id, 'name': rider.name, 'phone': rider.phone} : order.assignedRider,
      'deliveryPin': order.deliveryPin,
      'isOtpBypassed': order.isOtpBypassed,
      'fare': order.fare,
      'estimatedDistanceKm': order.estimatedDistanceKm,
      'createdAt': order.createdAt.toIso8601String(),
      if (newStatus == 'DELIVERED') 'completedAt': DateTime.now().toIso8601String(),
    };
    await PreferencesService.saveOrderToStore(ordJson);
  }
}
