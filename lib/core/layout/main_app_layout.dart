import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/home/presentation/pages/home_page.dart';
import 'package:sheserved/features/donation/presentation/pages/donation_dashboard_page.dart';
import 'package:sheserved/features/pharmacy/presentation/pages/pharmacy_products_page.dart';
import 'package:sheserved/features/profile/presentation/pages/profile_page.dart';
import 'package:sheserved/shared/widgets/tlz_bottom_navigation_bar.dart';
import 'package:sheserved/shared/widgets/tlz_drawer.dart';
import 'package:sheserved/services/service_locator.dart';

class MainAppLayout extends StatefulWidget {
  final int initialIndex;

  const MainAppLayout({
    super.key,
    this.initialIndex = 0,
  });

  @override
  State<MainAppLayout> createState() => _MainAppLayoutState();
}

class _MainAppLayoutState extends State<MainAppLayout> {
  late int _currentIndex;
  bool _isNavBarVisible = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          setState(() {
            _currentIndex = 0;
          });
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        extendBody: true, // สำคัญมาก เพื่อให้ Navigation Bar โปร่งใสแสดงทะลุเห็นเนื้อหาได้
        drawer: const TlzDrawer(),
        drawerEnableOpenDragGesture: _currentIndex == 0, // ให้เปิด Drawer จากขอบจอได้เฉพาะตอนอยู่หน้า Home
        body: NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            // ซ่อนเมื่อเลื่อนลงเพื่อดูเนื้อหา (ทิศทาง reverse เทียบกับ scroll)
            if (notification.direction == ScrollDirection.reverse) {
              if (_isNavBarVisible) {
                setState(() => _isNavBarVisible = false);
              }
            } 
            // แสดงเมื่อเลื่อนขึ้น (ชโงกกลับมา) หรือหยุดเลื่อน
            else if (notification.direction == ScrollDirection.forward) {
              if (!_isNavBarVisible) {
                setState(() => _isNavBarVisible = true);
              }
            }
            return false; // ให้ event ผ่านลงไปที่อื่นต่อ
          },
          child: IndexedStack(
            index: _currentIndex,
            children: [
              // Index 0: Home Page (ส่งค่า isActive ไปบอกว่าตอนนี้หน้าจอนี้เปิดอยู่)
              HomePage(isActive: _currentIndex == 0),

              // Index 1: Donation Page
              const DonationDashboardPage(),

              // Index 2: Empty Placeholder (ส่วนของปุ่มบวกตรงกลาง)
              const SizedBox.shrink(),

              // Index 3: Pharmacy Page
              const PharmacyProductsPage(),

              // Index 4: Profile Page
              const ProfilePage(),
            ],
          ),
        ),
        bottomNavigationBar: TlzBottomNavigationBar(
          isVisible: _isNavBarVisible,
          currentIndex: _currentIndex,
          onIndexChanged: (index) {
            if (index == 2) return; // ปุ่มบวกตรงกลางเราใช้ onAddPressed แยกทำงานไว้แล้ว
            
            // บังคับ Login หากเลือกหน้า Donation (Index 1) แล้วยังไม่ได้ Login
            if (index == 1 && ServiceLocator.instance.currentUser == null) {
              Navigator.pushNamed(
                context, 
                '/login',
                arguments: {
                  'route': '/main-app',
                  'args': {'index': 1}
                }, // ส่ง argument แบบนี้เพื่อให้ Login เสร็จแล้วเด้งกลับมาหน้าบริจาคพร้อมแถบเมนูด้านล่าง
              );
              return;
            }

            setState(() {
              _currentIndex = index;
            });
          },
          onAddPressed: () async {
            // ✅ ตรวจสอบ Login ก่อนเข้าหน้า Emergency (ตาม Login Navigation Workflow)
            if (ServiceLocator.instance.currentUser == null) {
              final result = await Navigator.pushNamed(
                context,
                '/login',
                arguments: '/emergency-live', // หลัง Login สำเร็จ ให้พาไปหน้า Emergency ทันที
              );
              if (result is int && mounted) {
                setState(() {
                  _currentIndex = result;
                });
              }
              return;
            }
            final result = await Navigator.pushNamed(context, '/emergency-live');
            if (result is int && mounted) {
              setState(() {
                _currentIndex = result;
              });
            }
          },
        ),
      ),
    );
  }
}
