// profession_package_rule.dart
// Phase 6.8: Expert Completion Rules

class ProfessionPackageRule {
  final String id;
  final String packageId;
  final String professionId;
  
  // Prescription rules
  final bool canPrescribe;
  final bool mustPrescribe;
  final bool requiresPrescriptionApproval;
  final int minPrescriptionItems;
  
  // Required question rules
  final bool canSetRequiredQuestions;
  final int minRequiredQuestions;
  final bool mustAnswerAllQuestions;
  
  // Video call
  final bool requiresVideoCall;
  
  // Health assessment
  final bool requiresHealthAssessment;
  
  // General chat messages
  final int minGeneralMessages;
  
  final DateTime createdAt;
  final DateTime updatedAt;

  ProfessionPackageRule({
    required this.id,
    required this.packageId,
    required this.professionId,
    this.canPrescribe = false,
    this.mustPrescribe = false,
    this.requiresPrescriptionApproval = false,
    this.minPrescriptionItems = 0,
    this.canSetRequiredQuestions = true,
    this.minRequiredQuestions = 0,
    this.mustAnswerAllQuestions = false,
    this.requiresVideoCall = false,
    this.requiresHealthAssessment = false,
    this.minGeneralMessages = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProfessionPackageRule.fromJson(Map<String, dynamic> json) {
    bool parseBool(dynamic value) {
      if (value == null) return false;
      if (value is bool) return value;
      if (value is String) return value.toLowerCase() == 'true';
      return false;
    }

    int parseInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return ProfessionPackageRule(
      id: json['id'] as String? ?? '',
      packageId: json['package_id'] as String? ?? '',
      professionId: json['profession_id'] as String? ?? '',
      canPrescribe: parseBool(json['can_prescribe']),
      mustPrescribe: parseBool(json['must_prescribe']),
      requiresPrescriptionApproval: parseBool(json['requires_prescription_approval']),
      minPrescriptionItems: parseInt(json['min_prescription_items']),
      canSetRequiredQuestions: parseBool(json['can_set_required_questions'] ?? true),
      minRequiredQuestions: parseInt(json['min_required_questions']),
      mustAnswerAllQuestions: parseBool(json['must_answer_all_questions']),
      requiresVideoCall: parseBool(json['requires_video_call']),
      requiresHealthAssessment: parseBool(json['requires_health_assessment']),
      minGeneralMessages: parseInt(json['min_general_messages']),
      createdAt: json['created_at'] != null 
        ? DateTime.parse(json['created_at'] as String) 
        : DateTime.now(),
      updatedAt: json['updated_at'] != null 
        ? DateTime.parse(json['updated_at'] as String) 
        : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (id.isNotEmpty) 'id': id,
    'package_id': packageId,
    'profession_id': professionId,
    'can_prescribe': canPrescribe,
    'must_prescribe': mustPrescribe,
    'requires_prescription_approval': requiresPrescriptionApproval,
    'min_prescription_items': minPrescriptionItems,
    'can_set_required_questions': canSetRequiredQuestions,
    'min_required_questions': minRequiredQuestions,
    'must_answer_all_questions': mustAnswerAllQuestions,
    'requires_video_call': requiresVideoCall,
    'requires_health_assessment': requiresHealthAssessment,
    'min_general_messages': minGeneralMessages,
    'updated_at': updatedAt.toIso8601String(),
  };

  ProfessionPackageRule copyWith({
    String? id,
    String? packageId,
    String? professionId,
    bool? canPrescribe,
    bool? mustPrescribe,
    bool? requiresPrescriptionApproval,
    int? minPrescriptionItems,
    bool? canSetRequiredQuestions,
    int? minRequiredQuestions,
    bool? mustAnswerAllQuestions,
    bool? requiresVideoCall,
    bool? requiresHealthAssessment,
    int? minGeneralMessages,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ProfessionPackageRule(
    id: id ?? this.id,
    packageId: packageId ?? this.packageId,
    professionId: professionId ?? this.professionId,
    canPrescribe: canPrescribe ?? this.canPrescribe,
    mustPrescribe: mustPrescribe ?? this.mustPrescribe,
    requiresPrescriptionApproval: requiresPrescriptionApproval ?? this.requiresPrescriptionApproval,
    minPrescriptionItems: minPrescriptionItems ?? this.minPrescriptionItems,
    canSetRequiredQuestions: canSetRequiredQuestions ?? this.canSetRequiredQuestions,
    minRequiredQuestions: minRequiredQuestions ?? this.minRequiredQuestions,
    mustAnswerAllQuestions: mustAnswerAllQuestions ?? this.mustAnswerAllQuestions,
    requiresVideoCall: requiresVideoCall ?? this.requiresVideoCall,
    requiresHealthAssessment: requiresHealthAssessment ?? this.requiresHealthAssessment,
    minGeneralMessages: minGeneralMessages ?? this.minGeneralMessages,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
