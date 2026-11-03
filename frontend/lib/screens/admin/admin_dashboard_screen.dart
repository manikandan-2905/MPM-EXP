import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  final Function(int targetTab)? onSwitchTab;
  const AdminDashboardScreen({Key? key, this.onSwitchTab}) : super(key: key);

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _dashboardData;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchStats();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _fetchStats(isSilent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchStats({bool isSilent = false}) async {
    if (!isSilent) setState(() => _isLoading = true);
    try {
      final data = await _apiService.getAdminDashboard();
      if (mounted) {
        setState(() {
          _dashboardData = data;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_dashboardData == null) {
            _error = e.toString().replaceAll('Exception: ', '');
          }
        });
      }
    }
  }

  Future<void> _callPhone(String phone) async {
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    final url = Uri.parse('tel:$clean');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _dashboardData == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0284C7)),
      );
    }

    if (_error != null && _dashboardData == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF475569))),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _fetchStats(),
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
              ),
            ],
          ),
        ),
      );
    }

    final stats = _dashboardData?['stats'] as Map<String, dynamic>? ?? {};
    final riders = (_dashboardData?['riders'] as List<dynamic>?) ?? [];

    final liveCount = stats['liveOrdersCount'] ?? 0;
    final totalOrders = stats['totalOrders'] ?? 0;
    final deliveredCount = stats['deliveredOrdersCount'] ?? 0;
    final totalRevenue = stats['totalRevenue'] ?? 0;
    final onlineRiders = stats['onlineRidersCount'] ?? 0;
    final totalRiders = stats['totalRiders'] ?? riders.length;
    final todayOrders = stats['todayOrdersCount'] ?? 0;
    final todayRevenue = stats['todayRevenue'] ?? 0;

    return RefreshIndicator(
      onRefresh: () => _fetchStats(),
      color: const Color(0xFF0284C7),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // Banner: Live Status Overview
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF334155)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
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
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF10B981).withOpacity(0.6),
                                blurRadius: 6,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'SYSTEM MONITORING LIVE',
                          style: TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white70, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _fetchStats(),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'ZIPPO Dispatch Command',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Real-time overview of active deliveries, riders on duty, and system performance.',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4 Grid Metric Cards
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: 'Live Orders',
                  value: '$liveCount',
                  subtitle: 'In dispatch progress',
                  icon: Icons.delivery_dining_rounded,
                  accentColor: const Color(0xFFF59E0B),
                  onTap: () => widget.onSwitchTab?.call(1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  title: 'Delivered',
                  value: '$deliveredCount',
                  subtitle: 'Completed trips',
                  icon: Icons.check_circle_rounded,
                  accentColor: const Color(0xFF10B981),
                  onTap: () => widget.onSwitchTab?.call(2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: 'Active Riders',
                  value: '$onlineRiders / $totalRiders',
                  subtitle: onlineRiders == 0 ? 'All riders offline' : '$onlineRiders online on duty',
                  icon: Icons.two_wheeler_rounded,
                  accentColor: const Color(0xFF0284C7),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  title: 'Total Revenue',
                  value: '₹$totalRevenue',
                  subtitle: 'Delivered volume',
                  icon: Icons.account_balance_wallet_rounded,
                  accentColor: const Color(0xFF8B5CF6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Cash vs UPI Collections Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.payments_rounded, size: 18, color: Color(0xFF059669)),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          "Revenue & Collections Breakdown",
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Color(0xFF0F172A)),
                        ),
                      ],
                    ),
                    Text(
                      '₹$totalRevenue',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF059669)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Text('💵', style: TextStyle(fontSize: 13)),
                                SizedBox(width: 6),
                                Text(
                                  'Cash Handover',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '₹${stats['cashRevenue'] ?? 0}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF78350F)),
                            ),
                            Text(
                              "Today: ₹${stats['todayCashRevenue'] ?? 0}",
                              style: const TextStyle(fontSize: 10, color: Color(0xFFB45309), fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Text('📱', style: TextStyle(fontSize: 13)),
                                SizedBox(width: 6),
                                Text(
                                  'UPI Received',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '₹${stats['upiRevenue'] ?? 0}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1E3A8A)),
                            ),
                            Text(
                              "Today: ₹${stats['todayUpiRevenue'] ?? 0}",
                              style: const TextStyle(fontSize: 10, color: Color(0xFF2563EB), fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Today's Performance Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.today_rounded, size: 18, color: Color(0xFF2563EB)),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      "Today's Activity",
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF0F172A)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildSubMetric("Today's Orders", "$todayOrders", const Color(0xFF0F172A)),
                    Container(width: 1, height: 32, color: const Color(0xFFE2E8F0)),
                    _buildSubMetric("Today's Revenue", "₹$todayRevenue", const Color(0xFF10B981)),
                    Container(width: 1, height: 32, color: const Color(0xFFE2E8F0)),
                    _buildSubMetric("All-Time Total", "$totalOrders", const Color(0xFF64748B)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Quick Navigation Shortcuts
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => widget.onSwitchTab?.call(1),
                  icon: const Icon(Icons.radar_rounded, size: 18, color: Color(0xFFF59E0B)),
                  label: const Text('Live Orders Map', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Color(0xFFFDE68A)),
                    backgroundColor: const Color(0xFFFEFCE8),
                    foregroundColor: const Color(0xFF92400E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => widget.onSwitchTab?.call(2),
                  icon: const Icon(Icons.history_rounded, size: 18, color: Color(0xFF10B981)),
                  label: const Text('Rider History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Color(0xFFA7F3D0)),
                    backgroundColor: const Color(0xFFECFDF5),
                    foregroundColor: const Color(0xFF065F46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Fleet Status (Riders on Duty)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Rider Fleet Status',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
              ),
              Text(
                '${riders.length} registered',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (riders.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Text('No riders registered yet.', style: TextStyle(color: Color(0xFF64748B))),
            )
          else
            ...riders.map((r) {
              final isOnline = r['isOnline'] == true;
              final name = r['name'] ?? 'Rider';
              final phone = r['phone'] ?? '';
              final totalDeliveries = r['totalDeliveries'] ?? 0;
              final totalEarnings = r['totalEarnings'] ?? 0;
              final activeTrip = r['activeTrip'] as Map<String, dynamic>?;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isOnline ? const Color(0xFFBBEF6D).withOpacity(0.7) : const Color(0xFFE2E8F0),
                    width: isOnline ? 1.5 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isOnline ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.two_wheeler_rounded,
                            color: isOnline ? const Color(0xFF059669) : const Color(0xFF94A3B8),
                            size: 22,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: isOnline ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                name,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF0F172A)),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isOnline ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isOnline ? 'ONLINE' : 'OFFLINE',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: isOnline ? const Color(0xFF15803D) : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            phone,
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 4),
                          if (activeTrip != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                border: Border.all(color: const Color(0xFFFDE68A)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.sync_rounded, size: 12, color: Color(0xFFD97706)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'On Trip #${activeTrip['orderNumber']} (${activeTrip['status']})',
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                                  ),
                                ],
                              ),
                            )
                          else
                            Text(
                              'Deliveries: $totalDeliveries  •  Earnings: ₹$totalEarnings',
                              style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                            ),
                        ],
                      ),
                    ),
                    if (phone.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.phone_rounded, color: Color(0xFF0284C7), size: 20),
                        onPressed: () => _callPhone(phone),
                        tooltip: 'Call Rider',
                      ),
                  ],
                ),
              );
            }).toList(),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 8,
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
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 16, color: accentColor),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
