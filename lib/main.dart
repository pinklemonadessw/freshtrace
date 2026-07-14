import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/household_setup_screen.dart';
import 'screens/navbar.dart';
import 'screens/verify_email_screen.dart';
import 'services/firestore_service.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await FirebaseAppCheck.instance.activate(
    webProvider: ReCaptchaV3Provider('6Lfh29osAAAAAAc9TKZM6lfPU4EzdsAakhd2jZrN')
  );
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FreshTrace',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.purple,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        // userChanges (not authStateChanges) so the app rebuilds after
        // User.reload(), which is how email verification gets detected.
        stream: FirebaseAuth.instance.userChanges(),
        builder: (context, authSnapshot) {
          if (authSnapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          if (!authSnapshot.hasData) {
            return const LoginScreen();
          }
          if (!authSnapshot.data!.emailVerified) {
            return const VerifyEmailScreen();
          }

          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(authSnapshot.data!.uid)
                .snapshots(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                    body: Center(child: CircularProgressIndicator()));
              }

              final data =
                  userSnapshot.data?.data() as Map<String, dynamic>?;
              final activeKitchenId =
                  data?['activeKitchenId'] as String?;

              if (activeKitchenId == null) {
                return const HouseholdSetupScreen();
              }

              FirestoreService.setActiveKitchen(activeKitchenId);
              return const MainShell();
            },
          );
        },
      ),
    );
  }
}
