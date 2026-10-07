/// Visual styles the Book Court venue card can be rendered in.
///
/// The admin picks one on the "รูปแบบการ์ด" tab of the จัดการกีฬา page and the
/// choice is stored in `app_settings` so every device renders the same card.
/// [classic] is the original flat card and the fallback whenever a stored
/// value is missing or unknown.
enum CourtCardStyle {
  classic(
    'classic',
    'การ์ดเดิม',
    'การ์ดแบนแบบเดิมของ Book Court — เบาที่สุด ไม่มีลูกเล่น 3 มิติ',
  ),
  painter3d(
    'painter_3d',
    '3D เรนเดอร์แก้ว',
    'เรนเดอร์กระจกโปร่งแสงด้วย ray tracer (เฟรมนิ่ง) — ทับซ้อนจริง ไม่โหลด runtime',
  ),
  shaderGlass(
    'shader_glass',
    '3D แก้วหักเห (Shader)',
    'พื้นผิวแก้วและแสงขอบคำนวณด้วย fragment shader ทับภาพเรนเดอร์ — ใกล้ภาพต้นฉบับที่สุด',
  ),
  lottieCubes(
    'lottie_cubes',
    '3D อนิเมชันเรนเดอร์',
    'ก้อนลูกบาศก์อนิเมชันจาก sprite sheet ที่เรนเดอร์ด้วย ray tracer — ขยับเบา ๆ',
  );

  const CourtCardStyle(this.wireValue, this.label, this.description);

  final String wireValue;
  final String label;
  final String description;

  /// The style used when nothing valid has been configured.
  static const CourtCardStyle fallback = CourtCardStyle.classic;

  /// Styles that render the 3D glass chrome (everything except [classic]).
  bool get isThreeDimensional => this != CourtCardStyle.classic;

  static CourtCardStyle fromWire(String? raw) {
    for (final style in values) {
      if (style.wireValue == raw) return style;
    }
    return fallback;
  }
}
