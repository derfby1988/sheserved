import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Hamburger Menu Button Widget
/// Custom hamburger menu with orange-yellow middle line
class TlzHamburgerMenu extends StatelessWidget {
  final VoidCallback? onPressed;
  final BuildContext? scaffoldContext;

  const TlzHamburgerMenu({
    super.key,
    this.onPressed,
    this.scaffoldContext,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (builderContext) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed ??
              () {
                // ค้นหา Scaffold ที่ใกล้ที่สุด
                final scaffold = Scaffold.maybeOf(scaffoldContext ?? builderContext);
                if (scaffold != null && scaffold.hasDrawer) {
                  scaffold.openDrawer();
                } else {
                  // ถ้าไม่พบ Drawer ใน Scaffold ปัจจุบัน อาจจะลองหา ScaffoldState อื่นๆ 
                  // หรือตรวจสอบในระดับลึกขึ้น
                  debugPrint('Drawer not available on this page');
                  // ถ้านี่ไม่ใช่หน้าแรก เราอาจจะให้กลับหน้าหลัก หรือทำอย่างอื่น
                }
              },
          borderRadius: BorderRadius.circular(8),
          // เพิ่ม padding เพื่อให้พื้นที่กดใหญ่ขึ้น (48x48 = ขนาดที่แนะนำสำหรับ touch target)
          child: Padding(
            padding: const EdgeInsets.all(16.0), // เพิ่ม padding ให้มากขึ้น
            child: Container(
              width: 29,
              height: 20,
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 23,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: AppColors.textOnPrimary,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                  Container(
                    width: 29,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: AppColors.accent, // สีส้ม-เหลือง
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                  Container(
                    width: 12.5,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: AppColors.textOnPrimary,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
