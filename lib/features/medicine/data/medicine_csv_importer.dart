// lib/features/medicine/data/medicine_csv_importer.dart
// ============================================================
// CSV IMPORTER — Add hundreds of medicines from a spreadsheet
//
// HOW TO USE:
//   1. Fill in medicines_template.csv (see below for format)
//   2. Put the CSV file in your app's assets folder
//   3. Call MedicineCsvImporter.importFromCsvString(csvContent)
//      from the Admin Screen
// ============================================================
// ignore_for_file: avoid_print

import 'package:uuid/uuid.dart';
import '../domain/entities/medicine.dart';
import 'repositories/medicine_repository.dart';

class MedicineCsvImporter {
  final MedicineRepository _repository;
  const MedicineCsvImporter(this._repository);

  // ─────────────────────────────────────────────────────────────
  // Import from a CSV string
  // Call this from your admin screen:
  //
  //   final csvString = await rootBundle.loadString('assets/medicines.csv');
  //   final importer = MedicineCsvImporter(MedicineRepository());
  //   await importer.importFromCsvString(csvString);
  // ─────────────────────────────────────────────────────────────
  Future<ImportResult> importFromCsvString(String csvContent) async {
    final lines = csvContent.split('\n');

    if (lines.isEmpty) {
      return ImportResult(success: 0, failed: 0, errors: ['CSV is empty']);
    }

    // First line is the header — skip it
    final dataLines = lines.skip(1).where((l) => l.trim().isNotEmpty).toList();

    int success = 0;
    int failed = 0;
    final errors = <String>[];

    for (int i = 0; i < dataLines.length; i++) {
      final lineNum = i + 2; // +2 because we skipped header (line 1)
      try {
        final medicine = _parseLine(dataLines[i]);
        if (medicine == null) {
          failed++;
          errors.add('Line $lineNum: Could not parse — skipping');
          continue;
        }
        await _repository.addMedicine(medicine);
        success++;
        print('  ✅ Line $lineNum: ${medicine.name}');
      } catch (e) {
        failed++;
        errors.add('Line $lineNum: $e');
        print('  ❌ Line $lineNum: $e');
      }
    }

    print('\n📊 Import done: ✅$success  ❌$failed');
    return ImportResult(success: success, failed: failed, errors: errors);
  }

  // ─────────────────────────────────────────────────────────────
  // Parse one CSV line into a Medicine object
  //
  // CSV Column order (must match the template):
  //  0  name
  //  1  genericName
  //  2  manufacturer
  //  3  category
  //  4  dosageForm
  //  5  strength
  //  6  description
  //  7  uses
  //  8  sideEffects
  //  9  precautions
  // 10  dosageInfo
  // 11  storageInstructions
  // 12  isCommon          (true / false)
  // 13  searchTerms       (pipe-separated: "paracetamol|pcm|fever|pain")
  // ─────────────────────────────────────────────────────────────
  Medicine? _parseLine(String line) {
    final cols = _parseCsvLine(line);

    if (cols.length < 14) {
      print('  ⚠️ Not enough columns (got ${cols.length}, need 14): $line');
      return null;
    }

    final name = cols[0].trim();
    if (name.isEmpty) return null; // skip blank rows

    // searchTerms are pipe-separated inside the CSV cell
    final searchTermsRaw = cols[13].trim();
    final searchTerms = searchTermsRaw
        .split('|')
        .map((t) => t.trim().toLowerCase())
        .where((t) => t.isNotEmpty)
        .toList();

    // Always add the medicine name and generic name to search terms
    if (!searchTerms.contains(name.toLowerCase())) {
      searchTerms.add(name.toLowerCase());
    }

    return Medicine(
      id: const Uuid().v4(),
      name: name,
      genericName: cols[1].trim(),
      manufacturer: cols[2].trim(),
      category: cols[3].trim().isNotEmpty ? cols[3].trim() : 'General',
      dosageForm: _nullIfEmpty(cols[4]),
      strength: _nullIfEmpty(cols[5]),
      description: _nullIfEmpty(cols[6]),
      uses: _nullIfEmpty(cols[7]),
      sideEffects: _nullIfEmpty(cols[8]),
      precautions: _nullIfEmpty(cols[9]),
      dosageInfo: _nullIfEmpty(cols[10]),
      storageInstructions: _nullIfEmpty(cols[11]),
      isCommon: cols[12].trim().toLowerCase() == 'true',
      searchTerms: searchTerms,
      createdAt: DateTime.now(),
    );
  }

  String? _nullIfEmpty(String s) => s.trim().isEmpty ? null : s.trim();

  // ─────────────────────────────────────────────────────────────
  // Proper CSV parser — handles quoted fields with commas inside
  // ─────────────────────────────────────────────────────────────
  List<String> _parseCsvLine(String line) {
    final fields = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final ch = line[i];

      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          // escaped quote inside quoted field
          buffer.write('"');
          i++; // skip next quote
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == ',' && !inQuotes) {
        fields.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }
    fields.add(buffer.toString()); // last field
    return fields;
  }
}

/// Result of a CSV import operation
class ImportResult {
  final int success;
  final int failed;
  final List<String> errors;
  const ImportResult(
      {required this.success, required this.failed, required this.errors});
}