import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/preferences_service.dart';
import '../../services/notification_service.dart';
import 'rider_dashboard_screen.dart';

class RiderLoginScreen extends StatefulWidget {
  const RiderLoginScreen({Key? key}) : super(key: key);

  @override
  State<RiderLoginScreen> createState() => _RiderLoginScreenState();
}

class _RiderLoginScreenState extends State<RiderLoginScreen> {
  final _phoneController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  Future<void> _checkExistingSession() async {
    final session = await PreferencesService.getRiderSession();
    if (session['id'] != null && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RiderDashboardScreen(
            riderId: session['id']!,
            initialName: session['name'] ?? 'Rider',
            initialPhone: session['phone'] ?? '',
          ),
        ),
      );
    }
  }

  Future<void> _login() async {
    final phone = _phoneController.text.trim();
    if (phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid 10-digit registered rider phone')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final fcmToken = await NotificationService().getCachedOrFreshToken();
      final rider = await ApiService().loginRider(phone, fcmToken: fcmToken);

      await PreferencesService.saveRiderSession(
        id: rider.id,
        name: rider.name,
        phone: rider.phone,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RiderDashboardScreen(
            riderId: rider.id,
            initialName: rider.name,
            initialPhone: rider.phone,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.two_wheeler, color: Color(0xFF10B981), size: 38),
              ),
              const SizedBox(height: 20),
              const Text(
                'Melapalayam Rider Portal',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Authorized login for verified local dispatch riders.',
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Registered Mobile Number',
                  labelStyle: const TextStyle(color: Colors.white70),
                  prefixIcon: const Icon(Icons.phone_android, color: Color(0xFF10B981)),
                  prefixText: '+91 ',
                  prefixStyle: const TextStyle(color: Colors.white),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Demo pre-seeded numbers: 9876543210, 9876543211, 9876543212, 9876543213',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isLoading ? null : _login,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text(
                          'Secure Rider Login',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
