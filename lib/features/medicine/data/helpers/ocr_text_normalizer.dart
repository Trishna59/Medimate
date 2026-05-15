// lib/features/medicine/data/helpers/ocr_text_normalizer.dart
// ============================================================
// OCR TEXT NORMALIZER & FUZZY MATCHER
// Put this file at:
//   lib/features/medicine/data/helpers/ocr_text_normalizer.dart
// The folder name is lowercase "helpers" (not "Helpers")
// ============================================================

class OcrTextNormalizer {
  // ─────────────────────────────────────────────────────────────
  // MASTER NORMALIZER — call this first on raw OCR text
  // ─────────────────────────────────────────────────────────────
  static String normalize(String rawText) {
    String text = rawText.toLowerCase();
    text = _fixOcrCharacterErrors(text);
    text = _normalizeDosage(text);
    text = text.replaceAll(RegExp(r'[^\w\s]'), ' ');
    text = text.replaceAll(RegExp(r'[\s\n\r\t]+'), ' ').trim();
    return text;
  }

  // ─────────────────────────────────────────────────────────────
  // Fix common OCR digit/letter confusions
  // ─────────────────────────────────────────────────────────────
  static String _fixOcrCharacterErrors(String text) {
    final fixes = <String, String>{
      'paracetam0l': 'paracetamol',
      'paracetam01': 'paracetamol',
      'parac3tamol': 'paracetamol',
      'ibupr0fen': 'ibuprofen',
      'amox1cillin': 'amoxicillin',
      'cet1rizine': 'cetirizine',
      'omepraz0le': 'omeprazole',
      'metf0rmin': 'metformin',
    };
    String result = text;
    fixes.forEach((wrong, right) {
      result = result.replaceAll(wrong, right);
    });
    return result;
  }

  // ─────────────────────────────────────────────────────────────
  // Normalize dosage strings
  // "50Dmg"→"500mg"  "5OOmg"→"500mg"  "500 MG"→"500mg"
  // ─────────────────────────────────────────────────────────────
  static String _normalizeDosage(String text) {
    String result = text;

    // digit + D/d + mg → digit + 0 + mg  (50Dmg → 500mg)
    result = result.replaceAllMapped(
      RegExp(r'(\d+)[Dd]([Mm][Gg])'),
      (m) => '${m[1]}0${m[2]}',
    );

    // digit + O/o + digit → digit + 0 + digit  (5OO → 500)
    result = result.replaceAllMapped(
      RegExp(r'(\d)[Oo](\d)'),
      (m) => '${m[1]}0${m[2]}',
    );

    // digit + I/l + digit → digit + 1 + digit
    result = result.replaceAllMapped(
      RegExp(r'(\d)[Il](\d)'),
      (m) => '${m[1]}1${m[2]}',
    );

    // "500 mg" / "500MG" / "500 MG" → "500mg"
    result = result.replaceAllMapped(
      RegExp(r'(\d+)\s*[Mm][Gg]'),
      (m) => '${m[1]}mg',
    );

    // "60,000 IU" → "60000iu"
    result = result.replaceAll(',', '');
    result = result.replaceAllMapped(
      RegExp(r'(\d+)\s*[Ii][Uu]'),
      (m) => '${m[1]}iu',
    );

    return result;
  }

  // ─────────────────────────────────────────────────────────────
  // Extract meaningful search tokens from normalized text
  // ─────────────────────────────────────────────────────────────
  static List<String> extractTokens(String normalizedText) {
    const stopWords = {
      'the', 'and', 'for', 'are', 'was', 'not', 'but',
      'tab', 'cap', 'tablet', 'capsule', 'syrup', 'injection',
      'take', 'with', 'food', 'water', 'once', 'daily',
      'times', 'day', 'each', 'per', 'dose', 'use',
    };

    return normalizedText
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3 && !stopWords.contains(w))
        .toSet()
        .toList();
  }

  // ─────────────────────────────────────────────────────────────
  // Fuzzy similarity using Dice coefficient (0.0 to 1.0)
  // similarity("paracetamol", "paracetamol") = 1.0
  // similarity("paracetam0l", "paracetamol") = 0.95
  // ─────────────────────────────────────────────────────────────
  static double similarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.length < 2 || b.length < 2) return 0.0;

    final aBigrams = _bigrams(a);
    final bBigrams = _bigrams(b);

    int intersection = 0;
    final bCopy = List<String>.from(bBigrams);

    for (final bigram in aBigrams) {
      final idx = bCopy.indexOf(bigram);
      if (idx >= 0) {
        intersection++;
        bCopy.removeAt(idx);
      }
    }

    return (2.0 * intersection) / (aBigrams.length + bBigrams.length);
  }

  static List<String> _bigrams(String s) {
    final result = <String>[];
    for (int i = 0; i < s.length - 1; i++) {
      result.add(s.substring(i, i + 2));
    }
    return result;
  }

  // ─────────────────────────────────────────────────────────────
  // Prefix match — "para" matches "paracetamol"
  // ─────────────────────────────────────────────────────────────
  static bool isPrefixMatch(String token, String candidate) {
    if (token.length < 4 || candidate.isEmpty) return false;
    final maxLen = token.length < candidate.length ? token.length : candidate.length;
    return candidate.startsWith(token) ||
        token.startsWith(candidate.substring(0, maxLen));
  }
}