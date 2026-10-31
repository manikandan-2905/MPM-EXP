import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/order_model.dart';
import '../../models/rider_model.dart';
import '../../services/api_service.dart';

class AdminRiderHistoryScreen extends StatefulWidget {
  const AdminRiderHistoryScreen({Key? key}) : super(key: key);

  @override
  State<AdminRiderHistoryScreen> createState() => _AdminRiderHistoryScreenState();
}

class _AdminRiderHistoryScreenState extends State<AdminRiderHistoryScreen> {
  final ApiService _apiService = ApiService();
  List<OrderModel> _allHistory = [];
  List<RiderModel> _riders = [];
  bool _isLoading = true;

  // Advanced Filters
  String _searchQuery = '';
  String _selectedRiderId = 'all';
  String _selectedStatus = 'all'; // 'all', 'DELIVERED', 'CANCELLED'
  String _selectedTimeRange = 'all'; // 'all', 'today', 'yesterday', 'week', 'month', 'custom_month'
  String _selectedSort = 'newest'; // 'newest', 'oldest', 'fare_high'
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final ridersFuture = _apiService.getAdminRiders();
      final historyFuture = _apiService.getAdminRiderHistory(
        riderId: _selectedRiderId == 'all' ? null : _selectedRiderId,
        status: _selectedStatus == 'all' ? null : _selectedStatus,
      );

      final results = await Future.wait([ridersFuture, historyFuture]);

