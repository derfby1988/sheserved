import 'package:flutter/material.dart';
import 'package:sheserved/features/sport_club/presentation/pages/sports_hub_page.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';
import '../../../../core/constants/app_text_styles.dart';

/// Pharmacy Card Widget - แสดงข้อมูลคลับคนรักการออกกำลังกาย สไตล์ Neumorphic
/// รักษารูปแบบและขนาดความสูงเดิมของการ์ด (Row layout) เพื่อไม่ให้กระทบ layout ของหน้า Home
/// มิติแสงเงาและมุมโค้งถูกปรับแต่งให้นูนลอยเด่นชัดเทียบเท่าภาพต้นแบบ
class HomePharmacyCard extends StatelessWidget {
  final VoidCallback? onSearchTap;

  const HomePharmacyCard({super.key, this.onSearchTap});

  void _navigateToSportsHub(BuildContext context, int initialPage) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SportsHubPage(initialPage: initialPage),
      ),
    );
  }

  Widget _buildMiniInsetButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required int targetPage,
    bool isActive = false,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showIcon = constraints.maxWidth >= 72;
        return NeumorphicInsetBox(
          height: 27,
          borderRadius: 9,
          distance: 2.2,
          blur: 4.0,
          border: isActive
              ? const BorderSide(color: NeumorphicTheme.accentCyan, width: 1.2)
              : null,
          outerGlowShadows: isActive
              ? [
                  BoxShadow(
                    color: NeumorphicTheme.accentCyan.withValues(alpha: 0.35),
                    offset: const Offset(0, 1),
                    blurRadius: 4,
                  ),
                ]
              : null,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () => _navigateToSportsHub(context, targetPage),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showIcon) ...[
                          Icon(
                            icon,
                            size: 12,
                            color: isActive
                                ? NeumorphicTheme.primaryBlue
                                : NeumorphicTheme.textSecondary,
                          ),
                          const SizedBox(width: 2.5),
                        ],
                        Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          style: TextStyle(
                            fontSize: showIcon ? 9.5 : 10.5,
                            fontWeight: isActive
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: isActive
                                ? NeumorphicTheme.primaryBlue
                                : NeumorphicTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchButton(BuildContext context) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: NeumorphicTheme.buttonGradient,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E40AF).withValues(alpha: 0.35),
            offset: const Offset(0, 4),
            blurRadius: 8,
          ),
          BoxShadow(
            color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
            offset: const Offset(0, 1.5),
            blurRadius: 7,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _navigateToSportsHub(context, 1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'เข้าคลับ',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                    SizedBox(width: 3),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final screenWidth = MediaQuery.of(context).size.width;

    Widget cardContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        // ไล่เฉดแสงเฉียง 135 องศา (บนซ้ายสว่างรับแสง -> ล่างขวาหลบแสง) ตามภาพต้นแบบ
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF8FAFD), // สว่างรับแสงมุมบนซ้าย
            Color(0xFFEBF0F5), // โทนกลางพื้น Neumorphic
            Color(0xFFDFE5ED), // หลบแสงมุมล่างขวา
          ],
          stops: [0.0, 0.45, 1.0],
        ),
        // ขอบสันรับแสงสะท้อนสีขาว (Specular Bevel Rim) ช่วยให้การ์ดดูนูนคมชัด
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.90),
          width: 1.4,
        ),
        boxShadow: [
          // 1. เงามืดฟุ้งลึกรอบนอก ยกระดับการ์ดให้ดูลอยตัวเหนือหน้า Home (Ambient Floating Elevation)
          BoxShadow(
            color: const Color(0xFF64748B).withValues(alpha: 0.25),
            offset: const Offset(0, 12),
            blurRadius: 28,
            spreadRadius: 1,
          ),
          // 2. เงามืดลึกมุมล่างขวา ตามทิศทางแสงเฉียงเดียวกับภาพต้นแบบ (Directional Neumorphic Shadow)
          const BoxShadow(
            color: Color.fromRGBO(150, 166, 188, 0.80),
            offset: Offset(12, 14),
            blurRadius: 24,
            spreadRadius: 1,
          ),
          // 3. เงาคมช่วงขอบล่างเพิ่มมิติความหนาของแผ่นการ์ด
          BoxShadow(
            color: const Color(0xFF8193AA).withValues(alpha: 0.35),
            offset: const Offset(3, 5),
            blurRadius: 8,
          ),
          // 4. แสงสว่างจ้าบนซ้ายสะท้อนจากแหล่งกำเนิดแสง (Directional Light Glow)
          const BoxShadow(
            color: Color.fromRGBO(255, 255, 255, 0.98),
            offset: Offset(-10, -10),
            blurRadius: 20,
            spreadRadius: 1,
          ),
          // 5. แสงสะท้อนสันขอบบนซ้ายคมชัด (Specular Edge Glow)
          const BoxShadow(
            color: Color.fromRGBO(255, 255, 255, 0.90),
            offset: Offset(-2, -2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: [
          // 1. Icon วงกลมนูนสไตล์ Raised Disc ตามภาพต้นแบบ พร้อมขอบรับแสง
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF7FAFD), Color(0xFFE2E8F0)],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.9),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color.fromRGBO(155, 170, 192, 0.60),
                  offset: const Offset(4, 4),
                  blurRadius: 8,
                ),
                const BoxShadow(
                  color: Color.fromRGBO(255, 255, 255, 0.95),
                  offset: Offset(-3, -3),
                  blurRadius: 7,
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFFFDF7D),
                      Color(0xFFF5B027),
                      Color(0xFFD48B10),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF996515).withValues(alpha: 0.45),
                      offset: const Offset(0, 2.5),
                      blurRadius: 5,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.fitness_center_rounded,
                    color: Colors.white,
                    size: 19,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // 2. Content ตรงกลาง (ความสูงคงที่ ไม่ทำให้การ์ดยืดออก)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final buttonWidth = constraints.maxWidth < 232
                    ? constraints.maxWidth * 0.38
                    : 88.0;
                final supportingWidth = (constraints.maxWidth - buttonWidth - 8)
                    .clamp(0.0, constraints.maxWidth)
                    .toDouble();

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // บรรทัดที่ 1: "คลับของคนรัก" + ไอคอนหัวใจสีขาว + "การออกกำลังกาย"
                        SizedBox(
                          width: double.infinity,
                          child: FittedBox(
                            fit: BoxFit.fitWidth,
                            alignment: Alignment.centerLeft,
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  const TextSpan(text: 'คลับของคนรัก '),
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Container(
                                      width: 17,
                                      height: 17,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient:
                                            NeumorphicTheme.buttonGradient,
                                        borderRadius: BorderRadius.circular(5),
                                        boxShadow: [
                                          BoxShadow(
                                            color: NeumorphicTheme.accentCyan
                                                .withValues(alpha: 0.4),
                                            offset: const Offset(0, 1),
                                            blurRadius: 3,
                                          ),
                                        ],
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.favorite_rounded,
                                          color: Colors.white,
                                          size: 10,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const TextSpan(text: ' การออกกำลังกาย'),
                                ],
                              ),
                              style: AppTextStyles.heading5.copyWith(
                                color: NeumorphicTheme.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                              maxLines: 1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 1),
                        SizedBox(
                          width: supportingWidth,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'ศูนย์รวมอุปกรณ์ อาหารเพื่อสุขภาพ ศูนย์ความงาม',
                              style: AppTextStyles.bodySmall.copyWith(
                                color: NeumorphicTheme.textSecondary,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        SizedBox(
                          width: supportingWidth,
                          child: Row(
                            children: [
                              Expanded(
                                child: _buildMiniInsetButton(
                                  context: context,
                                  icon: Icons.stadium_rounded,
                                  label: 'สนามกีฬา',
                                  targetPage: 0,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: _buildMiniInsetButton(
                                  context: context,
                                  icon: Icons.group_rounded,
                                  label: 'หาเพื่อน',
                                  targetPage: 1,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: _buildMiniInsetButton(
                                  context: context,
                                  icon: Icons.sports_rounded,
                                  label: 'ผู้ฝึกสอน',
                                  targetPage: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // 3. Search Button สไตล์ Vibrant Cyan-Blue Gradient Pill พร้อมเงาลอยเด่นชัด
                    Positioned(
                      right: 0,
                      bottom: 0,
                      width: buttonWidth,
                      child: _buildSearchButton(context),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );

    // Wrap with width constraint for landscape
    if (isLandscape) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: Alignment.center,
          child: SizedBox(width: screenWidth * 0.5, child: cardContent),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: cardContent,
    );
  }
}
