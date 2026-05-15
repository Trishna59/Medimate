// lib/features/medicine/presentation/screens/medicine_admin_screen.dart
// ============================================================
// ADMIN SCREEN — Updated with Local Cache Management
//
// NEW BUTTONS:
//   "Build Local Cache" — downloads all medicines from Firestore and
//   saves them to a local JSON file. Run this ONCE after seeding/
//   importing. After that, searches never hit Firestore again.
//
//   "Clear Local Cache" — wipes the file (useful for troubleshooting
//   or after a large update to the database).
// ============================================================
// ignore_for_file: avoid_print, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/medicine_database_seeder.dart';
import '../../data/medicine_csv_importer.dart';
import '../../data/repositories/medicine_repository.dart';
import '../../data/local/medicine_cache_service.dart';

class MedicineAdminScreen extends ConsumerStatefulWidget {
  const MedicineAdminScreen({super.key});

  @override
  ConsumerState<MedicineAdminScreen> createState() =>
      _MedicineAdminScreenState();
}

class _MedicineAdminScreenState extends ConsumerState<MedicineAdminScreen> {
  bool _isSeeding     = false;
  bool _isImporting   = false;
  bool _isBuilding    = false; // building local cache
  bool _isClearing    = false; // clearing local cache
  bool _isLoading     = false;

  int  _medicineCount = 0;
  int  _cacheCount    = 0;
  bool _cacheReady    = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    setState(() => _isLoading = true);
    try {
      final repo = MedicineRepository();
      final medicines = await repo.getAllMedicines();
      final info     = await repo.getCacheInfo();
      if (mounted) {
        setState(() {
          _medicineCount = medicines.length;
          _cacheCount    = info['count'] as int;
          _cacheReady    = info['isReady'] as bool;
          _isLoading     = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Seed with built-in sample data ───────────────────────────────────────
  Future<void> _seedDatabase() async {
    final confirmed = await _confirm(
      'Seed Database',
      _medicineCount > 0
          ? 'Database has $_medicineCount medicines. This will ADD more. Continue?'
          : 'This will add 5 sample medicines. Continue?',
    );
    if (confirmed != true) return;

    setState(() { _isSeeding = true; _message = null; });
    try {
      final repo    = MedicineRepository();
      final seeder  = MedicineDatabaseSeeder(repo);
      await seeder.seedDatabase();
      await _loadCounts();
      if (mounted) {
        setState(() { _isSeeding = false; _message = '✅ Seeded successfully! Now tap "Build Local Cache".'; });
        _snack('✅ Database seeded! Remember to build the local cache.', Colors.green);
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isSeeding = false; _message = '❌ Error: $e'; });
        _snack('Error: $e', Colors.red);
      }
    }
  }

  // ── Import from CSV asset ─────────────────────────────────────────────────
  Future<void> _importCsv() async {
    final confirmed = await _confirm(
      'Import from CSV',
      'This will import medicines from assets/medicines_template.csv\n\n'
      'Make sure you have added the file and declared it in pubspec.yaml:\n\n'
      '  assets:\n    - assets/medicines_template.csv',
    );
    if (confirmed != true) return;

    setState(() { _isImporting = true; _message = null; });
    try {
      final csvString = await rootBundle.loadString('assets/medicines_template.csv');
      final importer  = MedicineCsvImporter(MedicineRepository());
      final result    = await importer.importFromCsvString(csvString);

      await _loadCounts();
      if (mounted) {
        setState(() {
          _isImporting = false;
          _message = '✅ Imported ${result.success} medicines.'
              '${result.failed > 0 ? '\n❌ ${result.failed} failed.' : ''}'
              '\n\n👉 Now tap "Build Local Cache" to enable fast search!';
        });
        _snack('Imported ${result.success} medicines! Build the cache next.', Colors.green);
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isImporting = false; _message = '❌ Error: $e'; });
        _snack('Error: $e', Colors.red);
        if (e.toString().contains('Unable to load')) _showAssetHelp();
      }
    }
  }

