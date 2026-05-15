// lib/features/medicine/domain/entities/medicine.dart
// ============================================================
// MEDICINE ENTITY — Complete version
// Keeps original fields + calculateMatchConfidence method
// Adds: category, storageInstructions
// ============================================================

class Medicine {
  final String id;
  final String name;           // Brand name e.g. "Paracetamol 500mg"
  final String genericName;    // Generic/INN e.g. "Acetaminophen"
  final String manufacturer;
  final String category;       // NEW: e.g. "Analgesic", "Antibiotic"

  final String? description;
  final String? uses;
  final String? sideEffects;
  final String? precautions;
  final String? dosageInfo;
  final String? dosageForm;
  final String? strength;
  final String? storageInstructions; // NEW

  final List<String> searchTerms; // Alternative names for matching
  final String? imageUrl;
  final bool isCommon;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const Medicine({
    required this.id,
    required this.name,
    required this.genericName,
    required this.manufacturer,
    this.category = 'General',
    this.description,
    this.uses,
    this.sideEffects,
    this.precautions,
    this.dosageInfo,
    this.dosageForm,
    this.strength,
    this.storageInstructions,
    required this.searchTerms,
    this.imageUrl,
    this.isCommon = false,
    required this.createdAt,
    this.updatedAt,
  });

  // ─────────────────────────────────────────────────────────────
  // KEPT FROM ORIGINAL — needed by MedicineSearchResultsScreen
  // ─────────────────────────────────────────────────────────────

  /// Check if a text matches this medicine (simple check)
  bool matchesText(String text) {
    final searchText = text.toLowerCase().trim();
    if (name.toLowerCase().contains(searchText)) return true;
    if (genericName.toLowerCase().contains(searchText)) return true;
    if (manufacturer.toLowerCase().contains(searchText)) return true;
    for (final term in searchTerms) {
      if (term.toLowerCase().contains(searchText) ||
          searchText.contains(term.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  /// Calculate match confidence (0.0 to 1.0)
  /// KEPT FROM ORIGINAL — used by _MedicineResultCard in search results screen
  double calculateMatchConfidence(String extractedText) {
    final text = extractedText.toLowerCase();
    int matches = 0;
    int totalTerms = 0;

    for (final term in [...searchTerms, name, genericName]) {
      totalTerms++;
      if (text.contains(term.toLowerCase())) {
        matches++;
      }
    }

    return totalTerms > 0 ? matches / totalTerms : 0.0;
  }

  Medicine copyWith({
    String? id,
    String? name,
    String? genericName,
    String? manufacturer,
    String? category,
    String? description,
    String? uses,
    String? sideEffects,
    String? precautions,
    String? dosageInfo,
    String? dosageForm,
    String? strength,
    String? storageInstructions,
    List<String>? searchTerms,
    String? imageUrl,
    bool? isCommon,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Medicine(
      id: id ?? this.id,
      name: name ?? this.name,
      genericName: genericName ?? this.genericName,
      manufacturer: manufacturer ?? this.manufacturer,
      category: category ?? this.category,
      description: description ?? this.description,
      uses: uses ?? this.uses,
      sideEffects: sideEffects ?? this.sideEffects,
      precautions: precautions ?? this.precautions,
      dosageInfo: dosageInfo ?? this.dosageInfo,
      dosageForm: dosageForm ?? this.dosageForm,
      strength: strength ?? this.strength,
      storageInstructions: storageInstructions ?? this.storageInstructions,
      searchTerms: searchTerms ?? this.searchTerms,
      imageUrl: imageUrl ?? this.imageUrl,
      isCommon: isCommon ?? this.isCommon,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Medicine category enum — kept from original
enum MedicineCategory {
  painkiller,
  antibiotic,
  antacid,
  vitamin,
  coldFlu,
  diabetes,
  heartBloodPressure,
  allergy,
  other,
}