// lib/features/medicine/data/models/medicine_model.dart
// ============================================================
// FIREBASE MODEL — Converts Firestore ↔ Medicine entity
// ============================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/medicine.dart';

class MedicineModel extends Medicine {
  MedicineModel({
    required super.id,
    required super.name,
    required super.genericName,
    required super.manufacturer,
    super.category,
    super.description,
    super.uses,
    super.sideEffects,
    super.precautions,
    super.dosageInfo,
    super.dosageForm,
    super.strength,
    super.storageInstructions,
    required super.searchTerms,
    super.imageUrl,
    super.isCommon,
    required super.createdAt,
    super.updatedAt,
  });

  // Firestore document → MedicineModel
  factory MedicineModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MedicineModel(
      id: doc.id,
      name: data['name'] ?? '',
      genericName: data['genericName'] ?? '',
      manufacturer: data['manufacturer'] ?? '',
      category: data['category'] ?? 'General',
      description: data['description'],
      uses: data['uses'],
      sideEffects: data['sideEffects'],
      precautions: data['precautions'],
      dosageInfo: data['dosageInfo'],
      dosageForm: data['dosageForm'],
      strength: data['strength'],
      storageInstructions: data['storageInstructions'],
      searchTerms: List<String>.from(data['searchTerms'] ?? []),
      imageUrl: data['imageUrl'],
      isCommon: data['isCommon'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  // MedicineModel → Firestore map
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'genericName': genericName,
      'manufacturer': manufacturer,
      'category': category,
      'description': description,
      'uses': uses,
      'sideEffects': sideEffects,
      'precautions': precautions,
      'dosageInfo': dosageInfo,
      'dosageForm': dosageForm,
      'strength': strength,
      'storageInstructions': storageInstructions,
      'searchTerms': searchTerms,
      'imageUrl': imageUrl,
      'isCommon': isCommon,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  // Medicine entity → MedicineModel
  factory MedicineModel.fromEntity(Medicine medicine) {
    return MedicineModel(
      id: medicine.id,
      name: medicine.name,
      genericName: medicine.genericName,
      manufacturer: medicine.manufacturer,
      category: medicine.category,
      description: medicine.description,
      uses: medicine.uses,
      sideEffects: medicine.sideEffects,
      precautions: medicine.precautions,
      dosageInfo: medicine.dosageInfo,
      dosageForm: medicine.dosageForm,
      strength: medicine.strength,
      storageInstructions: medicine.storageInstructions,
      searchTerms: medicine.searchTerms,
      imageUrl: medicine.imageUrl,
      isCommon: medicine.isCommon,
      createdAt: medicine.createdAt,
      updatedAt: medicine.updatedAt,
    );
  }
}