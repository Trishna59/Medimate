// lib/core/utils/notification_service.dart
//
// ══════════════════════════════════════════════════════════════════════════════
// ANDROID 15 (API 35) COMPATIBLE NOTIFICATION SERVICE
// ══════════════════════════════════════════════════════════════════════════════
//
// ONLY CHANGE vs original:
//   _listenToAlarmEvents() now has a 'dose_no_action' handler so that when
//   the user dismisses the notification without tapping any button, the event
//   is forwarded to _handleDoseAction() and saved to Firestore as missed.
//   ALL other code is IDENTICAL to the original.
//
// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'native_alarm_manager.dart';
import 'text_to_speech_service.dart';

// ── Callback type for dose actions coming from the notification shade ─────────
// 'event' is one of: 'dose_taken' | 'dose_missed' | 'dose_no_action'
typedef DoseActionCallback = Future<void> Function({
  required String event,
  required int notificationId,
  required String reminderId,
  required String medicineName,
  required String dosage,
  required DateTime scheduledTime,
  required int retryCount,
});

class NotificationService {
  // Singleton
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final TextToSpeechService _tts = TextToSpeechService();

  bool _isInitialized = false;

  // ── EventChannel – receives alarm_fired, dose_taken, dose_missed, dose_no_action
  static const EventChannel _alarmEventChannel =
      EventChannel('com.medimate.app/alarm_events');
  StreamSubscription? _alarmEventSubscription;

  /// Register an external handler for dose actions (taken / missed / no_action).
  DoseActionCallback? onDoseAction;

  // ══════════════════════════════════════════════════════════════════════════
  // INITIALIZATION
  // ══════════════════════════════════════════════════════════════════════════

  @pragma('vm:entry-point')
  static void _onBackgroundNotificationTapped(NotificationResponse response) {
    print('🔔 BACKGROUND notification tapped – ID: ${response.id}');
  }

