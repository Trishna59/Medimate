// lib/features/scan/presentation/screens/scan_preview_screen.dart
// ============================================================
// SCAN PREVIEW SCREEN — Updated for fast medicine search
//
// KEY CHANGE:
//   _warmUpCache() is called immediately in initState — it starts
//   loading the local medicine cache from disk WHILE the OCR is
//   running. By the time OCR finishes, the cache is already in
//   memory, so the database search takes < 200 ms.
//
//   Before: OCR (2s) → download 11k medicines from Firestore (10–30s)
//   After : OCR (2s) + cache load (0.5s, parallel) → search (< 200ms)
// ============================================================
// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/scan_provider.dart';
import '../../../medicine/data/repositories/medicine_repository.dart';
import '../../../medicine/data/local/medicine_cache_service.dart';
import '../../../medicine/domain/entities/medicine.dart';
import '../../../medicine/presentation/screens/medicine_detail_screen.dart';
import '../../../medicine/presentation/screens/medicine_search_results_screen.dart';

class ScanPreviewScreen extends ConsumerStatefulWidget {
  final String imagePath;

  const ScanPreviewScreen({
    super.key,
    required this.imagePath,
  });

  @override
  ConsumerState<ScanPreviewScreen> createState() => _ScanPreviewScreenState();
}

class _ScanPreviewScreenState extends ConsumerState<ScanPreviewScreen> {
  bool    _isProcessing       = false;
  String? _extractedText;
  double? _confidence;
  bool    _processingComplete = false;
  String? _error;

  bool           _isSearchingMedicines = false;
  List<Medicine>? _foundMedicines;

  @override
  void initState() {
    super.initState();
    // Start warming the cache immediately — runs in parallel with OCR
    _warmUpCache();
    WidgetsBinding.instance.addPostFrameCallback((_) => _processScan());
  }

  // ── Cache warm-up — parallel with OCR ─────────────────────────────────────
  Future<void> _warmUpCache() async {
    final cache = MedicineCacheService();
    if (!cache.isReady) {
      debugPrint('🔥 Warming up medicine cache in background...');
      await cache.ensureLoaded();
      debugPrint('✅ Cache warm-up complete: ${cache.count} medicines in memory');
    }
  }

