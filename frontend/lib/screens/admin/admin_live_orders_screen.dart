import 'dart:async';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/order_model.dart';
import '../../models/rider_model.dart';
import '../../services/api_service.dart';

class AdminLiveOrdersScreen extends StatefulWidget {
  final Function(int targetTab)? onSwitchTab;
  const AdminLiveOrdersScreen({Key? key, this.onSwitchTab}) : super(key: key);

  @override
  State<AdminLiveOrdersScreen> createState() => _AdminLiveOrdersScreenState();
}

class _AdminLiveOrdersScreenState extends State<AdminLiveOrdersScreen> {
  final ApiService _apiService = ApiService();
  List<OrderModel> _liveOrders = [];
  List<RiderModel> _riders = [];
  bool _isLoading = true;
  Timer? _pollingTimer;
  DateTime _lastSyncTime = DateTime.now();

  // Advanced Filtering State
  String _searchQuery = '';
  String _selectedStatusFilter = 'ALL'; // 'ALL', 'ORDER_PLACED', 'RIDER_ASSIGNED', 'ITEM_PURCHASED', 'ON_THE_WAY'
  String _selectedTypeFilter = 'ALL'; // 'ALL', 'PICKUP_DROP', 'BUY_FOR_ME'
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchData();
    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _fetchData(isSilent: true);
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchData({bool isSilent = false}) async {
    if (!isSilent) setState(() => _isLoading = true);
    try {
      final ordersFuture = _apiService.getAdminLiveOrders();
      final ridersFuture = _apiService.getAdminRiders();

      final results = await Future.wait([ordersFuture, ridersFuture]);

      if (mounted) {
        setState(() {
          _liveOrders = results[0] as List<OrderModel>;
          _riders = results[1] as List<RiderModel>;
          _isLoading = false;
          _lastSyncTime = DateTime.now();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<OrderModel> get _filteredOrders {
    return _liveOrders.where((order) {
      // Status filter
      if (_selectedStatusFilter != 'ALL' && order.status != _selectedStatusFilter) {
        return false;
      }
      // Type filter
      if (_selectedTypeFilter != 'ALL' && order.orderType != _selectedTypeFilter) {
        return false;
      }
      // Search query
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchNum = order.orderNumber.toLowerCase().contains(q);
        final matchCust = order.customerName.toLowerCase().contains(q);
        final matchPhone = order.customerPhone.contains(q);
        final matchRider = (order.riderName ?? '').toLowerCase().contains(q);
        final matchDrop = order.dropAddress.toLowerCase().contains(q);
        final matchPickup = order.pickupAddress.toLowerCase().contains(q);
        if (!matchNum && !matchCust && !matchPhone && !matchRider && !matchDrop && !matchPickup) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Future<void> _callPhone(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    final url = Uri.parse('tel:$clean');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _launchWhatsApp(String? phone, String text) async {
    if (phone == null || phone.isEmpty) return;
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    final encoded = Uri.encodeComponent(text);
    final url = Uri.parse('https://wa.me/91$clean?text=$encoded');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _launchMaps(String address) async {
    final encoded = Uri.encodeComponent(address);
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$encoded');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  // Quick Action: Admin Assign Rider dialog
  Future<void> _showAssignRiderDialog(OrderModel order) async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Assign Dispatch Rider',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                  ),
                  Text('#${order.orderNumber}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Select an authorized rider to assign this live dispatch trip:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              const SizedBox(height: 14),
              ..._riders.map((r) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: r.isOnline ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                      child: Icon(Icons.two_wheeler, color: r.isOnline ? const Color(0xFF15803D) : const Color(0xFF94A3B8), size: 18),
                    ),
                    title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    subtitle: Text('${r.phone} • ${r.isOnline ? "Online" : "Offline"}', style: const TextStyle(fontSize: 11)),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _apiService.adminAdvanceOrder(order, 'RIDER_ASSIGNED', rider: r);
                        _fetchData();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Order #${order.orderNumber} assigned to ${r.name}!'), backgroundColor: const Color(0xFF059669)),
                        );
                      },
                      child: const Text('Assign', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  // Quick Action: Advance Milestone directly from Admin
  Future<void> _advanceOrderMilestone(OrderModel order, String newStatus) async {
    await _apiService.adminAdvanceOrder(order, newStatus);
    _fetchData();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(newStatus == 'DELIVERED'
            ? 'Order #${order.orderNumber} DELIVERED! Moved to Rider History.'
            : 'Order #${order.orderNumber} updated to $newStatus'),
        backgroundColor: newStatus == 'DELIVERED' ? const Color(0xFF059669) : const Color(0xFF0284C7),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredOrders;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          // Top Control Bar: Search & Status Count
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            color: Colors.white,
            child: Column(
              children: [
                // Live Indicator Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: const Color(0xFF10B981).withOpacity(0.6), blurRadius: 6, spreadRadius: 2),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_liveOrders.length} LIVE ORDERS MONITORED',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: 0.3),
                        ),
                      ],
                    ),
                    Text(
                      'Synced ${_timeAgo(_lastSyncTime)}',
                      style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Search Bar
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      hintText: 'Search by Order #, Customer, Rider, Landmark...',
                      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                      prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF64748B)),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  ),
                ),
                const SizedBox(height: 10),

                // Horizontal Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('ALL', 'All Live (${_liveOrders.length})'),
                      const SizedBox(width: 6),
                      _buildFilterChip('ORDER_PLACED', '🟡 Open in Pool (${_countStatus("ORDER_PLACED")})'),
                      const SizedBox(width: 6),
                      _buildFilterChip('RIDER_ASSIGNED', '🔵 Picked by Rider (${_countStatus("RIDER_ASSIGNED")})'),
                      const SizedBox(width: 6),
                      _buildFilterChip('ITEM_PURCHASED', '🟣 Items Picked (${_countStatus("ITEM_PURCHASED")})'),
                      const SizedBox(width: 6),
                      _buildFilterChip('ON_THE_WAY', '🚀 Out for Delivery (${_countStatus("ON_THE_WAY")})'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Main Live Cards List
          Expanded(
            child: _isLoading && _liveOrders.isEmpty
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0284C7)))
                : filtered.isEmpty
                    ? RefreshIndicator(
                        onRefresh: () => _fetchData(),
                        color: const Color(0xFF0284C7),
                        child: ListView(
                          padding: const EdgeInsets.all(32),
                          children: [
                            const SizedBox(height: 50),
                            Center(
                              child: Container(
                                width: 72,
                                height: 72,
                                decoration: const BoxDecoration(color: Color(0xFFEFF6FF), shape: BoxShape.circle),
                                child: const Icon(Icons.radar_rounded, size: 38, color: Color(0xFF0284C7)),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No Matching Live Orders',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Any placed order appears here live and tracks which rider is picked. When delivered or closed, it moves to Rider History.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            ),
                            const SizedBox(height: 20),
                            Center(
                              child: ElevatedButton.icon(
                                onPressed: () => widget.onSwitchTab?.call(2),
                                icon: const Icon(Icons.history_rounded, size: 16),
                                label: const Text('View Delivered Rider History'),
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7), foregroundColor: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _fetchData(),
                        color: const Color(0xFF0284C7),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final order = filtered[index];
                            return _buildModernLiveCard(order);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  int _countStatus(String st) => _liveOrders.where((o) => o.status == st).length;

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _selectedStatusFilter == key;
    return InkWell(
      onTap: () => setState(() => _selectedStatusFilter = key),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0284C7) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _buildModernLiveCard(OrderModel order) {
    final hasRider = order.assignedRider != null && order.riderName != null;
    final isPickup = order.orderType == 'PICKUP_DROP';

    Color statusColor;
    String statusTitle;
    switch (order.status) {
      case 'ORDER_PLACED':
        statusColor = const Color(0xFFEAB308);
        statusTitle = 'Open Pool (Awaiting Rider)';
        break;
      case 'RIDER_ASSIGNED':
        statusColor = const Color(0xFF0284C7);
        statusTitle = 'Rider Picked (Heading to pickup)';
        break;
      case 'ITEM_PURCHASED':
        statusColor = const Color(0xFF8B5CF6);
        statusTitle = 'Items Picked / Purchased';
        break;
      case 'ON_THE_WAY':
        statusColor = const Color(0xFF10B981);
        statusTitle = 'Out for Delivery to Landmark';
        break;
      default:
        statusColor = const Color(0xFF64748B);
        statusTitle = order.status;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasRider ? const Color(0xFFBAE6FD) : const Color(0xFFFDE68A),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Order Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.08),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        isPickup ? 'PICKUP & DROP' : 'BUY FOR ME',
                        style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '#${order.orderNumber}',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF0F172A)),
                    ),
                  ],
                ),
                Text(
                  '₹${order.fare}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF0F172A)),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Milestone Progress Bar
                _buildMilestoneProgressBar(order.status),
                const SizedBox(height: 12),

                // Current Milestone Status Highlight
                Row(
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        statusTitle,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: statusColor),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        'PIN: ${order.deliveryPin}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF0F172A), letterSpacing: 1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // WHICH RIDER IS PICKED HIGHLIGHT CARD
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: hasRider ? const Color(0xFFF0F9FF) : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: hasRider ? const Color(0xFFBAE6FD) : const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: hasRider ? const Color(0xFF0284C7) : const Color(0xFFF59E0B),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          hasRider ? Icons.two_wheeler_rounded : Icons.hourglass_top_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              hasRider ? 'PICKED BY DISPATCH RIDER' : 'RIDER STATUS',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                color: hasRider ? const Color(0xFF0369A1) : const Color(0xFFB45309),
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              hasRider ? '${order.riderName}' : 'Waiting for rider in pool...',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF0F172A)),
                            ),
                            if (hasRider && order.riderPhone != null)
                              Text(order.riderPhone!, style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
                          ],
                        ),
                      ),
                      if (hasRider && order.riderPhone != null) ...[
                        IconButton(
                          icon: const Icon(Icons.phone, size: 18, color: Color(0xFF0284C7)),
                          onPressed: () => _callPhone(order.riderPhone),
                          tooltip: 'Call Rider',
                        ),
                        IconButton(
                          icon: const Icon(Icons.chat_bubble_outline, size: 18, color: Color(0xFF10B981)),
                          onPressed: () => _launchWhatsApp(
                            order.riderPhone,
                            'Hello ${order.riderName}, regarding live order #${order.orderNumber} for ${order.customerName}.',
                          ),
                          tooltip: 'WhatsApp Rider',
                        ),
                      ] else ...[
                        ElevatedButton.icon(
                          onPressed: () => _showAssignRiderDialog(order),
                          icon: const Icon(Icons.person_add, size: 14),
                          label: const Text('Assign', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0284C7),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Customer & Locations
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.person_pin_circle_rounded, size: 16, color: Color(0xFF64748B)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Customer: ${order.customerName} (${order.customerPhone})',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
                      ),
                    ),
                    InkWell(
                      onTap: () => _callPhone(order.customerPhone),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.phone_in_talk_rounded, size: 16, color: Color(0xFF10B981)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFFEF4444)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Drop: ${order.dropAddress}',
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: () => _launchMaps(order.dropAddress),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.directions_rounded, size: 18, color: Color(0xFF0284C7)),
                      ),
                    ),
                  ],
                ),
                if (order.itemsList.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.shopping_bag_outlined, size: 16, color: Color(0xFF64748B)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Items: ${order.itemsList.join(", ")}',
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),

