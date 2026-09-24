/// Phase 6.14 — Closed-ended Question config model.
///
/// Mirrors the immutable `chat_messages.closed_ended_config` JSONB payload:
///   quantitative: {"schema_version":1,"type":"quantitative","scale_levels":3|5|10}
///   qualitative:  {"schema_version":1,"type":"qualitative","options":[2..10]}
///
/// `answer_count` is always derived — never stored. Confirmed patient answers
/// live in `closed_ended_question_answers`; `required_answer`/
/// `required_answered_at` on the message are compatibility projections.
library;

enum ClosedEndedType { quantitative, qualitative }

class ClosedEndedConfig {
  static const int schemaVersion = 1;

  /// Longest accepted qualitative label (matches the DB validator).
  static const int maxLabelLength = 80;

  /// Qualitative options bounds (matches the DB validator).
  static const int minOptions = 2;
  static const int maxOptions = 10;

  /// Allowed quantitative scale levels.
  static const List<int> allowedScaleLevels = [3, 5, 10];

  final ClosedEndedType type;

  /// 3, 5 or 10 — quantitative only.
  final int? scaleLevels;

  /// 2–10 non-empty, normalized, non-duplicate labels — qualitative only.
  final List<String>? options;

  const ClosedEndedConfig._({
    required this.type,
    this.scaleLevels,
    this.options,
  });

  factory ClosedEndedConfig.quantitative(int scaleLevels) {
    assert(allowedScaleLevels.contains(scaleLevels));
    return ClosedEndedConfig._(
      type: ClosedEndedType.quantitative,
      scaleLevels: scaleLevels,
    );
  }

  factory ClosedEndedConfig.qualitative(List<String> options) {
    return ClosedEndedConfig._(
      type: ClosedEndedType.qualitative,
      options: List.unmodifiable(options.map((o) => o.trim())),
    );
  }

  /// Number of answer choices, derived from the definition.
  int get answerCount => type == ClosedEndedType.quantitative
      ? (scaleLevels ?? 0)
      : (options?.length ?? 0);

  /// Option labels: `1..N` for quantitative, configured labels otherwise.
  List<String> get effectiveOptions {
    if (type == ClosedEndedType.qualitative) return options ?? const [];
    return List.generate(scaleLevels ?? 0, (i) => '${i + 1}');
  }

  /// Label for a 0-based option index, or null when out of range.
  String? labelAt(int index) {
    final opts = effectiveOptions;
    if (index < 0 || index >= opts.length) return null;
    return opts[index];
  }

  /// Client-side validation matching the DB rules. Returns an error key
  /// or null when the config is valid.
  String? validate() {
    if (type == ClosedEndedType.quantitative) {
      if (!allowedScaleLevels.contains(scaleLevels)) {
        return 'scale_levels must be 3, 5 or 10';
      }
      return null;
    }
    final opts = options;
    if (opts == null || opts.length < minOptions || opts.length > maxOptions) {
      return 'options must contain $minOptions-$maxOptions entries';
    }
    final seen = <String>{};
    for (final raw in opts) {
      final norm = raw.trim().toLowerCase();
      if (norm.isEmpty) return 'options must not contain empty labels';
      if (norm.length > maxLabelLength) {
        return 'option labels must not exceed $maxLabelLength characters';
      }
      if (!seen.add(norm)) {
        return 'options must not contain duplicate labels';
      }
    }
    return null;
  }

  bool get isValid => validate() == null;

  /// Safe parser — returns null for missing/malformed/invalid configs so
  /// legacy messages and bad payloads render a safe fallback instead of
  /// crashing the chat.
  static ClosedEndedConfig? tryParse(Object? json) {
    if (json is! Map) return null;
    try {
      final map = Map<String, dynamic>.from(json);
      final rawType = map['type'];
      if (rawType == 'quantitative') {
        final levels = (map['scale_levels'] as num?)?.toInt();
        final config = ClosedEndedConfig._(
          type: ClosedEndedType.quantitative,
          scaleLevels: levels,
        );
        return config.isValid ? config : null;
      }
      if (rawType == 'qualitative') {
        final rawOptions = map['options'];
        if (rawOptions is! List) return null;
        final config = ClosedEndedConfig._(
          type: ClosedEndedType.qualitative,
          options: rawOptions.map((e) => e.toString()).toList(),
        );
        return config.isValid ? config : null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'type': type == ClosedEndedType.quantitative
        ? 'quantitative'
        : 'qualitative',
    if (scaleLevels != null) 'scale_levels': scaleLevels,
    if (options != null) 'options': options,
  };

  /// Convenience wrapper used by callers that already hold a config.
  static ClosedEndedConfig? fromJson(Map<String, dynamic>? json) =>
      tryParse(json);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClosedEndedConfig &&
          type == other.type &&
          scaleLevels == other.scaleLevels &&
          _listEquals(options, other.options);

  @override
  int get hashCode =>
      Object.hash(type, scaleLevels, Object.hashAll(options ?? const []));

  static bool _listEquals(List<String>? a, List<String>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
