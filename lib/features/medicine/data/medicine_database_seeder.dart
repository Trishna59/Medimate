// lib/features/medicine/data/medicine_database_seeder.dart
// ============================================================
// DATABASE SEEDER — 5 complete sample medicines
// Run this ONCE from the Admin Screen to populate Firestore
// ============================================================
// ignore_for_file: avoid_print

import 'package:uuid/uuid.dart';
import '../domain/entities/medicine.dart';
import 'repositories/medicine_repository.dart';

class MedicineDatabaseSeeder {
  final MedicineRepository _repository;
  MedicineDatabaseSeeder(this._repository);

  Future<void> seedDatabase() async {
    print('🌱 Seeding database...');
    final medicines = _getSampleMedicines();
    int ok = 0, fail = 0;
    for (final m in medicines) {
      try {
        await _repository.addMedicine(m);
        ok++;
        print('  ✅ ${m.name}');
      } catch (e) {
        fail++;
        print('  ❌ ${m.name} — $e');
      }
    }
    print('🎉 Done: ✅$ok added  ❌$fail failed');
  }

  List<Medicine> _getSampleMedicines() {
    const uuid = Uuid();

    return [
      // ── 1. PARACETAMOL ──────────────────────────────────
      Medicine(
        id: uuid.v4(),
        name: 'Paracetamol 500mg',
        genericName: 'Acetaminophen',
        manufacturer: 'Various (Cipla, Alkem, Sun Pharma)',
        category: 'Analgesic / Antipyretic',
        description:
            'A common pain reliever and fever reducer. Safe for most people when taken at the recommended dose.',
        uses:
            'Used to treat:\n• Headaches and migraines\n• Muscle aches\n• Backaches\n• Toothaches\n• Fever\n• Common cold and flu\n• Arthritis pain',
        sideEffects:
            'Generally safe. Rare side effects:\n• Nausea or stomach upset\n• Loss of appetite\n• Dark urine (overdose sign — seek help)',
        precautions:
            '⚠️ Do NOT exceed 4000mg in 24 hours\n⚠️ Avoid alcohol\n⚠️ Tell doctor if liver disease\n⚠️ Do not combine with other paracetamol products',
        dosageInfo:
            'Adults & children >12:\n  500–1000mg every 4–6 hours\n  Max 4000mg/day\n\nChildren 6–12:\n  250–500mg every 4–6 hours\n  Max 2000mg/day',
        storageInstructions:
            'Store below 25°C in a dry place away from sunlight.\nKeep out of reach of children.',
        dosageForm: 'Tablet',
        strength: '500mg',
        searchTerms: [
          'paracetamol',
          'paracetam0l',
          'paracetam01',
          'para cetamol',
          'pcm',
          'acetaminophen',
          'tylenol',
          'crocin',
          'dolo',
          'panadol',
          'metacin',
          '500mg',
          'fever',
          'pain',
          'headache',
          'temperature',
        ],
        isCommon: true,
        createdAt: DateTime.now(),
      ),

      // ── 2. AMOXICILLIN ──────────────────────────────────
      Medicine(
        id: uuid.v4(),
        name: 'Amoxicillin 500mg',
        genericName: 'Amoxicillin Trihydrate',
        manufacturer: 'Various (GSK, Ranbaxy, Cipla)',
        category: 'Antibiotic',
        description:
            'A broad-spectrum penicillin antibiotic. Requires a prescription.',
        uses:
            'Used to treat:\n• Ear infections\n• Throat infections\n• Chest infections and pneumonia\n• Urinary tract infections (UTI)\n• Skin infections',
        sideEffects:
            'Common:\n• Nausea, vomiting, diarrhoea\n• Skin rash\n\nSerious (rare):\n• Severe allergic reaction\n• Severe diarrhoea',
        precautions:
            '⚠️ Complete the FULL course\n⚠️ Tell doctor if allergic to penicillin\n⚠️ May reduce effectiveness of oral contraceptives\n⚠️ Prescription required',
        dosageInfo:
            'Adults:\n  250–500mg every 8 hours  OR\n  500–875mg every 12 hours\n\nChildren: dose by weight — ask doctor.',
        storageInstructions:
            'Store below 25°C. Suspension: refrigerate, use within 7 days.',
        dosageForm: 'Capsule',
        strength: '500mg',
        searchTerms: [
          'amoxicillin',
          'amox1cillin',
          'amoxycillin',
          'amoxil',
          'mox',
          'novamox',
          'antibiotic',
          'infection',
          'penicillin',
          '500mg',
          'uti',
          'throat',
          'ear infection',
        ],
        isCommon: true,
        createdAt: DateTime.now(),
      ),

      // ── 3. CETIRIZINE ───────────────────────────────────
      Medicine(
        id: uuid.v4(),
        name: 'Cetirizine 10mg',
        genericName: 'Cetirizine Hydrochloride',
        manufacturer: 'Various (UCB Pharma, Cipla)',
        category: 'Antihistamine',
        description:
            'A second-generation antihistamine for allergy relief with minimal sedation.',
        uses:
            'Used to treat:\n• Hay fever (allergic rhinitis)\n• Hives (urticaria)\n• Itching and skin rash\n• Watery or itchy eyes\n• Runny nose and sneezing',
        sideEffects:
            'Common:\n• Drowsiness or fatigue\n• Dry mouth\n• Headache\n• Dizziness',
        precautions:
            '⚠️ May cause drowsiness — avoid driving\n⚠️ Avoid alcohol\n⚠️ Consult doctor if pregnant\n⚠️ Reduce dose for kidney problems',
        dosageInfo:
            'Adults & children >6:\n  10mg once daily\n\nChildren 2–6:\n  2.5–5mg once daily',
        storageInstructions: 'Store below 30°C away from moisture and heat.',
        dosageForm: 'Tablet',
        strength: '10mg',
        searchTerms: [
          'cetirizine',
          'cetrizine',
          'cet1rizine',
          'cetirizin',
          'zyrtec',
          'reactine',
          'okacet',
          'alerid',
          'cetzine',
          'allergy',
          'antihistamine',
          'itching',
          'hives',
          'hay fever',
          '10mg',
        ],
        isCommon: true,
        createdAt: DateTime.now(),
      ),

      // ── 4. OMEPRAZOLE ───────────────────────────────────
      Medicine(
        id: uuid.v4(),
        name: 'Omeprazole 20mg',
        genericName: 'Omeprazole',
        manufacturer: 'Various (AstraZeneca, Cipla)',
        category: 'Proton Pump Inhibitor',
        description:
            'Reduces stomach acid production. One of the most commonly prescribed medicines worldwide.',
        uses:
            'Used to treat:\n• Acid reflux / GERD\n• Heartburn\n• Stomach ulcers\n• H. pylori infection\n• Zollinger-Ellison syndrome',
        sideEffects:
            'Common:\n• Headache\n• Nausea or diarrhoea\n• Stomach pain\n\nLong-term:\n• Low magnesium\n• Vitamin B12 deficiency',
        precautions:
            '⚠️ Take 30 min BEFORE meals\n⚠️ Swallow capsule whole — do not crush\n⚠️ Tell doctor about liver disease\n⚠️ May interact with clopidogrel',
        dosageInfo:
            'Adults:\n  20mg once daily before breakfast\n  Severe cases: 40mg\n\nCourse: 4–8 weeks.',
        storageInstructions:
            'Store below 25°C away from moisture. Keep in original container.',
        dosageForm: 'Capsule',
        strength: '20mg',
        searchTerms: [
          'omeprazole',
          'omepraz0le',
          'omez',
          'prilosec',
          'losec',
          'ocid',
          'omecap',
          'acidity',
          'gastric',
          'ulcer',
          'reflux',
          'heartburn',
          'gerd',
          '20mg',
        ],
        isCommon: true,
        createdAt: DateTime.now(),
      ),

      // ── 5. IBUPROFEN ────────────────────────────────────
      Medicine(
        id: uuid.v4(),
        name: 'Ibuprofen 400mg',
        genericName: 'Ibuprofen',
        manufacturer: 'Various (Abbott, Cipla, GSK)',
        category: 'NSAID / Anti-inflammatory',
        description:
            'A non-steroidal anti-inflammatory drug (NSAID) that reduces pain, fever, and inflammation.',
        uses:
            'Used to treat:\n• Mild to moderate pain\n• Fever\n• Inflammation\n• Arthritis\n• Menstrual cramps\n• Headaches and migraines\n• Toothaches',
        sideEffects:
            'Common:\n• Upset stomach\n• Nausea\n• Heartburn\n• Dizziness\n\nSerious (rare):\n• Stomach bleeding\n• Kidney problems',
        precautions:
            '⚠️ Always take with food or milk\n⚠️ Do not use if stomach ulcers present\n⚠️ Avoid if allergic to aspirin\n⚠️ Do not use in 3rd trimester of pregnancy',
        dosageInfo:
            'Adults:\n  200–400mg every 4–6 hours\n  OTC max: 1200mg/day\n  Prescription max: 3200mg/day\n\nAlways take with food.',
        storageInstructions:
            'Store below 25°C in a dry place away from light and moisture.',
        dosageForm: 'Tablet',
        strength: '400mg',
        searchTerms: [
          'ibuprofen',
          'ibupr0fen',
          'ibu',
          'brufen',
          'advil',
          'motrin',
          'nurofen',
          'combiflam',
          'nsaid',
          'anti inflammatory',
          'pain',
          'fever',
          'inflammation',
          'period pain',
          '400mg',
        ],
        isCommon: true,
        createdAt: DateTime.now(),
      ),
    ];
  }
}