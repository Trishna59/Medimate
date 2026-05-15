// lib/features/medicine/data/local/medicine_cache_service.dart
// ============================================================
// LOCAL MEDICINE CACHE SERVICE
//
// WHY THIS EXISTS:
//   The old code called _firestore.collection('medicines').get() on
//   EVERY scan — downloading all 11,825 documents every time = slow.
//
// WHAT THIS DOES:
//   • First run after seeding: downloads all medicines from Firestore
//     and saves them to a local JSON file on the device (~5–10 MB).
//   • Every subsequent scan: reads from the local file (already in
//     memory after first load) — NO Firestore call needed.
//   • Also builds an in-memory inverted index for fast pre-filtering.
//
// SPEED COMPARISON:
//   Before: every scan → Firestore download → 10–30 seconds
//   After : first scan → load local file   → ~0.5–1 second
//           later scans → already in RAM   → <50 ms
// ============================================================
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/medicine.dart';

class MedicineCacheService {
  // ── Singleton ────────────────────────────────────────────
  static final MedicineCacheService _instance =
      MedicineCacheService._internal();
  factory MedicineCacheService() => _instance;
  MedicineCacheService._internal();

  // ── In-memory state ──────────────────────────────────────
  List<Medicine>? _medicines;
  Map<String, Medicine>? _byId;

  /// token → set of medicine IDs  (built once, searched many times)
  Map<String, Set<String>> _invertedIndex = {};

  /// If a load is already in progress, callers await this same Future
  Future<bool>? _loadFuture;

  // ── Public API ───────────────────────────────────────────

  bool get isReady => _medicines != null;
  int get count => _medicines?.length ?? 0;

  /// Call this on app start (or before the first scan).
  /// Safe to call multiple times — only loads once per session.
  Future<bool> ensureLoaded() {
    _loadFuture ??= _doLoad();
    return _loadFuture!;
  }

  /// Return ALL cached medicines (in-memory, instant).
  List<Medicine> get all => _medicines ?? [];

  /// Fast pre-filter: given OCR tokens, return only candidate medicines.
  /// Reduces the scoring pool from 11 k → typically 10–200 items.
  List<Medicine> getCandidates(List<String> tokens) {
    if (_medicines == null || tokens.isEmpty) return all;

    final ids = <String>{};
    for (final token in tokens) {
      // Exact index hit
      _invertedIndex[token]?.forEach(ids.add);

      // Prefix hit (token typed partially, e.g. "parace" → "paracetamol")
      if (token.length >= 4) {
        for (final key in _invertedIndex.keys) {
          if (key.startsWith(token)) {
            _invertedIndex[key]!.forEach(ids.add);
          }
        }
      }
    }

    // If nothing found in index, fall back to full list for fuzzy scoring
    if (ids.isEmpty) return all;

    return ids.map((id) => _byId![id]).whereType<Medicine>().toList();
  }

  // ── Build & persist cache from Firestore ─────────────────

  /// Downloads all medicines from Firestore and saves to disk.
  /// Call this once after seeding/importing.
  Future<CacheResult> buildFromFirestore(FirebaseFirestore firestore) async {
    try {
      print('📥 Building local cache from Firestore...');
      final snapshot = await firestore.collection('medicines').get();

      if (snapshot.docs.isEmpty) {
        return CacheResult(success: false, count: 0,
            error: 'Firestore medicines collection is empty');
      }

      // Import MedicineModel inline to avoid circular dependency issue
      final meds = snapshot.docs
          .map((doc) => _firestoreToMedicine(doc))
          .whereType<Medicine>()
          .toList();

      await _saveToFile(meds);
      _setInMemory(meds);

      print('✅ Cache built: ${meds.length} medicines');
      return CacheResult(success: true, count: meds.length);
    } catch (e) {
      print('❌ buildFromFirestore: $e');
      return CacheResult(success: false, count: 0, error: e.toString());
    }
  }

  /// Call this after adding or importing new medicines so the cache stays fresh.
  Future<void> appendMedicines(List<Medicine> newMeds) async {
    final current = List<Medicine>.from(_medicines ?? []);
    final existingIds = current.map((m) => m.id).toSet();
    final toAdd = newMeds.where((m) => !existingIds.contains(m.id)).toList();
    if (toAdd.isEmpty) return;
    final updated = [...current, ...toAdd];
    await _saveToFile(updated);
    _setInMemory(updated);
    print('🔄 Cache updated: ${updated.length} total medicines');
  }

  /// Wipe the local cache file and in-memory state.
  Future<void> clearCache() async {
    _medicines = null;
    _byId = null;
    _invertedIndex = {};
    _loadFuture = null;
    final f = await _cacheFile;
    if (f.existsSync()) f.deleteSync();
    print('🗑️ Local cache cleared');
  }

  // ── Private helpers ──────────────────────────────────────

  Future<bool> _doLoad() async {
    // Try reading from disk first
    final loaded = await _loadFromFile();
    if (loaded) return true;

    // No local file yet → caller must call buildFromFirestore()
    print('⚠️ No local cache found. Run "Build Local Cache" in Admin Screen.');
    return false;
  }

