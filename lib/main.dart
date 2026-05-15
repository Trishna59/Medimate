// ============================================
// FILE: lib/main.dart
// FIX: Eagerly initialize ReminderRepository via ProviderContainer +
//      UncontrolledProviderScope so the onDoseAction callback is wired
//      BEFORE any notification action can arrive.
//
// Root cause of the missing dose-tracking records:
//   Riverpod providers are LAZY – ReminderRepository (which sets
//   NotificationService.onDoseAction in its constructor) was never
//   created until a widget first watched reminderRepositoryProvider.
//   If a notification action arrived before that, onDoseAction was null
//   and nothing was written to Firestore → nothing appeared on the
//   Dose Tracking page.
//
// Fix:
//   1. Create a global ProviderContainer before runApp.
//   2. Call container.read(reminderRepositoryProvider) to force
//      construction of ReminderRepository (and therefore wiring of
//      onDoseAction) immediately on app start.
//   3. Pass the container to UncontrolledProviderScope so the entire
//      widget tree shares the same provider instances.
// ============================================

// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'core/config/firebase_options.dart';
import 'core/utils/notification_service.dart';
import 'features/reminders/presentation/providers/reminder_provider.dart'; // ← NEW
import 'shared/theme/app_theme.dart';
import 'routes/app_router.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Global ProviderContainer – created before runApp so we can eagerly
// read providers that must be alive from the very start.
// ─────────────────────────────────────────────────────────────────────────────
final _container = ProviderContainer();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Firebase ────────────────────────────────────────────────────────────
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ Firebase initialized successfully');
  } catch (e) {
    print('❌ Firebase initialization error: $e');
  }

  // ── Timezone ─────────────────────────────────────────────────────────────
  try {
    print('🌍 Initializing timezones...');
    tz.initializeTimeZones();
    final kathmandu = tz.getLocation('Asia/Kathmandu');
    tz.setLocalLocation(kathmandu);
    print('✅ Timezone set to: ${kathmandu.name}');
    print('   Current time: ${tz.TZDateTime.now(kathmandu)}');
  } catch (e) {
    print('⚠️ Timezone initialization error: $e');
    print('   Falling back to system timezone');
  }

    await NotificationService().initialize();       // sets up EventChannel listener
      _container.read(reminderRepositoryProvider);    // ← THE FIX: sets onDoseAction immediately

      runApp(
        UncontrolledProviderScope(                    // shares _container with widget tree
          container: _container,
          child: const MediMateApp(),
        ),
      );
    
  // ── Notification service ─────────────────────────────────────────────────
  try {
    print('🔔 Initializing notification service...');
    await NotificationService().initialize();
    print('✅ Notification service initialized');
  } catch (e) {
    print('❌ Notification service initialization error: $e');
  }

  // ── CRITICAL FIX: Eagerly initialize ReminderRepository ─────────────────
  //
  // ReminderRepository sets NotificationService.onDoseAction in its
  // constructor.  Without this line the repository is only created when a
  // widget first watches reminderRepositoryProvider, which can easily happen
  // AFTER the user has already tapped a notification action button.
  // Reading the provider here forces construction immediately, guaranteeing
  // that onDoseAction is non-null before any notification event arrives.
  //
  try {
    _container.read(reminderRepositoryProvider);
    print('✅ ReminderRepository eagerly initialized – onDoseAction wired');
  } catch (e) {
    print('❌ Failed to eagerly initialize ReminderRepository: $e');
  }

  // ── Orientation / status-bar ─────────────────────────────────────────────
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // ── Launch app ───────────────────────────────────────────────────────────
  //
  // UncontrolledProviderScope hands the pre-built container to the widget
  // tree so every widget that watches a provider uses the SAME instances
  // (including the already-initialized ReminderRepository).
  runApp(
    UncontrolledProviderScope(
      container: _container,
      child: const MediMateApp(),
    ),
  );
}

class MediMateApp extends ConsumerWidget {
  const MediMateApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'MediMate',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      routerConfig: router,
    );
  }
}
