import 'dart:async';
import 'package:flutter/material.dart';
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
import '../../widgets/rider_counter_badge.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({Key? key}) : super(key: key);

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  final ApiService _apiService = ApiService();

  // Top Mode Switcher ('customer' or 'rider')
  String _currentViewMode = 'customer';

  // Customer Form State
  String _activeTab = 'pickup'; // 'pickup' or 'buy'
  int _activeRidersCount = 3;
  bool _isLoadingRiders = false;
  Timer? _pollingTimer;

  // Contact Inputs
  final TextEditingController _primaryPhoneCtrl = TextEditingController(text: '9876543210');
  final TextEditingController _pickupPhoneCtrl = TextEditingController();
  final TextEditingController _dropPhoneCtrl = TextEditingController();
  final TextEditingController _pickupAddressCtrl = TextEditingController(text: 'Periya Theru, Melapalayam');
  final TextEditingController _dropAddressCtrl = TextEditingController(text: 'Melapalayam Bazaar Market');

  // Buy For Me Inputs
  final TextEditingController _buyShopCtrl = TextEditingController();
  final TextEditingController _buyListCtrl = TextEditingController();
  final TextEditingController _buyDropCtrl = TextEditingController(text: 'Hameempuram 3rd Street, Melapalayam');

  // Custom Item Input
  final TextEditingController _customItemCtrl = TextEditingController();

  String _selectedCategory = 'Food';
  String _selectedCategoryLabel = '🍱 Food / Tiffin';
  bool _isSenderMe = true;
  bool _isReceiverMe = false;
  bool _isUrgent = false;
  bool _isPlacingOrder = false;

  // Active Order (for live tracking modal)
  OrderModel? _activeOrder;
  bool _showTrackingModal = false;

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

  @override
  void initState() {
    super.initState();
    _loadStoredPreferences();
    _fetchLiveActiveRiders();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _fetchLiveActiveRiders();
      if (_currentViewMode == 'rider' && _isRiderLoggedIn && _isRiderOnline) {
        _fetchRiderPool();
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

  int _calculateFare() {
    int fare = AppConstants.baseFare; // ₹30
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
      // Fallback preset
      setState(() {
        if (target == 'pickup') {
          _pickupAddressCtrl.text = 'Hameempuram 2nd St, Melapalayam (GPS Pin: 8.7042, 77.7285)';
        } else if (target == 'drop') {
          _dropAddressCtrl.text = 'Bazaar Periya Theru Corner (GPS Pin: 8.7051, 77.7301)';
        } else if (target == 'buyDrop') {
          _buyDropCtrl.text = 'Near Al Ameen School, Kurichi (GPS Pin: 8.7020, 77.7265)';
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
          ? (_buyListCtrl.text.trim().isNotEmpty ? _buyListCtrl.text.trim() : 'Market Items')
          : (_selectedCategory == 'Custom' ? _customItemCtrl.text.trim() : _selectedCategoryLabel);

      final pickupLoc = isBuy
          ? (_buyShopCtrl.text.trim().isNotEmpty ? _buyShopCtrl.text.trim() : 'Melapalayam Bazaar Shop')
          : _pickupAddressCtrl.text.trim();

      final dropLoc = isBuy ? _buyDropCtrl.text.trim() : _dropAddressCtrl.text.trim();

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
        'estimatedDistanceKm': 2.0,
        'customerFcmToken': token,
      };

      final result = await _apiService.createOrder(payload);
      final order = result['order'] as OrderModel;
      final ticket = result['whatsappTicket'] as String;

      setState(() {
        _activeOrder = order;
        _pendingWhatsAppText = ticket;
        _isPlacingOrder = false;
      });

      _showWhatsAppDispatchDialog(order, ticket);
    } catch (e) {
      setState(() => _isPlacingOrder = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order placement failed: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _showWhatsAppDispatchDialog(OrderModel order, String ticket) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset('logo.png', width: 26, height: 26, fit: BoxFit.contain),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Dispatch to Mela Express Group',
                style: TextStyle(color: Color(0xFF065F46), fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This order ticket was formatted via Flutter share_plus for your WhatsApp dispatch group:',
              style: TextStyle(fontSize: 11, color: Color(0xFF475569)),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                ticket,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Color(0xFF1E293B)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Share.share(ticket);
              setState(() => _showTrackingModal = true);
            },
            child: const Text('Share Ticket', style: TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _showTrackingModal = true);
            },
            child: const Text('Track Order', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshActiveOrder() async {
    if (_activeOrder == null) return;
    try {
      final updated = await _apiService.getOrderById(_activeOrder!.id);
      if (mounted) setState(() => _activeOrder = updated);
    } catch (_) {}
  }

  Future<void> _handleCustomerCancel() async {
    if (_activeOrder == null) return;
    if (!_activeOrder!.canCancel) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot cancel: Rider has already purchased the item.'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    try {
      await _apiService.cancelOrder(_activeOrder!.id);
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
      _fetchRiderActiveOrder();
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
    if (_loggedInRider == null) return;
    try {
      final order = await _apiService.getRiderActiveOrder(_loggedInRider!.id);
      if (mounted) setState(() => _riderActiveTrip = order);
    } catch (_) {}
  }

  Future<void> _atomicClaimOrder(OrderModel order) async {
    if (_loggedInRider == null) return;
    try {
      final claimed = await _apiService.claimOrder(order.id, _loggedInRider!.id);
      setState(() {
        _riderActiveTrip = claimed;
        _riderPoolOrders.removeWhere((o) => o.id == order.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order locked and claimed!'), backgroundColor: Color(0xFF059669)),
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
        const SnackBar(content: Text('Please enter 4-digit PIN')),
      );
      return;
    }

    try {
      await _apiService.completeDelivery(
        _riderActiveTrip!.id,
        _loggedInRider!.id,
        deliveryPin: pin,
        isBypass: isBypass,
      );
      setState(() {
        _riderActiveTrip = null;
        _riderOtpCtrl.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isBypass ? 'Delivered successfully (OTP Bypassed).' : 'Delivered and verified via PIN! 🎉'),
          backgroundColor: const Color(0xFF059669),
        ),
      );
      // Refresh rider stats
      if (_loggedInRider != null) {
        final r = await _apiService.getRiderProfile(_loggedInRider!.id);
        setState(() => _loggedInRider = r);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _launchGoogleMaps(String address) async {
    final query = Uri.encodeComponent('$address, Melapalayam, Tirunelveli');
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$query');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617), // slate-950 shell
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            decoration: BoxDecoration(
              color: AppConstants.slate50,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: const Color(0xFF1E293B), width: 6),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.6),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Stack(
                children: [
                  Column(
                    children: [
                      // TOP VIEW SWITCHER (DEMO CONTROLLER)
                      _buildTopDemoSwitcher(),

                      // MAIN VIEW (CUSTOMER OR RIDER)
                      Expanded(
                        child: _currentViewMode == 'customer'
                            ? _buildCustomerView()
                            : _buildRiderView(),
                      ),
                    ],
                  ),

                  // CUSTOMER ORDER TRACKING MODAL OVERLAY
                  if (_showTrackingModal && _activeOrder != null)
                    _buildCustomerTrackingModal(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 1. TOP DEMO SWITCHER
  Widget _buildTopDemoSwitcher() {
    return Container(
      color: const Color(0xFF0F172A), // slate-900
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: const [
              Icon(Icons.bolt, color: Color(0xFF34D399), size: 16),
              SizedBox(width: 4),
              Text(
                'Mela Express Demo',
                style: TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B), // slate-800
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _buildModeToggleButton('customer', 'Customer'),
                _buildModeToggleButton('rider', 'Rider'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeToggleButton(String mode, String label) {
    final isSelected = _currentViewMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() => _currentViewMode = mode);
        if (mode == 'rider' && _isRiderLoggedIn) {
          _fetchRiderPool();
          _fetchRiderActiveOrder();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF059669) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF94A3B8),
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  // 2. CUSTOMER VIEW
  Widget _buildCustomerView() {
    return Column(
      children: [
        // Customer Header
        Container(
          color: const Color(0xFF065F46), // emerald-800
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 4),
                          ],
                        ),
                        padding: const EdgeInsets.all(2),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset('logo.png', fit: BoxFit.contain),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'Mela Express',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF059669),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'மேலப்பாளையம்',
                                  style: TextStyle(color: Colors.white, fontSize: 10),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          RiderCounterBadge(count: _activeRidersCount, isLoading: _isLoadingRiders),
                        ],
                      ),
                    ],
                  ),
                  if (_activeOrder != null)
                    GestureDetector(
                      onTap: () => setState(() => _showTrackingModal = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBBF24), // amber-400
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.location_searching, size: 12, color: Color(0xFF0F172A)),
                            SizedBox(width: 4),
                            Text(
                              'Track Order',
                              style: TextStyle(color: Color(0xFF0F172A), fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Service Tabs (Pickup & Drop vs Buy For Me)
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF064E3B).withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(3),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildServiceTabButton('pickup', 'Pickup & Drop'),
                    ),
                    Expanded(
                      child: _buildServiceTabButton('buy', 'Buy For Me'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Scrollable Form
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              // Legal Warning Banner
              const LegalWarningBanner(),

              const SizedBox(height: 10),

              // Contact Details Card
              _buildContactDetailsCard(),

              const SizedBox(height: 12),

              // Active Tab Content
              if (_activeTab == 'pickup') _buildPickupTabContent(),
              if (_activeTab == 'buy') _buildBuyTabContent(),

              const SizedBox(height: 12),

              // Urgent Priority Card
              _buildUrgentPriorityCard(),

              const SizedBox(height: 14),

              // Calculated Fare Banner & Confirm Order
              _buildFareBanner(),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildServiceTabButton(String tab, String label) {
    final isSelected = _activeTab == tab;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = tab),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF059669) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFFA7F3D0),
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildContactDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'தொடர்பு எண்கள் / Contact Details',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF334155), letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('Primary Phone (முக்கிய எண்) *', style: TextStyle(fontSize: 11, color: Color(0xFF475569))),
              Text('Auto-saved locally', style: TextStyle(fontSize: 9, color: Color(0xFF059669), fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _primaryPhoneCtrl,
            keyboardType: TextInputType.phone,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            decoration: _cleanInputDecoration('Enter 10-digit mobile number'),
            onChanged: (val) {
              PreferencesService.saveCustomerProfile('Guest', val);
              _syncPhoneCheckboxes();
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Checkbox(
                value: _isSenderMe,
                activeColor: const Color(0xFF059669),
                visualDensity: VisualDensity.compact,
                onChanged: (val) {
                  setState(() {
                    _isSenderMe = val ?? false;
                    _syncPhoneCheckboxes();
                  });
                },
              ),
              const Text('நான் தான் அனுப்பியவர் (I\'m sender)', style: TextStyle(fontSize: 11, color: Color(0xFF475569))),
            ],
          ),
          Row(
            children: [
              Checkbox(
                value: _isReceiverMe,
                activeColor: const Color(0xFF059669),
                visualDensity: VisualDensity.compact,
                onChanged: (val) {
                  setState(() {
                    _isReceiverMe = val ?? false;
                    _syncPhoneCheckboxes();
                  });
                },
              ),
              const Text('நான் தான் வாங்குபவர்', style: TextStyle(fontSize: 11, color: Color(0xFF475569))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Pickup Contact', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                    const SizedBox(height: 2),
                    TextField(
                      controller: _pickupPhoneCtrl,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF0F172A)),
                      decoration: _cleanInputDecoration('Sender phone'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Drop Contact', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                    const SizedBox(height: 2),
                    TextField(
                      controller: _dropPhoneCtrl,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF0F172A)),
                      decoration: _cleanInputDecoration('Receiver phone'),
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

  // Pickup Tab
  Widget _buildPickupTabContent() {
    return Column(
      children: [
        // Category Chips Grid (3 columns)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'பொருள் வகை / Item Category',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF334155), letterSpacing: 0.5),
              ),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 2.2,
                children: AppConstants.prototypeCategories.map((item) {
                  final isSelected = _selectedCategory == item['id'];
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedCategory = item['id']!;
                        _selectedCategoryLabel = item['label']!;
                      });
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFECFDF5) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF059669) : const Color(0xFFE2E8F0),
                          width: isSelected ? 1.8 : 1,
                        ),
                      ),
                      child: Text(
                        item['label']!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? const Color(0xFF064E3B) : const Color(0xFF334155),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (_selectedCategory == 'Custom') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _customItemCtrl,
                  style: const TextStyle(fontSize: 12),
                  decoration: _cleanInputDecoration('பொருளின் விபரம் உள்ளிடவும்...'),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Pickup Location
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: const [
                      CircleAvatar(radius: 4, backgroundColor: Color(0xFF10B981)),
                      SizedBox(width: 6),
                      Text('Pickup Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF334155))),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => _detectCurrentGPS('pickup'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.my_location, size: 10, color: Color(0xFF047857)),
                          SizedBox(width: 4),
                          Text('Use GPS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _pickupAddressCtrl,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                decoration: _cleanInputDecoration('Landmark or Street address...'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Drop Location
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: const [
                      CircleAvatar(radius: 4, backgroundColor: Color(0xFFEF4444)),
                      SizedBox(width: 6),
                      Text('Drop Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF334155))),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => _detectCurrentGPS('drop'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.my_location, size: 10, color: Color(0xFF047857)),
                          SizedBox(width: 4),
                          Text('Use GPS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _dropAddressCtrl,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                decoration: _cleanInputDecoration('Landmark or Street address...'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Buy Tab
  Widget _buildBuyTabContent() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('வாங்க வேண்டிய கடை / Shop Name', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
          const SizedBox(height: 4),
          TextField(
            controller: _buyShopCtrl,
            style: const TextStyle(fontSize: 12),
            decoration: _cleanInputDecoration('எ.கா: பஜார் மட்டன் ஸ்டால் / High Ground Medicals'),
          ),
          const SizedBox(height: 10),
          const Text('பொருட்கள் பட்டியல் / Items List', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
          const SizedBox(height: 4),
          TextField(
            controller: _buyListCtrl,
            maxLines: 2,
            style: const TextStyle(fontSize: 12),
            decoration: _cleanInputDecoration('1) 1/2 Kg Country Chicken (Small pieces)\n2) 1 strip Dolo 650'),
          ),
          const SizedBox(height: 10),
          const Text('டெலிவரி முகவரி / Deliver To', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
          const SizedBox(height: 4),
          TextField(
            controller: _buyDropCtrl,
            style: const TextStyle(fontSize: 12),
            decoration: _cleanInputDecoration('Delivery Address'),
          ),
        ],
      ),
    );
  }

  // Urgent Priority
  Widget _buildUrgentPriorityCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('⚡ அவசர டெலிவரி / Urgent Priority', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              Text('15-minute quick delivery (+₹15)', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
            ],
          ),
          Checkbox(
            value: _isUrgent,
            activeColor: const Color(0xFF059669),
            onChanged: (val) => setState(() => _isUrgent = val ?? false),
          ),
        ],
      ),
    );
  }

  // Calculated Fare Banner
  Widget _buildFareBanner() {
    final fare = _calculateFare();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF064E3B), // emerald-900
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: const Color(0xFF064E3B).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('மொத்த கட்டணம் / Estimated Fare', style: TextStyle(color: Color(0xFFA7F3D0), fontSize: 11)),
              const SizedBox(height: 2),
              Text('₹$fare', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              const Text('Base ₹30 for <2km inside Melapalayam', style: TextStyle(color: Color(0xFF6EE7B7), fontSize: 10)),
            ],
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF34D399), // emerald-400
              foregroundColor: const Color(0xFF020617), // slate-950
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 4,
            ),
            icon: _isPlacingOrder
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded, size: 16),
            label: Text(
              _isPlacingOrder ? 'Placing...' : 'Confirm Order',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
            ),
            onPressed: _isPlacingOrder ? null : _placeCustomerOrder,
          ),
        ],
      ),
    );
  }

  // 3. CUSTOMER TRACKING SCREEN MODAL
  Widget _buildCustomerTrackingModal() {
    if (_activeOrder == null) return const SizedBox();

    final status = _activeOrder!.status;
    String statusTitle = 'Order Placed (Waiting for Rider)';
    if (status == 'RIDER_ASSIGNED') statusTitle = 'Rider Assigned (Heading to pickup)';
    if (status == 'ITEM_PURCHASED') statusTitle = 'Item Purchased / Picked Up';
    if (status == 'ON_THE_WAY') statusTitle = 'Rider On The Way to Your Door!';
    if (status == 'DELIVERED') statusTitle = 'Delivered Successfully 🎉';
    if (status == 'CANCELLED') statusTitle = 'Order Cancelled';

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Tracking Header
          Container(
            color: const Color(0xFF065F46),
            padding: const EdgeInsets.all(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.asset('logo.png', fit: BoxFit.contain),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Active Order Tracking', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        Text('Order #${_activeOrder!.orderNumber}', style: const TextStyle(color: Color(0xFFA7F3D0), fontSize: 10)),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  onPressed: () => setState(() => _showTrackingModal = false),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Current State Banner with Delivery PIN
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('CURRENT STATE', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
                          Text(statusTitle, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF064E3B))),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFA7F3D0),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Delivery PIN: ${_activeOrder!.deliveryPin}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF064E3B)),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Stepper
                _buildTrackingStepper(),

                const SizedBox(height: 16),

                // Assigned Rider Card
                if (_activeOrder!.riderName != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A), // slate-900
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Text('🛵', style: TextStyle(fontSize: 26)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_activeOrder!.riderName!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              const Text('Hero Splendor • Melapalayam Dispatch', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          ),
                          icon: const Icon(Icons.phone, size: 14, color: Colors.white),
                          label: const Text('Call', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          onPressed: () {
                            if (_activeOrder!.riderPhone != null) {
                              launchUrl(Uri.parse('tel:${_activeOrder!.riderPhone}'));
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Cancellation Section
                if (!_activeOrder!.isDelivered && !_activeOrder!.isCancelled)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
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
                              _activeOrder!.canCancel ? 'Free cancellation before purchase.' : '🔒 Locked: Item bought.',
                              style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _activeOrder!.canCancel ? const Color(0xFFFFE4E6) : const Color(0xFFE2E8F0),
                            foregroundColor: _activeOrder!.canCancel ? const Color(0xFFBE123C) : const Color(0xFF94A3B8),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  Widget _buildTrackingStepper() {
    final status = _activeOrder!.status;
    final isStep1 = true;
    final isStep2 = status == 'RIDER_ASSIGNED' || status == 'ITEM_PURCHASED' || status == 'ON_THE_WAY' || status == 'DELIVERED';
    final isStep3 = status == 'ITEM_PURCHASED' || status == 'ON_THE_WAY' || status == 'DELIVERED';
    final isStep4 = status == 'DELIVERED';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        children: [
          _buildStepRow(1, 'Order Placed', 'Shared to WhatsApp Dispatch pool', isStep1),
          const SizedBox(height: 14),
          _buildStepRow(2, 'Rider Claimed & Assigned', _activeOrder!.riderName ?? 'Rider is on the job', isStep2),
          const SizedBox(height: 14),
          _buildStepRow(3, 'Item Purchased / Picked', 'At local bazaar shop', isStep3),
          const SizedBox(height: 14),
          _buildStepRow(4, 'Delivered to Destination', 'Cash / UPI on handover', isStep4),
        ],
      ),
    );
  }

  Widget _buildStepRow(int number, String title, String subtitle, bool isDone) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 10,
          backgroundColor: isDone ? const Color(0xFF059669) : const Color(0xFFCBD5E1),
          child: Text(
            isDone ? '✓' : '$number',
            style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: isDone ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 4. RIDER VIEW (LOGIN & DISPATCH)
  Widget _buildRiderView() {
    if (!_isRiderLoggedIn) {
      return _buildRiderLoginBox();
    }
    return _buildRiderDashboardBox();
  }

  Widget _buildRiderLoginBox() {
    return Container(
      padding: const EdgeInsets.all(24),
      color: const Color(0xFFF1F5F9), // slate-100
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            padding: const EdgeInsets.all(4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset('logo.png', fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Rider Partner Login', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF1E293B))),
          const Text('Melapalayam Dispatch Access', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pre-seeded Mobile Number', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                const SizedBox(height: 4),
                TextField(
                  controller: _riderLoginPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  decoration: _cleanInputDecoration('Enter registered rider phone'),
                ),
                const SizedBox(height: 4),
                const Text('Pre-registered: Sudalai (9363302266), Syed (9876543211)', style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8))),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _isRiderLoading ? null : _loginRider,
                    child: _isRiderLoading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Access Dashboard', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiderDashboardBox() {
    return Column(
      children: [
        // Rider Header
        Container(
          color: const Color(0xFF0F172A), // slate-900
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFF059669),
                    child: Text(
                      _loggedInRider?.name.substring(0, 2).toUpperCase() ?? 'PM',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _loggedInRider?.name ?? 'Peer Mohamed',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const Text('Melapalayam Zone', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    _isRiderOnline ? 'ONLINE' : 'OFFLINE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _isRiderOnline ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Switch(
                    value: _isRiderOnline,
                    activeColor: const Color(0xFF10B981),
                    onChanged: _toggleRiderOnline,
                  ),
                ],
              ),
            ],
          ),
        ),

        // Stats Bar
        Container(
          color: const Color(0xFFE2E8F0),
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    children: [
                      const Text('Today\'s Completed Trips', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                      const SizedBox(height: 2),
                      Text('${_loggedInRider?.totalDeliveries ?? 6} Trips', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    children: [
                      const Text('Earnings Today', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                      const SizedBox(height: 2),
                      Text('₹${_loggedInRider?.totalEarnings ?? 210}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF047857))),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Orders Feed
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // Active Trip Card
              if (_riderActiveTrip != null) _buildRiderActiveTripCard(),

              if (_riderActiveTrip == null) ...[
                if (_riderPoolOrders.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: const Center(
                      child: Text('No pool orders open right now.', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    ),
                  )
                else
                  ..._riderPoolOrders.map((order) => _buildPoolOrderCard(order)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPoolOrderCard(OrderModel order) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(6)),
                child: const Text('NEW POOL ORDER', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF92400E))),
              ),
              Text('Fee: ₹${order.fare}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF047857))),
            ],
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Item: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                TextSpan(text: order.itemsList.join(', '), style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Pickup: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                TextSpan(text: order.pickupAddress, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Drop: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                TextSpan(text: order.dropAddress, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              icon: const Icon(Icons.lock, size: 14, color: Colors.white),
              label: const Text('Accept & Pick Order (Lock)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6EE7B7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('My Active Delivery', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(6)),
                child: Text(trip.status.replaceAll('_', ' '), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF065F46))),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Target Address', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                      Text(trip.dropAddress, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB), // blue-600
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  ),
                  icon: const Icon(Icons.navigation, size: 12, color: Colors.white),
                  label: const Text('Open Maps', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                  onPressed: () => _launchGoogleMaps(trip.dropAddress),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (isAssigned)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B), // amber-500
                  foregroundColor: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.shopping_basket, size: 16),
                label: const Text('Swipe / Tap: Item Purchased / Picked', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                onPressed: () => _riderUpdateMilestone('ITEM_PURCHASED'),
              ),
            ),
          if (isPurchased)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488), // teal-600
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.two_wheeler, size: 16),
                label: const Text('Swipe / Tap: Heading to Customer', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                onPressed: () => _riderUpdateMilestone('ON_THE_WAY'),
              ),
            ),
          if (isOnWay) ...[
            const Divider(color: Color(0xFFF1F5F9), height: 20),
            const Text('Customer 4-Digit Delivery PIN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _riderOtpCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 4),
                    decoration: _cleanInputDecoration('Enter PIN').copyWith(counterText: ''),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onPressed: () => _riderVerifyPin(isBypass: false),
                  child: const Text('Verify', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: () => _riderVerifyPin(isBypass: true),
                child: const Text(
                  'Optional: Bypass OTP (Customer unavailable)',
                  style: TextStyle(fontSize: 10, color: Color(0xFF64748B), decoration: TextDecoration.underline),
                ),
              ),
            ),
          ],
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
