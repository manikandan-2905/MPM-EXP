import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../models/order_model.dart';
import '../models/rider_model.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final String baseUrl = AppConstants.apiBaseUrl;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  // 1. Live Active Riders Count (for Customer Top Bar)
  Future<int> getActiveRidersCount() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/riders/active-count'), headers: _headers)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['activeRidersCount'] ?? 0;
      }
      return 0;
    } catch (e) {
      // Graceful fallback during offline or network lag
      return 0;
    }
  }

  // 2. Create Order (Guest Customer)
  Future<Map<String, dynamic>> createOrder(Map<String, dynamic> payload) async {
    final response = await http.post(
      Uri.parse('$baseUrl/orders'),
      headers: _headers,
      body: jsonEncode(payload),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 201 && data['success'] == true) {
      return {
        'order': OrderModel.fromJson(data['order']),
        'whatsappTicket': data['whatsappTicket'] as String,
      };
    } else {
      throw Exception(data['message'] ?? 'Failed to place order');
    }
  }

  // 3. Get Order by ID
  Future<OrderModel> getOrderById(String orderId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/orders/$orderId'),
      headers: _headers,
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return OrderModel.fromJson(data['order']);
    } else {
      throw Exception(data['message'] ?? 'Order not found');
    }
  }

  // 4. Get Customer Orders History
  Future<List<OrderModel>> getCustomerOrders(String phone) async {
    final response = await http.get(
      Uri.parse('$baseUrl/orders/customer/$phone'),
      headers: _headers,
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      final list = (data['orders'] as List)
          .map((item) => OrderModel.fromJson(item))
          .toList();
      return list;
    }
    return [];
  }

  // 4b. Get Ongoing Active Order for Customer Phone
  Future<OrderModel?> getCustomerActiveOrder(String phone) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/orders/customer/$phone/active'),
        headers: _headers,
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['hasActiveOrder'] == true && data['order'] != null) {
        return OrderModel.fromJson(data['order']);
      }
    } catch (_) {}

    // Fallback: check customer orders history for any active order
    try {
      final list = await getCustomerOrders(phone);
      for (final o in list) {
        if (!o.isDelivered && !o.isCancelled) {
          return o;
        }
      }
    } catch (_) {}

    return null;
  }

  // 5. Cancel Order (Subject to locked cancellation rules)
  Future<void> cancelOrder(String orderId, {String reason = 'Customer requested'}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/orders/$orderId/cancel'),
      headers: _headers,
      body: jsonEncode({'reason': reason}),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 200 || data['success'] != true) {
      throw Exception(data['message'] ?? 'Cancellation failed');
    }
  }

  // 6. Rider Login (Pre-seeded phone check)
  Future<RiderModel> loginRider(String phone, {String? fcmToken}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/riders/login'),
      headers: _headers,
      body: jsonEncode({'phone': phone, 'fcmToken': fcmToken}),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return RiderModel.fromJson(data['rider']);
    } else {
      throw Exception(data['message'] ?? 'Rider authentication failed');
    }
  }

  // 7. Toggle Rider Online/Offline
  Future<bool> toggleOnlineStatus(String riderId, bool isOnline) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/riders/$riderId/online-status'),
      headers: _headers,
      body: jsonEncode({'isOnline': isOnline}),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return data['isOnline'] as bool;
    } else {
      throw Exception(data['message'] ?? 'Failed to update online status');
    }
  }

  // 8. Rider Pool: Get Available Unclaimed Orders
  Future<List<OrderModel>> getAvailableOrders() async {
    final response = await http.get(
      Uri.parse('$baseUrl/orders/pool/available'),
      headers: _headers,
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      final list = (data['orders'] as List)
          .map((item) => OrderModel.fromJson(item))
          .toList();
      return list;
    }
    return [];
  }

  // 9. Atomic Order Lock: Claim Order
  Future<OrderModel> claimOrder(String orderId, String riderId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/orders/$orderId/claim'),
      headers: _headers,
      body: jsonEncode({'riderId': riderId}),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return OrderModel.fromJson(data['order']);
    } else if (response.statusCode == 409) {
      throw Exception('Too late! This order was just claimed by another rider.');
    } else {
      throw Exception(data['message'] ?? 'Failed to claim order');
    }
  }

  // 10. Update Milestone Status ('ITEM_PURCHASED' | 'ON_THE_WAY')
  Future<OrderModel> updateMilestone(String orderId, String riderId, String status) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/orders/$orderId/milestone'),
      headers: _headers,
      body: jsonEncode({'riderId': riderId, 'status': status}),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return OrderModel.fromJson(data['order']);
    } else {
      throw Exception(data['message'] ?? 'Failed to update milestone');
    }
  }

  // 11. Complete Delivery (with 4-digit PIN verification or Emergency Bypass)
  Future<OrderModel> completeDelivery(
    String orderId,
    String riderId, {
    String? deliveryPin,
    bool isBypass = false,
    String paymentMode = 'Cash',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/orders/$orderId/complete'),
      headers: _headers,
      body: jsonEncode({
        'riderId': riderId,
        'deliveryPin': deliveryPin,
        'isBypass': isBypass,
        'paymentMode': paymentMode,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return OrderModel.fromJson(data['order']);
    } else {
      throw Exception(data['message'] ?? 'Verification failed. Please check 4-digit PIN.');
    }
  }

  // 12. Get Rider Active Order
  Future<OrderModel?> getRiderActiveOrder(String riderId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/riders/$riderId/active-order'),
      headers: _headers,
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['hasActiveOrder'] == true && data['order'] != null) {
      return OrderModel.fromJson(data['order']);
    }
    return null;
  }

  // 13. Get Rider Profile / Stats
  Future<RiderModel> getRiderProfile(String riderId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/riders/$riderId/profile'),
      headers: _headers,
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      return RiderModel.fromJson(data['rider']);
    } else {
      throw Exception(data['message'] ?? 'Failed to load profile');
    }
  }
}
