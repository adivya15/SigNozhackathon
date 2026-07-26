import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

/// Day 5: subscribes every device to the 'lessons_learned' topic (the
/// backend's notification_service.dart sends to this same topic name),
/// requests notification permission, and surfaces foreground messages
/// via a SnackBar since FCM does not show a system banner automatically
/// while the app is in the foreground.
///
/// Background/terminated-state notifications are handled by the OS
/// automatically once the background handler below is registered — no
/// extra UI code needed for that case.
class FcmService {
  final _messaging = FirebaseMessaging.instance;

  Future<void> init(GlobalKey<ScaffoldMessengerState> messengerKey) async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    await _messaging.subscribeToTopic('lessons_learned');

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final title = message.notification?.title ?? 'AtlasAI Alert';
      final body = message.notification?.body ?? '';
      messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('$title — $body'),
          duration: const Duration(seconds: 6),
        ),
      );
    });
  }
}

/// Must be a top-level (or static) function — the OS invokes this in a
/// separate isolate when a notification arrives while the app is
/// backgrounded or terminated. Register it in main.dart BEFORE runApp,
/// via FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Intentionally minimal — the OS renders the system notification
  // automatically from message.notification. Add analytics/logging
  // here later if needed, but avoid heavy work: background isolates
  // have a limited execution window.
}
