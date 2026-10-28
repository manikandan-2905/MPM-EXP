import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/order_model.dart';
import '../../models/rider_model.dart';
import '../../services/api_service.dart';
import '../../services/preferences_service.dart';
import 'rider_active_order_screen.dart';

class RiderDashboardScreen extends StatefulWidget {
  final String riderId;
  final String initialName;
  final String initialPhone;

  const RiderDashboardScreen({
    Key? key,
    required this.riderId,
    required this.initialName,
    required this.initialPhone,
  }) : super(key: key);

  @override
  State<RiderDashboardScreen> createState() => _RiderDashboardScreenState();
}

class _RiderDashboardScreenState extends State<RiderDashboardScreen> {
  final ApiService _apiService = ApiService();

  RiderModel? _rider;
  bool _isOnline = false;
  bool _isTogglingOnline = false;

  OrderModel? _activeOrder;
  List<OrderModel> _availablePoolOrders = [];
  bool _isLoadingPool = true;
  Timer? _poolTimer;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    // Poll available orders pool every 10 seconds
    _poolTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_isOnline) {
        _fetchAvailablePool();
        _checkActiveOrder();
      }
    });
  }

  @override
  void dispose() {
    _poolTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    await _fetchRiderProfile();
    await _checkActiveOrder();
    await _fetchAvailablePool();
  }

  Future<void> _fetchRiderProfile() async {
    try {
      final rider = await _apiService.getRiderProfile(widget.riderId);
      if (mounted) {
        setState(() {
          _rider = rider;
          _isOnline = rider.isOnline;
        });
      }
    } catch (_) {}
  }

  Future<void> _checkActiveOrder() async {
    try {
      final activeOrder = await _apiService.getRiderActiveOrder(widget.riderId);
      if (mounted) {
        setState(() => _activeOrder = activeOrder);
      }
    } catch (_) {}
  }

  Future<void> _fetchAvailablePool() async {
    try {
      final list = await _apiService.getAvailableOrders();
      if (mounted) {
        setState(() {
          _availablePoolOrders = list;
          _isLoadingPool = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingPool = false);
    }
  }

  Future<void> _toggleOnline(bool value) async {
    setState(() => _isTogglingOnline = true);
    try {
      final status = await _apiService.toggleOnlineStatus(widget.riderId, value);
      setState(() {
        _isOnline = status;
        _isTogglingOnline = false;
      });
      if (_isOnline) {
        _fetchAvailablePool();
      }
    } catch (e) {
      setState(() => _isTogglingOnline = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<void> _claimOrder(OrderModel order) async {
    try {
      // Atomic claim call
      final claimedOrder = await _apiService.claimOrder(order.id, widget.riderId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order #${order.orderNumber} locked for you!'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RiderActiveOrderScreen(
            order: claimedOrder,
            riderId: widget.riderId,
          ),
        ),
      ).then((_) => _loadDashboardData());
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
      _fetchAvailablePool();
    }
  }

  void _logout() async {
    await PreferencesService.clearRiderSession();
    if (mounted) {
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _rider?.name ?? widget.initialName,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Text(
              'Melapalayam Dispatch Rider',
              style: TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadDashboardData,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Online/Offline Availability Switch Card
            _buildAvailabilityCard(),

            const SizedBox(height: 16),

            // Rider Statistics (Earnings & Completed Trips)
            _buildStatisticsRow(),

            const SizedBox(height: 20),

            // Active In-Progress Order Banner (if any)
            if (_activeOrder != null) ...[
              _buildActiveOrderBanner(),
              const SizedBox(height: 20),
            ],

            // Available Orders Pool
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Available Orders Pool',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_availablePoolOrders.length} Open',
                    style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (!_isOnline)
              _buildOfflineWarning()
            else if (_isLoadingPool)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: Color(0xFF10B981)),
                ),
              )
            else if (_availablePoolOrders.isEmpty)
              _buildEmptyPoolPlaceholder()
            else
              ..._availablePoolOrders.map((order) => _buildPoolOrderCard(order)),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildAvailabilityCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _isOnline ? const Color(0xFF064E3B) : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isOnline ? const Color(0xFF10B981) : Colors.white12,
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isOnline ? const Color(0xFF34D399) : Colors.redAccent,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isOnline ? 'Rider Status: ONLINE 🟢' : 'Rider Status: OFFLINE 🔴',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Text(
                    _isOnline ? 'Receiving Melapalayam order requests' : 'Switch ON to accept deliveries',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          _isTogglingOnline
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Switch(
                  value: _isOnline,
                  activeColor: const Color(0xFF10B981),
                  onChanged: _toggleOnline,
                ),
        ],
      ),
    );
  }

  Widget _buildStatisticsRow() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total Trips', style: TextStyle(color: Colors.white60, fontSize: 12)),
                const SizedBox(height: 6),
                Text(
                  '${_rider?.totalDeliveries ?? 0}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total Earnings', style: TextStyle(color: Colors.white60, fontSize: 12)),
                const SizedBox(height: 6),
                Text(
                  '₹${_rider?.totalEarnings ?? 0}',
                  style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 22),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveOrderBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F362A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF10B981)),
      ),
      child: Row(
        children: [
          const Icon(Icons.delivery_dining, color: Color(0xFF10B981), size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Active Order in Progress',
                  style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  'Order #${_activeOrder!.orderNumber} • ${_activeOrder!.status.replaceAll('_', ' ')}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RiderActiveOrderScreen(
                    order: _activeOrder!,
                    riderId: widget.riderId,
                  ),
                ),
              ).then((_) => _loadDashboardData());
            },
            child: const Text('Resume', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineWarning() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Center(
        child: Text(
          'You are currently OFFLINE. Toggle the switch above to go ONLINE and view available orders.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildEmptyPoolPlaceholder() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: const [
          Icon(Icons.inbox_outlined, color: Colors.white38, size: 40),
          SizedBox(height: 10),
          Text(
            'No open orders in Melapalayam right now.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          SizedBox(height: 4),
          Text(
            'Keep your app open and notifications active.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildPoolOrderCard(OrderModel order) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: order.isUrgent ? Colors.amber.withOpacity(0.6) : Colors.white.withOpacity(0.08),
          width: order.isUrgent ? 1.5 : 1,
        ),
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
                    order.orderNumber,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  if (order.isUrgent) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.amber, width: 0.8),
                      ),
                      child: const Text('⚡ URGENT', style: TextStyle(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
              Text(
                '₹${order.fare}',
                style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            order.orderType == 'PICKUP_DROP'
                ? '📦 Pickup & Drop: ${order.category}'
                : '🛒 Buy For Me: ${order.shopName ?? "Market"} (Budget: ₹${order.budget})',
            style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 8),
          _buildCompactAddress('From', order.pickupAddress),
          const SizedBox(height: 4),
          _buildCompactAddress('To', order.dropAddress),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.lock_open, size: 18, color: Colors.white),
              label: const Text(
                'Accept & Pick Order',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              onPressed: () => _claimOrder(order),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactAddress(String prefix, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$prefix: ', style: const TextStyle(color: Colors.white54, fontSize: 11)),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
