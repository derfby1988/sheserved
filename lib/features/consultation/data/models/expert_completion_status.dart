// expert_completion_status.dart
// Phase 6.8: Expert Completion Rules

class ExpertCompletionStatus {
  final bool canFinish;
  final List<String> missingRequirements;
  final int progress; // 0-100
  
  // Prescription stats
  final int prescriptionCount;
  final int approvedCount;
  
  // Required question stats
  final int questionCount;
  final int answeredCount;
  final int unansweredCount;
  
  // Video call & assessment
  final bool hasVideoCall;
  final bool hasAssessment;
  
  // General chat messages
  final int generalMessageCount;

  ExpertCompletionStatus({
    required this.canFinish,
    this.missingRequirements = const [],
    this.progress = 0,
    this.prescriptionCount = 0,
    this.approvedCount = 0,
    this.questionCount = 0,
    this.answeredCount = 0,
    this.unansweredCount = 0,
    this.hasVideoCall = false,
    this.hasAssessment = false,
    this.generalMessageCount = 0,
  });

  factory ExpertCompletionStatus.fromJson(Map<String, dynamic> json) {
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

    List<String> parseMissing(dynamic value) {
      if (value == null) return [];
      if (value is List) {
        return value.map((e) => e.toString()).toList();
      }
      return [];
    }

    return ExpertCompletionStatus(
      canFinish: parseBool(json['can_finish']),
      missingRequirements: parseMissing(json['missing_requirements']),
      progress: parseInt(json['progress']),
      prescriptionCount: parseInt(json['prescription_count']),
      approvedCount: parseInt(json['approved_count']),
      questionCount: parseInt(json['question_count']),
      answeredCount: parseInt(json['answered_count']),
      unansweredCount: parseInt(json['unanswered_count']),
      hasVideoCall: parseBool(json['has_video_call']),
      hasAssessment: parseBool(json['has_assessment']),
      generalMessageCount: parseInt(json['general_message_count']),
    );
  }

  Map<String, dynamic> toJson() => {
    'can_finish': canFinish,
    'missing_requirements': missingRequirements,
    'progress': progress,
    'prescription_count': prescriptionCount,
    'approved_count': approvedCount,
    'question_count': questionCount,
    'answered_count': answeredCount,
    'unanswered_count': unansweredCount,
    'has_video_call': hasVideoCall,
    'has_assessment': hasAssessment,
    'general_message_count': generalMessageCount,
  };
}
