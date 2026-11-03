import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/order_model.dart';
import '../../services/api_service.dart';

class OrderTrackingScreen extends StatefulWidget {
  final String orderId;

  const OrderTrackingScreen({Key? key, required this.orderId}) : super(key: key);

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  final ApiService _apiService = ApiService();
  OrderModel? _order;
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _pollingTimer;

  final List<Map<String, dynamic>> _milestones = [
    {'key': 'ORDER_PLACED', 'title': 'Order Placed', 'desc': 'Waiting for ZIPPO rider to accept'},
    {'key': 'RIDER_ASSIGNED', 'title': 'Rider Assigned', 'desc': 'Rider is on the way to the pickup shop/spot'},
    {'key': 'ITEM_PURCHASED', 'title': 'Items Picked / Purchased', 'desc': 'Rider has verified and collected your items'},
    {'key': 'ON_THE_WAY', 'title': 'On The Way', 'desc': 'Rider is en route to your delivery location'},
    {'key': 'DELIVERED', 'title': 'Delivered', 'desc': 'Package delivered safely with 4-digit PIN'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchOrder();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _fetchOrder(silent: true);
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchOrder({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final order = await _apiService.getOrderById(widget.orderId);
      if (mounted) {
        setState(() {
          _order = order;
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  int _getCurrentMilestoneIndex() {
    if (_order == null) return 0;
    switch (_order!.status) {
      case 'ORDER_PLACED':
        return 0;
      case 'RIDER_ASSIGNED':
        return 1;
      case 'ITEM_PURCHASED':
        return 2;
      case 'ON_THE_WAY':
        return 3;
      case 'DELIVERED':
        return 4;
      case 'CANCELLED':
        return -1;
      default:
        return 0;
    }
  }

  Future<void> _callRider(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open phone dialer')),
      );
    }
  }

  void _confirmCancelOrder() {
    if (_order == null) return;
    if (!_order!.canCancel) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cancellation locked! The rider has already bought/picked up your items.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Cancel Order?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to cancel this order? This will release the order from the dispatch pool.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('No, Keep Order', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _apiService.cancelOrder(_order!.id);
                _fetchOrder();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
                );
              }
            },
            child: const Text('Yes, Cancel', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: Text(_order?.orderNumber ?? 'Order Tracking', style: const TextStyle(color: Colors.white)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: () => _fetchOrder(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_errorMessage!, style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => _fetchOrder(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _order == null
                  ? const SizedBox()
                  : RefreshIndicator(
                      onRefresh: () => _fetchOrder(),
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          // Top PIN & Status Card
                          _buildHeaderCard(),

                          const SizedBox(height: 16),

                          // Rider Contact Card (if assigned)
                          if (_order!.riderName != null) _buildRiderCard(),

                          const SizedBox(height: 20),

                          // Milestone Timeline
                          const Text(
                            'Delivery Milestones',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildMilestoneTimeline(),

                          const SizedBox(height: 20),

                          // Order Summary Details
                          _buildOrderSummaryCard(),

                          const SizedBox(height: 24),

                          // Cancellation Action (with locked rules)
                          if (!_order!.isDelivered && !_order!.isCancelled)
                            _buildCancellationSection(),

                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildHeaderCard() {
    final isCancelled = _order!.status == 'CANCELLED';
    final isDelivered = _order!.status == 'DELIVERED';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCancelled
              ? Colors.redAccent
              : isDelivered
                  ? const Color(0xFF10B981)
                  : const Color(0xFF38BDF8),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _order!.orderType == 'PICKUP_DROP'
                    ? 'Pickup & Drop (${_order!.category})'
                    : 'Buy For Me Order',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                'Total Fee: ₹${_order!.fare}',
                style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ],
          ),
          // 4-Digit Delivery PIN badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF10B981)),
            ),
            child: Column(
              children: [
                const Text(
                  'DELIVERY PIN',
                  style: TextStyle(color: Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  _order!.deliveryPin,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiderCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F362A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF10B981)),
            child: const Icon(Icons.two_wheeler, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Assigned Rider', style: TextStyle(color: Color(0xFFD1FAE5), fontSize: 11)),
                Text(
                  _order!.riderName ?? 'ZIPPO Rider',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Text(
                  _order!.riderPhone ?? '',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            icon: const Icon(Icons.call, size: 16, color: Colors.white),
            label: const Text('Call', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () => _callRider(_order!.riderPhone!),
          ),
        ],
      ),
    );
  }

  Widget _buildMilestoneTimeline() {
    final currentIndex = _getCurrentMilestoneIndex();
    final isCancelled = _order!.status == 'CANCELLED';

    if (isCancelled) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF450A0A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.cancel, color: Colors.redAccent, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'This order was cancelled and is no longer active.',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: _milestones.asMap().entries.map((entry) {
          final idx = entry.key;
          final milestone = entry.value;
          final isCompleted = idx <= currentIndex;
          final isCurrent = idx == currentIndex;
          final isLast = idx == _milestones.length - 1;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Circle & connecting line
              Column(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCompleted ? const Color(0xFF10B981) : const Color(0xFF334155),
                      border: Border.all(
                        color: isCurrent ? Colors.white : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: isCompleted
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : null,
                  ),
                  if (!isLast)
                    Container(
                      width: 2,
                      height: 40,
                      color: idx < currentIndex ? const Color(0xFF10B981) : const Color(0xFF334155),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              // Text Description
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        milestone['title'],
                        style: TextStyle(
                          color: isCompleted ? Colors.white : Colors.white38,
                          fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        milestone['desc'],
                        style: TextStyle(
                          color: isCompleted ? Colors.white70 : Colors.white24,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOrderSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Route & Item Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          _buildInfoRow('Pickup', _order!.pickupAddress, Icons.location_on),
          const SizedBox(height: 8),
          _buildInfoRow('Drop', _order!.dropAddress, Icons.flag),
          if (_order!.itemsList.isNotEmpty) ...[
            const Divider(color: Colors.white12, height: 16),
            const Text('Items:', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              _order!.itemsList.join('\n'),
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF10B981)),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(color: Colors.white60, fontSize: 12)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _buildCancellationSection() {
    final canCancel = _order!.canCancel;

    return Column(
      children: [
        if (!canCancel)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF332005),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.withOpacity(0.5)),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock, color: Colors.amber, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Cancellation is locked because the rider has already purchased or picked up the items.',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: canCancel ? Colors.redAccent : Colors.white24,
              side: BorderSide(color: canCancel ? Colors.redAccent.withOpacity(0.6) : Colors.white12),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: canCancel ? _confirmCancelOrder : null,
            child: Text(
              canCancel ? 'Cancel Order' : 'Cancel Order (Locked)',
              style: TextStyle(fontWeight: FontWeight.bold, color: canCancel ? Colors.redAccent : Colors.white24),
            ),
          ),
        ),
      ],
    );
  }
}
