import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../config/constants.dart';
import '../../services/api_service.dart';
import '../../services/preferences_service.dart';
import '../../services/notification_service.dart';
import 'order_success_share_screen.dart';

class BuyForMeFormScreen extends StatefulWidget {
  final String? guestName;
  final String? guestPhone;

  const BuyForMeFormScreen({
    Key? key,
    this.guestName,
    this.guestPhone,
  }) : super(key: key);

  @override
  State<BuyForMeFormScreen> createState() => _BuyForMeFormScreenState();
}

class _BuyForMeFormScreenState extends State<BuyForMeFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  final TextEditingController _shopNameController = TextEditingController();
  final TextEditingController _budgetController = TextEditingController();
  final TextEditingController _deliveryAddressController = TextEditingController();
  final TextEditingController _distanceController = TextEditingController(text: '2.0');

  final List<TextEditingController> _itemControllers = [
    TextEditingController(),
  ];

  bool _isUrgent = false;
  bool _isDetectingGps = false;
  bool _isSubmitting = false;
  double? _dropLat;
  double? _dropLng;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.guestName ?? '');
    _phoneController = TextEditingController(text: widget.guestPhone ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _shopNameController.dispose();
    _budgetController.dispose();
    _deliveryAddressController.dispose();
    _distanceController.dispose();
    for (var c in _itemControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addItemRow() {
    setState(() {
      _itemControllers.add(TextEditingController());
    });
  }

  void _removeItemRow(int index) {
    if (_itemControllers.length > 1) {
      setState(() {
        final ctrl = _itemControllers.removeAt(index);
        ctrl.dispose();
      });
    }
  }

  int _computeFare() {
    final double dist = double.tryParse(_distanceController.text) ?? 2.0;
    final double extraKm = (dist - AppConstants.baseKm).clamp(0.0, 50.0);
    final int distanceCost = (extraKm * AppConstants.perKmRate).round();
    final int urgentCost = _isUrgent ? AppConstants.urgentSurcharge : 0;
    return AppConstants.baseFare + distanceCost + urgentCost;
  }

  Future<void> _detectGpsDrop() async {
    setState(() => _isDetectingGps = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _dropLat = pos.latitude;
        _dropLng = pos.longitude;
        if (_deliveryAddressController.text.isEmpty) {
          _deliveryAddressController.text = 'GPS Pin (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})';
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delivery GPS captured successfully!'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('GPS Error: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      setState(() => _isDetectingGps = false);
    }
  }

  Future<void> _submitOrder() async {
    if (!_formKey.currentState!.validate()) return;

    final items = _itemControllers
        .map((c) => c.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one item to purchase!'), backgroundColor: Colors.amber),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await PreferencesService.saveCustomerProfile(
        _nameController.text.trim(),
        _phoneController.text.trim(),
      );

      final token = await NotificationService().getCachedOrFreshToken();
      final double distance = double.tryParse(_distanceController.text) ?? 2.0;
      final double budget = double.tryParse(_budgetController.text) ?? 0.0;

      final payload = {
        'customerName': _nameController.text.trim(),
        'customerPhone': _phoneController.text.trim(),
        'dropPhone': _phoneController.text.trim(),
        'orderType': 'BUY_FOR_ME',
        'category': 'BuyForMe',
        'shopName': _shopNameController.text.trim(),
        'itemsList': items,
        'budget': budget,
        'isUrgent': _isUrgent,
        'pickupAddress': _shopNameController.text.trim().isNotEmpty
            ? _shopNameController.text.trim()
            : 'Melapalayam Market',
        'dropAddress': _deliveryAddressController.text.trim(),
        'dropCoords': {'lat': _dropLat, 'lng': _dropLng},
        'estimatedDistanceKm': distance,
        'customerFcmToken': token,
      };

      final result = await ApiService().createOrder(payload);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => OrderSuccessShareScreen(
            order: result['order'],
            whatsappTicket: result['whatsappTicket'],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fare = _computeFare();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text('Buy For Me Service', style: TextStyle(color: Colors.white)),
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionHeader('1. Customer Contact'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Your Full Name', Icons.person),
              validator: (v) => v!.trim().isEmpty ? 'Enter your name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Mobile Number', Icons.phone, prefix: '+91 '),
              validator: (v) => v!.trim().length < 10 ? 'Enter valid 10-digit number' : null,
            ),

            const SizedBox(height: 20),

            _buildSectionHeader('2. Shop Details & Budget'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _shopNameController,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Shop Name / Area (e.g., Buhari Meat Stall / Bazar)', Icons.store),
              validator: (v) => v!.trim().isEmpty ? 'Enter shop name or area' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _budgetController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Estimated Item Cost Budget (₹)', Icons.currency_rupee),
              validator: (v) => v!.trim().isEmpty ? 'Enter estimated items budget' : null,
            ),

            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSectionHeader('3. Items Checklist'),
                TextButton.icon(
                  onPressed: _addItemRow,
                  icon: const Icon(Icons.add_circle, color: Color(0xFF10B981), size: 18),
                  label: const Text('Add Item', style: TextStyle(color: Color(0xFF10B981), fontSize: 13)),
                ),
              ],
            ),
            ..._itemControllers.asMap().entries.map((entry) {
              final idx = entry.key;
              final ctrl = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: ctrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _inputDecoration('Item ${idx + 1} (e.g. 1kg Mutton Biryani Rice)', Icons.check_box_outlined),
                      ),
                    ),
                    if (_itemControllers.length > 1)
                      IconButton(
                        icon: const Icon(Icons.remove_circle, color: Colors.redAccent, size: 20),
                        onPressed: () => _removeItemRow(idx),
                      ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 20),

            _buildSectionHeader('4. Delivery Destination'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _deliveryAddressController,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration(
                'Delivery Landmark / House Address',
                Icons.location_on,
                suffix: IconButton(
                  icon: _isDetectingGps
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location, color: Color(0xFF10B981)),
                  tooltip: '1-Tap Detect Current GPS',
                  onPressed: _detectGpsDrop,
                ),
              ),
              validator: (v) => v!.trim().isEmpty ? 'Delivery address is required' : null,
            ),

            const SizedBox(height: 20),

            _buildSectionHeader('5. Delivery Fare Calculation'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Distance to delivery spot (km):', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      SizedBox(
                        width: 70,
                        child: TextFormField(
                          controller: _distanceController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 6),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 20),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Urgent Express Purchase (+₹15)', style: TextStyle(color: Colors.white, fontSize: 14)),
                    subtitle: const Text('Rider heads straight to the shop', style: TextStyle(color: Colors.white54, fontSize: 11)),
                    value: _isUrgent,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (val) => setState(() => _isUrgent = val),
                  ),
                  const Divider(color: Colors.white12, height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Delivery Fee (excluding item cost):', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      Text(
                        '₹$fare',
                        style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 22),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isSubmitting ? null : _submitOrder,
              child: _isSubmitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text(
                      'Place Buy For Me Order & Dispatch',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon, {String? prefix, Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white60, fontSize: 13),
      prefixIcon: Icon(icon, color: const Color(0xFF0284C7), size: 20),
      prefixText: prefix,
      prefixStyle: const TextStyle(color: Colors.white),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFF1E293B),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF0284C7)),
      ),
    );
  }
}
