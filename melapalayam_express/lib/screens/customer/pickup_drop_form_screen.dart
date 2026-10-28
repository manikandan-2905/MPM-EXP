import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../config/constants.dart';
import '../../services/api_service.dart';
import '../../services/preferences_service.dart';
import '../../services/notification_service.dart';
import 'order_success_share_screen.dart';

class PickupDropFormScreen extends StatefulWidget {
  final String? guestName;
  final String? guestPhone;

  const PickupDropFormScreen({
    Key? key,
    this.guestName,
    this.guestPhone,
  }) : super(key: key);

  @override
  State<PickupDropFormScreen> createState() => _PickupDropFormScreenState();
}

class _PickupDropFormScreenState extends State<PickupDropFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  late TextEditingController _nameController;
  late TextEditingController _primaryPhoneController;
  final TextEditingController _pickupPhoneController = TextEditingController();
  final TextEditingController _dropPhoneController = TextEditingController();
  final TextEditingController _pickupAddressController = TextEditingController();
  final TextEditingController _dropAddressController = TextEditingController();
  final TextEditingController _itemDescController = TextEditingController();
  final TextEditingController _distanceController = TextEditingController(text: '2.0');

  String _selectedCategory = 'Food';
  bool _isUrgent = false;
  bool _isSenderMe = true;
  bool _isReceiverMe = false;
  bool _isDetectingGpsPickup = false;
  bool _isDetectingGpsDrop = false;
  bool _isSubmitting = false;

  double? _pickupLat;
  double? _pickupLng;
  double? _dropLat;
  double? _dropLng;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.guestName ?? '');
    _primaryPhoneController = TextEditingController(text: widget.guestPhone ?? '');

    if (_isSenderMe && widget.guestPhone != null) {
      _pickupPhoneController.text = widget.guestPhone!;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _primaryPhoneController.dispose();
    _pickupPhoneController.dispose();
    _dropPhoneController.dispose();
    _pickupAddressController.dispose();
    _dropAddressController.dispose();
    _itemDescController.dispose();
    _distanceController.dispose();
    super.dispose();
  }

  // Calculate live fare based on Distance & Urgent toggle
  int _computeFare() {
    final double dist = double.tryParse(_distanceController.text) ?? 2.0;
    final double extraKm = (dist - AppConstants.baseKm).clamp(0.0, 50.0);
    final int distanceCost = (extraKm * AppConstants.perKmRate).round();
    final int urgentCost = _isUrgent ? AppConstants.urgentSurcharge : 0;
    return AppConstants.baseFare + distanceCost + urgentCost;
  }

  // 1-Tap Current GPS detection
  Future<void> _detectCurrentLocation({required bool isPickup}) async {
    setState(() {
      if (isPickup) _isDetectingGpsPickup = true;
      else _isDetectingGpsDrop = true;
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied');
        }
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        if (isPickup) {
          _pickupLat = position.latitude;
          _pickupLng = position.longitude;
          if (_pickupAddressController.text.isEmpty) {
            _pickupAddressController.text = 'GPS Pin (${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)})';
          }
        } else {
          _dropLat = position.latitude;
          _dropLng = position.longitude;
          if (_dropAddressController.text.isEmpty) {
            _dropAddressController.text = 'GPS Pin (${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)})';
          }
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'GPS coordinates captured for ${isPickup ? "Pickup" : "Drop"} spot!',
          ),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not fetch GPS: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      setState(() {
        if (isPickup) _isDetectingGpsPickup = false;
        else _isDetectingGpsDrop = false;
      });
    }
  }

  Future<void> _submitOrder() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      // Save customer profile locally for zero-friction future orders
      await PreferencesService.saveCustomerProfile(
        _nameController.text.trim(),
        _primaryPhoneController.text.trim(),
      );

      final token = await NotificationService().getCachedOrFreshToken();
      final double distance = double.tryParse(_distanceController.text) ?? 2.0;

      final payload = {
        'customerName': _nameController.text.trim(),
        'customerPhone': _primaryPhoneController.text.trim(),
        'pickupPhone': _pickupPhoneController.text.trim().isNotEmpty
            ? _pickupPhoneController.text.trim()
            : _primaryPhoneController.text.trim(),
        'dropPhone': _dropPhoneController.text.trim().isNotEmpty
            ? _dropPhoneController.text.trim()
            : _primaryPhoneController.text.trim(),
        'orderType': 'PICKUP_DROP',
        'category': _selectedCategory,
        'itemsList': _itemDescController.text.trim().isNotEmpty
            ? [_itemDescController.text.trim()]
            : ['Pickup item (${_selectedCategory})'],
        'isUrgent': _isUrgent,
        'pickupAddress': _pickupAddressController.text.trim(),
        'pickupCoords': {'lat': _pickupLat, 'lng': _pickupLng},
        'dropAddress': _dropAddressController.text.trim(),
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
        title: const Text('Custom Pickup & Drop', style: TextStyle(color: Colors.white)),
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Section 1: Customer Contact Info
            _buildSectionHeader('1. Your Details (Customer)'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Your Full Name', Icons.person),
              validator: (v) => v!.trim().isEmpty ? 'Please enter your name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _primaryPhoneController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Primary Contact Number', Icons.phone, prefix: '+91 '),
              validator: (v) => v!.trim().length < 10 ? 'Enter valid 10-digit mobile number' : null,
              onChanged: (val) {
                if (_isSenderMe) _pickupPhoneController.text = val;
                if (_isReceiverMe) _dropPhoneController.text = val;
              },
            ),

            const SizedBox(height: 20),

            // Section 2: Category Selector
            _buildSectionHeader('2. Item Category'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AppConstants.pickupCategories.map((cat) {
                final isSelected = _selectedCategory == cat;
                return ChoiceChip(
                  label: Text(
                    cat,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: const Color(0xFF10B981),
                  backgroundColor: const Color(0xFF1E293B),
                  onSelected: (selected) {
                    if (selected) setState(() => _selectedCategory = cat);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _itemDescController,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Item Notes (e.g., 2kg Chicken or Tailor Suit)', Icons.notes),
            ),

            const SizedBox(height: 20),

            // Section 3: Pickup Landmark & Location
            _buildSectionHeader('3. Pickup Details (Sender)'),
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: _isSenderMe,
                  activeColor: const Color(0xFF10B981),
                  onChanged: (val) {
                    setState(() {
                      _isSenderMe = val ?? false;
                      if (_isSenderMe) {
                        _pickupPhoneController.text = _primaryPhoneController.text;
                      }
                    });
                  },
                ),
                const Text('I am the Sender', style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
            TextFormField(
              controller: _pickupPhoneController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Sender Mobile Number', Icons.phone_android, prefix: '+91 '),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _pickupAddressController,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration(
                'Pickup Landmark / Street / Store',
                Icons.location_on,
                suffix: IconButton(
                  icon: _isDetectingGpsPickup
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location, color: Color(0xFF10B981)),
                  tooltip: '1-Tap Detect Current GPS',
                  onPressed: () => _detectCurrentLocation(isPickup: true),
                ),
              ),
              validator: (v) => v!.trim().isEmpty ? 'Pickup location is required' : null,
            ),

            const SizedBox(height: 20),

            // Section 4: Drop Landmark & Location
            _buildSectionHeader('4. Delivery Details (Receiver)'),
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: _isReceiverMe,
                  activeColor: const Color(0xFF10B981),
                  onChanged: (val) {
                    setState(() {
                      _isReceiverMe = val ?? false;
                      if (_isReceiverMe) {
                        _dropPhoneController.text = _primaryPhoneController.text;
                      }
                    });
                  },
                ),
                const Text('I am the Receiver', style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
            TextFormField(
              controller: _dropPhoneController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration('Receiver Mobile Number', Icons.phone_android, prefix: '+91 '),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _dropAddressController,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDecoration(
                'Delivery Landmark / House Address',
                Icons.flag,
                suffix: IconButton(
                  icon: _isDetectingGpsDrop
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location, color: Color(0xFF10B981)),
                  tooltip: '1-Tap Detect Current GPS',
                  onPressed: () => _detectCurrentLocation(isPickup: false),
                ),
              ),
              validator: (v) => v!.trim().isEmpty ? 'Drop address is required' : null,
            ),

            const SizedBox(height: 20),

            // Section 5: Fare Engine & Distance
            _buildSectionHeader('5. Fare & Priority'),
            const SizedBox(height: 12),
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
                      const Text(
                        'Estimated Distance (km):',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
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
                  const SizedBox(height: 8),
                  const Text(
                    'Rule: ₹30 for first 2 km, +₹10 for every extra km',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const Divider(color: Colors.white12, height: 20),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Urgent Express Delivery (+₹15)', style: TextStyle(color: Colors.white, fontSize: 14)),
                    subtitle: const Text('Priority broadcast to all active riders', style: TextStyle(color: Colors.white54, fontSize: 11)),
                    value: _isUrgent,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (val) => setState(() => _isUrgent = val),
                  ),
                  const Divider(color: Colors.white12, height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Estimated Fare:',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        '₹$fare',
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Submit Button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isSubmitting ? null : _submitOrder,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'Confirm & Dispatch to WhatsApp Group',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
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
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 15,
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon, {String? prefix, Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white60, fontSize: 13),
      prefixIcon: Icon(icon, color: const Color(0xFF10B981), size: 20),
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
        borderSide: const BorderSide(color: Color(0xFF10B981)),
      ),
    );
  }
}
