import 'dart:math' as math;
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
import '../../services/location_service.dart';
import '../../services/preferences_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/legal_warning_banner.dart';
import '../admin/admin_login_screen.dart';
import '../admin/admin_shell_screen.dart';
import '../intro/zippo_landing_intro_screen.dart';

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
  int _activeRidersCount = 0;
  bool _isLoadingRiders = false;
  Timer? _pollingTimer;

  // Contact Inputs (Stored Locally)
  final TextEditingController _primaryPhoneCtrl = TextEditingController();
  final TextEditingController _pickupPhoneCtrl = TextEditingController();
  final TextEditingController _dropPhoneCtrl = TextEditingController();

  // Pickup & Drop Inputs
  final TextEditingController _pickupAddressCtrl = TextEditingController();
  final TextEditingController _dropAddressCtrl = TextEditingController();

  // Buy For Me Inputs
  final TextEditingController _buyShopCtrl = TextEditingController();
  final TextEditingController _buyListCtrl = TextEditingController();
  final TextEditingController _buyDropCtrl = TextEditingController();
  final TextEditingController _customBuyItemCtrl = TextEditingController();

  // Custom Item Input
  final TextEditingController _customItemCtrl = TextEditingController();

  String _selectedCategory = 'Medicines';
  String _selectedCategoryLabel = '💊 Medicine';
  String _selectedBuyCategory = 'Meat';
  String _selectedBuyCategoryLabel = '🥩 Fresh Meat';
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
  final TextEditingController _riderLoginPhoneCtrl = TextEditingController();
  final TextEditingController _riderLoginPasswordCtrl = TextEditingController();
  bool _obscureRiderPassword = true;
  DateTime? _lastShieldTap;
  bool _isRiderOnline = true;
  bool _isRiderLoading = false;
  List<OrderModel> _riderPoolOrders = [];
  OrderModel? _riderActiveTrip;
  final TextEditingController _riderOtpCtrl = TextEditingController();
  String _riderTab = 'active'; // 'active' | 'completed'
  String _closingPaymentMode = 'Cash'; // 'Cash' | 'UPI'
  List<Map<String, dynamic>> _riderCompletedTrips = [];
  final Set<String> _expandedOrderIds = {};
  List<Map<String, dynamic>> _inAppNotifications = [];
  bool get _hasUnreadNotifications => _inAppNotifications.any((n) => n['isRead'] == false || n['isRead'] == null);

  // ── Address autocomplete state ─────────────────────────────────────
  List<PlaceSuggestion> _pickupSuggestions = [];
  List<PlaceSuggestion> _dropSuggestions = [];
  List<PlaceSuggestion> _buyDropSuggestions = [];
  bool _isSearchingPickup = false;
  bool _isSearchingDrop = false;
  bool _isSearchingBuyDrop = false;
  bool _isGpsLoading = false;
  String _gpsTarget = '';
  Timer? _pickupDebounce;
  Timer? _dropDebounce;
  Timer? _buyDropDebounce;


  @override
  void initState() {
    super.initState();
    NotificationService().ensureDeviceRegistered(role: 'CUSTOMER');
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
    _pickupDebounce?.cancel();
    _dropDebounce?.cancel();
    _buyDropDebounce?.cancel();
    _primaryPhoneCtrl.dispose();
    _pickupPhoneCtrl.dispose();
    _dropPhoneCtrl.dispose();
    _pickupAddressCtrl.dispose();
    _dropAddressCtrl.dispose();
    _buyShopCtrl.dispose();
    _buyListCtrl.dispose();
    _buyDropCtrl.dispose();
    _customBuyItemCtrl.dispose();
    _customItemCtrl.dispose();
    _riderLoginPhoneCtrl.dispose();
    _riderOtpCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStoredPreferences() async {
    final notifs = await PreferencesService.getInAppNotifications();
    if (mounted) setState(() => _inAppNotifications = notifs);
    try {
      final remoteBroadcasts = await _apiService.getRecentBroadcasts();
      if (remoteBroadcasts.isNotEmpty) {
        await PreferencesService.syncRemoteBroadcasts(remoteBroadcasts);
        final syncedNotifs = await PreferencesService.getInAppNotifications();
        if (mounted) setState(() => _inAppNotifications = syncedNotifs);
      }
    } catch (_) {}
    // Keep primary phone empty by default unless user inputs it
    _syncPhoneCheckboxes();

    final lastRole = await PreferencesService.getLastViewMode();
    final isAdmin = await PreferencesService.isAdminLoggedIn();
    if (isAdmin && lastRole == 'admin') {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminShellScreen()),
        );
        return;
      }
    }
    final riderSession = await PreferencesService.getRiderSession();
    if (riderSession['id'] != null && riderSession['id']!.isNotEmpty) {
      final cachedRider = RiderModel(
        id: riderSession['id']!,
        name: riderSession['name'] ?? 'ZIPPO Rider',
        phone: riderSession['phone'] ?? '',
        isOnline: true,
        totalDeliveries: 0,
        totalEarnings: 0,
      );
      setState(() {
        _loggedInRider = cachedRider;
        _isRiderLoggedIn = true;
        _isRiderOnline = true;
        if (lastRole == 'rider') {
          _currentViewMode = 'rider';
        }
      });
      try {
        final rider = await _apiService.getRiderProfile(riderSession['id']!);
        if (mounted) {
          setState(() {
            _loggedInRider = rider;
            _isRiderOnline = rider.isOnline;
          });
        }
      } catch (_) {}
    }

    // Load only real completed trips (no fake/sample trips)
    final savedTrips = await PreferencesService.getRiderCompletedTrips();
    final realTrips = savedTrips
        .map((str) {
          try {
            return jsonDecode(str) as Map<String, dynamic>;
          } catch (_) {
            return null;
          }
        })
        .where((t) =>
            t != null &&
            t['orderNumber'] != 'MPM-261028-4102' &&
            t['orderNumber'] != 'MPM-261027-1892')
        .cast<Map<String, dynamic>>()
        .toList();

    setState(() {
      _riderCompletedTrips = realTrips;
    });

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
        try {
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
        } catch (_) {
          await PreferencesService.clearCustomerActiveOrderId();
          if (mounted) {
            setState(() {
              _activeOrder = null;
              _showTrackingModal = false;
            });
          }
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
        } else {
          await PreferencesService.clearCustomerActiveOrderId();
          if (mounted && _activeOrder != null) {
            setState(() {
              _activeOrder = null;
              _showTrackingModal = false;
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

      await PreferencesService.clearRiderActiveOrderId();
      if (mounted) {
        setState(() => _riderActiveTrip = null);
      }
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
    } catch (e) {
      if (e.toString().contains('Order not found')) {
        await PreferencesService.clearRiderActiveOrderId();
        if (mounted) {
          setState(() => _riderActiveTrip = null);
        }
      }
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
        if (_activeRidersCount != count) setState(() => _activeRidersCount = count);
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
    setState(() {
      _isGpsLoading = true;
      _gpsTarget = target;
    });
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission denied. Please enable in Settings.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final addressText = await LocationService.reverseGeocode(
        position.latitude,
        position.longitude,
      );

      if (!mounted) return;
      setState(() {
        if (target == 'pickup') {
          _pickupAddressCtrl.text = addressText;
          _pickupSuggestions = [];
        } else if (target == 'drop') {
          _dropAddressCtrl.text = addressText;
          _dropSuggestions = [];
        } else if (target == 'buyDrop') {
          _buyDropCtrl.text = addressText;
          _buyDropSuggestions = [];
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'GPS: $addressText',
                  style: const TextStyle(fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(12),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GPS Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGpsLoading = false;
          _gpsTarget = '';
        });
      }
    }
  }

  // ── Address autocomplete search handlers ──
  void _onPickupAddressChanged(String query) {
    _pickupDebounce?.cancel();
    if (query.trim().length < 3) {
      setState(() {
        _pickupSuggestions = [];
        _isSearchingPickup = false;
      });
      return;
    }
    setState(() => _isSearchingPickup = true);
    _pickupDebounce = Timer(const Duration(milliseconds: 450), () async {
      final results = await LocationService.searchPlaces(query);
      if (mounted) {
        setState(() {
          _pickupSuggestions = results;
          _isSearchingPickup = false;
        });
      }
    });
  }

  void _onDropAddressChanged(String query) {
    _dropDebounce?.cancel();
    if (query.trim().length < 3) {
      setState(() {
        _dropSuggestions = [];
        _isSearchingDrop = false;
      });
      return;
    }
    setState(() => _isSearchingDrop = true);
    _dropDebounce = Timer(const Duration(milliseconds: 450), () async {
      final results = await LocationService.searchPlaces(query);
      if (mounted) {
        setState(() {
          _dropSuggestions = results;
          _isSearchingDrop = false;
        });
      }
    });
  }

  void _onBuyDropAddressChanged(String query) {
    _buyDropDebounce?.cancel();
    if (query.trim().length < 3) {
      setState(() {
        _buyDropSuggestions = [];
        _isSearchingBuyDrop = false;
      });
      return;
    }
    setState(() => _isSearchingBuyDrop = true);
    _buyDropDebounce = Timer(const Duration(milliseconds: 450), () async {
      final results = await LocationService.searchPlaces(query);
      if (mounted) {
        setState(() {
          _buyDropSuggestions = results;
          _isSearchingBuyDrop = false;
        });
      }
    });
  }

  Widget _buildQuickLocalityChips({required Function(String) onSelect}) {
    final quickPlaces = [
      {'label': 'Kodimaram (கொடிமரம்)', 'full': 'Kodimaram Main Road, Melapalayam, Tirunelveli - 627005'},
      {'label': 'Anna Street (அண்ணா தெரு)', 'full': 'Anna Street, Melapalayam, Tirunelveli - 627005'},
      {'label': 'Bazaar Road (பஜார்)', 'full': 'Bazaar Main Road, Melapalayam, Tirunelveli - 627005'},
      {'label': 'Periya Theru (பெரிய தெரு)', 'full': 'Periya Theru (Big Street), Melapalayam, Tirunelveli - 627005'},
      {'label': 'Uzhavar Sandhai', 'full': 'Uzhavar Sandhai, Market Road, Melapalayam, Tirunelveli - 627005'},
      {'label': 'Hameempuram 4th St', 'full': 'Hameempuram 4th Street, Melapalayam, Tirunelveli - 627005'},
      {'label': 'Rahmath Nagar', 'full': 'Rahmath Nagar Main Road, Melapalayam, Tirunelveli - 627005'},
      {'label': 'Kurichi (குறிச்சி)', 'full': 'Kurichi Road, Melapalayam, Tirunelveli - 627005'},
      {'label': 'Al Ameen Nagar', 'full': 'Al Ameen Nagar, Melapalayam, Tirunelveli - 627005'},
      {'label': 'Jinnah Nagar', 'full': 'Jinnah Nagar, Melapalayam, Tirunelveli - 627005'},
      {'label': 'Shifa Hospital', 'full': 'Shifa Hospital, Main Road, Melapalayam, Tirunelveli - 627005'},
      {'label': 'Chinna Theru', 'full': 'Chinna Theru, Melapalayam, Tirunelveli - 627005'},
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'QUICK SELECT LOCAL AREA (எளிதாக தேர்ந்தெடுக்க):',
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B), letterSpacing: 0.3),
          ),
          const SizedBox(height: 5),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: quickPlaces.map((p) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: () => onSelect(p['full']!),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.place_outlined, size: 10, color: Color(0xFF15803D)),
                          const SizedBox(width: 4),
                          Text(
                            p['label']!,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressSuggestionList({
    required List<PlaceSuggestion> suggestions,
    required bool isSearching,
    required void Function(PlaceSuggestion) onSelect,
  }) {
    if (isSearching) {
      return Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: const [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF76C457)),
            ),
            SizedBox(width: 8),
            Text('Searching nearby Melapalayam places...', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          ],
        ),
      );
    }
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: suggestions.take(4).map((s) {
            return InkWell(
              onTap: () => onSelect(s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF76C457)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.displayName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF0F172A)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            s.fullAddress,
                            style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showNoRidersAvailableOrderDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFFEF2F2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.two_wheeler_outlined, color: Color(0xFFDC2626), size: 22),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'No Rider Available Now',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'தற்போது ரைடர்கள் யாரும் ஆன்லைனில் இல்லை.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
            ),
            const SizedBox(height: 6),
            const Text(
              'Please wait a few minutes for a rider to come online before placing your order, or contact our helpline directly for instant booking.',
              style: TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.4),
            ),
            const SizedBox(height: 4),
            const Text(
              'ரைடர் வந்தவுடன் உங்கள் ஆர்டர் விரைவாக டெலிவரி செய்யப்படும். ஆர்டர் தொடர்பான விபரங்களுக்கு அழைக்கவும்:',
              style: TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.3),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.phone, size: 14, color: Color(0xFF15803D)),
                          label: const Text('6379329930', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF15803D))),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF86EFAC)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _launchPhone('6379329930');
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.phone, size: 14, color: Color(0xFF15803D)),
                          label: const Text('7639483476', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF15803D))),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF86EFAC)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _launchPhone('7639483476');
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Wait & Try Later', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 14),
                  label: const Text('Check Again'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF15803D),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _fetchLiveActiveRiders();
                    if (_activeRidersCount > 0) {
                      _placeCustomerOrder();
                    } else {
                      if (mounted) _showNoRidersAvailableOrderDialog();
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _placeCustomerOrder() async {
    final phone = _primaryPhoneCtrl.text.trim();
    final pickupPhone = _pickupPhoneCtrl.text.trim();
    final dropPhone = _dropPhoneCtrl.text.trim();

    // 1. Phone number validation (at least one valid 10-digit number is mandatory)
    final effectivePhone = phone.isNotEmpty ? phone : (pickupPhone.isNotEmpty ? pickupPhone : dropPhone);
    if (effectivePhone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please enter a valid 10-digit Phone Number (கைபேசி எண் உள்ளிடவும்)'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // Associate customer phone with device FCM token seamlessly
    NotificationService().ensureDeviceRegistered(role: 'CUSTOMER', phone: effectivePhone);

    final isBuy = _activeTab == 'buy';

    // 2. Validate Pickup & Drop required fields
    if (!isBuy) {
      if (_pickupAddressCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Please enter Pickup Address (பொருளை எடுக்கும் இடம் உள்ளிடவும்)'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      if (_dropAddressCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Please enter Drop Address (பொருளை சேர்க்கும் இடம் உள்ளிடவும்)'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      if (_selectedCategory == 'Custom' && _customItemCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Please enter Item Details (பொருட்கள் விபரம் உள்ளிடவும்)'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    } else {
      // 3. Validate Buy For Me required fields
      if (_buyShopCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Please enter Shop Name / Location (கடை பெயர் / இடம் உள்ளிடவும்)'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      if (_selectedBuyCategory == 'Others' &&
          _customBuyItemCtrl.text.trim().isEmpty &&
          _buyListCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Please specify item details manually (பொருள் விபரங்கள் உள்ளிடவும்)'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      if (_buyListCtrl.text.trim().isEmpty && _customBuyItemCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Please enter Items to Buy (வாங்க வேண்டிய பொருட்கள் உள்ளிடவும்)'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      if (_buyDropCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Please enter Delivery Address (சேர்க்க வேண்டிய இடம் உள்ளிடவும்)'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    }

    // 4. Pre-Order Placement Rider Availability Guard
    // Check if any rider is online right now before accepting order
    int availableRiders = _activeRidersCount;
    try {
      final freshCount = await _apiService.getActiveRidersCount();
      availableRiders = freshCount;
      if (mounted) setState(() => _activeRidersCount = freshCount);
    } catch (_) {}

    if (availableRiders <= 0) {
      if (!mounted) return;
      _showNoRidersAvailableOrderDialog();
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

      final itemDesc = isBuy
          ? (_selectedBuyCategory == 'Others' && _customBuyItemCtrl.text.trim().isNotEmpty
              ? '${_customBuyItemCtrl.text.trim()} - ${_buyListCtrl.text.trim()}'
              : _buyListCtrl.text.trim())
          : (_selectedCategory == 'Custom'
              ? _customItemCtrl.text.trim()
              : _selectedCategoryLabel);

      final pickupLoc = isBuy
          ? _buyShopCtrl.text.trim()
          : _pickupAddressCtrl.text.trim();

      final dropLoc = isBuy ? _buyDropCtrl.text.trim() : _dropAddressCtrl.text.trim();
      final fare = _calculateFare();

      final payload = {
        'customerName': 'Customer ($effectivePhone)',
        'customerPhone': effectivePhone,
        'pickupPhone': pickupPhone.isNotEmpty ? pickupPhone : effectivePhone,
        'dropPhone': dropPhone.isNotEmpty ? dropPhone : effectivePhone,
        'orderType': isBuy ? 'BUY_FOR_ME' : 'PICKUP_DROP',
        'category': isBuy
            ? (_selectedBuyCategory == 'Others' && _customBuyItemCtrl.text.trim().isNotEmpty
                ? _customBuyItemCtrl.text.trim()
                : _selectedBuyCategory)
            : _selectedCategory,
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

      await PreferencesService.saveCustomerProfile('Customer', effectivePhone);
      await PreferencesService.saveCustomerActiveOrderId(order.id);

      setState(() {
        _activeOrder = order;
        _isPlacingOrder = false;
        _showTrackingModal = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order placed successfully! Broadcasted to ZIPPO rider pool 🛵'),
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
        final wasCancelled = updated.isCancelled;
        final cancelReason = updated.cancellationReason ?? 'Cancelled by Rider';
        setState(() => _activeOrder = updated);
        if (updated.isDelivered || updated.isCancelled) {
          await PreferencesService.clearCustomerActiveOrderId();
          if (wasCancelled && _showTrackingModal) {
            _showCustomerOrderCancelledDialog(cancelReason);
          }
        }
      }
    } catch (e) {
      if (e.toString().contains('Order not found')) {
        await PreferencesService.clearCustomerActiveOrderId();
        if (mounted) {
          setState(() {
            _activeOrder = null;
            _showTrackingModal = false;
          });
        }
      }
    }
  }


  // Dialog to inform Customer when Rider closes/cancels order
  void _showCustomerOrderCancelledDialog(String reason) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.cancel_rounded, color: Color(0xFFDC2626), size: 24),
            SizedBox(width: 8),
            Text('Trip Closed / Cancelled', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The rider had to close this order.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Text(
                'Reason: $reason',
                style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B), fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'You can place a new order or call our support desk (7639483476 / 6379329930) for instant help.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _launchPhone('7639483476');
            },
            child: const Text('Call Support', style: TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _activeOrder = null;
                _showTrackingModal = false;
              });
            },
            child: const Text('OK / Place New Order'),
          ),
        ],
      ),
    );
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

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancel Order?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'Are you sure you want to cancel this order before rider confirmation?\n\n(ஆர்டரை ரத்து செய்ய விரும்புகிறீர்களா?)',
          style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Order', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _apiService.cancelOrder(_activeOrder!.id);
      await PreferencesService.clearCustomerActiveOrderId();
      if (mounted) {
        setState(() {
          _activeOrder = null;
          _showTrackingModal = false;
        });
      }
      await _refreshActiveOrder();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order cancelled successfully.'), backgroundColor: Color(0xFF059669)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cancellation error: ${e.toString().replaceAll("Exception: ", "")}'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _openAdminConsole() async {
    final isAdmin = await PreferencesService.isAdminLoggedIn();
    if (!mounted) return;
    if (isAdmin) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminShellScreen()),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
      );
    }
  }

  // --- RIDER ACTIONS ---

  Future<void> _loginRider() async {
    final password = _riderLoginPasswordCtrl.text.trim();

    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter password or passcode')),
      );
      return;
    }

    if (password == 'mani2006') {
      _riderLoginPasswordCtrl.clear();
      await PreferencesService.saveAdminSession();
      await PreferencesService.saveLastViewMode('admin');
      setState(() {
        _isRiderLoading = false;
        _currentViewMode = 'customer';
      });
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminShellScreen()),
      );
      return;
    }

    setState(() => _isRiderLoading = true);
    try {
      final token = await NotificationService().getCachedOrFreshToken();
      final rider = await _apiService.loginRider(password, fcmToken: token);

      await PreferencesService.saveRiderSession(id: rider.id, name: rider.name, phone: rider.phone);
      await PreferencesService.saveLastViewMode('rider');

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
      if (isOnline) { _fetchRiderPool(); _syncRiderCompletedTrips(); }
      _fetchLiveActiveRiders();
    } catch (_) {}
  }

  Future<void> _fetchRiderPool() async {
    try {
      final pool = await _apiService.getAvailableOrders();
      if (mounted) {
        if (_currentViewMode == 'rider' && _isRiderLoggedIn && _isRiderOnline) {
          final previousIds = _riderPoolOrders.map((o) => o.id).toSet();
          final newOrders = pool.where((o) => !previousIds.contains(o.id)).toList();
          if (newOrders.isNotEmpty && _riderPoolOrders.isNotEmpty) {
            HapticFeedback.heavyImpact();
            final latest = newOrders.first;
            ScaffoldMessenger.of(context).removeCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.electric_moped_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '🚨 New Order #' + latest.orderNumber + ' in Pool! (₹' + latest.fare.toString() + ')',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                backgroundColor: const Color(0xFF15803D),
                duration: const Duration(seconds: 4),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          }
        }
        setState(() => _riderPoolOrders = pool);
      }
    } catch (_) {}
  }

  Future<void> _syncRiderCompletedTrips() async {
    if (_loggedInRider == null) return;
    try {
      final history = await _apiService.getAdminRiderHistory(
        riderId: _loggedInRider!.id,
        status: 'DELIVERED',
      );
      if (mounted) {
        final List<Map<String, dynamic>> trips = history.map((o) => {
          'orderNumber': o.orderNumber,
          'fare': o.fare,
          'itemsList': o.itemsList,
          'createdAt': o.createdAt.toIso8601String(),
          'pickupAddress': o.pickupAddress,
          'dropAddress': o.dropAddress,
        }).toList();
        setState(() => _riderCompletedTrips = trips);
        await PreferencesService.setRiderCompletedTrips(
          trips.map((t) => jsonEncode(t)).toList(),
        );
      }
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
    await PreferencesService.saveLastViewMode('customer');
    setState(() {
      _isRiderLoggedIn = false;
      _loggedInRider = null;
      _riderActiveTrip = null;
      _currentViewMode = 'customer';
    });
  }

  // Real-time Today Rider Metrics (Orders count, Cash collected, UPI collected)
  int get _todayOrdersCount {
    final now = DateTime.now();
    return _riderCompletedTrips.where((t) {
      final dtStr = t['completedAt'] as String?;
      if (dtStr == null) return false;
      final dt = DateTime.tryParse(dtStr);
      if (dt == null) return false;
      return dt.year == now.year && dt.month == now.month && dt.day == now.day;
    }).length;
  }

  int get _todayCashTotal {
    final now = DateTime.now();
    int total = 0;
    for (final t in _riderCompletedTrips) {
      final dtStr = t['completedAt'] as String?;
      if (dtStr == null) continue;
      final dt = DateTime.tryParse(dtStr);
      if (dt == null) continue;
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        final mode = (t['paymentMode'] ?? 'Cash').toString().toUpperCase();
        if (mode == 'CASH') {
          total += ((t['fare'] ?? 0) as num).toInt();
        }
      }
    }
    return total;
  }

  int get _todayUpiTotal {
    final now = DateTime.now();
    int total = 0;
    for (final t in _riderCompletedTrips) {
      final dtStr = t['completedAt'] as String?;
      if (dtStr == null) continue;
      final dt = DateTime.tryParse(dtStr);
      if (dt == null) continue;
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        final mode = (t['paymentMode'] ?? '').toString().toUpperCase();
        if (mode == 'UPI') {
          total += ((t['fare'] ?? 0) as num).toInt();
        }
      }
    }
    return total;
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

  Future<void> _launchEmail(String email) async {
    final uri = Uri.parse('mailto:$email?subject=ZIPPO%20Customer%20Support');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _launchPhone(String phone) async {
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _launchWhatsApp(String phone, String orderNumber) async {
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    final fullPhone = clean.length == 10 ? '91$clean' : clean;
    final text = Uri.encodeComponent('Vanakkam! Regarding ZIPPO order #$orderNumber.');
    final url = Uri.parse('https://wa.me/$fullPhone?text=$text');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _launchWhatsAppEnquiry({String? message}) async {
    final text = Uri.encodeComponent(message ?? 'Vanakkam ZIPPO Team! I have an enquiry regarding ZIPPO delivery service.');
    final url = Uri.parse('https://wa.me/917639483476?text=$text');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _showRiderCancelTripDialog() async {
    if (_riderActiveTrip == null || _loggedInRider == null) return;
    String selectedReason = 'Customer requested cancellation';
    final reasons = [
      'Customer requested cancellation',
      'Store closed / Item unavailable',
      'Customer unreachable / wrong address',
      'Vehicle breakdown / Emergency',
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
              SizedBox(width: 8),
              Text('Cancel Active Trip?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Please select the reason for cancelling this trip. It will be logged in completed trips with a CANCELLED badge.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              for (final r in reasons)
                RadioListTile<String>(
                  title: Text(r, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  value: r,
                  groupValue: selectedReason,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  activeColor: const Color(0xFFDC2626),
                  onChanged: (val) {
                    if (val != null) setDlgState(() => selectedReason = val);
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Go Back', style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm Cancel'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && _riderActiveTrip != null) {
      final tripToCancel = _riderActiveTrip!;
      try {
        await _apiService.cancelOrder(
          tripToCancel.id,
          reason: selectedReason,
          isRider: true,
          riderId: _loggedInRider!.id,
        );
      } catch (_) {}

      final completedMap = {
        'orderNumber': tripToCancel.orderNumber,
        'items': tripToCancel.itemsList.join(', '),
        'pickup': tripToCancel.pickupAddress,
        'drop': tripToCancel.dropAddress,
        'fare': 0,
        'status': 'CANCELLED',
        'isCancelled': true,
        'reason': selectedReason,
        'paymentMode': 'Cancelled',
        'completedAt': DateTime.now().toIso8601String(),
      };

      await PreferencesService.saveRiderCompletedTrip(jsonEncode(completedMap));
      await PreferencesService.clearRiderActiveOrderId();

      setState(() {
        _riderCompletedTrips.insert(0, completedMap);
        _riderActiveTrip = null;
        _riderOtpCtrl.clear();
        _riderTab = 'completed';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Trip #${tripToCancel.orderNumber} cancelled and recorded.'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
      _fetchRiderPool();
    }
  }


  // ── Available Riders Bottom Sheet (Direct Call & WhatsApp Confirmation) ──
  void _showAvailableRidersSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _apiService.getOnlineRiders(),
            builder: (ctx, snapshot) {
              final riders = snapshot.data ?? [];
              final isLoading = snapshot.connectionState == ConnectionState.waiting;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag Handle
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Color(0xFFDCFCE7),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.phone_in_talk_rounded, size: 20, color: Color(0xFF15803D)),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'Available ZIPPO Riders',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                                ),
                                Text(
                                  'Call rider directly to confirm your order',
                                  style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),

                  const Divider(color: Color(0xFFE2E8F0)),

                  if (isLoading)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(color: Color(0xFF15803D)),
                    )
                  else if (riders.isEmpty) ...[
                    // No Riders Available Card (Shown when no one is available)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFEF2F2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.two_wheeler_outlined, size: 32, color: Color(0xFFEF4444)),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No rider available now',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF0F172A)),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'தற்போது ரைடர்கள் யாரும் ஆன்லைனில் இல்லை',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'For order enquiry contact:',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF334155)),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.phone, size: 14),
                                  label: const Text('6379329930', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF15803D),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _launchPhone('6379329930');
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.phone, size: 14),
                                  label: const Text('7639483476', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF15803D),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _launchPhone('7639483476');
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.chat_bubble_outline, size: 14, color: Color(0xFF15803D)),
                              label: const Text('WhatsApp Order Enquiry', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF15803D))),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF86EFAC)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _launchWhatsAppEnquiry();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // Active Available Riders List (Only shows genuinely available riders)
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: riders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, idx) {
                          final r = riders[idx];
                          final name = r['name']?.toString() ?? 'ZIPPO Rider';
                          final phone = r['phone']?.toString() ?? '';
                          final vehicle = r['vehicleNumber']?.toString() ?? 'Melapalayam Patrol';
                          final isOnline = r['isOnline'] == true;

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.02),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF22C55E),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14.5,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                if (phone.isNotEmpty)
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF15803D),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    icon: const Icon(Icons.phone, size: 14),
                                    label: const Text('Call', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    onPressed: () => _launchPhone(phone),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                ],
              );
            },
          ),
        );
      },
    );
  }

  // ── Download QR, Share & Policy Bottom Sheet ───────────────────────
  void _openAppDownloadAndPolicySheet() {
    const String downloadUrl = AppConstants.appDownloadUrl;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(modalCtx).size.height * 0.92,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2FE),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 20,
                            color: Color(0xFF0284C7),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Download & Share ZIPPO',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              'Direct APK Link & Service Guide',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 22, color: Color(0xFF64748B)),
                      onPressed: () => Navigator.pop(modalCtx),
                    ),
                  ],
                ),
              ),

              const Divider(height: 16, thickness: 1, color: Color(0xFFE2E8F0)),

              // Scrollable Details
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  children: [
                    // QR Code Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4FBF0),
                              borderRadius: BorderRadius.circular(9999),
                              border: Border.all(color: const Color(0xFFCBEDBC)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.verified_rounded, size: 12, color: Color(0xFF3A642B)),
                                SizedBox(width: 4),
                                Text(
                                  'Official Android & iOS App QR Code',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF3A642B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.asset(
                                'assets/download_qr.png',
                                width: 190,
                                height: 190,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Scan with any Camera or QR Scanner app to open the app download page (Android & iOS).',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Download Link Box with Copy Button
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.link_rounded, size: 18, color: Color(0xFF0284C7)),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: SelectableText(
                                    downloadUrl,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () {
                                    Clipboard.setData(const ClipboardData(text: downloadUrl));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Download link copied to clipboard! 📋'),
                                        backgroundColor: Color(0xFF059669),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F172A),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(Icons.copy_rounded, size: 12, color: Colors.white),
                                        SizedBox(width: 4),
                                        Text(
                                          'Copy',
                                          style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 14),

                          // Share Buttons
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF25D366),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 11),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    elevation: 0,
                                  ),
                                  icon: const Icon(Icons.share_rounded, size: 15),
                                  label: const Text(
                                    'Share APK Link',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                                  ),
                                  onPressed: () {
                                    Share.share(
                                      '🛵 Download ZIPPO (Melapalayam Express) - Hyperlocal goods & errand delivery in Melapalayam & Tirunelveli!\n\n📲 Direct Download: ' + downloadUrl + '\n\nSupport Helpline: 7639483476 / 6379329930 | Email: zippompm@gmail.com',
                                      subject: 'ZIPPO MPM Express App Download',
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0284C7),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 11),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    elevation: 0,
                                  ),
                                  icon: const Icon(Icons.open_in_browser_rounded, size: 15),
                                  label: const Text(
                                    'Open Link',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                                  ),
                                  onPressed: () async {
                                    final uri = Uri.parse(downloadUrl);
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Services & Dual Modes Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.delivery_dining_rounded, size: 18, color: Color(0xFF76C457)),
                              SizedBox(width: 8),
                              Text(
                                'Our 2 Core Services (சேவைகள்)',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF0F172A)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Mode 1: Pickup & Drop
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFBBF7D0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Row(
                                  children: [
                                    Icon(Icons.inventory_2_outlined, size: 15, color: Color(0xFF16A34A)),
                                    SizedBox(width: 6),
                                    Text(
                                      '1. Pickup & Delivery (பொருளை எடுத்து டெலிவரி)',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF15803D)),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Deliver ANY legal item or package — keys, urgent documents, medicine, parcels, tailoring clothes, and lunch boxes safely across Melapalayam & surrounds.',
                                  style: TextStyle(fontSize: 11, color: Color(0xFF166534), height: 1.35),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Mode 2: Buy For Me
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFBFDBFE)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Row(
                                  children: [
                                    Icon(Icons.shopping_bag_outlined, size: 15, color: Color(0xFF2563EB)),
                                    SizedBox(width: 6),
                                    Text(
                                      '2. Buy For You (உங்களுக்காக வாங்கித் தருதல்)',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1D4ED8)),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'We BUY ANY legal items from your favorite shops, stalls, bazaar, hotels or pharmacies and deliver directly with store bill verification.',
                                  style: TextStyle(fontSize: 11, color: Color(0xFF1E40AF), height: 1.35),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 12),
                          const Text(
                            '📍 Delivery Coverage: Melapalayam & surrounds (Palayamkottai, Vannarpettai, Tirunelveli Town, New Bus Stand within 10 km).',
                            style: TextStyle(fontSize: 11, color: Color(0xFF475569), fontWeight: FontWeight.w600, height: 1.35),
                          ),

                          const SizedBox(height: 10),
                          const Text(
                            'Supported Categories (ஆதரிக்கப்படும் பொருட்கள்):',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _buildServicePill('Medicines & Pharmacy', '💊'),
                              _buildServicePill('Keys & Urgent Docs', '🔑'),
                              _buildServicePill('Grocery & Shop Items', '🛒'),
                              _buildServicePill('Tailoring & Clothes', '🧵'),
                              _buildServicePill('Lunch / Any Food', '🍱'),
                              _buildServicePill('Fresh Meat / Mutton', '🥩'),
                              _buildServicePill('Any Legal Item / Custom', '✍️'),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Transparent Fare Policy Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.currency_rupee_rounded, size: 18, color: Color(0xFFD97706)),
                              SizedBox(width: 8),
                              Text(
                                'Transparent Pricing Policy',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF0F172A)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _buildFareRow('Base Fare (First 2 km)', '₹30'),
                          _buildFareRow('Distance Rate (beyond 2 km)', '₹10 / km'),
                          _buildFareRow('Urgent Priority Delivery', '+₹15'),
                          _buildFareRow('Cross-Zone Area (Palayamkottai / High Ground)', '+₹20'),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Legal & Security Warning
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F2),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFFECDD3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Icon(Icons.gavel_rounded, size: 16, color: Color(0xFFE11D48)),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'பாதுகாப்பு விதிமுறைகள்: பணம் (Cash), மதுபானம், போதைப்பொருட்கள், அல்லது பில் இல்லாத மருந்துகள் கொண்டு செல்லப்பட மாட்டாது.\n\nStrict Prohibition: Cash transfers, liquor, illegal items, and unprescribed pharmacy drugs are strictly prohibited.',
                              style: TextStyle(fontSize: 10.5, color: Color(0xFF881337), height: 1.4, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ZIPPO Customer Support Desk Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.support_agent_rounded, size: 20, color: Color(0xFF38BDF8)),
                              SizedBox(width: 8),
                              Text(
                                'ZIPPO Customer Support Desk',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13.5),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '📞 Helpline: +91 7639483476 / +91 6379329930\n✉️ Email: zippompm@gmail.com\nNeed order assistance, parcel inquiry, or delivery support? Reach our support team directly.',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, height: 1.45),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0284C7),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  icon: const Icon(Icons.phone, size: 13),
                                  label: const Text('Call: 7639483476', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                                  onPressed: () => _launchPhone('7639483476'),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0369A1),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  icon: const Icon(Icons.phone, size: 13),
                                  label: const Text('Call: 6379329930', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                                  onPressed: () => _launchPhone('6379329930'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF38BDF8),
                                    side: const BorderSide(color: Color(0xFF0284C7)),
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  icon: const Icon(Icons.email_outlined, size: 13),
                                  label: const Text('zippompm@gmail.com', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                  onPressed: () => _launchEmail('zippompm@gmail.com'),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF25D366),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  icon: const Icon(Icons.chat, size: 13),
                                  label: const Text('WhatsApp Help', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                                  onPressed: () => _launchWhatsAppEnquiry(),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildServicePill(String label, String icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
        ],
      ),
    );
  }

  Widget _buildFareRow(String title, String fare) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), fontWeight: FontWeight.w500)),
          Text(fare, style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A), fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  // Customer Orders History Bottom Sheet (User order details, contact numbers & live track reopening)
  Future<void> _openCustomerHistorySheet() async {
    final phone = _primaryPhoneCtrl.text.trim();
    List<OrderModel> orders = [];

    if (phone.isNotEmpty) {
      try {
        orders = await _apiService.getCustomerOrders(phone);
      } catch (_) {
        orders = [];
      }
    } else {
      final stored = await PreferencesService.getStoredOrders();
      for (final s in stored) {
        try {
          orders.add(OrderModel.fromJson(s));
        } catch (_) {}
      }
    }

    if (_activeOrder != null) {
      final exists = orders.any((o) => o.id == _activeOrder!.id || o.orderNumber == _activeOrder!.orderNumber);
      if (!exists) {
        orders.insert(0, _activeOrder!);
      }
    }

    orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setModalState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(modalCtx).size.height * 0.88,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE5F6DE),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.receipt_long_rounded,
                                size: 20,
                                color: Color(0xFF3A642B),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'My Orders & History',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  ' order recorded on this device',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Color(0xFFE2E8F0)),

                  Expanded(
                    child: orders.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.history_toggle_off_rounded, size: 52, color: Color(0xFF94A3B8)),
                                  SizedBox(height: 12),
                                  Text(
                                    'No past orders yet',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF334155)),
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    'Book a Pick and Deliver or Buy For Me delivery to track it and contact your rider anytime here.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: orders.length + 1,
                            itemBuilder: (ctx, index) {
                              if (index == orders.length) {
                                return _buildCustomerHistoryHelplineCard();
                              }
                              final order = orders[index];
                              return _buildCustomerHistoryOrderCard(order, modalCtx, setModalState, orders);
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteLocalOrder(
    OrderModel order,
    StateSetter setModalState,
    List<OrderModel> ordersList,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 22),
            SizedBox(width: 8),
            Text('Delete from Device?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'Remove Order # from this device history?\n\n'
          '⚠️ Note: This only clears it from this phone\'s history. The order remains recorded in the system.\n\n'
          '(இது உங்கள் போனிலிருந்து மட்டுமே நீக்கப்படும். சர்வரில் இருக்கும்.)',
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: const Text('Keep', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text('Delete (நீக்கு)', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await PreferencesService.removeOrderFromStore(order.id);
      await PreferencesService.removeOrderFromStore(order.orderNumber);
      setModalState(() {
        ordersList.removeWhere((o) => o.id == order.id || o.orderNumber == order.orderNumber);
      });
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order # deleted from this device.'),
            backgroundColor: const Color(0xFF334155),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget _buildCustomerHistoryOrderCard(
    OrderModel order,
    BuildContext modalCtx,
    StateSetter setModalState,
    List<OrderModel> ordersList,
  ) {
    final isDelivered = order.status == 'DELIVERED';
    final isCancelled = order.status == 'CANCELLED';
    final isOngoing = !isDelivered && !isCancelled;
    final isExpanded = _expandedOrderIds.contains(order.id) || _expandedOrderIds.contains(order.orderNumber);

    Color badgeBg;
    Color badgeText;
    String statusLabel;

    switch (order.status) {
      case 'DELIVERED':
        badgeBg = const Color(0xFFE5F6DE);
        badgeText = const Color(0xFF3A642B);
        statusLabel = '✅ DELIVERED';
        break;
      case 'CANCELLED':
        badgeBg = const Color(0xFFFEE2E2);
        badgeText = const Color(0xFFDC2626);
        statusLabel = '❌ CANCELLED';
        break;
      case 'ON_THE_WAY':
        badgeBg = const Color(0xFFFEF3C7);
        badgeText = const Color(0xFFD97706);
        statusLabel = '🚀 ON THE WAY';
        break;
      case 'ITEM_PURCHASED':
        badgeBg = const Color(0xFFF3E8FF);
        badgeText = const Color(0xFF7E22CE);
        statusLabel = '🛍️ ITEMS BOUGHT';
        break;
      case 'RIDER_ASSIGNED':
        badgeBg = const Color(0xFFDBEAFE);
        badgeText = const Color(0xFF1D4ED8);
        statusLabel = '🛵 RIDER ASSIGNED';
        break;
      default:
        badgeBg = const Color(0xFFF1F5F9);
        badgeText = const Color(0xFF475569);
        statusLabel = '⏳ SEARCHING RIDER';
    }

    final hasRider = order.assignedRider != null || (order.riderName != null && order.riderName!.isNotEmpty);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOngoing ? const Color(0xFF76C457) : const Color(0xFFE2E8F0),
          width: isOngoing ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isOngoing
                ? const Color(0xFF76C457).withOpacity(0.12)
                : Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header: Order Number + Status Badge + Big Visible Price Tag + Delete Icon
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Order Number & Status
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '#' + order.orderNumber,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: Color(0xFF0F172A),
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: badgeBg,
                              borderRadius: BorderRadius.circular(9999),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: badgeText),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _formatTripTime(order.createdAt.toIso8601String()),
                        style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),

                // BOLD PROMINENT PRICE BADGE
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF86EFAC), width: 1.2),
                  ),
                  child: Text(
                    '₹' + order.fare.toString(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: Color(0xFF15803D),
                    ),
                  ),
                ),
                const SizedBox(width: 4),

                // Delete Trash Icon
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                  tooltip: 'Delete from device history',
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  splashRadius: 18,
                  onPressed: () => _confirmDeleteLocalOrder(order, setModalState, ordersList),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),

          // Service / Items Summary
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      order.orderType == 'BUY_FOR_ME' ? Icons.shopping_bag_outlined : Icons.inventory_2_outlined,
                      size: 14,
                      color: const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        order.orderType == 'BUY_FOR_ME'
                            ? 'Buy For Me (' + (order.shopName ?? 'Market') + ')'
                            : 'Pick and Deliver (' + order.category + ')',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                      ),
                    ),
                  ],
                ),
                if (order.itemsList.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    order.itemsList.join(', '),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    maxLines: isExpanded ? 6 : 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Expanded Details: Addresses, Rider info, Live track button
          if (isExpanded) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Pickup & Drop
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Pickup
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.circle, size: 8, color: Color(0xFF10B981)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    order.pickupAddress,
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (order.pickupPhone != null && order.pickupPhone!.isNotEmpty)
                                    InkWell(
                                      onTap: () => _launchPhone(order.pickupPhone!),
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.phone, size: 10, color: Color(0xFF0284C7)),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Pickup Contact: ' + order.pickupPhone!,
                                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 4),
                          child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                        ),
                        // Drop
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.location_on, size: 10, color: Color(0xFFEF4444)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    order.dropAddress,
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (order.dropPhone != null && order.dropPhone!.isNotEmpty)
                                    InkWell(
                                      onTap: () => _launchPhone(order.dropPhone!),
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.phone, size: 10, color: Color(0xFF0284C7)),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Drop Contact: ' + order.dropPhone!,
                                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Assigned Rider
                  if (hasRider) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFDCFCE7),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.two_wheeler_rounded, size: 16, color: Color(0xFF15803D)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      order.riderName ?? 'Assigned Rider',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF14532D)),
                                    ),
                                    Text(
                                      order.riderPhone ?? 'Rider on duty',
                                      style: const TextStyle(fontSize: 10.5, color: Color(0xFF166534)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (order.riderPhone != null && order.riderPhone!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF15803D),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 7),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    icon: const Icon(Icons.phone, size: 12),
                                    label: const Text('Call Rider', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    onPressed: () => _launchPhone(order.riderPhone!),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF25D366),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 7),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    icon: const Icon(Icons.chat, size: 12),
                                    label: const Text('WhatsApp', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    onPressed: () => _launchWhatsApp(order.riderPhone!, order.orderNumber),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isOngoing ? const Color(0xFF76C457) : const Color(0xFF0F172A),
                        foregroundColor: isOngoing ? const Color(0xFF0F172A) : Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: Icon(
                        isOngoing ? Icons.navigation_rounded : Icons.visibility_rounded,
                        size: 14,
                      ),
                      label: Text(
                        isOngoing ? '📍 Live Track Order' : 'View Full Order Details',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                      ),
                      onPressed: () {
                        Navigator.pop(modalCtx);
                        setState(() {
                          _activeOrder = order;
                          _showTrackingModal = true;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Expand / Collapse Bar
          InkWell(
            onTap: () {
              setModalState(() {
                if (isExpanded) {
                  _expandedOrderIds.remove(order.id);
                  _expandedOrderIds.remove(order.orderNumber);
                } else {
                  _expandedOrderIds.add(order.id);
                  _expandedOrderIds.add(order.orderNumber);
                }
              });
            },
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
                border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isExpanded ? 'Hide details ▲' : 'Tap for full details ▼ (விபரம் காண்க)',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0284C7)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerHistoryHelplineCard() {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.support_agent_rounded, size: 20, color: Color(0xFF38BDF8)),
              SizedBox(width: 8),
              Text(
                'ZIPPO Customer Support Desk',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '📞 Helpline: +91 7639483476 / +91 6379329930\n✉️ Email: zippompm@gmail.com\nHave any delivery questions, app enquiries, or order support? Contact directly 24/7.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, height: 1.45),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.phone, size: 13),
                  label: const Text('Call: 7639483476', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                  onPressed: () => _launchPhone('7639483476'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0369A1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.phone, size: 13),
                  label: const Text('Call: 6379329930', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                  onPressed: () => _launchPhone('6379329930'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(color: Color(0xFF0284C7)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.email_outlined, size: 13),
                  label: const Text('zippompm@gmail.com', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  onPressed: () => _launchEmail('zippompm@gmail.com'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.chat, size: 13),
                  label: const Text('WhatsApp Help', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                  onPressed: () => _launchWhatsAppEnquiry(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerHistoryIconButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openCustomerHistorySheet(),
        borderRadius: BorderRadius.circular(9999),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withOpacity(0.75),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF334155).withOpacity(0.8)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(
                Icons.receipt_long_rounded,
                color: Color(0xFFE2E8F0),
                size: 20,
              ),
              if (_activeOrder != null)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFF76C457),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF76C457).withOpacity(0.8),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // ROOT BUILD METHOD
  // ==========================================
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFFF8FAFC),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        floatingActionButton: _currentViewMode == 'customer' && !_showTrackingModal
            ? Modern270CallOrderButton(
                onTap: _showAvailableRidersSheet,
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        body: Stack(
          children: [
            if (_currentViewMode == 'customer') _buildCustomerView(),
            if (_currentViewMode == 'rider') _buildRiderView(),
            if (_currentViewMode == 'inspector') SafeArea(child: _buildStateInspectorView()),

            // Notification Center Drawer Popup
            if (_showNotificationDrawer && (_currentViewMode == 'customer' || _currentViewMode == 'rider'))
              _buildNotificationDrawer(),

            // Full-screen Tracking Modal Sheet
            if (_showTrackingModal && _activeOrder != null)
              Positioned.fill(child: _buildCustomerTrackingModal()),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteInAppNotificationWithUndo(Map<String, dynamic> item) async {
    final notifId = item['id']?.toString() ?? '';
    final index = _inAppNotifications.indexOf(item);
    setState(() {
      _inAppNotifications.remove(item);
    });
    await PreferencesService.removeInAppNotification(notifId);

    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: const [
            Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Notification deleted',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: 'UNDO (2s)',
          textColor: const Color(0xFF76C457),
          onPressed: () async {
            if (index >= 0 && index <= _inAppNotifications.length) {
              _inAppNotifications.insert(index, item);
            } else {
              _inAppNotifications.add(item);
            }
            setState(() {});
            await PreferencesService.restoreInAppNotification(item);
          },
        ),
      ),
    );
  }

  // Live In-App Notification Center Drawer
  Widget _buildNotificationDrawer() {
    final topOffset = MediaQuery.of(context).padding.top + 74;
    final hasActiveOrder = _activeOrder != null;

    return Positioned(
      top: topOffset,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.72,
          ),
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
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE5F6DE),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.notifications_active_rounded, size: 15, color: Color(0xFF467D32)),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Live Alerts & Notifications',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF0F172A)),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      if (_inAppNotifications.isNotEmpty)
                        InkWell(
                          onTap: () async {
                            await PreferencesService.clearInAppNotifications();
                            if (mounted) setState(() => _inAppNotifications = []);
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Text(
                              'Clear All',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                            ),
                          ),
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
                ],
              ),
              const SizedBox(height: 12),

              // Content Body
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1. Live Active Order Card (Real)
                      if (hasActiveOrder) ...[
                        InkWell(
                          onTap: () {
                            setState(() {
                              _showNotificationDrawer = false;
                              _showTrackingModal = true;
                            });
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFDCFCE7),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.delivery_dining_rounded, size: 18, color: Color(0xFF15803D)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Order #' + _activeOrder!.orderNumber,
                                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Color(0xFF14532D)),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF15803D),
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: const Text(
                                              'LIVE TRACK',
                                              style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: Colors.white),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        'Status: ' + _activeOrder!.status + ' • ₹' + _activeOrder!.fare.toString(),
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF166534), fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],



                      // 3. In-App Notifications List with Left-Swipe Dismiss and Delete Icon
                      if (_inAppNotifications.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: const [
                              Icon(Icons.swipe_left_rounded, size: 13, color: Color(0xFF94A3B8)),
                              SizedBox(width: 4),
                              Text(
                                'Swipe left or tap trash icon to delete notification',
                                style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                        ..._inAppNotifications.map((n) {
                          final notifKey = ValueKey(n['id']?.toString() ?? UniqueKey().toString());
                          return Dismissible(
                            key: notifKey,
                            direction: DismissDirection.endToStart, // Swipe left
                            background: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.only(right: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              alignment: Alignment.centerRight,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: const [
                                  Text(
                                    'Delete',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(Icons.delete_rounded, color: Colors.white, size: 18),
                                ],
                              ),
                            ),
                            onDismissed: (_) {
                              _deleteInAppNotificationWithUndo(n);
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    margin: const EdgeInsets.only(top: 5),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF0284C7),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          n['title'] ?? 'Alert',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF0F172A)),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          n['body'] ?? '',
                                          style: const TextStyle(fontSize: 10.5, color: Color(0xFF475569), height: 1.3),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Dedicated Delete Icon Button
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFF94A3B8)),
                                    tooltip: 'Delete notification',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    splashRadius: 16,
                                    onPressed: () => _deleteInAppNotificationWithUndo(n),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ],

                      // 4. Clean Empty State (When no active order and no notifications)
                      if (!hasActiveOrder && _inAppNotifications.isEmpty && _activeRidersCount == 0) ...[
                        const SizedBox(height: 16),
                        const Icon(Icons.notifications_none_rounded, size: 36, color: Color(0xFFCBD5E1)),
                        const SizedBox(height: 8),
                        const Text(
                          'No new notifications',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF475569)),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Real-time alerts will appear here when an order is placed, claimed, or delivered.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),
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
          padding: EdgeInsets.fromLTRB(18, MediaQuery.of(context).padding.top + 30, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ZippoLandingIntroScreen(),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.asset(
                              'assets/logo.png',
                              cacheWidth: 90,
                              cacheHeight: 90,
                              width: 44,
                              height: 44,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) => Container(
                                width: 44,
                                height: 44,
                                color: const Color(0xFFF97316),
                                child: const Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 24),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'ZIPPO',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 20,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFEA580C), Color(0xFFF97316)],
                                  ),
                                  borderRadius: BorderRadius.circular(9999),
                                ),
                                child: const Text(
                                  'மேலப்பாளையம்',
                                  style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _activeRidersCount > 0 ? const Color(0xFF76C457) : const Color(0xFF94A3B8),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _activeRidersCount > 0
                                    ? '$_activeRidersCount ${_activeRidersCount == 1 ? 'Rider' : 'Riders'} Available on duty'
                                    : '0 Riders Online (Pool Standby)',
                                style: TextStyle(
                                  color: _activeRidersCount > 0 ? const Color(0xFFA7DF92) : Colors.white70,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Header actions: Notification Bell & Discreet Rider Portal
                  Row(
                    children: [
                      // Dedicated Notification Bell with dynamic icon fill color (no circle dot badge)
                      GestureDetector(
                        onTap: () async {
                          await PreferencesService.markNotificationsAsRead();
                          final notifs = await PreferencesService.getInAppNotifications();
                          if (mounted) {
                            setState(() {
                              _inAppNotifications = notifs;
                              _showNotificationDrawer = !_showNotificationDrawer;
                            });
                          }
                        },
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _hasUnreadNotifications
                                ? const Color(0xFF76C457).withOpacity(0.18)
                                : const Color(0xFF1E293B).withOpacity(0.9),
                            border: Border.all(
                              color: _hasUnreadNotifications
                                  ? const Color(0xFF76C457)
                                  : const Color(0xFF334155),
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _hasUnreadNotifications
                                ? Icons.notifications_active_rounded
                                : Icons.notifications_none_rounded,
                            color: _hasUnreadNotifications
                                ? const Color(0xFF76C457)
                                : const Color(0xFF94A3B8),
                            size: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Shield Trigger: Single Tap -> QR & Policy Sheet | Double Tap -> Rider/Admin Portal
                      GestureDetector(
                        onTap: () => _openAppDownloadAndPolicySheet(),
                        onDoubleTap: () {
                          setState(() => _currentViewMode = 'rider');
                          if (_isRiderLoggedIn) {
                            PreferencesService.saveLastViewMode('rider');
                          }
                        },
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
                      const SizedBox(width: 8),

                      // Direct Customer Support & Helpline Trigger
                      GestureDetector(
                        onTap: () => _launchWhatsAppEnquiry(),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B).withOpacity(0.9),
                            border: Border.all(color: const Color(0xFF334155)),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.headset_mic_rounded, color: Color(0xFF38BDF8), size: 16),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Tactile Pill Service Buttons + History Icon Button Row
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withOpacity(0.55),
                        border: Border.all(color: const Color(0xFF334155).withOpacity(0.7)),
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildServiceTabButton('pickup', Icons.inventory_2_outlined, 'Pick and Deliver'),
                          ),
                          Expanded(
                            child: _buildServiceTabButton('buy', Icons.shopping_bag_outlined, 'Buy For Me'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Separate History Icon Button (User Order Details, Contact & Live Track)
                  _buildCustomerHistoryIconButton(),
                ],
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

              // Modern Fare Engine & Action Button Bar (Payment Card)
              _buildFareEngineActionCard(),

              const SizedBox(height: 14),

              // Safety Legal Warning Banner (Amber) - Moved below payment card
              const LegalWarningBanner(),

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

  // Contact Phone Card (Reverted to White Background UI)
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
                      hintStyle: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
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
                  decoration: _cleanInputDecoration('Specify item details (பொருள் விபரங்கள்)...'),
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
                        'PICKUP ADDRESS (பொருளை எடுக்கும் இடம்)',
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
                          Text('Use GPS ', style: TextStyle(color: Color(0xFF3A642B), fontWeight: FontWeight.bold, fontSize: 9.5)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Stack(
                children: [
                  TextField(
                    controller: _pickupAddressCtrl,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                    decoration: _cleanInputDecoration('e.g. Periya Theru, Near Big Mosque, Melapalayam'),
                    onChanged: _onPickupAddressChanged,
                  ),
                  if (_isGpsLoading && _gpsTarget == 'pickup')
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                        child: const LinearProgressIndicator(
                          minHeight: 3,
                          backgroundColor: Color(0xFFE5F6DE),
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3A642B)),
                        ),
                      ),
                    ),
                ],
              ),
              if (_isGpsLoading && _gpsTarget == 'pickup')
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF3A642B))),
                      SizedBox(width: 5),
                      Text('Getting GPS address…', style: TextStyle(fontSize: 10, color: Color(0xFF3A642B), fontWeight: FontWeight.w500)),
                    ],
                  ),
                )
              else if (_isSearchingPickup)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF3A642B))),
                      SizedBox(width: 5),
                      Text('Searching places…', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                    ],
                  ),
                )
              else if (_pickupAddressCtrl.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 5, left: 2),
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _pickupAddressCtrl.clear();
                      _pickupSuggestions = [];
                    }),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.cancel_rounded, size: 11, color: Color(0xFF94A3B8)),
                        SizedBox(width: 3),
                        Text('Clear address', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), decoration: TextDecoration.underline)),
                      ],
                    ),
                  ),
                ),
              if (_pickupAddressCtrl.text.isEmpty && _pickupSuggestions.isEmpty)
                _buildQuickLocalityChips(
                  onSelect: (addr) => setState(() {
                    _pickupAddressCtrl.text = addr;
                    _pickupSuggestions = [];
                  }),
                ),
              _buildAddressSuggestionList(
                suggestions: _pickupSuggestions,
                isSearching: _isSearchingPickup,
                onSelect: (s) {
                  setState(() {
                    _pickupAddressCtrl.text = s.fullAddress;
                    _pickupSuggestions = [];
                  });
                  FocusScope.of(context).unfocus();
                },
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
                        'DROP ADDRESS (பொருளை சேர்க்கும் இடம்)',
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
                          Text('Use GPS ', style: TextStyle(color: Color(0xFF3A642B), fontWeight: FontWeight.bold, fontSize: 9.5)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Stack(
                children: [
                  TextField(
                    controller: _dropAddressCtrl,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                    decoration: _cleanInputDecoration('e.g. Melapalayam Bazaar Market'),
                    onChanged: (val) {
                      setState(() {});
                      _onDropAddressChanged(val);
                    },
                  ),
                  if (_isGpsLoading && _gpsTarget == 'drop')
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                        child: const LinearProgressIndicator(
                          minHeight: 3,
                          backgroundColor: Color(0xFFFFECEC),
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF43F5E)),
                        ),
                      ),
                    ),
                ],
              ),
              if (_isGpsLoading && _gpsTarget == 'drop')
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFFF43F5E))),
                      SizedBox(width: 5),
                      Text('Getting GPS address…', style: TextStyle(fontSize: 10, color: Color(0xFFF43F5E), fontWeight: FontWeight.w500)),
                    ],
                  ),
                )
              else if (_isSearchingDrop)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF64748B))),
                      SizedBox(width: 5),
                      Text('Searching places…', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                    ],
                  ),
                )
              else if (_dropAddressCtrl.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 5, left: 2),
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _dropAddressCtrl.clear();
                      _dropSuggestions = [];
                    }),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.cancel_rounded, size: 11, color: Color(0xFF94A3B8)),
                        SizedBox(width: 3),
                        Text('Clear address', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), decoration: TextDecoration.underline)),
                      ],
                    ),
                  ),
                ),
              if (_dropAddressCtrl.text.isEmpty && _dropSuggestions.isEmpty)
                _buildQuickLocalityChips(
                  onSelect: (addr) => setState(() {
                    _dropAddressCtrl.text = addr;
                    _dropSuggestions = [];
                  }),
                ),
              _buildAddressSuggestionList(
                suggestions: _dropSuggestions,
                isSearching: _isSearchingDrop,
                onSelect: (s) {
                  setState(() {
                    _dropAddressCtrl.text = s.fullAddress;
                    _dropSuggestions = [];
                  });
                  FocusScope.of(context).unfocus();
                },
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

  // Buy For Me Form Group (First Choose Category, then Shop Name, Items to Buy, Delivery Address)
  Widget _buildBuyFormGroup() {
    final currentCat = AppConstants.buyForMeCategories.firstWhere(
      (c) => c['id'] == _selectedBuyCategory,
      orElse: () => AppConstants.buyForMeCategories.first,
    );
    final itemHint = currentCat['placeholder'] ?? 'e.g. 1) Items to buy\n2) Quantity';

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
          // 1. Choose Buy Category First (6 items in 3 columns)
          const Text(
            'CHOOSE BUY CATEGORY (பிரிவு தேர்வு செய்க)',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF334155), letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.45,
            children: AppConstants.buyForMeCategories.map((item) {
              final isSelected = _selectedBuyCategory == item['id'];
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedBuyCategory = item['id']!;
                    _selectedBuyCategoryLabel = '${item['emoji']} ${item['label']}';
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFF4FBF0) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF76C457) : const Color(0xFFE2E8F0),
                      width: isSelected ? 1.8 : 1,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(item['emoji']!, style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(
                        item['label']!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9.5,
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

          // Manual Entry for Others (like Pick and Deliver)
          if (_selectedBuyCategory == 'Others') ...[
            const SizedBox(height: 10),
            TextField(
              controller: _customBuyItemCtrl,
              style: const TextStyle(fontSize: 12),
              decoration: _cleanInputDecoration('Specify item details manually (பொருள் விபரங்கள் உள்ளிடவும்)...'),
              onChanged: (_) => setState(() {}),
            ),
          ],

          const SizedBox(height: 12),

          // 2. Shop Name Field
          const Text('SHOP / STALL NAME (கடை பெயர் / இடம்)',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF334155), letterSpacing: 0.5)),
          const SizedBox(height: 4),
          TextField(
            controller: _buyShopCtrl,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            decoration: _cleanInputDecoration('e.g. Melapalayam Bazaar / Periya Theru Stall'),
          ),
          const SizedBox(height: 10),

          // 3. Items To Buy Field (with dynamic hint per category)
          const Text('ITEMS TO BUY (வாங்க வேண்டிய பொருட்கள்)',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF334155), letterSpacing: 0.5)),
          const SizedBox(height: 4),
          TextField(
            controller: _buyListCtrl,
            maxLines: 2,
            style: const TextStyle(fontSize: 12),
            decoration: _cleanInputDecoration(itemHint),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF43F5E),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFFECDD3), width: 2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'DELIVERY ADDRESS (சேர்க்க வேண்டிய இடம்)',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Color(0xFF334155), letterSpacing: 0.5),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () => _detectCurrentGPS('buyDrop'),
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
                      Text('Use GPS ', style: TextStyle(color: Color(0xFF3A642B), fontWeight: FontWeight.bold, fontSize: 9.5)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Stack(
            children: [
              TextField(
                controller: _buyDropCtrl,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                decoration: _cleanInputDecoration('e.g. Hameempuram 4th Street, Melapalayam'),
                onChanged: (val) {
                  setState(() {});
                  _onBuyDropAddressChanged(val);
                },
              ),
              if (_isGpsLoading && _gpsTarget == 'buyDrop')
                Positioned(
                  left: 0, right: 0, bottom: 0,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                    child: const LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor: Color(0xFFE5F6DE),
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3A642B)),
                    ),
                  ),
                ),
            ],
          ),
          if (_isGpsLoading && _gpsTarget == 'buyDrop')
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF3A642B))),
                  SizedBox(width: 5),
                  Text('Getting GPS address…', style: TextStyle(fontSize: 10, color: Color(0xFF3A642B), fontWeight: FontWeight.w500)),
                ],
              ),
            )
          else if (_isSearchingBuyDrop)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF64748B))),
                  SizedBox(width: 5),
                  Text('Searching places…', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                ],
              ),
            )
          else if (_buyDropCtrl.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 5, left: 2),
              child: GestureDetector(
                onTap: () => setState(() {
                  _buyDropCtrl.clear();
                  _buyDropSuggestions = [];
                }),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.cancel_rounded, size: 11, color: Color(0xFF94A3B8)),
                    SizedBox(width: 3),
                    Text('Clear address', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), decoration: TextDecoration.underline)),
                  ],
                ),
              ),
            ),
          if (_buyDropCtrl.text.isEmpty && _buyDropSuggestions.isEmpty)
            _buildQuickLocalityChips(
              onSelect: (addr) => setState(() {
                _buyDropCtrl.text = addr;
                _buyDropSuggestions = [];
              }),
            ),
          _buildAddressSuggestionList(
            suggestions: _buyDropSuggestions,
            isSearching: _isSearchingBuyDrop,
            onSelect: (s) {
              setState(() {
                _buyDropCtrl.text = s.fullAddress;
                _buyDropSuggestions = [];
              });
              FocusScope.of(context).unfocus();
            },
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
                  const Text('DELIVERY CHARGE ',
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
                _isPlacingOrder ? 'Placing Order...' : 'Confirm & Place Order  🛵',
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
                        subtitle: 'Broadcasted to ZIPPO Rider Pool',
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
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(24),
        color: const Color(0xFFF8FAFC),
        child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset(
              'assets/logo.png',
              cacheWidth: 150,
              cacheHeight: 150,
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, stack) => Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF5DA441), Color(0xFF76C457), Color(0xFFBEF264)],
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.two_wheeler_rounded, size: 34, color: Color(0xFF0F172A)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Rider Partner Portal', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF0F172A))),
          const Text('ZIPPO Dispatch Partner', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
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
                const Text('PORTAL ACCESS PASSWORD (கடவுச்சொல்)',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF475569))),
                const SizedBox(height: 6),
                TextField(
                  controller: _riderLoginPasswordCtrl,
                  obscureText: _obscureRiderPassword,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  decoration: _cleanInputDecoration('Rider Passcode or Admin Key').copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureRiderPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                        size: 18,
                        color: const Color(0xFF64748B),
                      ),
                      onPressed: () => setState(() => _obscureRiderPassword = !_obscureRiderPassword),
                    ),
                  ),
                ),
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
                        : const Text('Access Dispatch Portal', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
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
          padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 26, 16, 20),
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
                      // Rider Notification Bell Icon with dynamic active fill color
                      GestureDetector(
                        onTap: () async {
                          await PreferencesService.markNotificationsAsRead();
                          final notifs = await PreferencesService.getInAppNotifications();
                          if (mounted) {
                            setState(() {
                              _inAppNotifications = notifs;
                              _showNotificationDrawer = !_showNotificationDrawer;
                            });
                          }
                        },
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: _hasUnreadNotifications
                                ? const Color(0xFF76C457).withOpacity(0.18)
                                : Colors.white.withOpacity(0.12),
                            border: Border.all(
                              color: _hasUnreadNotifications
                                  ? const Color(0xFF76C457)
                                  : Colors.white24,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _hasUnreadNotifications
                                ? Icons.notifications_active_rounded
                                : Icons.notifications_none_rounded,
                            color: _hasUnreadNotifications
                                ? const Color(0xFF76C457)
                                : const Color(0xFF94A3B8),
                            size: 17,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
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
                'Delivery Partner • ZIPPO Hub',
                style: TextStyle(
                  color: Color(0xFFA7DF92),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),

              // 4 Quick Metrics / Info Cards (Real-time data based on today's deliveries)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildRiderHeaderBadge(
                    icon: Icons.inventory_2_outlined,
                    title: 'Today Orders',
                    subtitle: '$_todayOrdersCount',
                    iconColor: const Color(0xFF76C457),
                  ),
                  _buildRiderHeaderBadge(
                    icon: Icons.payments_outlined,
                    title: 'Today Cash',
                    subtitle: '₹$_todayCashTotal',
                    iconColor: const Color(0xFF38BDF8),
                  ),
                  _buildRiderHeaderBadge(
                    icon: Icons.qr_code_2_rounded,
                    title: 'Today UPI',
                    subtitle: '₹$_todayUpiTotal',
                    iconColor: const Color(0xFFA78BFA),
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
                  onTap: () { setState(() => _riderTab = 'completed'); _syncRiderCompletedTrips(); },
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
                  'Order Pool (ZIPPO)',
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
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
                      icon: const Icon(Icons.cancel_outlined, size: 14),
                      label: const Text(
                        'Issue with order? Cancel & Move to Completed',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => _showRiderCancelTripDialog(),
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
                          Builder(
                            builder: (ctx) {
                              final status = (trip['status'] ?? 'DELIVERED').toString().toUpperCase();
                              final isCancelled = status == 'CANCELLED' || trip['isCancelled'] == true;
                              final isPending = status == 'PENDING' || status == 'ON_THE_WAY' || status == 'RIDER_ASSIGNED';

                              final badgeColor = isCancelled
                                  ? const Color(0xFFFEE2E2)
                                  : isPending
                                      ? const Color(0xFFFEF3C7)
                                      : const Color(0xFFE5F6DE);
                              final badgeTextColor = isCancelled
                                  ? const Color(0xFFDC2626)
                                  : isPending
                                      ? const Color(0xFFD97706)
                                      : const Color(0xFF3A642B);
                              final badgeText = isCancelled
                                  ? '❌ CANCELLED'
                                  : isPending
                                      ? '⏳ PENDING'
                                      : '✅ DELIVERED';

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: badgeColor,
                                  borderRadius: BorderRadius.circular(9999),
                                ),
                                child: Text(
                                  badgeText,
                                  style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: badgeTextColor),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      Builder(
                        builder: (ctx) {
                          final status = (trip['status'] ?? 'DELIVERED').toString().toUpperCase();
                          final isCancelled = status == 'CANCELLED' || trip['isCancelled'] == true;

                          return Text(
                            isCancelled ? '₹0 (Cancelled)' : '+₹${trip['fare']}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: isCancelled ? const Color(0xFFDC2626) : const Color(0xFF3A642B),
                              decoration: isCancelled ? TextDecoration.lineThrough : null,
                            ),
                          );
                        },
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
                      Builder(
                        builder: (ctx) {
                          final status = (trip['status'] ?? 'DELIVERED').toString().toUpperCase();
                          final isCancelled = status == 'CANCELLED' || trip['isCancelled'] == true;
                          final isPending = status == 'PENDING' || status == 'ON_THE_WAY' || status == 'RIDER_ASSIGNED';

                          if (isCancelled) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFFECACA)),
                              ),
                              child: Text(
                                trip['reason'] != null ? '⚠️ ${trip['reason']}' : '⚠️ Order Cancelled',
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                            );
                          }

                          if (isPending) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFFDE68A)),
                              ),
                              child: const Text(
                                '⏳ In Progress',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFD97706),
                                ),
                              ),
                            );
                          }

                          return Container(
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
                          );
                        },
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