  Future<void> initialize() async {
    if (_isInitialized) {
      print('ℹ️ NotificationService already initialized');
      return;
    }
    print('🔔 Initializing NotificationService for Android 15...');
    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _notifications.initialize(
        const InitializationSettings(
            android: androidSettings, iOS: iosSettings),
        onDidReceiveNotificationResponse: _onNotificationTapped,
        onDidReceiveBackgroundNotificationResponse:
            _onBackgroundNotificationTapped,
      );
      print('✅ Plugin initialized');
      await _requestAllPermissions();
      await _verifyPermissions();
      _listenToAlarmEvents();
      _isInitialized = true;
      print('✅ NotificationService fully initialized\n');
    } catch (e) {
      print('❌ NotificationService initialization error: $e');
      rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ALARM EVENT LISTENER  (alarm_fired | dose_taken | dose_missed | dose_no_action)
  // ══════════════════════════════════════════════════════════════════════════

  void _listenToAlarmEvents() {
    print('📡 Setting up alarm event listener...');
    _alarmEventSubscription = _alarmEventChannel
        .receiveBroadcastStream()
        .listen((dynamic event) async {
      try {
        if (event is! Map) return;
        final eventType = event['event'] as String?;
        final id = event['id'] as int?;

        // ── Alarm fired (original reminder time) ─────────────────────────
        if (eventType == 'alarm_fired' && id != null) {
          print('🔔 Alarm fired event: ID $id');
          try {
            await _notifications.cancel(id);
            print('✅ Cancelled Flutter notification: ID $id');
          } catch (e) {
            print('❌ Error cancelling notification: $e');
          }
          return;
        }

        // ── Dose TAKEN from notification ✅ button ───────────────────────
        if (eventType == 'dose_taken') {
          print('✅ dose_taken event received for ${event['medicineName']}');
          await _handleDoseAction(event, 'dose_taken');
          return;
        }

        // ── Dose MISSED from notification ❌ button ──────────────────────
        if (eventType == 'dose_missed') {
          print('❌ dose_missed event received for ${event['medicineName']}');
          await _handleDoseAction(event, 'dose_missed');
          return;
        }

        // ────────────────────────────────────────────────────────────────
        // FIX: Dose NO-ACTION — notification swiped away without any tap.
        // Previously this case was silently dropped, so nothing was recorded
        // on the Dose Tracking page when the user dismissed a notification.
        // Now we forward it exactly like dose_missed.
        // ────────────────────────────────────────────────────────────────
        if (eventType == 'dose_no_action') {
          print(
              '🔕 dose_no_action event received for ${event['medicineName']}');
          await _handleDoseAction(event, 'dose_no_action');
          return;
        }
      } catch (e) {
        print('❌ Error handling alarm event: $e');
      }
    }, onError: (error) {
      print('❌ Alarm event stream error: $error');
    });
    print('✅ Alarm event listener active');
  }

  Future<void> _handleDoseAction(Map event, String eventType) async {
    final notificationId = _toInt(event['notificationId']);
    final reminderId = event['reminderId'] as String? ?? '';
    final medicineName = event['medicineName'] as String? ?? '';
    final dosage = event['dosage'] as String? ?? '';
    final scheduledMs = _toLong(event['scheduledTime']);
    final retryCount = _toInt(event['retryCount']);
    final scheduledTime = DateTime.fromMillisecondsSinceEpoch(scheduledMs);

    if (onDoseAction != null) {
      await onDoseAction!(
        event: eventType,
        notificationId: notificationId,
        reminderId: reminderId,
        medicineName: medicineName,
        dosage: dosage,
        scheduledTime: scheduledTime,
        retryCount: retryCount,
      );
    } else {
      print('⚠️ onDoseAction callback not set – cannot process $eventType');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SCHEDULING
  // ══════════════════════════════════════════════════════════════════════════

  /// Schedule a single reminder alarm.
  Future<void> scheduleReminder({
    required int id,
    required String medicineName,
    required String dosage,
    required DateTime scheduledTime,
    String? instructions,
    String reminderId = '',
    bool speakNow = false,
  }) async {
    await initialize();
    print('\n🔔 SCHEDULING REMINDER');
    print('ID        : $id');
    print('Medicine  : $medicineName');
    print('Dosage    : $dosage');
    print('Scheduled : $scheduledTime');
    print('ReminderId: $reminderId');

    final now = DateTime.now();
    if (scheduledTime.isBefore(now)) {
      print('❌ Time is in the past – SKIPPING');
      return;
    }

    try {
      // 1. Schedule native Android alarm (reliable on OPPO / Doze mode)
      final nativeSuccess = await NativeAlarmManager.scheduleAlarm(
        id: id,
        medicineName: medicineName,
        dosage: dosage,
        instructions: instructions ?? '',
        scheduledTime: scheduledTime,
        reminderId: reminderId,
        originalScheduledTime: scheduledTime,
      );
      if (nativeSuccess) print('✅ Native alarm scheduled');

      // 2. Also schedule via flutter_local_notifications for the pending list
      final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);
      final androidDetails = AndroidNotificationDetails(
        'medicine_reminders',
        'Medicine Reminders',
        channelDescription: 'Time-sensitive medicine reminders',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
        styleInformation: BigTextStyleInformation(
          '$medicineName – $dosage'
          '${instructions != null ? '\n$instructions' : ''}',
        ),
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      );
      await _notifications.zonedSchedule(
        id,
        '💊 Medicine Reminder',
        '$medicineName – $dosage',
        tzTime,
        NotificationDetails(android: androidDetails, iOS: iosDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload:
            'reminder:$id|$medicineName|$dosage|${instructions ?? ''}|$reminderId',
      );
      print('✅ Flutter notification scheduled');

      // Verify
      final pending = await getPendingNotifications();
      final scheduled = pending.any((n) => n.id == id);
      print(scheduled
          ? '✅ VERIFIED: In pending list (total: ${pending.length})'
          : '⚠️ WARNING: Not found in pending list');
    } catch (e) {
      print('❌ SCHEDULING ERROR: $e');
      rethrow;
    }

    if (speakNow) {
      await _tts.speakReminder(
          medicineName: medicineName,
          dosage: dosage,
          instructions: instructions);
    }
  }

  /// Schedule daily reminders for multiple times-of-day.
  Future<void> scheduleDailyReminders({
    required int baseId,
    required String medicineName,
    required String dosage,
    required List<String> times,
    String? instructions,
    String reminderId = '',
  }) async {
    await initialize();
    print('\n🔔 SCHEDULING ${times.length} DAILY REMINDERS for $medicineName');
    final now = tz.TZDateTime.now(tz.local);
    int successCount = 0;

    for (int i = 0; i < times.length; i++) {
      try {
        final parts = times[i].split(':');
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        var scheduled =
            tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
        if (scheduled.isBefore(now)) {
          scheduled = scheduled.add(const Duration(days: 1));
          print('⏰ ${times[i]} passed today – scheduling for tomorrow');
        }
        await scheduleReminder(
          id: baseId + i,
          medicineName: medicineName,
          dosage: dosage,
          scheduledTime: scheduled.toLocal(),
          instructions: instructions,
          reminderId: reminderId,
        );
        successCount++;
        print('✅ [$successCount/${times.length}] Scheduled ${times[i]}');
      } catch (e) {
        print('❌ Failed to schedule ${times[i]}: $e');
      }
    }
    print('✅ Scheduled $successCount/${times.length} reminders\n');
    await _verifyScheduledCount(baseId, successCount);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CANCELLATION
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> cancelReminder(int id) async {
    await _notifications.cancel(id);
    print('🗑️ Cancelled notification ID: $id');
  }

  Future<void> cancelRemindersByBaseId(int baseId) async {
    for (int i = 0; i < 100; i++) {
      await _notifications.cancel(baseId + i);
    }
    print('✅ Cancelled up to 100 IDs from base $baseId');
  }

  Future<void> cancelAll() async {
    await _notifications.cancelAll();
    print('🗑️ Cancelled ALL notifications');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // QUERIES
  // ══════════════════════════════════════════════════════════════════════════

  Future<List<PendingNotificationRequest>> getPendingNotifications() async =>
      _notifications.pendingNotificationRequests();

  Future<void> _verifyScheduledCount(int baseId, int expected) async {
    try {
      final pending = await getPendingNotifications();
      final relevant =
          pending.where((n) => n.id >= baseId && n.id < baseId + 100).toList();
      print('\n📊 VERIFICATION: expected=$expected, found=${relevant.length}');
      if (relevant.length != expected) print('⚠️ Mismatch!');
      for (final n in relevant) {
        print('  • ID ${n.id}: ${n.title}');
      }
    } catch (e) {
      print('⚠️ Verification error: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TESTING / DEBUGGING
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> showImmediateNotification({
    required int id,
    required String title,
    required String body,
    bool speak = true,
  }) async {
    await initialize();
    final androidDetails = AndroidNotificationDetails(
      'medicine_reminders',
      'Medicine Reminders',
      channelDescription: 'Immediate test notifications',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
      styleInformation: BigTextStyleInformation(body),
    );
    await _notifications.show(
      id,
      title,
      body,
      NotificationDetails(android: androidDetails),
      payload: 'immediate:$id',
    );
    print('✅ Immediate notification shown (ID: $id)');
    if (speak) await _tts.speak(body);
  }

  Future<Map<String, dynamic>> getStatus() async {
    final pending = await getPendingNotifications();
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    bool? notifPerm, exactAlarm;
    if (androidPlugin != null) {
      notifPerm = await androidPlugin.areNotificationsEnabled();
      try {
        exactAlarm = await androidPlugin.canScheduleExactNotifications();
      } catch (_) {}
    }
    final battery = await Permission.ignoreBatteryOptimizations.status;
    return {
      'isInitialized': _isInitialized,
      'notificationPermission': notifPerm ?? 'unknown',
      'exactAlarmPermission': exactAlarm ?? 'unknown',
      'batteryOptimization': battery.isGranted ? 'exempted' : 'not exempted',
      'pendingCount': pending.length,
      'pendingReminders': pending
          .map((n) => {'id': n.id, 'title': n.title, 'body': n.body})
          .toList(),
    };
  }

  // ══════════════════════════════════════════════════════════════════════════
  // NOTIFICATION TAPPED HANDLER
  // ══════════════════════════════════════════════════════════════════════════

  void _onNotificationTapped(NotificationResponse response) {
    print(
        '🔔 Notification tapped – action=${response.actionId} payload=${response.payload}');
    _refreshPendingCount();
    if (response.actionId == null &&
        response.payload != null &&
        response.payload!.contains('|')) {
      final parts = response.payload!.split('|');
      if (parts.length >= 3) {
        _tts.speakReminder(
          medicineName: parts[1],
          dosage: parts[2],
          instructions: parts.length > 3 ? parts[3] : null,
        );
      }
    }
  }

  Future<void> _refreshPendingCount() async {
    try {
      final pending = await getPendingNotifications();
      print('📊 Pending count: ${pending.length}');
    } catch (e) {
      print('⚠️ Error refreshing count: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PERMISSIONS
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _requestAllPermissions() async {
    print('\n🔐 Requesting Android 15 Permissions...');
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;
    try {
      final g = await androidPlugin.requestNotificationsPermission();
      print('  Notifications: ${g == true ? '✅' : '❌'}');
    } catch (e) {
      print('  Notifications error: $e');
    }
    try {
      final g = await androidPlugin.requestExactAlarmsPermission();
      print('  Exact alarms: ${g == true ? '✅' : '❌'}');
    } catch (e) {
      print('  Exact alarms error: $e');
    }
    try {
      final g = await androidPlugin.requestFullScreenIntentPermission();
      print('  Full screen: ${g == true ? '✅' : '❌'}');
    } catch (e) {
      print('  Full screen error: $e');
    }
    try {
      final s = await Permission.ignoreBatteryOptimizations.request();
      print('  Battery exemption: ${s.isGranted ? '✅' : '❌'}');
    } catch (e) {
      print('  Battery error: $e');
    }
    print('✅ Permission requests done\n');
  }

  Future<void> _verifyPermissions() async {
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;
    final notifEnabled = await androidPlugin.areNotificationsEnabled();
    final canScheduleExact =
        await androidPlugin.canScheduleExactNotifications();
    final battery = await Permission.ignoreBatteryOptimizations.status;
    print('Notifications: ${notifEnabled == true ? '✅' : '❌'}');
    print('Exact alarms : ${canScheduleExact == true ? '✅' : '❌'}');
    print('Battery exemp: ${battery.isGranted ? '✅' : '❌'}');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PUBLIC HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> speakReminder({
    required String medicineName,
    required String dosage,
    String? instructions,
  }) async =>
      _tts.speakReminder(
          medicineName: medicineName,
          dosage: dosage,
          instructions: instructions);

  Future<void> testNotification() async => showImmediateNotification(
        id: 999_999,
        title: '💊 Test Medicine Reminder',
        body: 'Paracetamol – 500mg\nTake with food',
        speak: true,
      );

  void dispose() {
    _alarmEventSubscription?.cancel();
    _tts.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // UTILITY
  // ══════════════════════════════════════════════════════════════════════════

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static int _toLong(dynamic v) => _toInt(v);
}