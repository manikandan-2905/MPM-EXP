import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/order_model.dart';
import '../../services/api_service.dart';
import '../../widgets/swipe_button.dart';

class RiderActiveOrderScreen extends StatefulWidget {
  final OrderModel order;
  final String riderId;

  const RiderActiveOrderScreen({
    Key? key,
    required this.order,
    required this.riderId,
  }) : super(key: key);

  @override
  State<RiderActiveOrderScreen> createState() => _RiderActiveOrderScreenState();
}

class _RiderActiveOrderScreenState extends State<RiderActiveOrderScreen> {
  final ApiService _apiService = ApiService();
  late OrderModel _order;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  // 1-Tap Google Maps Turn-by-Turn Navigation
  Future<void> _launchGoogleMapsNavigation({
    required String address,
    OrderCoordinates? coords,
  }) async {
    Uri navUri;
    if (coords != null && coords.lat != null && coords.lng != null) {
      // Direct Turn-by-Turn Android navigation intent
      navUri = Uri.parse('google.navigation:q=${coords.lat},${coords.lng}&mode=d');
    } else {
      // Fallback to landmark search
      final query = Uri.encodeComponent('$address, Melapalayam, Tirunelveli');
      navUri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$query');
    }

    try {
      if (await canLaunchUrl(navUri)) {
        await launchUrl(navUri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback web url
        final webUri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=${coords?.lat ?? ""},${coords?.lng ?? Uri.encodeComponent(address)}',
        );
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch Google Maps: $e')),
      );
    }
  }