                // Interactive Admin Milestone Control (Advances trip & closes to history)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'ADMIN DISPATCH ACTIONS:',
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Color(0xFF64748B)),
                      ),
                      Row(
                        children: [
                          if (!hasRider)
                            TextButton(
                              onPressed: () => _showAssignRiderDialog(order),
                              child: const Text('+ Pick Rider', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
                            ),
                          if (order.status == 'RIDER_ASSIGNED')
                            TextButton(
                              onPressed: () => _advanceOrderMilestone(order, 'ITEM_PURCHASED'),
                              child: const Text('Mark Picked', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6))),
                            ),
                          if (order.status == 'ITEM_PURCHASED')
                            TextButton(
                              onPressed: () => _advanceOrderMilestone(order, 'ON_THE_WAY'),
                              child: const Text('Mark On Way', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
                            ),
                          if (order.status == 'ON_THE_WAY' || order.status == 'RIDER_ASSIGNED' || order.status == 'ITEM_PURCHASED')
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                              ),
                              onPressed: () => _advanceOrderMilestone(order, 'DELIVERED'),
                              child: const Text('Close & Deliver ✓', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Action Bar: Track Everything Button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showOrderTrackingDetails(order),
                    icon: const Icon(Icons.visibility_rounded, size: 16),
                    label: const Text('Track Full Live Order Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0F172A),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMilestoneProgressBar(String status) {
    int currentStep = 0;
    if (status == 'ORDER_PLACED') currentStep = 1;
    if (status == 'RIDER_ASSIGNED') currentStep = 2;
    if (status == 'ITEM_PURCHASED') currentStep = 3;
    if (status == 'ON_THE_WAY') currentStep = 4;
    if (status == 'DELIVERED') currentStep = 5;

    return Row(
      children: [
        _buildStepPill(1, 'Placed', currentStep >= 1),
        _buildStepDivider(currentStep >= 2),
        _buildStepPill(2, 'Assigned', currentStep >= 2),
        _buildStepDivider(currentStep >= 3),
        _buildStepPill(3, 'Picked', currentStep >= 3),
        _buildStepDivider(currentStep >= 4),
        _buildStepPill(4, 'On Way', currentStep >= 4),
      ],
    );
  }

  Widget _buildStepPill(int step, String label, bool isDone) {
    return Expanded(
      child: Column(
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: isDone ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: isDone ? FontWeight.w800 : FontWeight.w500,
              color: isDone ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepDivider(bool isDone) {
    return Container(width: 4, height: 4, margin: const EdgeInsets.symmetric(horizontal: 2));
  }

  void _showOrderTrackingDetails(OrderModel order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildOrderTrackingModal(order),
    );
  }

  Widget _buildOrderTrackingModal(OrderModel order) {
    final hasRider = order.assignedRider != null && order.riderName != null;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Live Tracking: #${order.orderNumber}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                    Text('Created ${_formatTime(order.createdAt)}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                  ],
                ),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ASSIGNED RIDER INFORMATION', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Color(0xFF0284C7))),
                      const SizedBox(height: 10),
                      if (hasRider) ...[
                        Row(
                          children: [
                            const CircleAvatar(backgroundColor: Color(0xFF0284C7), child: Icon(Icons.person, color: Colors.white)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(order.riderName!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                                  Text(order.riderPhone ?? '', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                                ],
                              ),
                            ),
                            if (order.riderPhone != null)
                              IconButton.filled(
                                onPressed: () => _callPhone(order.riderPhone),
                                icon: const Icon(Icons.phone, size: 18),
                                style: IconButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                              ),
                          ],
                        ),
                      ] else ...[
                        const Text('No rider has accepted this order yet. Waiting in ZIPPO open rider pool.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('CUSTOMER & DROP INFORMATION', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: Color(0xFF64748B))),
                      const SizedBox(height: 8),
                      Text('Customer Name: ${order.customerName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Customer Phone: ${order.customerPhone}'),
                          TextButton.icon(
                            onPressed: () => _callPhone(order.customerPhone),
                            icon: const Icon(Icons.phone, size: 14),
                            label: const Text('Call'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Pickup Address: ${order.pickupAddress}'),
                      const SizedBox(height: 4),
                      Text('Drop Address: ${order.dropAddress}'),
                      const SizedBox(height: 8),
                      Text('Customer PIN: ${order.deliveryPin}', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF10B981))),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () {
                    final ticket =
                        '🛵 *ZIPPO DISPATCH*\nOrder: #${order.orderNumber}\nCustomer: ${order.customerName} (${order.customerPhone})\nPickup: ${order.pickupAddress}\nDrop: ${order.dropAddress}\nFare: ₹${order.fare}\nStatus: ${order.status}';
                    Share.share(ticket);
                  },
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: const Text('Share Dispatch Alert to WhatsApp'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 10) return 'Just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    return '${diff.inMinutes}m ago';
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '$hour:$min $period';
  }
}
