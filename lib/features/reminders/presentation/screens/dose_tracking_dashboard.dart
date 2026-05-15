// ============================================
// FILE: lib/features/reminders/presentation/screens/dose_tracking_dashboard.dart
//
// CHANGES vs original:
//  1. _DoseLogCard now renders three distinct visual states:
//       • Taken  → green  ✅  "Taken"
//       • Missed → red    ❌  "Missed"   (includes no-action records,
//                                         which are stored as DoseStatus.missed
//                                         with notes = 'No action taken')
//  2. Subtitle shows the *source* of the action when available:
//       • taken    → "Taken at HH:mm"
//       • no-action → "Dismissed without action"
//       • missed   → "Missed" (+ retry info if present in notes)
//  3. Empty-state card is cleaner.
//  4. RefreshIndicator also invalidates adherenceRateProvider.
//  5. A small real-time stats row (taken / missed counts) sits below the
//     adherence card so the user sees instant feedback after every action.
// ============================================

// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/dose_log.dart';
import '../providers/reminder_provider.dart';

class DoseTrackingDashboard extends ConsumerWidget {
  const DoseTrackingDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adherenceAsync = ref.watch(adherenceRateProvider);
    final recentLogsAsync = ref.watch(recentDoseLogsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dose Tracking'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(adherenceRateProvider);
          ref.invalidate(recentDoseLogsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Adherence score ────────────────────────────────────────────
            adherenceAsync.when(
              data: (adherence) => _buildAdherenceCard(context, adherence),
              loading: () => _buildLoadingCard(),
              error: (_, __) => _buildErrorCard(),
            ),

            const SizedBox(height: 12),

            // ── Quick stats row (taken / missed) ──────────────────────────
            recentLogsAsync.when(
              data: (logs) => _buildStatsRow(context, logs),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 20),

            // ── Recent Activity header ────────────────────────────────────
            Text(
              'Recent Activity',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Last 7 days – updates automatically after each dose action',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),

            // ── Log list ──────────────────────────────────────────────────
            recentLogsAsync.when(
              data: (logs) {
                if (logs.isEmpty) return _buildEmptyState(context);
                return _buildLogsList(logs);
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error loading logs: $error',
                  style: TextStyle(color: Colors.red[400]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Adherence card ─────────────────────────────────────────────────────────
  Widget _buildAdherenceCard(BuildContext context, double adherence) {
    final color = adherence >= 80
        ? Colors.green
        : adherence >= 60
            ? Colors.orange
            : Colors.red;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withOpacity(0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            const Text(
              'Adherence Rate',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Text(
              '${adherence.toStringAsFixed(0)}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 48,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              adherence >= 80
                  ? '🎉 Excellent adherence!'
                  : adherence >= 60
                      ? '👍 Good, keep it up!'
                      : '💪 Let\'s improve together!',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Last 7 days',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Quick stats row ────────────────────────────────────────────────────────
  Widget _buildStatsRow(BuildContext context, List<DoseLog> logs) {
    final takenCount =
        logs.where((l) => l.status == DoseStatus.taken).length;
    final missedCount =
        logs.where((l) => l.status == DoseStatus.missed).length;

    return Row(
      children: [
        Expanded(
          child: _StatChip(
            icon: Icons.check_circle,
            color: Colors.green,
            label: 'Taken',
            count: takenCount,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatChip(
            icon: Icons.cancel,
            color: Colors.red,
            label: 'Missed',
            count: missedCount,
          ),
        ),
      ],
    );
  }

  // ── Loading / error / empty placeholders ───────────────────────────────────
  Widget _buildLoadingCard() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 12),
            const Text('Error loading adherence data'),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.history, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No activity yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Your dose records will appear here after you respond to '
            'a medicine reminder (or dismiss one).',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsList(List<DoseLog> logs) {
    return Column(
      children: logs.map((log) => _DoseLogCard(log: log)).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small stat chip used in the quick-stats row
// ─────────────────────────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int count;

  const _StatChip({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: color.withOpacity(0.8),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual dose log card
//
// Three visual states:
//   • Taken       – green  ✅  "Taken"
//   • Missed      – red    ❌  "Missed"
//   • (no-action is stored as missed with notes = 'No action taken' / 'No
//     action – retry N of 5', so it renders exactly like Missed.  The notes
//     string is shown in the subtitle so the user can tell them apart.)
// ─────────────────────────────────────────────────────────────────────────────
class _DoseLogCard extends StatelessWidget {
  final DoseLog log;

  const _DoseLogCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final isTaken = log.status == DoseStatus.taken;

    // Colour scheme: green for taken, red for missed/no-action.
    final color = isTaken ? Colors.green : Colors.red;
    final icon = isTaken ? Icons.check_circle : Icons.cancel;
    final statusLabel = isTaken ? 'Taken' : 'Missed';

    // Build a human-readable subtitle.
    final dateStr = DateFormat('MMM dd, hh:mm a').format(log.scheduledTime);
    String subtitleSuffix;
    if (isTaken && log.takenAt != null) {
      subtitleSuffix =
          ' • Taken at ${DateFormat('hh:mm a').format(log.takenAt!)}';
    } else if (!isTaken &&
        log.notes != null &&
        log.notes!.toLowerCase().contains('no action')) {
      // Distinguish "dismissed without action" from "tapped ❌ Missed"
      subtitleSuffix = ' • Dismissed (no action)';
    } else if (!isTaken &&
        log.notes != null &&
        log.notes!.toLowerCase().startsWith('retry')) {
      subtitleSuffix = ' • ${log.notes}';
    } else {
      subtitleSuffix = '';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          log.medicineName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '$dateStr$subtitleSuffix',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            statusLabel,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
