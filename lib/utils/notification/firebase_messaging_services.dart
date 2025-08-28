import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../utils/notification/notification_services.dart';
import 'package:esas/app/routes/app_pages.dart';
import 'package:esas/app/services/api_provider.dart';
import 'package:esas/app/widgets/views/snackbar.dart';

// --- Global Background Message Handler ---
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Pastikan Firebase diinisialisasi untuk background handler
  await Firebase.initializeApp();
  debugPrint("Background message: ${message.messageId}");
  debugPrint("Data: ${message.data}");
  debugPrint("Notification body: ${message.notification?.body}");

  NotificationService().showNotification(
    message.notification?.title ?? "Background Notification",
    message.notification?.body ?? "New background message",
  );
}

class FirebaseMessagingService extends GetxService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  late final NotificationService _notificationService;
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  final RxString _fcmToken = ''.obs;
  String get fcmToken => _fcmToken.value;

  @override
  void onInit() {
    super.onInit();
    _notificationService = Get.find<NotificationService>();
    _initializeFirebaseMessagingListeners();
  }

  /// Menginisialisasi semua listener Firebase Messaging.
  Future<void> _initializeFirebaseMessagingListeners() async {
    try {
      // 1. Meminta izin notifikasi dari pengguna
      await _requestPermissions();

      // 2. Pada iOS, ambil token APNS terlebih dahulu
      // Ini adalah langkah KRUSIAL untuk menghindari error "APNS token not set"
      if (Platform.isIOS) {
        String? apnsToken = await _firebaseMessaging.getAPNSToken();
        if (apnsToken == null) {
          debugPrint("Warning: APNS token is not yet available.");
        } else {
          debugPrint("APNS Token: $apnsToken");
        }
      }

      // 3. Mengambil dan mencetak token FCM
      await _getAndSetupFCMToken();

      // 4. Mengatur handler untuk berbagai skenario
      _setupMessageHandlers();
    } catch (e) {
      debugPrint("Error initializing Firebase Messaging: $e");
    }
  }

  /// Meminta izin notifikasi dari pengguna.
  Future<void> _requestPermissions() async {
    final settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('Notification permission granted.');
    } else {
      debugPrint('Notification permission denied or provisional.');
    }
  }

  /// Mengambil token FCM dan mengirimkannya ke server.
  Future<void> _getAndSetupFCMToken() async {
    final token = await _firebaseMessaging.getToken();
    if (token != null) {
      debugPrint("FCM Token: $token");
      _fcmToken.value = token;
      await setupToken(_fcmToken.value);
    } else {
      debugPrint("Unable to get FCM Token.");
      _fcmToken.value = '';
    }

    // Mendengarkan saat token diperbarui
    _firebaseMessaging.onTokenRefresh.listen(
      (newToken) async {
        debugPrint("FCM Token Refreshed: $newToken");
        _fcmToken.value = newToken;
        await setupToken(newToken);
      },
      onError: (err) {
        debugPrint("FCM Token Refresh Error: $err");
      },
    );
  }

  /// Mengatur semua listener pesan (foreground, background, opened app).
  void _setupMessageHandlers() {
    // Handler untuk pesan di foreground
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint("Foreground message: ${message.data}");
      _notificationService.showNotification(
        message.notification?.title ?? "New Notification",
        message.notification?.body ?? "You have a new message",
      );
    });

    // Handler untuk pesan saat aplikasi dibuka dari terminated/background
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('Notification opened app. Data: ${message.data}');
      _handleNotificationNavigation(message.data);
    });

    // Mengambil pesan awal jika aplikasi diluncurkan dari terminated oleh notifikasi
    _firebaseMessaging.getInitialMessage().then((initialMessage) {
      if (initialMessage != null) {
        debugPrint("Initial message opened app: ${initialMessage.data}");
        _handleNotificationNavigation(initialMessage.data);
      }
    });

    // Mengatur handler pesan background global
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  /// Helper method untuk menangani navigasi berdasarkan data notifikasi.
  void _handleNotificationNavigation(Map<String, dynamic> data) {
    if (data.containsKey('route')) {
      Get.toNamed(data['route'] as String, arguments: data);
    } else {
      Get.toNamed(Routes.NOTIFICATION, arguments: data);
    }
  }

  Future<void> setupToken(String token) async {
    Map<String, dynamic> datapost = {'token': token};
    debugPrint("ini data post setup token : $datapost");
    final response = await _apiProvider.post(
      '/general-module/auth/set-token',
      datapost,
    );
    if (response.statusCode == 200) {
      showSuccessSnackbar('Token FCM anda berhasil ditetapkan');
    } else {
      showErrorSnackbar('Terjadi kesalahan');
    }
  }

  @override
  void onClose() {
    // Bersihkan resource jika ada
    super.onClose();
  }
}