  Future<bool> _loadFromFile() async {
    try {
      final file = await _cacheFile;
      if (!file.existsSync()) return false;

      final stat = file.statSync();
      print('📂 Loading local cache (${(stat.size / 1024 / 1024).toStringAsFixed(1)} MB)...');

      final stopwatch = Stopwatch()..start();
      final jsonStr = await file.readAsString();
      final jsonList = jsonDecode(jsonStr) as List;
      final meds = jsonList.map((j) => _fromJson(j as Map<String, dynamic>)).toList();

      _setInMemory(meds);
      stopwatch.stop();

      print('✅ Cache loaded: ${meds.length} medicines in ${stopwatch.elapsedMilliseconds}ms');
      return true;
    } catch (e) {
      print('❌ _loadFromFile: $e');
      return false;
    }
  }

  Future<void> _saveToFile(List<Medicine> meds) async {
    final file = await _cacheFile;
    final json = jsonEncode(meds.map(_toJson).toList());
    await file.writeAsString(json, flush: true);
    print('💾 Saved cache to disk (${(json.length / 1024 / 1024).toStringAsFixed(1)} MB)');
  }

  void _setInMemory(List<Medicine> meds) {
    _medicines = meds;
    _byId = {for (final m in meds) m.id: m};
    _buildInvertedIndex(meds);
  }

  void _buildInvertedIndex(List<Medicine> meds) {
    final index = <String, Set<String>>{};
    for (final m in meds) {
      // Collect all searchable strings for this medicine
      final terms = <String>{
        ...m.searchTerms,
        m.name.toLowerCase(),
        m.genericName.toLowerCase(),
        if (m.dosageForm != null) m.dosageForm!.toLowerCase(),
        if (m.strength != null) m.strength!.toLowerCase(),
      };

      for (final term in terms) {
        // Index whole term
        if (term.length >= 3) {
          index.putIfAbsent(term, () => {}).add(m.id);
        }
        // Also index individual words within multi-word terms
        for (final word in term.split(RegExp(r'[\s|+,]+'))) {
          if (word.length >= 3) {
            index.putIfAbsent(word, () => {}).add(m.id);
          }
        }
      }
    }
    _invertedIndex = index;
    print('🔍 Inverted index built: ${index.length} tokens');
  }

  Future<File> get _cacheFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/medimate_medicines_cache.json');
  }

  // ── Serialisation ─────────────────────────────────────────

  Map<String, dynamic> _toJson(Medicine m) => {
        'id': m.id,
        'name': m.name,
        'genericName': m.genericName,
        'manufacturer': m.manufacturer,
        'category': m.category,
        'dosageForm': m.dosageForm,
        'strength': m.strength,
        'description': m.description,
        'uses': m.uses,
        'sideEffects': m.sideEffects,
        'precautions': m.precautions,
        'dosageInfo': m.dosageInfo,
        'storageInstructions': m.storageInstructions,
        'isCommon': m.isCommon,
        'searchTerms': m.searchTerms,
        'createdAt': m.createdAt.toIso8601String(),
      };

  Medicine _fromJson(Map<String, dynamic> j) => Medicine(
        id: j['id'] as String,
        name: j['name'] as String,
        genericName: j['genericName'] as String,
        manufacturer: j['manufacturer'] as String,
        category: (j['category'] as String?) ?? 'General',
        dosageForm: j['dosageForm'] as String?,
        strength: j['strength'] as String?,
        description: j['description'] as String?,
        uses: j['uses'] as String?,
        sideEffects: j['sideEffects'] as String?,
        precautions: j['precautions'] as String?,
        dosageInfo: j['dosageInfo'] as String?,
        storageInstructions: j['storageInstructions'] as String?,
        isCommon: (j['isCommon'] as bool?) ?? false,
        searchTerms: List<String>.from((j['searchTerms'] as List?) ?? []),
        createdAt: DateTime.parse(j['createdAt'] as String),
      );

  /// Converts a Firestore DocumentSnapshot to a Medicine.
  /// (Mirrors MedicineModel.fromFirestore without the import.)
  Medicine? _firestoreToMedicine(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>;
      return Medicine(
        id: doc.id,
        name: data['name'] as String? ?? '',
        genericName: data['genericName'] as String? ?? '',
        manufacturer: data['manufacturer'] as String? ?? '',
        category: data['category'] as String? ?? 'General',
        dosageForm: data['dosageForm'] as String?,
        strength: data['strength'] as String?,
        description: data['description'] as String?,
        uses: data['uses'] as String?,
        sideEffects: data['sideEffects'] as String?,
        precautions: data['precautions'] as String?,
        dosageInfo: data['dosageInfo'] as String?,
        storageInstructions: data['storageInstructions'] as String?,
        isCommon: data['isCommon'] as bool? ?? false,
        searchTerms: List<String>.from(data['searchTerms'] as List? ?? []),
        createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      );
    } catch (e) {
      print('⚠️ Could not parse medicine ${doc.id}: $e');
      return null;
    }
  }
}

// ── Result model ──────────────────────────────────────────────────────────────
class CacheResult {
  final bool success;
  final int count;
  final String? error;
  const CacheResult({required this.success, required this.count, this.error});
}