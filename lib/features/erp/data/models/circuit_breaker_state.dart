/// Model สำหรับ circuit_breaker_states (reliability pattern)
class CircuitBreakerState {
  final String id;
  final String professionId;
  final String serviceName;
  final String circuitState; // closed, open, half_open
  final int failureCount;
  final int successCount;
  final DateTime? lastFailureAt;
  final DateTime? lastSuccessAt;
  final DateTime? openedAt;
  final DateTime? halfOpenAt;
  final int maxFailures;
  final int resetTimeoutSec;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CircuitBreakerState({
    required this.id,
    required this.professionId,
    required this.serviceName,
    required this.circuitState,
    this.failureCount = 0,
    this.successCount = 0,
    this.lastFailureAt,
    this.lastSuccessAt,
    this.openedAt,
    this.halfOpenAt,
    this.maxFailures = 5,
    this.resetTimeoutSec = 1800,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CircuitBreakerState.fromJson(Map<String, dynamic> json) {
    return CircuitBreakerState(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      serviceName: json['service_name'] as String,
      circuitState: json['circuit_state'] as String,
      failureCount: (json['failure_count'] as num?)?.toInt() ?? 0,
      successCount: (json['success_count'] as num?)?.toInt() ?? 0,
      lastFailureAt: json['last_failure_at'] != null
          ? DateTime.parse(json['last_failure_at'] as String)
          : null,
      lastSuccessAt: json['last_success_at'] != null
          ? DateTime.parse(json['last_success_at'] as String)
          : null,
      openedAt: json['opened_at'] != null
          ? DateTime.parse(json['opened_at'] as String)
          : null,
      halfOpenAt: json['half_open_at'] != null
          ? DateTime.parse(json['half_open_at'] as String)
          : null,
      maxFailures: (json['max_failures'] as num?)?.toInt() ?? 5,
      resetTimeoutSec: (json['reset_timeout_sec'] as num?)?.toInt() ?? 1800,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'service_name': serviceName,
      'circuit_state': circuitState,
      'failure_count': failureCount,
      'success_count': successCount,
      'last_failure_at': lastFailureAt?.toIso8601String(),
      'last_success_at': lastSuccessAt?.toIso8601String(),
      'opened_at': openedAt?.toIso8601String(),
      'half_open_at': halfOpenAt?.toIso8601String(),
      'max_failures': maxFailures,
      'reset_timeout_sec': resetTimeoutSec,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  bool get isClosed => circuitState == 'closed';
  bool get isOpen => circuitState == 'open';
  bool get isHalfOpen => circuitState == 'half_open';
  bool get isHealthy => isClosed || isHalfOpen;
}