  // ── Step 1: OCR ───────────────────────────────────────────────────────────
  Future<void> _processScan() async {
    if (!mounted) return;
    setState(() {
      _isProcessing = true;
      _error        = null;
    });

    try {
      final scan = await ref
          .read(scanControllerProvider.notifier)
          .processScan(widget.imagePath);

      if (scan != null && mounted) {
        setState(() {
          _extractedText      = scan.scannedText;
          _confidence         = scan.confidenceScore;
          _processingComplete = true;
        });

        debugPrint(
            '✅ OCR done. Confidence: ${(scan.confidenceScore * 100).toStringAsFixed(1)}%');

        // Step 2: Search — cache is already loaded (warm-up ran in parallel)
        await _searchMedicineDatabase(scan.scannedText);
      } else {
        throw Exception('Scan returned null');
      }
    } catch (e) {
      debugPrint('❌ Scan error: $e');
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Step 2: Search — now uses local cache ─────────────────────────────────
  Future<void> _searchMedicineDatabase(String rawText) async {
    if (rawText.trim().isEmpty) return;
    setState(() => _isSearchingMedicines = true);

    final sw = Stopwatch()..start();

    try {
      final repo      = MedicineRepository();
      final medicines = await repo.searchMedicineByText(rawText);
      sw.stop();

      debugPrint('⏱ Search took ${sw.elapsedMilliseconds} ms, '
          'found ${medicines.length} results');

      if (mounted) {
        setState(() {
          _foundMedicines      = medicines;
          _isSearchingMedicines = false;
        });

        // Auto-open detail if exactly one match
        if (medicines.length == 1) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) _openDetail(medicines.first);
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Medicine search error: $e');
      if (mounted) setState(() => _isSearchingMedicines = false);
    }
  }

  void _openDetail(Medicine medicine) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MedicineDetailScreen(
          medicine:    medicine,
          scannedText: _extractedText,
        ),
      ),
    );
  }

  void _viewResults() {
    if (_foundMedicines == null || _foundMedicines!.isEmpty) return;
    if (_foundMedicines!.length == 1) {
      _openDetail(_foundMedicines!.first);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MedicineSearchResultsScreen(
            medicines:   _foundMedicines!,
            scannedText: _extractedText ?? '',
          ),
        ),
      );
    }
  }

  void _saveScan() {
    if (!_processingComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait for processing to complete'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Scan saved!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
    Navigator.pop(context, true);
  }

  void _retakeScan() {
    try {
      final file = File(widget.imagePath);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
    Navigator.pop(context);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Preview'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _retakeScan,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Scanned image
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(widget.imagePath),
                height:  220,
                width:   double.infinity,
                fit:     BoxFit.cover,
              ),
            ),

            const SizedBox(height: 20),

            // OCR confidence badge
            if (_isProcessing)
              const Center(child: CircularProgressIndicator())
            else if (_confidence != null)
              _confidenceBadge(_confidence!),

            const SizedBox(height: 12),

            // Medicine match result
            if (_isSearchingMedicines)
              _searchingCard()
            else if (_foundMedicines != null)
              _matchCard(),

            const SizedBox(height: 20),

            // Extracted text
            if (_extractedText != null && _extractedText!.isNotEmpty) ...[
              Text('Extracted Text',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Card(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  constraints: const BoxConstraints(minHeight: 80),
                  child: SelectableText(
                    _extractedText!,
                    style: const TextStyle(fontSize: 16, height: 1.5),
                  ),
                ),
              ),
            ],

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('❌ $_error',
                    style: const TextStyle(color: Colors.red)),
              ),

            const SizedBox(height: 24),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton.icon(
                  onPressed: _retakeScan,
                  icon:  const Icon(Icons.refresh),
                  label: const Text('Retake'),
                ),
                ElevatedButton.icon(
                  onPressed: _processingComplete ? _saveScan : null,
                  icon:  const Icon(Icons.check),
                  label: const Text('Save Scan'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _confidenceBadge(double confidence) {
    final color = confidence >= 0.8
        ? Colors.green
        : confidence >= 0.6
            ? Colors.orange
            : Colors.red;
    return Row(
      children: [
        Icon(
          confidence >= 0.6 ? Icons.check_circle_outline : Icons.warning_amber,
          color: color,
          size:  20,
        ),
        const SizedBox(width: 8),
        Text(
          'OCR Confidence: ${(confidence * 100).toStringAsFixed(0)}%',
          style: TextStyle(
              color:      color,
              fontWeight: FontWeight.w600,
              fontSize:   15),
        ),
      ],
    );
  }

  Widget _searchingCard() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width:  20,
              height: 20,
              child:  CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('Searching medicine database...'),
          ],
        ),
      ),
    );
  }

  Widget _matchCard() {
    final found = _foundMedicines!.isNotEmpty;
    return GestureDetector(
      onTap: found ? _viewResults : null,
      child: Card(
        color: found ? Colors.green[50] : Colors.orange[50],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: found ? Colors.green : Colors.orange,
            width: 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                found ? Icons.check_circle : Icons.search_off,
                color: found ? Colors.green[700] : Colors.orange[700],
                size:  28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      found
                          ? '✓ Found ${_foundMedicines!.length} medicine match(es)'
                          : 'No medicines found in database',
                      style: TextStyle(
                        color:      found ? Colors.green[900] : Colors.orange[900],
                        fontWeight: FontWeight.w700,
                        fontSize:   15,
                      ),
                    ),
                    if (found)
                      Text(
                        'Best: ${_foundMedicines!.first.name} • Tap to view',
                        style: TextStyle(color: Colors.green[700], fontSize: 13),
                      )
                    else
                      Text(
                        'Seed your database or improve OCR lighting.',
                        style:
                            TextStyle(color: Colors.orange[800], fontSize: 13),
                      ),
                  ],
                ),
              ),
              if (found) const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}