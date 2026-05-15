// lib/features/medicine/data/repositories/medicine_repository.dart
// ============================================================
// MEDICINE REPOSITORY — v2 (Cache-First)
//
// SEARCH FLOW (new):
//   1. Load local cache (JSON file on device) — done ONCE per session
//   2. Use inverted index to get ~10–200 candidate medicines
//   3. Score only those candidates (not all 11,825!)
//   4. Return ranked results  — total time: < 200 ms
//
// WRITE FLOW (unchanged):
//   addMedicine / updateMedicine / deleteMedicine still go to Firestore.
//   After a write, we append to / refresh the local cache automatically.
//
// NO CHANGES NEEDED in any screen code — same public API.
// ============================================================
// ignore_for_file: avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/medicine.dart';
import '../models/medicine_model.dart';
import '../helpers/ocr_text_normalizer.dart';
import '../local/medicine_cache_service.dart';   // ← NEW

class MedicineRepository {
  final FirebaseFirestore _firestore;
  final MedicineCacheService _cache = MedicineCacheService(); // singleton

  MedicineRepository({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  // ────────────────────────────────────────────────────────────────────────
  // MAIN SEARCH — cache-first, fast
  // ────────────────────────────────────────────────────────────────────────

  Future<List<Medicine>> searchMedicineByText(String rawOcrText) async {
    try {
      final sw = Stopwatch()..start();

      // ── Step 1: Normalise OCR text ─────────────────────────────────────
      final normalizedText = OcrTextNormalizer.normalize(rawOcrText);
      final tokens = OcrTextNormalizer.extractTokens(normalizedText);

      print('🔍 Raw OCR   : $rawOcrText');
      print('✨ Normalized: $normalizedText');
      print('🔑 Tokens    : $tokens');

      if (tokens.isEmpty) {
        print('⚠️ No usable tokens — cannot search');
        return [];
      }

      // ── Step 2: Ensure local cache is loaded ───────────────────────────
      final cacheReady = await _cache.ensureLoaded();

      if (!cacheReady) {
        // Cache file doesn't exist yet (first time, or after clearing).
        // Fall back to Firestore the old way, then save cache.
        print('⚠️ Cache not ready — falling back to Firestore (slow path)');
        return _searchViaFirestore(normalizedText, tokens);
      }

      // ── Step 3: Fast pre-filter via inverted index ─────────────────────
      final candidates = _cache.getCandidates(tokens);
      print('📊 Candidates from index: ${candidates.length} / ${_cache.count}');

      // ── Step 4: Score only the candidates ─────────────────────────────
      final scored = <_ScoredMedicine>[];
      for (final medicine in candidates) {
        final score = _scoreMatch(
          normalizedText: normalizedText,
          tokens: tokens,
          medicine: medicine,
        );
        if (score >= 0.20) {
          scored.add(_ScoredMedicine(medicine: medicine, score: score));
        }
      }

      scored.sort((a, b) => b.score.compareTo(a.score));
      sw.stop();

      if (scored.isEmpty) {
        print('❌ No medicines matched. (${sw.elapsedMilliseconds}ms)');
      } else {
        print('✅ ${scored.length} match(es) in ${sw.elapsedMilliseconds}ms:');
        for (final s in scored.take(5)) {
          print('  • ${s.medicine.name} — ${(s.score * 100).toStringAsFixed(1)}%');
        }
      }

      return scored.map((s) => s.medicine).toList();
    } catch (e, stack) {
      print('❌ searchMedicineByText: $e\n$stack');
      rethrow;
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // SCORING ENGINE — unchanged from original, works on any candidate list
  // ────────────────────────────────────────────────────────────────────────

  double _scoreMatch({
    required String normalizedText,
    required List<String> tokens,
    required Medicine medicine,
  }) {
    double score = 0.0;

    final candidateName      = OcrTextNormalizer.normalize(medicine.name);
    final candidateGeneric   = OcrTextNormalizer.normalize(medicine.genericName);
    final candidateMfr       = OcrTextNormalizer.normalize(medicine.manufacturer);
    final candidateTerms     = medicine.searchTerms.map(OcrTextNormalizer.normalize).toList();

    // Rule 1 — exact brand name substring
    if (normalizedText.contains(candidateName))    score += 1.0;

    // Rule 2 — generic name exact substring
    if (normalizedText.contains(candidateGeneric)) score += 0.95;

    // Rule 3 — searchTerms / aliases (proportional)
    if (candidateTerms.isNotEmpty) {
      final hits = candidateTerms.where((t) => normalizedText.contains(t)).length;
      score += (hits / candidateTerms.length) * 0.85;
    }

    // Rule 4 — manufacturer
    if (normalizedText.contains(candidateMfr))     score += 0.5;

    // Rule 5 — token-level partial / prefix
    if (tokens.isNotEmpty) {
      int tokenHits = 0;
      for (final token in tokens) {
        final hit = candidateName.contains(token) ||
            candidateGeneric.contains(token) ||
            candidateTerms.any((t) => t.contains(token)) ||
            OcrTextNormalizer.isPrefixMatch(token, candidateName) ||
            OcrTextNormalizer.isPrefixMatch(token, candidateGeneric);
        if (hit) tokenHits++;
      }
      score += (tokenHits / tokens.length) * 0.7;
    }

    // Rule 6 — fuzzy Dice coefficient
    double maxFuzzy = 0.0;
    for (final token in tokens) {
      final similarities = [
        OcrTextNormalizer.similarity(token, candidateName),
        OcrTextNormalizer.similarity(token, candidateGeneric),
        ...candidateTerms.map((t) => OcrTextNormalizer.similarity(token, t)),
      ];
      final best = similarities.fold<double>(0.0, (p, s) => s > p ? s : p);
      if (best > maxFuzzy) maxFuzzy = best;
    }
    if (maxFuzzy > 0.6) score += maxFuzzy * 0.6;

    // Normalise to 0–1 (max possible = 1.0+0.95+0.85+0.5+0.7+0.6 = 4.6)
    return (score / 4.6).clamp(0.0, 1.0);
  }

  // ────────────────────────────────────────────────────────────────────────
  // SLOW PATH — Firestore fallback (used only when cache doesn't exist yet)
  // ────────────────────────────────────────────────────────────────────────

  Future<List<Medicine>> _searchViaFirestore(
    String normalizedText,
    List<String> tokens,
  ) async {
    final snapshot = await _firestore.collection('medicines').get();
    if (snapshot.docs.isEmpty) {
      print('⚠️ Firestore medicines collection is empty');
      return [];
    }

    final allMedicines = snapshot.docs
        .map((doc) => MedicineModel.fromFirestore(doc))
        .toList();

    // Save to local cache so next search is fast
    await _cache.appendMedicines(allMedicines);

    final scored = <_ScoredMedicine>[];
    for (final medicine in allMedicines) {
      final score = _scoreMatch(
        normalizedText: normalizedText,
        tokens: tokens,
        medicine: medicine,
      );
      if (score >= 0.20) {
        scored.add(_ScoredMedicine(medicine: medicine, score: score));
      }
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.map((s) => s.medicine).toList();
  }

  // ────────────────────────────────────────────────────────────────────────
  // CACHE MANAGEMENT (called from Admin Screen)
  // ────────────────────────────────────────────────────────────────────────

  /// Downloads all medicines from Firestore and saves to local cache.
  /// Call once after seeding/importing.
  Future<CacheResult> buildLocalCache() =>
      _cache.buildFromFirestore(_firestore);

  /// Returns cache status info for Admin Screen display.
  Future<Map<String, dynamic>> getCacheInfo() async {
    await _cache.ensureLoaded();
    return {
      'isReady': _cache.isReady,
      'count': _cache.count,
    };
  }

  // ────────────────────────────────────────────────────────────────────────
  // STANDARD CRUD — unchanged
  // ────────────────────────────────────────────────────────────────────────

  Future<Medicine?> getMedicineById(String medicineId) async {
    try {
      final doc = await _firestore.collection('medicines').doc(medicineId).get();
      if (doc.exists) return MedicineModel.fromFirestore(doc);
      return null;
    } catch (e) {
      print('❌ getMedicineById: $e');
      return null;
    }
  }

  Future<List<Medicine>> getAllMedicines() async {
    // Return from cache if ready — avoids network round-trip
    if (_cache.isReady) return _cache.all;
    try {
      final snapshot = await _firestore
          .collection('medicines')
          .orderBy('name')
          .get();
      return snapshot.docs.map((doc) => MedicineModel.fromFirestore(doc)).toList();
    } catch (e) {
      print('❌ getAllMedicines: $e');
      return [];
    }
  }

  Future<List<Medicine>> getCommonMedicines() async {
    // Serve from local cache when available — instant
    if (_cache.isReady) {
      return _cache.all.where((m) => m.isCommon).take(20).toList();
    }
    try {
      final snapshot = await _firestore
          .collection('medicines')
          .where('isCommon', isEqualTo: true)
          .limit(20)
          .get();
      return snapshot.docs.map((doc) => MedicineModel.fromFirestore(doc)).toList();
    } catch (e) {
      print('❌ getCommonMedicines: $e');
      return [];
    }
  }

  Future<void> addMedicine(Medicine medicine) async {
    try {
      final model = MedicineModel.fromEntity(medicine);
      await _firestore.collection('medicines').doc(medicine.id).set(model.toFirestore());
      // Keep local cache in sync
      await _cache.appendMedicines([medicine]);
      print('✅ Added: ${medicine.name}');
    } catch (e) {
      print('❌ addMedicine: $e');
      rethrow;
    }
  }

  Future<void> updateMedicine(Medicine medicine) async {
    try {
      final model = MedicineModel.fromEntity(medicine);
      await _firestore
          .collection('medicines')
          .doc(medicine.id)
          .update(model.toFirestore());
      // Invalidate cache so it reloads fresh next time
      await _cache.clearCache();
      print('✅ Updated: ${medicine.name}');
    } catch (e) {
      print('❌ updateMedicine: $e');
      rethrow;
    }
  }

  Future<void> deleteMedicine(String medicineId) async {
    try {
      await _firestore.collection('medicines').doc(medicineId).delete();
      await _cache.clearCache();
      print('✅ Deleted medicine $medicineId');
    } catch (e) {
      print('❌ deleteMedicine: $e');
      rethrow;
    }
  }
}

// ── Private helper ────────────────────────────────────────────────────────────
class _ScoredMedicine {
  final Medicine medicine;
  final double score;
  const _ScoredMedicine({required this.medicine, required this.score});
}

/// Public helper — used by UI to show confidence %
class MedicineWithConfidence {
  final Medicine medicine;
  final double confidence;
  const MedicineWithConfidence(
      {required this.medicine, required this.confidence});
}