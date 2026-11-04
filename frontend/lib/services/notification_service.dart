import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'preferences_service.dart';
import 'api_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  try {
    final title = message.notification?.title ?? message.data['title'] ?? 'ZIPPO Alert';
    final body = message.notification?.body ?? message.data['body'] ?? message.data['message'] ?? '';
    final type = message.data['type']?.toString();
    final orderId = message.data['order_id']?.toString();
    final isRiderAlert = message.data['isRider'] == 'true' || message.data['isRider'] == true;
    final isAdminAlert = message.data['isAdmin'] == 'true' || message.data['isAdmin'] == true;

    if (title.isNotEmpty || body.isNotEmpty) {
      await PreferencesService.saveInAppNotification(
        title: title,
        body: body,
        type: type,
        orderId: orderId,
      );
    }

    // Display WhatsApp-like heads-up popup banner when app is in background/closed
    final flutterLocalNotifications = FlutterLocalNotificationsPlugin();
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotifications.initialize(initializationSettings);

    final channelId = isRiderAlert
        ? 'zippo_rider_dispatch_alerts'
        : (isAdminAlert ? 'zippo_admin_supervisor_alerts' : 'melapalayam_delivery_milestones');

    final channelName = isRiderAlert
        ? 'ZIPPO Rider Urgent Dispatch'
        : (isAdminAlert ? 'ZIPPO Admin Supervisor Alerts' : 'ZIPPO Delivery Milestones');

    final Color notifColor = isRiderAlert
        ? const Color(0xFF22C55E)
        : (isAdminAlert ? const Color(0xFFF59E0B) : const Color(0xFF76C457));

    final Int64List? vibPattern = isRiderAlert
        ? Int64List.fromList([0, 600, 200, 600, 200, 600, 400, 800])
        : null;

    await flutterLocalNotifications.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: 'High priority heads-up notification',
          icon: '@mipmap/ic_launcher',
          color: notifColor,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          vibrationPattern: vibPattern,
          fullScreenIntent: false,
          category: AndroidNotificationCategory.message,
          visibility: NotificationVisibility.public,
          ticker: title,
        ),
      ),
      payload: orderId,
    );
  } catch (e) {
    debugPrint('[Background Notification Handler Warning]: $e');
  }
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
    'ZIPPO Delivery Milestones',
    description: 'High-priority alerts for order pickup, status updates, and rider phone calls',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static final AndroidNotificationChannel _riderChannel = AndroidNotificationChannel(
    'zippo_rider_dispatch_alerts',
    'ZIPPO Rider Urgent Dispatch',
    description: 'High-volume alerts with double vibration for new available orders',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 600, 200, 600, 200, 600, 400, 800]),
  );

  static const AndroidNotificationChannel _adminChannel = AndroidNotificationChannel(
    'zippo_admin_supervisor_alerts',
    'ZIPPO Admin Supervisor Alerts',
    description: 'Real-time overview alerts for administrators',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  Future<void> initialize({Function(String orderId)? onNotificationOrderTap}) async {
    try {
      // 1. Setup Android Local Notifications (Skipped on Web)
      if (!kIsWeb) {
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
            } else if (response.payload != null && (response.payload!.startsWith('http://') || response.payload!.startsWith('https://'))) {
              final uri = Uri.parse(response.payload!);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            } else if (response.payload != null && onNotificationOrderTap != null) {
              onNotificationOrderTap(response.payload!);
            }
          },
        );

        if (Platform.isAndroid) {
          final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
          if (androidPlugin != null) {
            await androidPlugin.requestNotificationsPermission();
            await androidPlugin.createNotificationChannel(_channel);
            await androidPlugin.createNotificationChannel(_riderChannel);
            await androidPlugin.createNotificationChannel(_adminChannel);
          }
        }
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
          final title = message.notification?.title ?? message.data['title'] ?? 'ZIPPO Alert';
          final body = message.notification?.body ?? message.data['body'] ?? message.data['message'] ?? '';
          final data = message.data;

          if (title.isNotEmpty || body.isNotEmpty) {
            PreferencesService.saveInAppNotification(
              title: title,
              body: body,
              type: data['type']?.toString(),
              orderId: data['order_id']?.toString(),
            );
            final callerPhone = data['caller_phone'] ?? '';
            final orderId = data['order_id'] ?? '';
            final isRiderAlert = data['isRider'] == 'true' || data['isRider'] == true;
            final isAdminAlert = data['isAdmin'] == 'true' || data['isAdmin'] == true;

            final targetChannel = isRiderAlert
                ? _riderChannel
                : isAdminAlert
                    ? _adminChannel
                    : _channel;

            final Color notifColor = isRiderAlert
                ? const Color(0xFF22C55E)
                : (isAdminAlert ? const Color(0xFFF59E0B) : const Color(0xFF76C457));

            final Int64List? vibPattern = isRiderAlert
                ? Int64List.fromList([0, 600, 200, 600, 200, 600, 400, 800])
                : null;

            _localNotifications.show(
              message.hashCode,
              title,
              body,
              NotificationDetails(
                android: AndroidNotificationDetails(
                  targetChannel.id,
                  targetChannel.name,
                  channelDescription: targetChannel.description,
                  icon: '@mipmap/ic_launcher',
                  color: notifColor,
                  importance: Importance.max,
                  priority: Priority.max,
                  playSound: true,
                  enableVibration: true,
                  vibrationPattern: vibPattern,
                  category: AndroidNotificationCategory.message,
                  visibility: NotificationVisibility.public,
                  ticker: title,
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

        // Handle background notification clicks when app opens
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
          final actionUrl = message.data['action_url'];
          if (actionUrl != null && actionUrl.toString().isNotEmpty) {
            final uri = Uri.parse(actionUrl.toString());
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          } else if (message.data['order_id'] != null && onNotificationOrderTap != null) {
            onNotificationOrderTap(message.data['order_id']);
          }
        });

        // Handle FCM token rotation
        fcm.onTokenRefresh.listen((newToken) async {
          await PreferencesService.saveFcmToken(newToken);
          final platform = kIsWeb ? 'web' : (Platform.isIOS ? 'ios' : 'android');
          ApiService().registerDeviceToken(fcmToken: newToken, role: 'CUSTOMER', platform: platform);
        });

        // Ensure first-time install user is registered immediately
        await ensureDeviceRegistered(role: 'CUSTOMER');
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

  /// Ensures device FCM token is generated and registered with MongoDB backend.
  /// Seamlessly connects first-time install users (even before entering a phone number)
  /// and updates with phone number once entered.
  Future<void> ensureDeviceRegistered({String role = 'CUSTOMER', String? phone}) async {
    try {
      String? token = await getCachedOrFreshToken();

      // Retry up to 3 times if token is still generating on fresh app install
      int retries = 0;
      while (token == null && retries < 3) {
        await Future.delayed(Duration(seconds: 1 + retries));
        token = await getCachedOrFreshToken();
        retries++;
      }

      if (token != null) {
        final platform = kIsWeb ? 'web' : (Platform.isIOS ? 'ios' : 'android');
        final success = await ApiService().registerDeviceToken(
          fcmToken: token,
          role: role,
          phone: phone,
          platform: platform,
        );
        debugPrint('[NotificationService]: Device registered with backend (role: \, phone: \, success: \)');
      }
    } catch (e) {
      debugPrint('[NotificationService Error in ensureDeviceRegistered]: ');
    }
  }

  /// Register device token with role 'ADMIN' so supervisor alerts are delivered
  Future<void> registerAdminDevice() async {
    await ensureDeviceRegistered(role: 'ADMIN');
  }
}