// ─────────────────────────────────────────────────────────────────────────────
// MODERN 270° ANIMATED CALL & ORDER BUTTON
// Features: Animated pulsing call icon with curved 270° circular outline & text
// ─────────────────────────────────────────────────────────────────────────────
class Modern270CallOrderButton extends StatefulWidget {
  final VoidCallback onTap;
  const Modern270CallOrderButton({Key? key, required this.onTap}) : super(key: key);

  @override
  State<Modern270CallOrderButton> createState() => _Modern270CallOrderButtonState();
}

class _Modern270CallOrderButtonState extends State<Modern270CallOrderButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.94, end: 1.05).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut),
    );

    _glowAnimation = Tween<double>(begin: 4.0, end: 12.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animCtrl,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: GestureDetector(
            onTap: widget.onTap,
            child: SizedBox(
              width: 82,
              height: 82,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 270° Circular Outline with Curved Text (Not horizontal or vertical)
                  CustomPaint(
                    size: const Size(82, 82),
                    painter: _Circle270TextOutlinePainter(
                      glowRadius: _glowAnimation.value,
                    ),
                  ),

                  // Center Modern Phone Icon Button with Gradient and Glow
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF15803D), Color(0xFF76C457)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF15803D).withOpacity(0.45),
                          blurRadius: _glowAnimation.value,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.phone_in_talk_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Circle270TextOutlinePainter extends CustomPainter {
  final double glowRadius;

  _Circle270TextOutlinePainter({required this.glowRadius});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const radius = 35.0;

    // 270 degrees sweep angle in radians (1.5 * pi)
    // Starts at -135 degrees (-0.75 * pi) and sweeps 270 degrees to +135 degrees (+0.75 * pi)
    // Leaves bottom 90 degrees open!
    const startAngle = -math.pi * 0.75;
    const sweepAngle = math.pi * 1.5; // Exactly 270 degrees circular outline

    // 1. Draw glowing 270° Arc Outline Track
    final arcPaint = Paint()
      ..color = const Color(0xFF76C457)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, startAngle, sweepAngle, false, arcPaint);

    // 2. Draw Curved "★ CALL TO ORDER ★" Text along the 270° Circular Outline
    const text = '★ CALL TO ORDER ★';
    const textStyle = TextStyle(
      color: Color(0xFF0F172A),
      fontSize: 7.8,
      fontWeight: FontWeight.w900,
      letterSpacing: 0.5,
    );

    final angleStep = sweepAngle / (text.length + 1);

    for (int i = 0; i < text.length; i++) {
      final charAngle = startAngle + (i + 1) * angleStep;
      final x = center.dx + radius * math.cos(charAngle);
      final y = center.dy + radius * math.sin(charAngle);

      final textSpan = TextSpan(text: text[i], style: textStyle);
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      canvas.save();
      // Move to character position along the 270° circle
      canvas.translate(x, y);
      // Rotate upright along the circular curve tangent
      canvas.rotate(charAngle + math.pi / 2);
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _Circle270TextOutlinePainter oldDelegate) {
    return oldDelegate.glowRadius != glowRadius;
  }
}
