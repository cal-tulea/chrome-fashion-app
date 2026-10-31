import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

import 'core/theme.dart';
import 'screens/explore/explore_screen.dart';
import 'screens/canvas/canvas_screen.dart';
import 'screens/camera/camera_screen.dart';
import 'screens/closet/closet_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/auth/auth_gate.dart';
import 'widgets/bottom_nav.dart';
import 'widgets/screen_scaffold.dart';
import 'core/nav_state.dart';
import 'services/closet_service.dart';
import 'services/correction_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Crashlytics — catch all unhandled errors in production builds only
  if (!kDebugMode) {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  // Analytics — disabled in debug so dev sessions don't pollute data
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(!kDebugMode);

  await ClosetService().load();
  await CorrectionService().load();
  runApp(const FashionApp());
}

class FashionApp extends StatelessWidget {
  const FashionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Chromé',
      theme: AppTheme.dark,
      home: const AuthGate(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  // Feed opens first, then Canvas, Camera, Closet, Profile
  final List<Widget> _screens = const [
    ExploreScreen(),
    CanvasScreen(),
    CameraScreen(),
    ClosetScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    globalNavIndex.addListener(_onNavChange);
  }

  @override
  void dispose() {
    globalNavIndex.removeListener(_onNavChange);
    super.dispose();
  }

  void _onNavChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final idx = globalNavIndex.value;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ScreenScaffold(child: _screens[idx]),
      bottomNavigationBar: BottomNavBar(
        currentIndex: idx,
        onTap: (index) => setState(() => globalNavIndex.value = index),
      ),
    );
  }
}
