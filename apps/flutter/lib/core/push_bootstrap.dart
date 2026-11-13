import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Public Firebase app identifiers can be supplied at native build time.
/// No backend service-account credentials are ever compiled into the app.
const firebaseApiKey = String.fromEnvironment('OAGENT_FIREBASE_API_KEY');
const firebaseProject = String.fromEnvironment('OAGENT_FIREBASE_PROJECT_ID');
const firebaseSender = String.fromEnvironment('OAGENT_FIREBASE_SENDER_ID');
const firebaseAndroidId = String.fromEnvironment('OAGENT_FIREBASE_ANDROID_APP_ID');
const firebaseIosId = String.fromEnvironment('OAGENT_FIREBASE_IOS_APP_ID');

bool get hasPushConfiguration =>
  firebaseApiKey.isNotEmpty && firebaseProject.isNotEmpty &&
  firebaseSender.isNotEmpty && (Platform.isIOS
    ? firebaseIosId.isNotEmpty : firebaseAndroidId.isNotEmpty);

/// We never process sensitive approval data in a background isolate.
/// An OS notification only opens the authenticated O-AGENT application.
@pragma('vm:entry-point')
Future<void> oAgentBackgroundPushHandler(RemoteMessage message) async {
  // Deliberately empty. FCM presents the minimal notification payload.
  // The app fetches authoritative approval state after the user opens it.
}

Future<bool> configureFirebaseMessaging() async {
  if (!hasPushConfiguration) return false;
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: FirebaseOptions(
        apiKey: firebaseApiKey,
        projectId: firebaseProject,
        messagingSenderId: firebaseSender,
        appId: Platform.isIOS ? firebaseIosId : firebaseAndroidId,
      ));
    }
    FirebaseMessaging.onBackgroundMessage(oAgentBackgroundPushHandler);
    if (Platform.isIOS) {
      await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true, badge: true, sound: true);
    }
    return true;
  } catch (e) {
    // Firebase is an opt-in optional integration. A failed configuration
    // never prevents basic owner login or real agent approvals in the app.
    debugPrint('Optional Firebase push initialization failed.');
    return false;
  }
}
