import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'screens/auth_gate.dart';
import 'services/fcm_service.dart';

final GlobalKey<ScaffoldMessengerState> rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Day 5: must be registered before runApp — this is what lets FCM
  // wake a background isolate to show a system notification when the
  // app isn't in the foreground.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(const AtlasAIApp());
}

class AtlasAIApp extends StatefulWidget {
  const AtlasAIApp({super.key});

  @override
  State<AtlasAIApp> createState() => _AtlasAIAppState();
}

class _AtlasAIAppState extends State<AtlasAIApp> {
  @override
  void initState() {
    super.initState();
    // Fire-and-forget: subscribes to the 'lessons_learned' topic and
    // requests notification permission. Doesn't block first frame —
    // permission prompts feel better after the UI is already visible.
    FcmService().init(rootMessengerKey);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AtlasAI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      scaffoldMessengerKey: rootMessengerKey,
      home: const AuthGate(),
    );
  }
}
