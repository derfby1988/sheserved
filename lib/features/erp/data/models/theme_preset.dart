/// Model สำหรับ master theme preset (จาก theme_presets table)
class ThemePreset {
  final String presetKey;
  final String presetNameTh;
  final String presetNameEn;
  final String primaryColor;
  final String accentColor;
  final String surfaceColor;
  final String textPrimary;
  final String textSecondary;
  final String errorColor;
  final String? cardBg;
  final String? cardText;

  const ThemePreset({
    required this.presetKey,
    required this.presetNameTh,
    required this.presetNameEn,
    required this.primaryColor,
    required this.accentColor,
    required this.surfaceColor,
    required this.textPrimary,
    required this.textSecondary,
    required this.errorColor,
    this.cardBg,
    this.cardText,
  });

  factory ThemePreset.fromJson(Map<String, dynamic> json) {
    return ThemePreset(
      presetKey: json['preset_key'] as String? ?? '',
      presetNameTh: json['preset_name_th'] as String? ?? '',
      presetNameEn: json['preset_name_en'] as String? ?? '',
      primaryColor: json['primary_color'] as String? ?? '#00695C',
      accentColor: json['accent_color'] as String? ?? '#FFC107',
      surfaceColor: json['surface_color'] as String? ?? '#FFFFFF',
      textPrimary: json['text_primary'] as String? ?? '#FFFFFF',
      textSecondary: json['text_secondary'] as String? ?? 'rgba(255,255,255,0.7)',
      errorColor: json['error_color'] as String? ?? '#F85149',
      cardBg: json['card_bg'] as String?,
      cardText: json['card_text'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'preset_key': presetKey,
    'preset_name_th': presetNameTh,
    'preset_name_en': presetNameEn,
    'primary_color': primaryColor,
    'accent_color': accentColor,
    'surface_color': surfaceColor,
    'text_primary': textPrimary,
    'text_secondary': textSecondary,
    'error_color': errorColor,
    'card_bg': cardBg,
    'card_text': cardText,
  };
}
