import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/constants.dart';
import '../../models/order_model.dart';
import '../../models/rider_model.dart';
import '../../services/api_service.dart';
import '../../services/preferences_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/legal_warning_banner.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({Key? key}) : super(key: key);

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  final ApiService _apiService = ApiService();

  // Top App Perspective Switcher ('customer' | 'rider' | 'inspector')
  String _currentViewMode = 'customer';

  // Customer Form State
  String _activeTab = 'pickup'; // 'pickup' | 'buy'
  int _activeRidersCount = 3;
  bool _isLoadingRiders = false;
  Timer? _pollingTimer;

  // Contact Inputs (Stored Locally)
  final TextEditingController _primaryPhoneCtrl = TextEditingController(text: '9876543210');
  final TextEditingController _pickupPhoneCtrl = TextEditingController();
  final TextEditingController _dropPhoneCtrl = TextEditingController();

  // Pickup & Drop Inputs
  final TextEditingController _pickupAddressCtrl =
      TextEditingController(text: 'Periya Theru, Near Big Mosque, Melapalayam');
  final TextEditingController _dropAddressCtrl =
      TextEditingController(text: 'Melapalayam Bazaar Market');

  // Buy For Me Inputs
  final TextEditingController _buyShopCtrl =
      TextEditingController(text: 'Bazaar Mutton Stall, Periya Theru');
  final TextEditingController _buyListCtrl = TextEditingController(
      text: '1) 1/2 Kg Fresh Mutton (Leg piece curry cut)\n2) 2 Lemons');
  final TextEditingController _buyDropCtrl =
      TextEditingController(text: 'Hameempuram 4th Street, Melapalayam');

  // Custom Item Input
  final TextEditingController _customItemCtrl = TextEditingController();

  String _selectedCategory = 'Meat';
  String _selectedCategoryLabel = '🥩 Fresh Meat';
  bool _isSenderMe = true;
  bool _isReceiverMe = false;
  bool _isUrgent = false;
  bool _isPlacingOrder = false;

  // Active Order (for live tracking modal)
  OrderModel? _activeOrder;
  bool _showTrackingModal = false;
  bool _showNotificationDrawer = false;

  // WhatsApp Share Dialog
  String? _pendingWhatsAppText;

  // Rider View State
  bool _isRiderLoggedIn = false;
  RiderModel? _loggedInRider;
  final TextEditingController _riderLoginPhoneCtrl = TextEditingController(text: '9363302266');
  bool _isRiderOnline = true;
  bool _isRiderLoading = false;
  List<OrderModel> _riderPoolOrders = [];
  OrderModel? _riderActiveTrip;
  final TextEditingController _riderOtpCtrl = TextEditingController();
  String _riderTab = 'active'; // 'active' | 'completed'
  String _closingPaymentMode = 'Cash'; // 'Cash' | 'UPI'
  List<Map<String, dynamic>> _riderCompletedTrips = [];


  @override
  void initState() {
    super.initState();
    _loadStoredPreferences();
    _fetchLiveActiveRiders();

    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _fetchLiveActiveRiders();
      if (_currentViewMode == 'rider' && _isRiderLoggedIn) {
        if (_isRiderOnline) _fetchRiderPool();
        if (_riderActiveTrip != null) _refreshRiderActiveTrip();
      }
      if (_activeOrder != null && _showTrackingModal) {
        _refreshActiveOrder();
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _primaryPhoneCtrl.dispose();
    _pickupPhoneCtrl.dispose();
    _dropPhoneCtrl.dispose();
    _pickupAddressCtrl.dispose();
    _dropAddressCtrl.dispose();
    _buyShopCtrl.dispose();
    _buyListCtrl.dispose();
    _buyDropCtrl.dispose();
    _customItemCtrl.dispose();
    _riderLoginPhoneCtrl.dispose();
    _riderOtpCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStoredPreferences() async {
    final profile = await PreferencesService.getCustomerProfile();
    if (profile['phone'] != null && profile['phone']!.isNotEmpty) {
      _primaryPhoneCtrl.text = profile['phone']!;
    }
    _syncPhoneCheckboxes();

    final riderSession = await PreferencesService.getRiderSession();
    if (riderSession['id'] != null && riderSession['id']!.isNotEmpty) {
      try {
        final rider = await _apiService.getRiderProfile(riderSession['id']!);
        setState(() {
          _loggedInRider = rider;
          _isRiderLoggedIn = true;
          _isRiderOnline = rider.isOnline;
        });
      } catch (_) {}
    }

    final savedTrips = await PreferencesService.getRiderCompletedTrips();
    if (savedTrips.isNotEmpty) {
      try {
        setState(() {
          _riderCompletedTrips = savedTrips
              .map((str) => jsonDecode(str) as Map<String, dynamic>)
              .toList();
        });
      } catch (_) {}
    } else {
      final sampleTrips = [
        {
          'orderNumber': 'MPM-261028-4102',
          'items': '1/2 Kg Fresh Mutton (Leg piece curry cut)',
          'pickup': 'Bazaar Mutton Stall, Periya Theru',
          'drop': 'Hameempuram 4th Street, Melapalayam',
          'fare': 45,
          'paymentMode': 'Cash',
          'completedAt': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
        },
        {
          'orderNumber': 'MPM-261027-1892',
          'items': 'Medicines & Documents envelope',
          'pickup': 'Kurichi Medicals, Main Road',
          'drop': 'Al Ameen School Road, Melapalayam',
          'fare': 30,
          'paymentMode': 'UPI',
          'completedAt': DateTime.now().subtract(const Duration(days: 1, hours: 3)).toIso8601String(),
        },
      ];
      setState(() {
        _riderCompletedTrips = sampleTrips;
      });
      for (final t in sampleTrips) {
        PreferencesService.saveRiderCompletedTrip(jsonEncode(t));
      }
    }

    // Recover Customer and Rider active orders on launch
    await _recoverCustomerActiveOrder();
    if (_loggedInRider != null) {
      await _recoverRiderActiveTrip();
    }
  }

  // Active Order Persistence & Recovery
  Future<void> _recoverCustomerActiveOrder() async {
    try {
      final cachedOrderId = await PreferencesService.getCustomerActiveOrderId();
      if (cachedOrderId != null && cachedOrderId.isNotEmpty) {
        final order = await _apiService.getOrderById(cachedOrderId);
        if (!order.isDelivered && !order.isCancelled) {
          if (mounted) {
            setState(() {
              _activeOrder = order;
              _showTrackingModal = true;
            });
          }
          return;
        } else {
          await PreferencesService.clearCustomerActiveOrderId();
        }
      }

      final phone = _primaryPhoneCtrl.text.trim();
      if (phone.isNotEmpty) {
        final activeOrder = await _apiService.getCustomerActiveOrder(phone);
        if (activeOrder != null && !activeOrder.isDelivered && !activeOrder.isCancelled) {
          await PreferencesService.saveCustomerActiveOrderId(activeOrder.id);
          if (mounted) {
            setState(() {
              _activeOrder = activeOrder;
              _showTrackingModal = true;
            });
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _recoverRiderActiveTrip() async {
    if (_loggedInRider == null) return;
    try {
      final activeTrip = await _apiService.getRiderActiveOrder(_loggedInRider!.id);
      if (activeTrip != null && !activeTrip.isDelivered && !activeTrip.isCancelled) {
        await PreferencesService.saveRiderActiveOrderId(activeTrip.id);
        if (mounted) {
          setState(() {
            _riderActiveTrip = activeTrip;
            _currentViewMode = 'rider';
            _riderTab = 'active';
          });
        }
        return;
      }

      final cachedId = await PreferencesService.getRiderActiveOrderId();
      if (cachedId != null && cachedId.isNotEmpty) {
        final order = await _apiService.getOrderById(cachedId);
        if (!order.isDelivered && !order.isCancelled && order.assignedRiderId == _loggedInRider!.id) {
          if (mounted) {
            setState(() {
              _riderActiveTrip = order;
              _currentViewMode = 'rider';
              _riderTab = 'active';
            });
          }
          return;
        }
      }

      await PreferencesService.clearRiderActiveOrderId();
    } catch (_) {}
  }

  Future<void> _refreshRiderActiveTrip() async {
    if (_riderActiveTrip == null || _loggedInRider == null) return;
    try {
      final updated = await _apiService.getOrderById(_riderActiveTrip!.id);
      if (mounted) {
        if (updated.isDelivered || updated.isCancelled) {
          await PreferencesService.clearRiderActiveOrderId();
          setState(() => _riderActiveTrip = null);
        } else {
          setState(() => _riderActiveTrip = updated);
        }
      }
    } catch (_) {}
  }

  void _syncPhoneCheckboxes() {
    final pPhone = _primaryPhoneCtrl.text.trim();
    if (_isSenderMe) _pickupPhoneCtrl.text = pPhone;
    if (_isReceiverMe) _dropPhoneCtrl.text = pPhone;
  }

  Future<void> _fetchLiveActiveRiders() async {
    try {
      final count = await _apiService.getActiveRidersCount();
      if (mounted) {
        setState(() => _activeRidersCount = count);
      }
    } catch (_) {}
  }

  bool get _isCrossZone {
    final drop = (_activeTab == 'pickup' ? _dropAddressCtrl.text : _buyDropCtrl.text).toLowerCase();
    return drop.contains('palayamkottai') ||
        drop.contains('junction') ||
        drop.contains('high ground');
  }

  int _calculateFare() {
    int fare = AppConstants.baseFare; // ₹30
    if (_isCrossZone) fare += 20; // +₹20 Cross-Zone Surcharge
    if (_isUrgent) fare += AppConstants.urgentSurcharge; // +₹15
    return fare;
  }

  Future<void> _detectCurrentGPS(String target) async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final gpsText = 'GPS Pin (${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}), Melapalayam';

      setState(() {
        if (target == 'pickup') {
          _pickupAddressCtrl.text = gpsText;
        } else if (target == 'drop') {
          _dropAddressCtrl.text = gpsText;
        } else if (target == 'buyDrop') {
          _buyDropCtrl.text = gpsText;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GPS Location captured!'), backgroundColor: Color(0xFF059669)),
      );
    } catch (e) {
      // Fallback sample locations from prototype
      final samples = [
        "Near Big Mosque, Melapalayam (GPS 8.7042, 77.7285)",
        "Periya Theru Corner, Bazaar (GPS 8.7051, 77.7301)",
        "Al Ameen School Road, Kurichi (GPS 8.7020, 77.7265)"
      ];
      samples.shuffle();
      final randomLoc = samples.first;
      setState(() {
        if (target == 'pickup') {
          _pickupAddressCtrl.text = randomLoc;
        } else if (target == 'drop') {
          _dropAddressCtrl.text = randomLoc;
        } else if (target == 'buyDrop') {
          _buyDropCtrl.text = randomLoc;
        }
      });
    }
  }

  Future<void> _placeCustomerOrder() async {
    final phone = _primaryPhoneCtrl.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter primary contact number')),
      );
      return;
    }

    setState(() => _isPlacingOrder = true);

    try {
      String? token;
      try {
        token = await NotificationService().getCachedOrFreshToken();
      } catch (_) {
        token = null;
      }

      final isBuy = _activeTab == 'buy';
      final itemDesc = isBuy
          ? (_buyListCtrl.text.trim().isNotEmpty
              ? _buyListCtrl.text.trim().split('\n').first
              : 'Market Items')
          : (_selectedCategory == 'Custom'
              ? _customItemCtrl.text.trim()
              : _selectedCategoryLabel);

      final pickupLoc = isBuy
          ? (_buyShopCtrl.text.trim().isNotEmpty ? _buyShopCtrl.text.trim() : 'Bazaar Stall, Melapalayam')
          : _pickupAddressCtrl.text.trim();

      final dropLoc = isBuy ? _buyDropCtrl.text.trim() : _dropAddressCtrl.text.trim();
      final fare = _calculateFare();

      final payload = {
        'customerName': 'Customer ($phone)',
        'customerPhone': phone,
        'pickupPhone': _pickupPhoneCtrl.text.trim().isNotEmpty ? _pickupPhoneCtrl.text.trim() : phone,
        'dropPhone': _dropPhoneCtrl.text.trim().isNotEmpty ? _dropPhoneCtrl.text.trim() : phone,
        'orderType': isBuy ? 'BUY_FOR_ME' : 'PICKUP_DROP',
        'category': _selectedCategory,
        'itemsList': [itemDesc],
        'shopName': isBuy ? pickupLoc : '',
        'isUrgent': _isUrgent,
        'pickupAddress': pickupLoc,
        'dropAddress': dropLoc,
        'estimatedDistanceKm': _isCrossZone ? 4.8 : 1.8,
        'customerFcmToken': token,
        'calculatedFare': fare,
      };

      final result = await _apiService.createOrder(payload);
      final order = result['order'] as OrderModel;

      await PreferencesService.saveCustomerProfile('Customer', phone);
      await PreferencesService.saveCustomerActiveOrderId(order.id);

      setState(() {
        _activeOrder = order;
        _isPlacingOrder = false;
        _showTrackingModal = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order placed successfully! Broadcasted to Melapalayam rider pool 🛵'),
          backgroundColor: Color(0xFF059669),
        ),
      );
    } catch (e) {
      setState(() => _isPlacingOrder = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order placement failed: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _refreshActiveOrder() async {
    if (_activeOrder == null) return;
    try {
      final updated = await _apiService.getOrderById(_activeOrder!.id);
      if (mounted) {
        setState(() => _activeOrder = updated);
        if (updated.isDelivered || updated.isCancelled) {
          await PreferencesService.clearCustomerActiveOrderId();
        }
      }
    } catch (_) {}
  }

  Future<void> _handleCustomerCancel() async {
    if (_activeOrder == null) return;
    if (!_activeOrder!.canCancel) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot cancel: Rider has already purchased the item.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    try {
      await _apiService.cancelOrder(_activeOrder!.id);
      await PreferencesService.clearCustomerActiveOrderId();
      await _refreshActiveOrder();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order cancelled successfully.'), backgroundColor: Color(0xFF059669)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cancellation error: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  // --- RIDER ACTIONS ---

  Future<void> _loginRider() async {
    final phone = _riderLoginPhoneCtrl.text.trim();
    if (phone.isEmpty) return;

    setState(() => _isRiderLoading = true);
    try {
      final token = await NotificationService().getCachedOrFreshToken();
      final rider = await _apiService.loginRider(phone, fcmToken: token);

      await PreferencesService.saveRiderSession(id: rider.id, name: rider.name, phone: rider.phone);

      setState(() {
        _loggedInRider = rider;
        _isRiderLoggedIn = true;
        _isRiderOnline = rider.isOnline;
        _isRiderLoading = false;
      });

      _fetchRiderPool();
      await _recoverRiderActiveTrip();
    } catch (e) {
      setState(() => _isRiderLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _toggleRiderOnline(bool val) async {
    if (_loggedInRider == null) return;
    try {
      final isOnline = await _apiService.toggleOnlineStatus(_loggedInRider!.id, val);
      setState(() => _isRiderOnline = isOnline);
      if (isOnline) _fetchRiderPool();
      _fetchLiveActiveRiders();
    } catch (_) {}
  }

  Future<void> _fetchRiderPool() async {
    try {
      final pool = await _apiService.getAvailableOrders();
      if (mounted) setState(() => _riderPoolOrders = pool);
    } catch (_) {}
  }

  Future<void> _fetchRiderActiveOrder() async {
    await _recoverRiderActiveTrip();
  }

  Future<void> _atomicClaimOrder(OrderModel order) async {
    if (_loggedInRider == null) return;
    try {
      final claimed = await _apiService.claimOrder(order.id, _loggedInRider!.id);
      await PreferencesService.saveRiderActiveOrderId(claimed.id);
      setState(() {
        _riderActiveTrip = claimed;
        _riderTab = 'active';
        _riderPoolOrders.removeWhere((o) => o.id == order.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order locked and claimed! 🛵'), backgroundColor: Color(0xFF059669)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
      );
      _fetchRiderPool();
    }
  }

  Future<void> _riderUpdateMilestone(String status) async {
    if (_riderActiveTrip == null || _loggedInRider == null) return;
    try {
      final updated = await _apiService.updateMilestone(_riderActiveTrip!.id, _loggedInRider!.id, status);
      setState(() => _riderActiveTrip = updated);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _riderVerifyPin({bool isBypass = false}) async {
    if (_riderActiveTrip == null || _loggedInRider == null) return;
    final pin = _riderOtpCtrl.text.trim();

    if (!isBypass && pin.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter 4-digit Delivery PIN')),
      );
      return;
    }

    try {
      await _apiService.completeDelivery(
        _riderActiveTrip!.id,
        _loggedInRider!.id,
        deliveryPin: pin,
        isBypass: isBypass,
        paymentMode: _closingPaymentMode,
      );

      await PreferencesService.clearRiderActiveOrderId();

      final completedMap = {
        'orderNumber': _riderActiveTrip!.orderNumber,
        'items': _riderActiveTrip!.itemsList.join(', '),
        'pickup': _riderActiveTrip!.pickupAddress,
        'drop': _riderActiveTrip!.dropAddress,
        'fare': _riderActiveTrip!.fare,
        'paymentMode': _closingPaymentMode,
        'completedAt': DateTime.now().toIso8601String(),
      };

      await PreferencesService.saveRiderCompletedTrip(jsonEncode(completedMap));

      setState(() {
        _riderCompletedTrips.insert(0, completedMap);
        _riderActiveTrip = null;
        _riderOtpCtrl.clear();
      });

      // Reload rider stats
      _apiService.getRiderProfile(_loggedInRider!.id).then((r) {
        if (mounted) setState(() => _loggedInRider = r);
      }).catchError((_) {});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order closed! ₹${completedMap['fare']} collected via $_closingPaymentMode 🎉'),
          backgroundColor: const Color(0xFF059669),
        ),
      );
      _fetchRiderPool();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PIN Verification Failed: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _logoutRider() async {
    await PreferencesService.clearRiderSession();
    await PreferencesService.clearRiderActiveOrderId();
    setState(() {
      _isRiderLoggedIn = false;
      _loggedInRider = null;
      _riderActiveTrip = null;
      _currentViewMode = 'customer';
    });
  }

  Map<String, List<Map<String, dynamic>>> _groupTripsByDate(List<Map<String, dynamic>> trips) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    final now = DateTime.now();

    for (final trip in trips) {
      final dateStr = trip['completedAt'] as String?;
      DateTime dt = DateTime.now();
      if (dateStr != null) {
        dt = DateTime.tryParse(dateStr) ?? DateTime.now();
      }

      String dateHeader;
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        dateHeader = "Today, ${dt.day} ${_monthName(dt.month)} ${dt.year}";
      } else if (dt.year == now.year && dt.month == now.month && dt.day == now.day - 1) {
        dateHeader = "Yesterday, ${dt.day} ${_monthName(dt.month)} ${dt.year}";
      } else {
        dateHeader = "${dt.day} ${_monthName(dt.month)} ${dt.year}";
      }

      if (!grouped.containsKey(dateHeader)) {
        grouped[dateHeader] = [];
      }
      grouped[dateHeader]!.add(trip);
    }
    return grouped;
  }

  String _monthName(int m) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return (m >= 1 && m <= 12) ? months[m - 1] : '';
  }

  String _formatTripTime(String? dateStr) {
    if (dateStr == null) return '';
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) return '';
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '$hour:$min $period';
  }

  Future<void> _launchGoogleMaps(String address) async {
    final encoded = Uri.encodeComponent(address);
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$encoded');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  // ==========================================
  // ROOT BUILD METHOD
  // ==========================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // slate-50
      body: SafeArea(
        child: Stack(
          children: [
            if (_currentViewMode == 'customer') _buildCustomerView(),
            if (_currentViewMode == 'rider') _buildRiderView(),
            if (_currentViewMode == 'inspector') _buildStateInspectorView(),

            // Notification Center Drawer Popup
            if (_showNotificationDrawer && _currentViewMode == 'customer')
              _buildNotificationDrawer(),

            // Full-screen Tracking Modal Sheet
            if (_showTrackingModal && _activeOrder != null)
              Positioned.fill(child: _buildCustomerTrackingModal()),
          ],
        ),
      ),
    );
  }

  // Notification Center Drawer Popup (from Prototype)
  Widget _buildNotificationDrawer() {
    return Positioned(
      top: 90,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE5F6DE),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.notifications_active_rounded, size: 14, color: Color(0xFF467D32)),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Notifications & Alerts',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF0F172A)),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _showNotificationDrawer = false),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 14, color: Color(0xFF64748B)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4FBF0),
                  border: Border.all(color: const Color(0xFFCBEDBC)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: const BoxDecoration(
                        color: Color(0xFF76C457),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Active Riders on Duty', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Color(0xFF0F172A))),
                          SizedBox(height: 2),
                          Text('3 riders currently active in Melapalayam Bazaar & Kurichi.', style: TextStyle(fontSize: 10, color: Color(0xFF475569))),
                          SizedBox(height: 2),
                          Text('2 mins ago', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF467D32))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: const BoxDecoration(
                        color: Color(0xFFCBD5E1),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Fair Hyperlocal Pricing', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Color(0xFF0F172A))),
                          SizedBox(height: 2),
                          Text('Base fare ₹30 for first 2 km anywhere inside Melapalayam.', style: TextStyle(fontSize: 10, color: Color(0xFF475569))),
                          SizedBox(height: 2),
                          Text('1 hour ago', style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => setState(() => _showNotificationDrawer = false),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFF1F5F9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: Color(0xFF475569))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------
  // 2. VIEW A: CUSTOMER GUEST VIEW
  // ----------------------------------------------------
  Widget _buildCustomerView() {
    return Column(
      children: [
        // Customer Header With Organic Modern Curve
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF162A1A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(32),
              bottomRight: Radius.circular(32),
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 15,
                offset: Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF76C457),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF76C457).withOpacity(0.5),
                                  blurRadius: 6,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 7),
                          const Text(
                            'MPM Express',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: -0.2),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF76C457),
                              borderRadius: BorderRadius.circular(9999),
                            ),
                            child: const Text(
                              'மேலப்பாளையம்',
                              style: TextStyle(color: Color(0xFF0F172A), fontSize: 9.5, fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF76C457),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$_activeRidersCount Riders Available on duty',
                            style: const TextStyle(
                              color: Color(0xFFA7DF92),
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Header actions: Notification Bell & Discreet Rider Portal
                  Row(
                    children: [
                      // Dedicated Notification Bell with animated counter badge
                      GestureDetector(
                        onTap: () => setState(() => _showNotificationDrawer = !_showNotificationDrawer),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B).withOpacity(0.9),
                                border: Border.all(color: const Color(0xFF334155)),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.notifications_outlined, color: Colors.white, size: 17),
                            ),
                            Positioned(
                              top: -2,
                              right: -2,
                              child: Container(
                                width: 15,
                                height: 15,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF76C457),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF76C457).withOpacity(0.6),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                alignment: Alignment.center,
                                child: const Text(
                                  '2',
                                  style: TextStyle(color: Color(0xFF0F172A), fontSize: 9, fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Discreet Rider Access Trigger
                      GestureDetector(
                        onTap: () => setState(() => _currentViewMode = 'rider'),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B).withOpacity(0.9),
                            border: Border.all(color: const Color(0xFF334155)),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.shield_outlined, color: Color(0xFF94A3B8), size: 16),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Tactile Pill Service Buttons (Round Corner + Sliding Smooth Style)
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withOpacity(0.55),
                  border: Border.all(color: const Color(0xFF334155).withOpacity(0.7)),
                  borderRadius: BorderRadius.circular(9999),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildServiceTabButton('pickup', Icons.inventory_2_outlined, 'Pickup & Drop'),
                    ),
                    Expanded(
                      child: _buildServiceTabButton('buy', Icons.shopping_bag_outlined, 'Buy For Me'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Scrollable Form Body
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              // Active Order Banner (if exists and ongoing)
              if (_activeOrder != null && !_activeOrder!.isDelivered && !_activeOrder!.isCancelled) ...[
                _buildActiveOrderBanner(),
                const SizedBox(height: 12),
              ],

              // Legal Warning Card (Amber)
              const LegalWarningBanner(),

              const SizedBox(height: 12),

              // Contact Phone Card (Stored Locally)
              _buildContactPhoneCard(),

              const SizedBox(height: 12),

              // Form Variant Content
              if (_activeTab == 'pickup') _buildPickupFormGroup(),
              if (_activeTab == 'buy') _buildBuyFormGroup(),

              const SizedBox(height: 12),

              // Urgent Priority Card
              _buildUrgentPriorityCard(),

              const SizedBox(height: 14),

              // Modern Fare Engine & Action Button Bar
              _buildFareEngineActionCard(),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildServiceTabButton(String tab, IconData icon, String label) {
    final isSelected = _activeTab == tab;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = tab),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF76C457) : Colors.transparent,
          borderRadius: BorderRadius.circular(9999),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF76C457).withOpacity(0.45),
                    blurRadius: 16,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Floating Active Order Notification Pill
  Widget _buildActiveOrderBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        border: Border.all(color: const Color(0xFF76C457).withOpacity(0.4)),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF76C457).withOpacity(0.2),
                  border: Border.all(color: const Color(0xFF76C457).withOpacity(0.4)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.alt_route_rounded, color: Color(0xFF76C457), size: 18),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Active Order', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF76C457),
                          borderRadius: BorderRadius.circular(9999),
                        ),
                        child: Text(
                          '#${_activeOrder!.orderNumber}',
                          style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w900, fontSize: 9.5),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _activeOrder!.status.replaceAll('_', ' '),
                    style: const TextStyle(color: Color(0xFFA7DF92), fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF76C457),
              foregroundColor: const Color(0xFF0F172A),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
              shadowColor: const Color(0xFF76C457).withOpacity(0.45),
            ),
            onPressed: () => setState(() => _showTrackingModal = true),
            child: const Text('Track', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  // Contact Phone Card
  Widget _buildContactPhoneCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.phone_outlined, size: 13, color: Color(0xFF467D32)),
                  SizedBox(width: 5),
                  Text(
                    'CUSTOMER MOBILE (கைபேசி எண்)',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10.5, color: Color(0xFF334155), letterSpacing: 0.5),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5F6DE),
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: const Text(
                  'Stored Locally',
                  style: TextStyle(color: Color(0xFF3A642B), fontWeight: FontWeight.bold, fontSize: 9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Phone Field with +91 Prefix
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('+91', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF64748B), fontSize: 12)),
                ),
                Expanded(
                  child: TextField(
                    controller: _primaryPhoneCtrl,
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0F172A), fontSize: 12),
                    decoration: const InputDecoration(
                      hintText: '10-digit mobile number',
                      border: InputBorder.none,
                      counterText: '',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: (val) {
                      PreferencesService.saveCustomerProfile('Guest', val);
                      _syncPhoneCheckboxes();
                    },
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Checkboxes
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isSenderMe = !_isSenderMe;
                    _syncPhoneCheckboxes();
                  });
                },
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: Checkbox(
                        value: _isSenderMe,
                        activeColor: const Color(0xFF76C457),
                        onChanged: (v) {
                          setState(() {
                            _isSenderMe = v ?? false;
                            _syncPhoneCheckboxes();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('I am the Sender', style: TextStyle(fontSize: 11, color: Color(0xFF475569))),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isReceiverMe = !_isReceiverMe;
                    _syncPhoneCheckboxes();
                  });
                },
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: Checkbox(
                        value: _isReceiverMe,
                        activeColor: const Color(0xFF76C457),
                        onChanged: (v) {
                          setState(() {
                            _isReceiverMe = v ?? false;
                            _syncPhoneCheckboxes();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('I am the Receiver', style: TextStyle(fontSize: 11, color: Color(0xFF475569))),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Secondary Contacts
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Pickup Contact', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                    const SizedBox(height: 3),
                    TextField(
                      controller: _pickupPhoneCtrl,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(fontSize: 11),
                      decoration: _cleanInputDecoration("Sender's Phone"),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Drop Contact', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                    const SizedBox(height: 3),
                    TextField(
                      controller: _dropPhoneCtrl,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(fontSize: 11),
                      decoration: _cleanInputDecoration("Receiver's Phone"),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Pickup & Drop Form Group
  Widget _buildPickupFormGroup() {
    return Column(
      children: [
        // Category Pills Grid (6 items in 3 columns)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ITEM CATEGORY (பொருள் வகை)',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10.5, color: Color(0xFF334155), letterSpacing: 0.5),
              ),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.5,
                children: AppConstants.prototypeCategories.map((item) {
                  final isSelected = _selectedCategory == item['id'];
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedCategory = item['id']!;
                        _selectedCategoryLabel = '${item['emoji']} ${item['label']}';
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFF4FBF0) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF76C457) : const Color(0xFFE2E8F0),
                          width: isSelected ? 1.6 : 1,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(item['emoji']!, style: const TextStyle(fontSize: 16)),
                          const SizedBox(height: 2),
                          Text(
                            item['label']!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              color: isSelected ? const Color(0xFF172E12) : const Color(0xFF334155),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              if (_selectedCategory == 'Custom') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _customItemCtrl,
                  style: const TextStyle(fontSize: 12),
                  decoration: _cleanInputDecoration('Specify item details...'),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Pickup Location Field
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: const Color(0xFF76C457),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFCBEDBC), width: 2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'PICKUP ADDRESS',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10.5, color: Color(0xFF334155)),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => _detectCurrentGPS('pickup'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5F6DE),
                        border: Border.all(color: const Color(0xFFCBEDBC)),
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.location_searching, size: 10, color: Color(0xFF3A642B)),
                          SizedBox(width: 4),
                          Text('Use GPS', style: TextStyle(color: Color(0xFF3A642B), fontWeight: FontWeight.bold, fontSize: 9.5)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pickupAddressCtrl,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                decoration: _cleanInputDecoration('Street, Door No, or Landmark'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Drop Location Field with Cross-Zone Intelligence
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF43F5E), // rose-500
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFFECDD3), width: 2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'DROP ADDRESS',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10.5, color: Color(0xFF334155)),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => _detectCurrentGPS('drop'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5F6DE),
                        border: Border.all(color: const Color(0xFFCBEDBC)),
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.location_searching, size: 10, color: Color(0xFF3A642B)),
                          SizedBox(width: 4),
                          Text('Use GPS', style: TextStyle(color: Color(0xFF3A642B), fontWeight: FontWeight.bold, fontSize: 9.5)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _dropAddressCtrl,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                decoration: _cleanInputDecoration('Destination street or landmark'),
                onChanged: (_) => setState(() {}),
              ),

              // Auto-detected Cross-Zone Notice
              if (_isCrossZone) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB), // amber-50
                    border: Border.all(color: const Color(0xFFFDE68A)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Row(
                        children: [
                          Icon(Icons.map_outlined, size: 12, color: Color(0xFFD97706)),
                          SizedBox(width: 5),
                          Text('Cross-Zone (Palayamkottai / Junction area)',
                              style: TextStyle(fontSize: 10, color: Color(0xFF78350F), fontWeight: FontWeight.w600)),
                        ],
                      ),
                      Text('+₹20 Surcharge', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFB45309))),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // Buy For Me Form Group
  Widget _buildBuyFormGroup() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SHOP / STALL NAME (கடை பெயர்)',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF334155), letterSpacing: 0.5)),
          const SizedBox(height: 4),
          TextField(
            controller: _buyShopCtrl,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            decoration: _cleanInputDecoration('e.g. Bazaar Mutton Stall, Periya Theru'),
          ),
          const SizedBox(height: 10),
          const Text('REQUIRED ITEMS & CUT SPECS (பொருட்கள் விபரம்)',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF334155), letterSpacing: 0.5)),
          const SizedBox(height: 4),
          TextField(
            controller: _buyListCtrl,
            maxLines: 2,
            style: const TextStyle(fontSize: 12),
            decoration: _cleanInputDecoration('1) 1/2 Kg Fresh Mutton (Leg piece curry cut)\n2) 2 Lemons'),
          ),
          const SizedBox(height: 10),
          const Text('DELIVER TO ADDRESS (டெலிவரி இடம்)',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF334155), letterSpacing: 0.5)),
          const SizedBox(height: 4),
          TextField(
            controller: _buyDropCtrl,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            decoration: _cleanInputDecoration('Hameempuram 4th Street, Melapalayam'),
            onChanged: (_) => setState(() {}),
          ),
          if (_isCrossZone) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                border: Border.all(color: const Color(0xFFFDE68A)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Row(
                    children: [
                      Icon(Icons.map_outlined, size: 12, color: Color(0xFFD97706)),
                      SizedBox(width: 5),
                      Text('Cross-Zone Delivery Area',
                          style: TextStyle(fontSize: 10, color: Color(0xFF78350F), fontWeight: FontWeight.w600)),
                    ],
                  ),
                  Text('+₹20 Surcharge', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFB45309))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Urgent Priority Toggle Card
  Widget _buildUrgentPriorityCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Text('⚡', style: TextStyle(fontSize: 14)),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Urgent Priority (அவசரம்)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                  Text('Direct dispatch, no batching (+₹15)', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                ],
              ),
            ],
          ),
          Switch(
            value: _isUrgent,
            activeColor: const Color(0xFF76C457),
            onChanged: (val) => setState(() => _isUrgent = val),
          ),
        ],
      ),
    );
  }

  // Modern Fare Engine & Action Button Bar
  Widget _buildFareEngineActionCard() {
    final fare = _calculateFare();
    final distText = _isCrossZone ? '• ~4.8 km (Cross-Zone)' : '• ~1.8 km';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1E293B)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('DELIVERY CHARGE',
                      style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w800, fontSize: 9.5, letterSpacing: 1.2)),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('₹$fare',
                          style: const TextStyle(color: Color(0xFF76C457), fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                      const SizedBox(width: 6),
                      Text(distText,
                          style: const TextStyle(color: Color(0xFFA7DF92), fontWeight: FontWeight.bold, fontSize: 11)),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Payment Method', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 9.5)),
                  const SizedBox(height: 2),
                  Row(
                    children: const [
                      Icon(Icons.qr_code_2_rounded, size: 12, color: Color(0xFF76C457)),
                      SizedBox(width: 4),
                      Text('Cash / UPI Handover',
                          style: TextStyle(color: Color(0xFF76C457), fontWeight: FontWeight.bold, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 10),
          const Divider(color: Color(0xFF1E293B), height: 1),
          const SizedBox(height: 10),

          const Text(
            'Base fee ₹30 covers up to 2 km inside Melapalayam. Zero convenience fee.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 9.5),
          ),

          const SizedBox(height: 12),

          // Confirm & Place Order Action Button
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF76C457),
              borderRadius: BorderRadius.circular(9999),
              boxShadow: [
                BoxShadow(color: const Color(0xFF76C457).withOpacity(0.45), blurRadius: 18, offset: const Offset(0, 4)),
              ],
            ),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: const Color(0xFF0F172A),
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
              ),
              icon: _isPlacingOrder
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F172A)))
                  : const Icon(Icons.delivery_dining_rounded, size: 20),
              label: Text(
                _isPlacingOrder ? 'Placing Order...' : 'Confirm & Place Order 🛵',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              ),
              onPressed: _isPlacingOrder ? null : _placeCustomerOrder,
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------
  // 3. MODAL: ORDER TRACKING DETAIL SHEET
  // ----------------------------------------------------
  Widget _buildCustomerTrackingModal() {
    final status = _activeOrder!.status;

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Tracking Header
          Container(
            color: const Color(0xFF0F172A),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('LIVE STATUS TRACKER',
                        style: TextStyle(color: Color(0xFF86CF69), fontWeight: FontWeight.w800, fontSize: 9, letterSpacing: 1.2)),
                    const SizedBox(height: 2),
                    Text(
                      'Order #${_activeOrder!.orderNumber}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  onPressed: () async {
                    if (_activeOrder != null && (_activeOrder!.isDelivered || _activeOrder!.isCancelled)) {
                      await PreferencesService.clearCustomerActiveOrderId();
                      setState(() {
                        _showTrackingModal = false;
                        _activeOrder = null;
                      });
                    } else {
                      setState(() => _showTrackingModal = false);
                    }
                  },
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Delivery PIN Card (only while trip is ongoing)
                if (!_activeOrder!.isDelivered && !_activeOrder!.isCancelled) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFF76C457).withOpacity(0.4)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 15, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('DELIVERY HANDOVER PIN',
                                style: TextStyle(color: Color(0xFF86CF69), fontWeight: FontWeight.w800, fontSize: 9.5)),
                            SizedBox(height: 2),
                            Text('Share with rider only upon package receipt', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 10)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF76C457).withOpacity(0.2),
                            border: Border.all(color: const Color(0xFF76C457).withOpacity(0.5)),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            _activeOrder!.deliveryPin,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: Color(0xFF76C457),
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Delivery Completed Celebration Card
                if (_activeOrder!.isDelivered) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F172A), Color(0xFF162A1A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFF76C457).withOpacity(0.4)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF76C457).withOpacity(0.2),
                          blurRadius: 15,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Color(0xFF76C457), size: 48),
                        const SizedBox(height: 10),
                        const Text(
                          'Order Delivered Successfully! 🎉',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Delivery PIN verified and package handed over.\nTotal Fare: ₹${_activeOrder!.fare}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFE5F6DE), fontSize: 11.5, height: 1.4),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF76C457),
                              foregroundColor: const Color(0xFF0F172A),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                            ),
                            onPressed: () async {
                              await PreferencesService.clearCustomerActiveOrderId();
                              setState(() {
                                _showTrackingModal = false;
                                _activeOrder = null;
                              });
                            },
                            child: const Text('Back to Home', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Order Cancelled Card
                if (_activeOrder!.isCancelled) ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F2),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFFECDD3)),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.cancel_outlined, color: Color(0xFFE11D48), size: 40),
                        const SizedBox(height: 8),
                        const Text('Order Cancelled',
                            style: TextStyle(color: Color(0xFF9F1239), fontWeight: FontWeight.w900, fontSize: 15)),
                        const SizedBox(height: 4),
                        const Text('This order has been cancelled and closed.',
                            style: TextStyle(color: Color(0xFFE11D48), fontSize: 11)),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE11D48),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                            ),
                            onPressed: () async {
                              await PreferencesService.clearCustomerActiveOrderId();
                              setState(() {
                                _showTrackingModal = false;
                                _activeOrder = null;
                              });
                            },
                            child: const Text('Return to Home', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Milestones Stepper
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TRIP PROGRESSION',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 10.5, color: Color(0xFF334155), letterSpacing: 0.5)),
                      const SizedBox(height: 12),
                      _buildStepperStep(
                        isCompleted: true,
                        title: 'Order Placed',
                        subtitle: 'Broadcasted to Melapalayam Rider Pool',
                      ),
                      _buildStepperStep(
                        isCompleted: status == 'RIDER_ASSIGNED' || status == 'ITEM_PURCHASED' || status == 'ON_THE_WAY' || status == 'DELIVERED',
                        title: 'Rider Claimed & Assigned',
                        subtitle: _activeOrder!.riderName ?? 'Awaiting nearest rider claim',
                      ),
                      _buildStepperStep(
                        isCompleted: status == 'ITEM_PURCHASED' || status == 'ON_THE_WAY' || status == 'DELIVERED',
                        title: 'Item Purchased / Picked',
                        subtitle: 'At merchant or pickup point',
                      ),
                      _buildStepperStep(
                        isCompleted: status == 'DELIVERED',
                        isLast: true,
                        title: 'Delivered to Hand',
                        subtitle: 'Verified via 4-digit PIN',
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Assigned Rider Card
                if (_activeOrder!.riderName != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE5F6DE),
                                border: Border.all(color: const Color(0xFFCBEDBC)),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              alignment: Alignment.center,
                              child: const Text('🛵', style: TextStyle(fontSize: 20)),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_activeOrder!.riderName!,
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: Color(0xFF0F172A))),
                                const Text('Hero Splendor • TN-72-AB-4021', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                                const SizedBox(height: 2),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE5F6DE),
                                    borderRadius: BorderRadius.circular(9999),
                                  ),
                                  child: const Text('Verified Partner',
                                      style: TextStyle(color: Color(0xFF3A642B), fontWeight: FontWeight.bold, fontSize: 8.5)),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (_activeOrder!.riderPhone != null)
                          GestureDetector(
                            onTap: () => launchUrl(Uri.parse('tel:${_activeOrder!.riderPhone}')),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFF76C457),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF76C457).withOpacity(0.4),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.phone, color: Color(0xFF0F172A), size: 16),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Cancellation Section
                if (!_activeOrder!.isDelivered && !_activeOrder!.isCancelled)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Order Cancellation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B))),
                            Text(
                              _activeOrder!.canCancel ? 'Free before rider purchases item.' : '🔒 Locked: Item bought from shop.',
                              style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _activeOrder!.canCancel ? const Color(0xFFFFF1F2) : const Color(0xFFE2E8F0),
                            foregroundColor: _activeOrder!.canCancel ? const Color(0xFFE11D48) : const Color(0xFF94A3B8),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                          ),
                          onPressed: _activeOrder!.canCancel ? _handleCustomerCancel : null,
                          child: const Text('Cancel', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepperStep({required bool isCompleted, required String title, required String subtitle, bool isLast = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: isCompleted ? const Color(0xFF76C457) : const Color(0xFFE2E8F0),
                shape: BoxShape.circle,
                boxShadow: isCompleted
                    ? [
                        BoxShadow(
                          color: const Color(0xFF76C457).withOpacity(0.4),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: isCompleted
                  ? const Text('✓', style: TextStyle(color: Color(0xFF0F172A), fontSize: 10, fontWeight: FontWeight.w900))
                  : const Text('', style: TextStyle(fontSize: 10)),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 24,
                color: isCompleted ? const Color(0xFF76C457) : const Color(0xFFE2E8F0),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                color: isCompleted ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
              ),
            ),
            Text(subtitle, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
          ],
        ),
      ],
    );
  }

  // ----------------------------------------------------
  // 4. VIEW B: RIDER PARTNER PORTAL
  // ----------------------------------------------------
  Widget _buildRiderView() {
    if (!_isRiderLoggedIn) {
      return _buildRiderLoginView();
    }
    return _buildRiderDashboardView();
  }

  Widget _buildRiderLoginView() {
    return Container(
      padding: const EdgeInsets.all(24),
      color: const Color(0xFFF8FAFC),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF5DA441), Color(0xFF76C457), Color(0xFFBEF264)],
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: const Color(0xFF76C457).withOpacity(0.45), blurRadius: 20, offset: const Offset(0, 6)),
              ],
            ),
            child: const Icon(Icons.two_wheeler_rounded, size: 34, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 12),
          const Text('Rider Partner Portal', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF0F172A))),
          const Text('Melapalayam Dispatch Access', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('PRE-REGISTERED PHONE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF475569))),
                const SizedBox(height: 6),
                TextField(
                  controller: _riderLoginPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  decoration: _cleanInputDecoration('Enter registered rider phone'),
                ),
                const SizedBox(height: 4),
                const Text('Pre-seeded accounts: Peer Mohamed (9845012345), Sudalai (9363302266)',
                    style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8))),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF76C457),
                      foregroundColor: const Color(0xFF0F172A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shadowColor: const Color(0xFF76C457).withOpacity(0.45),
                    ),
                    onPressed: _isRiderLoading ? null : _loginRider,
                    child: _isRiderLoading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F172A)))
                        : const Text('Access Dashboard', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5)),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: TextButton.icon(
                    onPressed: () => setState(() => _currentViewMode = 'customer'),
                    icon: const Icon(Icons.arrow_back, size: 14, color: Color(0xFF64748B)),
                    label: const Text('Back to Customer App',
                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiderDashboardView() {
    return Column(
      children: [
        // Top Curved Header (Matching Prototype Organic Curved Header Wave)
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF162A1A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            boxShadow: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            children: [
              // Top Navigation Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _currentViewMode = 'customer'),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
                    ),
                  ),
                  const Text(
                    'Rider Profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      letterSpacing: 0.3,
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
                        tooltip: 'Refresh Pool',
                        onPressed: () {
                          _fetchRiderPool();
                          _fetchRiderActiveOrder();
                          if (_loggedInRider != null) {
                            _apiService.getRiderProfile(_loggedInRider!.id).then((r) {
                              if (mounted) setState(() => _loggedInRider = r);
                            }).catchError((_) {});
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                        tooltip: 'Logout',
                        onPressed: _logoutRider,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Center Avatar
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF76C457).withOpacity(0.4), width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 34,
                      backgroundColor: const Color(0xFF76C457),
                      child: const Icon(Icons.two_wheeler_rounded, size: 36, color: Color(0xFF0F172A)),
                    ),
                  ),
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: _isRiderOnline ? const Color(0xFF76C457) : Colors.redAccent,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF0F172A), width: 2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Rider Name & Subtitle
              Text(
                _loggedInRider?.name ?? 'Peer Mohamed',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Delivery Partner • Melapalayam Hub',
                style: TextStyle(
                  color: Color(0xFFA7DF92),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),

              // 4 Quick Metrics / Info Cards
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildRiderHeaderBadge(
                    icon: Icons.two_wheeler_outlined,
                    title: 'Vehicle',
                    subtitle: 'Splendor',
                  ),
                  _buildRiderHeaderBadge(
                    icon: Icons.star_rounded,
                    title: 'Rating',
                    subtitle: '4.9 ★',
                    iconColor: Colors.amber,
                  ),
                  _buildRiderHeaderBadge(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Earned',
                    subtitle: '₹${_loggedInRider?.totalEarnings ?? 245}',
                    iconColor: const Color(0xFF76C457),
                  ),
                  GestureDetector(
                    onTap: () => _toggleRiderOnline(!_isRiderOnline),
                    child: _buildRiderHeaderBadge(
                      icon: _isRiderOnline ? Icons.power_settings_new_rounded : Icons.power_off_rounded,
                      title: 'Duty',
                      subtitle: _isRiderOnline ? 'ONLINE' : 'OFFLINE',
                      iconColor: _isRiderOnline ? const Color(0xFF76C457) : Colors.redAccent,
                      highlight: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Bottom Section: 2 Segmented Tabs (Tactile Pill Slider Track)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withOpacity(0.55),
            border: Border.all(color: const Color(0xFF334155).withOpacity(0.7)),
            borderRadius: BorderRadius.circular(9999),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _riderTab = 'active'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _riderTab == 'active' ? const Color(0xFF76C457) : Colors.transparent,
                      borderRadius: BorderRadius.circular(9999),
                      boxShadow: _riderTab == 'active'
                          ? [
                              BoxShadow(
                                color: const Color(0xFF76C457).withOpacity(0.45),
                                blurRadius: 16,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.electric_moped_outlined,
                          size: 16,
                          color: _riderTab == 'active' ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Active Orders',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            color: _riderTab == 'active' ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
                          ),
                        ),
                        if (_riderPoolOrders.isNotEmpty && _riderActiveTrip == null) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: _riderTab == 'active' ? const Color(0xFF0F172A) : const Color(0xFF76C457),
                              borderRadius: BorderRadius.circular(9999),
                            ),
                            child: Text(
                              '${_riderPoolOrders.length}',
                              style: TextStyle(
                                fontSize: 10,
                                color: _riderTab == 'active' ? const Color(0xFF76C457) : const Color(0xFF0F172A),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _riderTab = 'completed'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _riderTab == 'completed' ? const Color(0xFF76C457) : Colors.transparent,
                      borderRadius: BorderRadius.circular(9999),
                      boxShadow: _riderTab == 'completed'
                          ? [
                              BoxShadow(
                                color: const Color(0xFF76C457).withOpacity(0.45),
                                blurRadius: 16,
                                offset: const Offset(0, 3),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.task_alt_rounded,
                          size: 16,
                          color: _riderTab == 'completed' ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Completed Orders',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            color: _riderTab == 'completed' ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Tab Content Feed
        Expanded(
          child: _riderTab == 'active'
              ? _buildRiderActiveOrdersTab()
              : _buildRiderCompletedOrdersTab(),
        ),
      ],
    );
  }

  Widget _buildRiderHeaderBadge({
    required IconData icon,
    required String title,
    required String subtitle,
    Color? iconColor,
    bool highlight = false,
  }) {
    return Container(
      width: 78,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: highlight
            ? (iconColor ?? const Color(0xFF76C457)).withOpacity(0.18)
            : Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlight
              ? (iconColor ?? const Color(0xFF76C457)).withOpacity(0.4)
              : Colors.white.withOpacity(0.12),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: iconColor ?? Colors.white),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(fontSize: 9.5, color: Color(0xFFCBD5E1), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w900),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildRiderActiveOrdersTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (_riderActiveTrip != null) ...[
          _buildRiderActiveTripCard(),
          const SizedBox(height: 20),
        ],

        if (_riderActiveTrip == null) ...[
          if (!_isRiderOnline)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.power_off_rounded, color: Colors.redAccent, size: 36),
                  const SizedBox(height: 10),
                  const Text('You are currently OFFLINE',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF0F172A))),
                  const SizedBox(height: 4),
                  const Text(
                    'Toggle the Duty switch in the header card above to go ONLINE and receive live orders.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF76C457),
                      foregroundColor: const Color(0xFF0F172A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      shadowColor: const Color(0xFF76C457).withOpacity(0.45),
                    ),
                    icon: const Icon(Icons.power_settings_new_rounded, size: 16),
                    label: const Text('Go Online Now', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                    onPressed: () => _toggleRiderOnline(true),
                  ),
                ],
              ),
            )
          else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Order Pool (Melapalayam)',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF0F172A)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5F6DE),
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: Text(
                    '${_riderPoolOrders.length} Open',
                    style: const TextStyle(color: Color(0xFF3A642B), fontWeight: FontWeight.w900, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_riderPoolOrders.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: const [
                    Icon(Icons.inbox_outlined, size: 40, color: Color(0xFF94A3B8)),
                    SizedBox(height: 10),
                    Text('No orders in pool right now',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155))),
                    SizedBox(height: 4),
                    Text('Keep duty ONLINE. New customer requests will appear here instantly.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                  ],
                ),
              )
            else
              ..._riderPoolOrders.map((order) => _buildRiderPoolOrderCard(order)),
          ],
        ],
      ],
    );
  }

  Widget _buildRiderPoolOrderCard(OrderModel order) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: order.isUrgent ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0),
          width: order.isUrgent ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: Text(
                      '#${order.orderNumber}',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8)),
                    ),
                  ),
                  if (order.isUrgent) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: const Text('⚡ URGENT',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF92400E))),
                    ),
                  ],
                ],
              ),
              Text(
                'Fee: ₹${order.fare}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF3A642B)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            order.itemsList.join(', '),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.trip_origin_rounded, size: 12, color: Color(0xFF0284C7)),
              const SizedBox(width: 5),
              Expanded(
                child: Text('From: ${order.pickupAddress}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_rounded, size: 12, color: Color(0xFF76C457)),
              const SizedBox(width: 5),
              Expanded(
                child: Text('To: ${order.dropAddress}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF76C457),
                foregroundColor: const Color(0xFF0F172A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shadowColor: const Color(0xFF76C457).withOpacity(0.45),
              ),
              icon: const Icon(Icons.lock_open_rounded, size: 15),
              label: const Text('Accept & Pick Order', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
              onPressed: () => _atomicClaimOrder(order),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiderActiveTripCard() {
    final trip = _riderActiveTrip!;
    final isAssigned = trip.status == 'RIDER_ASSIGNED';
    final isPurchased = trip.status == 'ITEM_PURCHASED';
    final isOnWay = trip.status == 'ON_THE_WAY';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF76C457), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF76C457).withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PICKED ORDER IN PROGRESS',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF3A642B))),
                  const SizedBox(height: 2),
                  Text('#${trip.orderNumber}',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF0F172A))),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5F6DE),
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Text(
                  'Fee: ₹${trip.fare}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Color(0xFF3A642B)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Items Details Checklist
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.checklist_rounded, size: 15, color: Color(0xFF475569)),
                    const SizedBox(width: 6),
                    Text(
                      trip.orderType == 'PICKUP_DROP'
                          ? 'Package (${trip.category})'
                          : 'Buy For Me (${trip.shopName ?? "Market"})',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF334155)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ...trip.itemsList.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle, size: 13, color: Color(0xFF76C457)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(item,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Pickup & Drop Landmark Cards
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.trip_origin_rounded, color: Color(0xFF0284C7), size: 15),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('PICKUP / SHOP SPOT',
                              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
                          Text(trip.pickupAddress,
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(color: Color(0xFFF1F5F9), height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on_rounded, color: Color(0xFF76C457), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('DELIVERY DESTINATION',
                              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF3A642B))),
                          Text(trip.dropAddress,
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: const Size(0, 30),
                      ),
                      icon: const Icon(Icons.turn_right_rounded, size: 12),
                      label: const Text('Maps', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      onPressed: () => _launchGoogleMaps(trip.dropAddress),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Direct Call to Confirm Box (Before Picking / For Inquiry)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF2563EB), size: 16),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Call Customer to Confirm Order',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF1E40AF)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                const Text(
                  'Call before picking up product to confirm item availability, price, or ask any enquiry.',
                  style: TextStyle(fontSize: 10, color: Color(0xFF475569)),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.phone, size: 14),
                    label: Text(
                      'Call Customer (${trip.customerPhone})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                    ),
                    onPressed: () => launchUrl(Uri.parse('tel:${trip.customerPhone}')),
                  ),
                ),
                if (trip.pickupPhone != null && trip.pickupPhone != trip.customerPhone) ...[
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2563EB),
                      side: const BorderSide(color: Color(0xFF93C5FD)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.phone, size: 12),
                    label: Text('Call Pickup Contact (${trip.pickupPhone})',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                    onPressed: () => launchUrl(Uri.parse('tel:${trip.pickupPhone}')),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Milestone Progression Actions
          if (isAssigned)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.shopping_bag_outlined, size: 16),
                label: const Text('Mark Item Purchased / Picked', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                onPressed: () => _riderUpdateMilestone('ITEM_PURCHASED'),
              ),
            ),

          if (isPurchased)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF76C457),
                  foregroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shadowColor: const Color(0xFF76C457).withOpacity(0.45),
                ),
                icon: const Icon(Icons.two_wheeler_rounded, size: 16),
                label: const Text('Heading to Customer Door', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                onPressed: () => _riderUpdateMilestone('ON_THE_WAY'),
              ),
            ),

          if (isOnWay) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Step 1: Enter Customer 4-Digit Delivery PIN',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _riderOtpCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 8),
                    decoration: _cleanInputDecoration('----').copyWith(counterText: ''),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Step 2: Select Payment Method Collected:',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _closingPaymentMode = 'Cash'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _closingPaymentMode == 'Cash' ? const Color(0xFF76C457) : Colors.white,
                              borderRadius: BorderRadius.circular(9999),
                              border: Border.all(
                                color: _closingPaymentMode == 'Cash' ? const Color(0xFF76C457) : const Color(0xFFCBD5E1),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '💵 Cash Handover',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: _closingPaymentMode == 'Cash' ? const Color(0xFF0F172A) : const Color(0xFF334155),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _closingPaymentMode = 'UPI'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _closingPaymentMode == 'UPI' ? const Color(0xFF2563EB) : Colors.white,
                              borderRadius: BorderRadius.circular(9999),
                              border: Border.all(
                                color: _closingPaymentMode == 'UPI' ? const Color(0xFF2563EB) : const Color(0xFFCBD5E1),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '📱 UPI Received',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: _closingPaymentMode == 'UPI' ? Colors.white : const Color(0xFF334155),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF76C457),
                        foregroundColor: const Color(0xFF0F172A),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shadowColor: const Color(0xFF76C457).withOpacity(0.45),
                      ),
                      icon: const Icon(Icons.verified, size: 16),
                      label: const Text(
                        'Verify PIN & Close Order',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5),
                      ),
                      onPressed: () => _riderVerifyPin(isBypass: false),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: TextButton(
                      onPressed: () => _riderVerifyPin(isBypass: true),
                      child: const Text(
                        'Customer phone unavailable? Emergency Bypass PIN',
                        style: TextStyle(fontSize: 10, color: Color(0xFF64748B), decoration: TextDecoration.underline),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRiderCompletedOrdersTab() {
    if (_riderCompletedTrips.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.history_toggle_off_rounded, size: 48, color: Color(0xFF94A3B8)),
              SizedBox(height: 12),
              Text(
                'No completed orders yet',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF334155)),
              ),
              SizedBox(height: 4),
              Text(
                'Claim and complete orders from the pool to view your daily delivery summary here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      );
    }

    final grouped = _groupTripsByDate(_riderCompletedTrips);

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_rounded, size: 13, color: Color(0xFF64748B)),
                const SizedBox(width: 6),
                Text(
                  entry.key,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: Color(0xFF475569),
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Divider(color: const Color(0xFFCBD5E1).withOpacity(0.5))),
              ],
            ),
          ),
          ...entry.value.map(
            (trip) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            '#${trip['orderNumber']}',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF0F172A)),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE5F6DE),
                              borderRadius: BorderRadius.circular(9999),
                            ),
                            child: const Text('✅ DELIVERED',
                                style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF3A642B))),
                          ),
                        ],
                      ),
                      Text(
                        '+₹${trip['fare']}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF3A642B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    trip['items'] ?? 'Market Order',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 12, color: Color(0xFF64748B)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          trip['drop'] ?? 'Melapalayam',
                          style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatTripTime(trip['completedAt']),
                        style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: trip['paymentMode'] == 'UPI'
                              ? const Color(0xFFEFF6FF)
                              : const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: trip['paymentMode'] == 'UPI'
                                ? const Color(0xFFBFDBFE)
                                : const Color(0xFFFDE68A),
                          ),
                        ),
                        child: Text(
                          trip['paymentMode'] == 'UPI' ? '📱 UPI Received' : '💵 Cash Handover',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: trip['paymentMode'] == 'UPI'
                                ? const Color(0xFF1D4ED8)
                                : const Color(0xFFB45309),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ----------------------------------------------------
  // 5. VIEW C: STATE INSPECTOR & PRIVACY AUDITOR
  // ----------------------------------------------------
  Widget _buildStateInspectorView() {
    final storageDump = {
      'mpm_guest_phone': _primaryPhoneCtrl.text.trim(),
      'mpm_active_order_id': _activeOrder?.orderNumber ?? 'None',
      'privacy_rule': 'No other user orders stored or queryable by this device',
    };

    final orderJson = _activeOrder != null
        ? {
            'orderId': '#${_activeOrder!.orderNumber}',
            'status': _activeOrder!.status,
            'customerPhone': _activeOrder!.customerPhone,
            'fare': '₹${_activeOrder!.fare}',
            'deliveryPin': _activeOrder!.deliveryPin,
            'pickup': _activeOrder!.pickupAddress,
            'drop': _activeOrder!.dropAddress,
            'riderAssigned': _activeOrder!.riderName ?? 'None',
          }
        : {'status': 'No active order document in memory'};

    final encoder = const JsonEncoder.withIndent('  ');

    return Container(
      color: const Color(0xFF0F172A), // slate-900
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Row(
                children: [
                  Icon(Icons.terminal_rounded, color: Color(0xFF34D399), size: 16),
                  SizedBox(width: 6),
                  Text('LOCAL STATE & PRIVACY INSPECTOR',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.8)),
                ],
              ),
              Text('Free Tier M0 Audit', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 9.5)),
            ],
          ),
          const SizedBox(height: 12),

          // LocalStorage Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF020617),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📱 DEVICE LOCALSTORAGE (Guest Device):',
                    style: TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.bold, fontSize: 10)),
                const SizedBox(height: 6),
                Text(
                  encoder.convert(storageDump),
                  style: const TextStyle(fontFamily: 'monospace', color: Color(0xFFCBD5E1), fontSize: 10),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Privacy Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF020617),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('🔒 ISOLATION AUDIT (Why others cannot see this):',
                    style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 10)),
                SizedBox(height: 6),
                Text(
                  'Orders are NOT listed via an open GET /orders endpoint. Each guest phone queries strictly by its locally held orderId. Riders query available pool behind authentication.',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5, height: 1.4),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Active Document Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF020617),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📦 ACTIVE ORDER RECORD (MongoDB Document):',
                    style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 10)),
                const SizedBox(height: 6),
                Text(
                  encoder.convert(orderJson),
                  style: const TextStyle(fontFamily: 'monospace', color: Color(0xFFCBD5E1), fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _cleanInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF059669))),
    );
  }
}
