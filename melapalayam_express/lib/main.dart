import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'config/constants.dart';
import 'services/notification_service.dart';
import 'screens/customer/customer_home_screen.dart';
import 'screens/customer/order_tracking_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    await NotificationService().initialize(
      onNotificationOrderTap: (orderId) {
        if (orderId.isNotEmpty) {
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => OrderTrackingScreen(orderId: orderId),
            ),
          );
        }
      },
    );
  } catch (e) {
    debugPrint('[Firebase Init Warning]: Running in local/simulation mode: $e');
  }

  runApp(const MelapalayamExpressApp());
}

class MelapalayamExpressApp extends StatelessWidget {
  const MelapalayamExpressApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MPM Express | மேலப்பாளையம்',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppConstants.slate50,
        primaryColor: AppConstants.emerald600,
        colorScheme: ColorScheme.light(
          primary: AppConstants.emerald600,
          secondary: AppConstants.emerald500,
          surface: Colors.white,
          background: AppConstants.slate50,
          error: const Color(0xFFE11D48),
        ),
        fontFamily: 'sans-serif',
        useMaterial3: true,
      ),
      home: const CustomerHomeScreen(),
    );
  }
}
