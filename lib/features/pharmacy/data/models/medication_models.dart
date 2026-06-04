class MedicationModel {
  final String id;
  final String sourceType;
  final String? referenceCode;
  
  final String? genericName;
  final String tradeName;
  final String? dosageForm;
  final String? strength;
  final String? manufacturer;
  final String status;
  final String? fdaRiskStatus;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  
  // Relations
  final TmtDetailsModel? tmtDetails;
  final UnregisteredDetailsModel? unregisteredDetails;
  final ClinicalKnowledgeModel? clinicalKnowledge;
  final List<ProductCategoryModel>? categories;

  // Sheserved specifics
  final double? price;
  final String? imageUrl;
  final bool inStock;
  final bool isFavorite;

  MedicationModel({
    required this.id,
    required this.sourceType,
    this.referenceCode,
    this.genericName,
    required this.tradeName,
    this.dosageForm,
    this.strength,
    this.manufacturer,
    required this.status,
    this.fdaRiskStatus,
    this.createdAt,
    this.updatedAt,
    this.tmtDetails,
    this.unregisteredDetails,
    this.clinicalKnowledge,
    this.categories,
    this.price,
    this.imageUrl,
    this.inStock = true,
    this.isFavorite = false,
  });

  factory MedicationModel.fromJson(Map<String, dynamic> json) {
    return MedicationModel(
      id: json['id'] as String,
      sourceType: json['source_type'] as String,
      referenceCode: json['reference_code'] as String?,
      genericName: json['generic_name'] as String?,
      tradeName: json['trade_name'] as String,
      dosageForm: json['dosage_form'] as String?,
      strength: json['strength'] as String?,
      manufacturer: json['manufacturer'] as String?,
      status: json['status'] as String? ?? 'ACTIVE',
      fdaRiskStatus: json['fda_risk_status'] as String?,
      price: json['price'] != null ? double.tryParse(json['price'].toString()) : null,
      imageUrl: json['image_url'] as String?,
      inStock: json['in_stock'] as bool? ?? true,
      isFavorite: json['is_favorite'] as bool? ?? false,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
      
      // Relations
      tmtDetails: json['tmt_details'] != null && (json['tmt_details'] as List).isNotEmpty
          ? TmtDetailsModel.fromJson((json['tmt_details'] as List).first as Map<String, dynamic>)
          : null,
      unregisteredDetails: json['unregistered_details'] != null && (json['unregistered_details'] as List).isNotEmpty
          ? UnregisteredDetailsModel.fromJson((json['unregistered_details'] as List).first as Map<String, dynamic>)
          : null,
      clinicalKnowledge: json['clinical_knowledge'] != null && (json['clinical_knowledge'] as List).isNotEmpty
          ? ClinicalKnowledgeModel.fromJson((json['clinical_knowledge'] as List).first as Map<String, dynamic>)
          : null,
      categories: json['medication_category_mappings'] != null 
          ? (json['medication_category_mappings'] as List)
              .map((mapping) => mapping['product_categories'] != null 
                  ? ProductCategoryModel.fromJson(mapping['product_categories'] as Map<String, dynamic>) 
                  : null)
              .where((c) => c != null)
              .cast<ProductCategoryModel>()
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'source_type': sourceType,
      'reference_code': referenceCode,
      'generic_name': genericName,
      'trade_name': tradeName,
      'dosage_form': dosageForm,
      'strength': strength,
      'manufacturer': manufacturer,
      'status': status,
    };
  }
}

class TmtDetailsModel {
  final String medicationId;
  final String? vtmCode;
  final String? gpCode;
  final String? gpuCode;
  final String? tpCode;
  final String? tpuCode;

  TmtDetailsModel({
    required this.medicationId,
    this.vtmCode,
    this.gpCode,
    this.gpuCode,
    this.tpCode,
    this.tpuCode,
  });

  factory TmtDetailsModel.fromJson(Map<String, dynamic> json) {
    return TmtDetailsModel(
      medicationId: json['medication_id'] as String,
      vtmCode: json['vtm_code'] as String?,
      gpCode: json['gp_code'] as String?,
      gpuCode: json['gpu_code'] as String?,
      tpCode: json['tp_code'] as String?,
      tpuCode: json['tpu_code'] as String?,
    );
  }
}

class UnregisteredDetailsModel {
  final String medicationId;
  final String? originCountry;
  final String? originalLanguageName;
  final String? fdaEquivalentStatus;
  final String? riskLevel;
  final String? ingredientsList;

  UnregisteredDetailsModel({
    required this.medicationId,
    this.originCountry,
    this.originalLanguageName,
    this.fdaEquivalentStatus,
    this.riskLevel,
    this.ingredientsList,
  });

  factory UnregisteredDetailsModel.fromJson(Map<String, dynamic> json) {
    return UnregisteredDetailsModel(
      medicationId: json['medication_id'] as String,
      originCountry: json['origin_country'] as String?,
      originalLanguageName: json['original_language_name'] as String?,
      fdaEquivalentStatus: json['fda_equivalent_status'] as String?,
      riskLevel: json['risk_level'] as String?,
      ingredientsList: json['ingredients_list'] as String?,
    );
  }
}

class ClinicalKnowledgeModel {
  final String id;
  final String genericName;
  
  final String? indications;
  final String? dosageAdministration;
  final String? contraindications;
  final String? specialPrecautions;
  final String? adverseReactions;
  final String? drugInteractions;
  final String? pregnancyCategory;
  final String? storageConditions;

  ClinicalKnowledgeModel({
    required this.id,
    required this.genericName,
    this.indications,
    this.dosageAdministration,
    this.contraindications,
    this.specialPrecautions,
    this.adverseReactions,
    this.drugInteractions,
    this.pregnancyCategory,
    this.storageConditions,
  });

  factory ClinicalKnowledgeModel.fromJson(Map<String, dynamic> json) {
    return ClinicalKnowledgeModel(
      id: json['id'] as String,
      genericName: json['generic_name'] as String,
      indications: json['indications'] as String?,
      dosageAdministration: json['dosage_administration'] as String?,
      contraindications: json['contraindications'] as String?,
      specialPrecautions: json['special_precautions'] as String?,
      adverseReactions: json['adverse_reactions'] as String?,
      drugInteractions: json['drug_interactions'] as String?,
      pregnancyCategory: json['pregnancy_category'] as String?,
      storageConditions: json['storage_conditions'] as String?,
    );
  }
}

class ProductCategoryModel {
  final String id;
  final String name;
  final String type;
  final bool isActive;
  final int displayOrder;

  ProductCategoryModel({
    required this.id,
    required this.name,
    this.type = 'CATEGORY',
    this.isActive = true,
    this.displayOrder = 0,
  });

  factory ProductCategoryModel.fromJson(Map<String, dynamic> json) {
    return ProductCategoryModel(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String? ?? 'CATEGORY',
      isActive: json['is_active'] as bool? ?? true,
      displayOrder: json['display_order'] as int? ?? 0,
    );
  }

  ProductCategoryModel copyWith({
    String? id,
    String? name,
    String? type,
    bool? isActive,
    int? displayOrder,
  }) {
    return ProductCategoryModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      isActive: isActive ?? this.isActive,
      displayOrder: displayOrder ?? this.displayOrder,
    );
  }
}
