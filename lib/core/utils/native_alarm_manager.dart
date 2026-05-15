// lib/core/utils/native_alarm_manager.dart
// ignore_for_file: avoid_print

import 'package:flutter/services.dart';

/// Bridges Flutter to the Android native AlarmManager via MethodChannel.
/// This ensures alarms fire reliably even on OPPO / Android 15 devices
/// that aggressively kill background processes.
class NativeAlarmManager {
  static const _platform = MethodChannel('com.medimate.app/native_alarm');

  /// Schedule a native exact alarm.
  ///
  /// [id]                    – Unique notification / alarm ID.
  /// [medicineName]          – Medicine to display and speak.
  /// [dosage]                – Dose string, e.g. "500mg".
  /// [instructions]          – Optional extra instructions.
  /// [scheduledTime]         – When the alarm should fire.
  /// [reminderId]            – Firestore reminder document ID (used when
  ///                           recording a dose log from the notification action).
  /// [originalScheduledTime] – The first/original scheduled time for this dose
  ///                           (remains constant across retry alarms so the dose
  ///                           history entry is linked to the correct slot).
  static Future<bool> scheduleAlarm({
    required int id,
    required String medicineName,
    required String dosage,
    required String instructions,
    required DateTime scheduledTime,
    String reminderId = '',
    DateTime? originalScheduledTime,
  }) async {
    try {
      print('📱 Scheduling NATIVE alarm...');
      print('   ID         : $id');
      print('   Medicine   : $medicineName');
      print('   Fire time  : $scheduledTime');
      print('   ReminderId : $reminderId');

      final result = await _platform.invokeMethod<bool>('scheduleAlarm', {
        'id'                 : id,
        'medicineName'       : medicineName,
        'dosage'             : dosage,
        'instructions'       : instructions,
        'triggerTimeMillis'  : scheduledTime.millisecondsSinceEpoch,
        'reminderId'         : reminderId,
        // Keep the original time so missed-dose history is accurate
        'scheduledTimeMillis': (originalScheduledTime ?? scheduledTime)
            .millisecondsSinceEpoch,
      });

      print('✅ Native alarm scheduled: $result');
      return result == true;
    } catch (e) {
      print('❌ Failed to schedule native alarm: $e');
      return false;
    }
  }

  /// Cancel a previously scheduled native alarm.
  static Future<bool> cancelAlarm(int id) async {
    try {
      final result = await _platform.invokeMethod<bool>('cancelAlarm', {
        'id': id,
      });
      print('🗑️ Native alarm cancelled: ID $id');
      return result == true;
    } catch (e) {
      print('❌ Failed to cancel native alarm: $e');
      return false;
    }
  }
}