      if (mounted) {
        setState(() {
          _riders = results[0] as List<RiderModel>;
          _allHistory = results[1] as List<OrderModel>;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<OrderModel> get _filteredHistory {
    final now = DateTime.now();
    return _allHistory.where((order) {
      // Status
      if (_selectedStatus != 'all' && order.status != _selectedStatus) {
        return false;
      }
      // Rider
      if (_selectedRiderId != 'all') {
        final assignedId = order.assignedRiderId;
        if (assignedId != _selectedRiderId) return false;
      }
      // Time Range
      if (_selectedTimeRange == 'today') {
        final isToday = order.createdAt.year == now.year &&
            order.createdAt.month == now.month &&
            order.createdAt.day == now.day;
        if (!isToday) return false;
      } else if (_selectedTimeRange == 'yesterday') {
        final yesterday = now.subtract(const Duration(days: 1));
        final isYesterday = order.createdAt.year == yesterday.year &&
            order.createdAt.month == yesterday.month &&
            order.createdAt.day == yesterday.day;
        if (!isYesterday) return false;
      } else if (_selectedTimeRange == 'week') {
        final diff = now.difference(order.createdAt).inDays;
        if (diff > 7) return false;
      } else if (_selectedTimeRange == 'month') {
        final isThisMonth = order.createdAt.year == now.year &&
            order.createdAt.month == now.month;
        if (!isThisMonth) return false;
      } else if (_selectedTimeRange == 'custom_month') {
        final isCustomMonth = order.createdAt.year == _selectedYear &&
            order.createdAt.month == _selectedMonth;
        if (!isCustomMonth) return false;
      }
      // Search query
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchNum = order.orderNumber.toLowerCase().contains(q);
        final matchCust = order.customerName.toLowerCase().contains(q);
        final matchPhone = order.customerPhone.contains(q);
        final matchRider = (order.riderName ?? '').toLowerCase().contains(q);
        final matchDrop = order.dropAddress.toLowerCase().contains(q);
        if (!matchNum && !matchCust && !matchPhone && !matchRider && !matchDrop) {
          return false;
        }
      }
      return true;
    }).toList()
      ..sort((a, b) {
        if (_selectedSort == 'fare_high') return b.fare.compareTo(a.fare);
        if (_selectedSort == 'oldest') return a.createdAt.compareTo(b.createdAt);
        return b.createdAt.compareTo(a.createdAt);
      });
  }

  String _getMonthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[(month - 1).clamp(0, 11)];
  }

  Future<void> _pickParticularMonth() async {
    int tempMonth = _selectedMonth;
    int tempYear = _selectedYear;

    final picked = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.calendar_month_rounded, color: Color(0xFF0284C7)),
              SizedBox(width: 8),
              Text('Select Particular Month', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Filter all delivery orders, cash and UPI collections by month.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<int>(
                      value: tempMonth,
                      decoration: InputDecoration(
                        labelText: 'Month',
                        labelStyle: const TextStyle(fontSize: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      items: List.generate(12, (i) => i + 1).map((m) {
                        return DropdownMenuItem<int>(
                          value: m,
                          child: Text(_getMonthName(m), style: const TextStyle(fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDlgState(() => tempMonth = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<int>(
                      value: tempYear,
                      decoration: InputDecoration(
                        labelText: 'Year',
                        labelStyle: const TextStyle(fontSize: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      items: [2025, 2026, 2027].map((y) {
                        return DropdownMenuItem<int>(
                          value: y,
                          child: Text('$y', style: const TextStyle(fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDlgState(() => tempYear = val);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apply Filter'),
            ),
          ],
        ),
      ),
    );

    if (picked == true) {
      setState(() {
        _selectedMonth = tempMonth;
        _selectedYear = tempYear;
        _selectedTimeRange = 'custom_month';
      });
      _fetchData();
    }
  }

  Future<void> _callPhone(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    final url = Uri.parse('tel:$clean');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredHistory;
    final deliveredOnly = filtered.where((o) => o.status == 'DELIVERED').toList();
    final cancelledOnly = filtered.where((o) => o.status == 'CANCELLED').toList();
    final totalEarned = deliveredOnly.fold<int>(0, (sum, o) => sum + o.fare);
    final cashEarned = deliveredOnly
        .where((o) => o.paymentMode.toUpperCase() != 'UPI')
        .fold<int>(0, (sum, o) => sum + o.fare);
    final upiEarned = deliveredOnly
        .where((o) => o.paymentMode.toUpperCase() == 'UPI')
        .fold<int>(0, (sum, o) => sum + o.fare);
    final avgFare = deliveredOnly.isNotEmpty ? (totalEarned / deliveredOnly.length).round() : 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          // Header Filter Bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            color: Colors.white,
            child: Column(
              children: [
                // Summary Stats Row & Collection Breakdown
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.history_edu_rounded, size: 16, color: Color(0xFF15803D)),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${filtered.length} ARCHIVED TRIPS',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF0F172A)),
                        ),
                      ],
                    ),
                    Text(
                      'Total: ₹$totalEarned',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF15803D)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Financial Collection Breakdown Chips (Total Volume, Cash Handover, UPI Received)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Text('💵 Cash Handover', style: TextStyle(fontSize: 10, color: Color(0xFFB45309), fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text('₹$cashEarned', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFFB45309))),
                        ],
                      ),
                      Container(width: 1, height: 24, color: const Color(0xFFCBD5E1)),
                      Column(
                        children: [
                          const Text('📱 UPI Received', style: TextStyle(fontSize: 10, color: Color(0xFF1D4ED8), fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text('₹$upiEarned', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF1D4ED8))),
                        ],
                      ),
                      Container(width: 1, height: 24, color: const Color(0xFFCBD5E1)),
                      Column(
                        children: [
                          Text('Delivered / Cancel', style: const TextStyle(fontSize: 10, color: Color(0xFF475569), fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text('${deliveredOnly.length} / ${cancelledOnly.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Search Box
                Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Search archive by Order #, Customer, Rider, Landmark...',
                      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                      prefixIcon: const Icon(Icons.search, size: 16, color: Color(0xFF64748B)),
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
                      contentPadding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  ),
                ),
                const SizedBox(height: 8),

                // Dropdown Filters Row
                Row(
                  children: [
                    // Rider Selector
                    Expanded(
                      flex: 3,
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedRiderId,
                            isExpanded: true,
                            icon: const Icon(Icons.arrow_drop_down, size: 18),
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            items: [
                              const DropdownMenuItem(value: 'all', child: Text('All Fleet Riders')),
                              ..._riders.map((r) => DropdownMenuItem(value: r.id, child: Text(r.name))),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedRiderId = val);
                                _fetchData();
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Status Selector
                    Expanded(
                      flex: 2,
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedStatus,
                            isExpanded: true,
                            icon: const Icon(Icons.arrow_drop_down, size: 18),
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('All Status')),
                              DropdownMenuItem(value: 'DELIVERED', child: Text('Delivered')),
                              DropdownMenuItem(value: 'CANCELLED', child: Text('Cancelled')),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedStatus = val);
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Time Range Selector with Custom Month Picker
                    Expanded(
                      flex: 3,
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedTimeRange,
                            isExpanded: true,
                            icon: const Icon(Icons.arrow_drop_down, size: 18),
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                            items: [
                              const DropdownMenuItem(value: 'all', child: Text('All Time')),
                              const DropdownMenuItem(value: 'today', child: Text('Today (Day)')),
                              const DropdownMenuItem(value: 'yesterday', child: Text('Yesterday')),
                              const DropdownMenuItem(value: 'week', child: Text('This Week')),
                              const DropdownMenuItem(value: 'month', child: Text('This Month')),
                              DropdownMenuItem(
                                value: 'custom_month',
                                child: Text('📅 ${_getMonthName(_selectedMonth).substring(0, 3)} $_selectedYear'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val == 'custom_month') {
                                _pickParticularMonth();
                              } else if (val != null) {
                                setState(() => _selectedTimeRange = val);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // History List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0284C7)))
                : filtered.isEmpty
                    ? RefreshIndicator(
                        onRefresh: _fetchData,
                        child: ListView(
                          padding: const EdgeInsets.all(32),
                          children: const [
                            SizedBox(height: 60),
                            Center(child: Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFF94A3B8))),
                            SizedBox(height: 16),
                            Text(
                              'No Matching Closed Trips',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF0F172A)),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Delivered and cancelled trips move automatically into this history archive.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetchData,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final order = filtered[index];
                            return _buildModernHistoryCard(order);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernHistoryCard(OrderModel order) {
    final isDelivered = order.status == 'DELIVERED';
    final hasRider = order.assignedRider != null && order.riderName != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDelivered ? const Color(0xFFE2E8F0) : const Color(0xFFFECACA)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDelivered ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDelivered ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isDelivered ? Icons.check_circle_rounded : Icons.cancel_rounded,
                            size: 12,
                            color: isDelivered ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isDelivered ? 'DELIVERED' : 'CANCELLED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: isDelivered ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('#${order.orderNumber}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF0F172A))),
                  ],
                ),
                Text(
                  '₹${order.fare}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: isDelivered ? const Color(0xFF15803D) : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Rider Section
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: isDelivered ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.two_wheeler_rounded, size: 18, color: isDelivered ? const Color(0xFF2563EB) : const Color(0xFF94A3B8)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasRider ? 'Fulfilled by: ${order.riderName}' : 'No Rider Assigned',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: Color(0xFF0F172A)),
                          ),
                          if (hasRider && order.riderPhone != null)
                            Text(order.riderPhone!, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                        ],
                      ),
                    ),
                    if (hasRider && order.riderPhone != null)
                      IconButton(
                        icon: const Icon(Icons.phone_rounded, size: 18, color: Color(0xFF0284C7)),
                        onPressed: () => _callPhone(order.riderPhone),
                        tooltip: 'Call Rider',
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // Customer & Drop Address
                Text(
                  'Customer: ${order.customerName} (${order.customerPhone})',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                ),
                const SizedBox(height: 4),
                Text('Delivery Landmark: ${order.dropAddress}', style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                if (order.itemsList.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Items: ${order.itemsList.join(", ")}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                ],
                const SizedBox(height: 8),

                // Footer with Date & PIN verification status
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDate(order.createdAt),
                      style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                    ),
                    if (isDelivered)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: order.isOtpBypassed ? const Color(0xFFFEF3C7) : const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          order.isOtpBypassed ? '⚠️ Emergency Bypass' : '🔒 Verified PIN',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: order.isOtpBypassed ? const Color(0xFFB45309) : const Color(0xFF15803D),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