  Future<void> _makePhoneCall(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _updateMilestone(String nextStatus) async {
    setState(() => _isLoading = true);
    try {
      final updated = await _apiService.updateMilestone(
        _order.id,
        widget.riderId,
        nextStatus,
      );
      setState(() {
        _order = updated;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Milestone updated: ${nextStatus.replaceAll("_", " ")}'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _showCompleteDeliveryDialog() {
    final pinController = TextEditingController();
    bool isVerifying = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text(
              'Complete Delivery',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter customer\'s 4-digit Delivery PIN to verify package handover:',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: pinController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '----',
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                // Emergency Bypass Option
                InkWell(
                  onTap: isVerifying
                      ? null
                      : () async {
                          setDialogState(() => isVerifying = true);
                          try {
                            final completed = await _apiService.completeDelivery(
                              _order.id,
                              widget.riderId,
                              isBypass: true,
                            );
                            Navigator.pop(ctx);
                            _onDeliveryComplete(completed);
                          } catch (err) {
                            setDialogState(() => isVerifying = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Bypass Error: $err'), backgroundColor: Colors.redAccent),
                            );
                          }
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'Emergency? Optional Bypass PIN',
                      style: TextStyle(
                        color: Colors.amber.shade400,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: isVerifying
                    ? null
                    : () async {
                        if (pinController.text.trim().length != 4) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter 4-digit PIN')),
                          );
                          return;
                        }

                        setDialogState(() => isVerifying = true);
                        try {
                          final completed = await _apiService.completeDelivery(
                            _order.id,
                            widget.riderId,
                            deliveryPin: pinController.text.trim(),
                            isBypass: false,
                          );
                          Navigator.pop(ctx);
                          _onDeliveryComplete(completed);
                        } catch (err) {
                          setDialogState(() => isVerifying = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(err.toString().replaceAll('Exception: ', '')),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        }
                      },
                child: isVerifying
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Verify & Finish', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _onDeliveryComplete(OrderModel order) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('🎉 Delivery Completed!', style: TextStyle(color: Colors.white)),
        content: Text(
          'Trip fee of ₹${order.fare} has been credited to your rider account.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () {
              Navigator.pop(ctx); // Close dialog
              Navigator.pop(context); // Return to Dashboard
            },
            child: const Text('Back to Dashboard', style: TextStyle(color: Colors.white)),
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
        title: Text('Trip #${_order.orderNumber}', style: const TextStyle(color: Colors.white)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Order Header Banner
          _buildTripHeader(),

          const SizedBox(height: 16),

          // Route & 1-Tap Google Maps Navigation Buttons
          _buildNavigationSection(),

          const SizedBox(height: 16),

          // Customer & Contact Cards
          _buildCustomerContactCard(),

          const SizedBox(height: 16),

          // Items Checklist
          if (_order.itemsList.isNotEmpty) _buildItemsCard(),

          const SizedBox(height: 28),

          // Milestone Progression Sliding Controls (Anti-pocket-touch)
          _buildMilestoneSliderControl(),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildTripHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF10B981)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _order.orderType == 'PICKUP_DROP'
                    ? 'Pickup & Drop (${_order.category})'
                    : 'Buy For Me (${_order.shopName ?? "Market"})',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                'Status: ${_order.status.replaceAll("_", " ")}',
                style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF064E3B),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Trip Fee: ₹${_order.fare}',
              style: const TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '1-Tap Turn-by-Turn Navigation',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 14),

          // Pickup Location Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on, color: Color(0xFF38BDF8), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('PICKUP SPOT', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold)),
                    Text(_order.pickupAddress, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.navigation, size: 14, color: Colors.white),
                label: const Text('Maps', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: () => _launchGoogleMapsNavigation(
                  address: _order.pickupAddress,
                  coords: _order.pickupCoords,
                ),
              ),
            ],
          ),

          const Divider(color: Colors.white12, height: 24),

          // Drop Location Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.flag, color: Color(0xFF10B981), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('DROP SPOT', style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold)),
                    Text(_order.dropAddress, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.navigation, size: 14, color: Colors.white),
                label: const Text('Maps', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: () => _launchGoogleMapsNavigation(
                  address: _order.dropAddress,
                  coords: _order.dropCoords,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerContactCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Customer & Contacts', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_order.customerName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(_order.customerPhone, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.phone, color: Color(0xFF10B981)),
                onPressed: () => _makePhoneCall(_order.customerPhone),
              ),
            ],
          ),
          if (_order.pickupPhone != null && _order.pickupPhone != _order.customerPhone) ...[
            const Divider(color: Colors.white12, height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Sender Contact', style: TextStyle(color: Colors.white54, fontSize: 11)),
                    Text(_order.pickupPhone!, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.phone, color: Color(0xFF38BDF8)),
                  onPressed: () => _makePhoneCall(_order.pickupPhone!),
                ),
              ],
            ),
          ],
          if (_order.dropPhone != null && _order.dropPhone != _order.customerPhone) ...[
            const Divider(color: Colors.white12, height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Receiver Contact', style: TextStyle(color: Colors.white54, fontSize: 11)),
                    Text(_order.dropPhone!, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.phone, color: Color(0xFF10B981)),
                  onPressed: () => _makePhoneCall(_order.dropPhone!),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Checklist / Order Items', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 10),
          ..._order.itemsList.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(item, style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ),
          if (_order.budget > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Item Budget: ₹${_order.budget}',
              style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildMilestoneSliderControl() {
    if (_order.status == 'RIDER_ASSIGNED') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Step 1: Item Pickup Confirmation',
            style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SwipeButton(
            label: 'Slide: Item Picked / Purchased >>',
            icon: Icons.shopping_cart_checkout,
            activeColor: const Color(0xFF0284C7),
            onSwipeComplete: () => _updateMilestone('ITEM_PURCHASED'),
          ),
        ],
      );
    } else if (_order.status == 'ITEM_PURCHASED') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Step 2: Transit Confirmation',
            style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SwipeButton(
            label: 'Slide: On the Way to Customer >>',
            icon: Icons.two_wheeler,
            activeColor: const Color(0xFFD97706),
            onSwipeComplete: () => _updateMilestone('ON_THE_WAY'),
          ),
        ],
      );
    } else if (_order.status == 'ON_THE_WAY') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Step 3: Handover & PIN Verification',
            style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.verified, color: Colors.white),
              label: const Text(
                'Complete Delivery (Verify 4-Digit PIN)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              onPressed: _showCompleteDeliveryDialog,
            ),
          ),
        ],
      );
    } else if (_order.status == 'DELIVERED') {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF064E3B),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            '✅ Delivery completed & fee credited.',
            style: TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    return const SizedBox();
  }
}