  // ── BUILD LOCAL CACHE ─────────────────────────────────────────────────────
  // This is the KEY step that makes searches fast.
  Future<void> _buildLocalCache() async {
    final confirmed = await _confirm(
      'Build Local Cache',
      'This downloads all $_medicineCount medicines from Firestore '
      'and saves them on the device.\n\n'
      'After this, medicine searches will be INSTANT (no internet needed).\n\n'
      'This may take 30–60 seconds depending on your connection.',
    );
    if (confirmed != true) return;

    setState(() { _isBuilding = true; _message = null; });
    try {
      final repo   = MedicineRepository();
      final result = await repo.buildLocalCache();

      await _loadCounts();
      if (mounted) {
        if (result.success) {
          setState(() {
            _isBuilding = false;
            _message = '🚀 Local cache built!\n'
                '${result.count} medicines saved to device.\n'
                'Searches are now instant — no internet needed!';
          });
          _snack('🚀 Cache built! ${result.count} medicines ready for fast search.', Colors.green);
        } else {
          setState(() {
            _isBuilding = false;
            _message = '❌ Cache build failed: ${result.error}';
          });
          _snack('Cache build failed: ${result.error}', Colors.red);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isBuilding = false; _message = '❌ Error: $e'; });
        _snack('Error: $e', Colors.red);
      }
    }
  }

  // ── CLEAR LOCAL CACHE ─────────────────────────────────────────────────────
  Future<void> _clearLocalCache() async {
    final confirmed = await _confirm(
      'Clear Local Cache',
      'This will delete the local medicine cache from this device.\n\n'
      'Searches will fall back to Firestore (slower) until you rebuild the cache.',
      destructive: true,
    );
    if (confirmed != true) return;

    setState(() { _isClearing = true; _message = null; });
    try {
      await MedicineCacheService().clearCache();
      await _loadCounts();
      if (mounted) {
        setState(() {
          _isClearing  = false;
          _message     = '🗑️ Local cache cleared. Tap "Build Local Cache" to rebuild.';
        });
        _snack('Cache cleared', Colors.orange);
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isClearing = false; _message = '❌ Error: $e'; });
      }
    }
  }

  // ── Clear all Firestore medicines ─────────────────────────────────────────
  Future<void> _clearDatabase() async {
    final confirmed = await _confirm(
      'Clear Database',
      '⚠️ This will DELETE ALL $_medicineCount medicines from Firestore. Cannot be undone!',
      destructive: true,
    );
    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final repo      = MedicineRepository();
      final medicines = await repo.getAllMedicines();
      for (final m in medicines) {
        await repo.deleteMedicine(m.id);
      }
      await _loadCounts();
      if (mounted) _snack('✅ Database cleared', Colors.orange);
    } catch (e) {
      if (mounted) _snack('Error: $e', Colors.red);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Medicine Admin'),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Stats card ─────────────────────────────────────────────
            _StatsCard(
              firestoreCount: _medicineCount,
              cacheCount:     _cacheCount,
              cacheReady:     _cacheReady,
              isLoading:      _isLoading,
              onRefresh:      _loadCounts,
            ),

            const SizedBox(height: 20),

            // ── Status message ─────────────────────────────────────────
            if (_message != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _message!.startsWith('❌') ? Colors.red[50] : Colors.green[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _message!.startsWith('❌') ? Colors.red[200]! : Colors.green[200]!,
                  ),
                ),
                child: Text(
                  _message!,
                  style: TextStyle(
                    color: _message!.startsWith('❌') ? Colors.red[900] : Colors.green[900],
                    height: 1.5,
                  ),
                ),
              ),

            if (_message != null) const SizedBox(height: 20),

            // ── Section: Firestore ──────────────────────────────────────
            _sectionHeader('Firestore Database', Icons.cloud),
            const SizedBox(height: 10),

            _AdminButton(
              label: 'Seed Sample Data (5 medicines)',
              icon: Icons.science,
              color: Colors.blue,
              isLoading: _isSeeding,
              onTap: _seedDatabase,
            ),
            const SizedBox(height: 10),

            _AdminButton(
              label: 'Import from CSV (medicines_template.csv)',
              icon: Icons.upload_file,
              color: Colors.indigo,
              isLoading: _isImporting,
              onTap: _importCsv,
            ),

            const SizedBox(height: 24),

            // ── Section: Local Cache ────────────────────────────────────
            _sectionHeader('Local Cache (Fast Search)', Icons.speed),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'After seeding or importing, build the local cache so '
                'medicine searches are instant (< 200 ms) instead of '
                'downloading from Firestore every time (10–30 s).',
                style: TextStyle(color: Colors.grey[600], fontSize: 13, height: 1.4),
              ),
            ),

            _AdminButton(
              label: _cacheReady
                  ? 'Rebuild Local Cache ($_cacheCount medicines cached)'
                  : 'Build Local Cache  ← DO THIS after importing',
              icon: Icons.rocket_launch,
              color: Colors.green[700]!,
              isLoading: _isBuilding,
              onTap: _buildLocalCache,
              highlighted: !_cacheReady,
            ),
            const SizedBox(height: 10),

            _AdminButton(
              label: 'Clear Local Cache',
              icon: Icons.delete_outline,
              color: Colors.orange,
              isLoading: _isClearing,
              onTap: _clearLocalCache,
            ),

            const SizedBox(height: 24),

            // ── Section: Danger zone ────────────────────────────────────
            _sectionHeader('Danger Zone', Icons.warning_amber, danger: true),
            const SizedBox(height: 10),

            _AdminButton(
              label: 'Clear All Firestore Medicines',
              icon: Icons.delete_forever,
              color: Colors.red,
              isLoading: _isLoading,
              onTap: _clearDatabase,
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, {bool danger = false}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: danger ? Colors.red : Colors.green[700]),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: danger ? Colors.red : Colors.green[800],
          ),
        ),
      ],
    );
  }

  // ── Dialogs / snack ──────────────────────────────────────────────────────

  Future<bool?> _confirm(String title, String body, {bool destructive = false}) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: destructive
                  ? TextButton.styleFrom(foregroundColor: Colors.red)
                  : null,
              child: const Text('Confirm'),
            ),
          ],
        ),
      );

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      duration: const Duration(seconds: 4),
    ));
  }

  void _showAssetHelp() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('CSV File Not Found'),
        content: const Text(
          'Make sure you:\n\n'
          '1. Created the file at:\n'
          '   assets/medicines_template.csv\n\n'
          '2. Added it to pubspec.yaml:\n'
          '   flutter:\n'
          '     assets:\n'
          '       - assets/medicines_template.csv\n\n'
          '3. Ran: flutter pub get',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final int  firestoreCount;
  final int  cacheCount;
  final bool cacheReady;
  final bool isLoading;
  final VoidCallback onRefresh;

  const _StatsCard({
    required this.firestoreCount,
    required this.cacheCount,
    required this.cacheReady,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Database Status',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (isLoading)
                  const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else
                  IconButton(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Refresh counts',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const Divider(height: 20),
            _statRow('☁️ Firestore medicines', '$firestoreCount'),
            const SizedBox(height: 8),
            _statRow(
              '💾 Local cache',
              cacheReady ? '$cacheCount medicines (ready)' : 'Not built',
              valueColor: cacheReady ? Colors.green[700] : Colors.orange[700],
            ),
            if (!cacheReady) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.orange[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Local cache is not built. Searches will be slow.\n'
                        'Tap "Build Local Cache" below to fix this.',
                        style: TextStyle(fontSize: 12, color: Colors.orange[900], height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value, {Color? valueColor}) => Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: valueColor,
            ),
          ),
        ],
      );
}

class _AdminButton extends StatelessWidget {
  final String    label;
  final IconData  icon;
  final Color     color;
  final bool      isLoading;
  final VoidCallback onTap;
  final bool      highlighted;

  const _AdminButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.isLoading,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: isLoading ? null : onTap,
        icon: isLoading
            ? SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
              )
            : Icon(icon, size: 18),
        label: Text(label, textAlign: TextAlign.left),
        style: ElevatedButton.styleFrom(
          // ignore: deprecated_member_use
          backgroundColor: highlighted ? color : color.withOpacity(0.85),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          alignment: Alignment.centerLeft,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: highlighted ? 4 : 1,
        ),
      ),
    );
  }
}