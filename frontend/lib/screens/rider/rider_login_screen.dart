import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/preferences_service.dart';
import '../../services/notification_service.dart';
import 'rider_dashboard_screen.dart';
import '../admin/admin_shell_screen.dart';

class RiderLoginScreen extends StatefulWidget {
  const RiderLoginScreen({Key? key}) : super(key: key);

  @override
  State<RiderLoginScreen> createState() => _RiderLoginScreenState();
}

class _RiderLoginScreenState extends State<RiderLoginScreen> {
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
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
    final password = _passwordController.text.trim();

    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter password or passcode')),
      );
      return;
    }

    if (password == 'mani2006') {
      _passwordController.clear();
      await PreferencesService.saveAdminSession();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AdminShellScreen()),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final fcmToken = await NotificationService().getCachedOrFreshToken();
      final rider = await ApiService().loginRider(
        password,
        fcmToken: fcmToken,
      );

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
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Image.asset(
                  'assets/logo.png',
                  width: 64,
                  height: 64,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'ZIPPO Rider Portal',
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
              const SizedBox(height: 24),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                keyboardType: TextInputType.text,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: 'Rider Password / Passcode',
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintText: 'Enter your assigned password (e.g. 02266)',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                  prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF10B981)),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white60,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF10B981), width: 2),
                  ),
                ),
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
