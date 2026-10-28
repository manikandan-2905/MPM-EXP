import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'preferences_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  FirebaseMessaging? get _fcm {
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseMessaging.instance;
      }
    } catch (_) {}
    return null;
  }

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'melapalayam_delivery_milestones',
    'Melapalayam Delivery Milestones',
    description: 'High-priority alerts for order pickup, status updates, and rider phone calls',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  Future<void> initialize({Function(String orderId)? onNotificationOrderTap}) async {
    try {
      // 1. Setup Android Local Notifications
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);

      await _localNotifications.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) async {
          if (response.actionId == 'ACTION_CALL_DIRECT' && response.payload != null) {
            final uri = Uri.parse('tel:${response.payload}');
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
            }
          } else if (response.payload != null && onNotificationOrderTap != null) {
            onNotificationOrderTap(response.payload!);
          }
        },
      );

      if (Platform.isAndroid) {
        await _localNotifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(_channel);
      }

      // 2. Setup Firebase if initialized
      final fcm = _fcm;
      if (fcm != null) {
        await fcm.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );

        FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          final notification = message.notification;
          final data = message.data;

          if (notification != null) {
            final callerPhone = data['caller_phone'] ?? '';
            final orderId = data['order_id'] ?? '';

            _localNotifications.show(
              notification.hashCode,
              notification.title,
              notification.body,
              NotificationDetails(
                android: AndroidNotificationDetails(
                  _channel.id,
                  _channel.name,
                  channelDescription: _channel.description,
                  icon: '@mipmap/ic_launcher',
                  importance: Importance.max,
                  priority: Priority.high,
                  playSound: true,
                  actions: callerPhone.isNotEmpty
                      ? [
                          AndroidNotificationAction(
                            'ACTION_CALL_DIRECT',
                            'Call ($callerPhone)',
                            showsUserInterface: true,
                            cancelNotification: true,
                          ),
                        ]
                      : null,
                ),
              ),
              payload: callerPhone.isNotEmpty ? callerPhone : orderId,
            );
          }
        });

        final token = await fcm.getToken();
        if (token != null) {
          await PreferencesService.saveFcmToken(token);
        }
      }
    } catch (e) {
      debugPrint('[NotificationService Warning]: $e');
    }
  }

  Future<String?> getCachedOrFreshToken() async {
    try {
      final fcm = _fcm;
      if (fcm != null) {
        final token = await fcm.getToken();
        if (token != null) {
          await PreferencesService.saveFcmToken(token);
          return token;
        }
      }
    } catch (_) {}
    return await PreferencesService.getFcmToken();
  }
}
