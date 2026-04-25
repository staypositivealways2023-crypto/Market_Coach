import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:market_coach/app/market_coach_app.dart';
import 'config/api_config.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseAuth.instance.setLanguageCode('en');

  // FCM background handler — mobile only (not available on web)
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }
  await NotificationService.initialize();

  // ── RevenueCat — mobile only (purchases_flutter does not support web) ──────
  if (!kIsWeb) {
    await Purchases.configure(
      PurchasesConfiguration(APIConfig.revenueCatApiKey),
    );
  }

  runApp(const ProviderScope(child: MarketCoachApp()));
}
