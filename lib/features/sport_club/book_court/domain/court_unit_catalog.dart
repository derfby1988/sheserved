/// Court unit label resolution for Book Court.
///
/// Resolution order (mirrors `upsert_sports_venue_court` server-side):
/// explicit per-court label -> venue+sport override -> sport catalog
/// default -> generic fallback 'สนาม'. Runtime code must never guess a
/// unit name from the sport name.
class CourtUnitCatalog {
  const CourtUnitCatalog();

  static const String fallbackUnitLabel = 'สนาม';

  /// Resolves the display label for a court. [overrideLabel] is the
  /// venue+sport override; [catalogDefault] is the seeded sport default.
  static String resolve({
    String? courtLabel,
    String? overrideLabel,
    String? catalogDefault,
  }) {
    for (final candidate in [courtLabel, overrideLabel, catalogDefault]) {
      final trimmed = candidate?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return fallbackUnitLabel;
  }
}
