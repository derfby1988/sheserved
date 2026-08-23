import 'package:flutter/material.dart';
import '../../../../shared/widgets/tlz_app_top_bar.dart';
import '../../../../shared/widgets/tlz_drawer.dart';
import '../../../../services/service_locator.dart';
import '../../data/models/medication_models.dart';

class MedicationDetailPage extends StatefulWidget {
  final String? medicationId;

  const MedicationDetailPage({super.key, this.medicationId});

  @override
  State<MedicationDetailPage> createState() => _MedicationDetailPageState();
}

class _MedicationDetailPageState extends State<MedicationDetailPage> {
  int _selectedNumber = 1;
  String _textSize = 'S';
  
  bool _isLoading = true;
  String? _error;
  MedicationModel? _medication;

  @override
  void initState() {
    super.initState();
    _fetchMedicationDetails();
  }

  Future<void> _fetchMedicationDetails() async {
    if (widget.medicationId == null) {
      setState(() => _isLoading = false);
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final repo = ServiceLocator.instance.pharmacyRepository;
      final userId = ServiceLocator.instance.currentUser?.id;
      final detail = await repo.getMedicationDetails(
        medicationId: widget.medicationId!,
        userId: userId,
      );
      setState(() {
        _medication = detail;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFB5D172), // สีเขียวอ่อนแบบในภาพ
      drawer: const TlzDrawer(),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header Bar
            TlzAppTopBar.onPrimary(
              notificationCount: 0,
              searchHintText: 'ค้นหายา...',
              onQRTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('QR Scanner จะเปิดใช้งานเร็วๆ นี้')),
                );
              },
              onNotificationTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('การแจ้งเตือนจะเปิดใช้งานเร็วๆ นี้')),
                );
              },
              onCartTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ตะกร้าสินค้าจะเปิดใช้งานเร็วๆ นี้')),
                );
              },
              onResultTap: (item) {
                // สำหรับช่องค้นหา
              },
            ),
            
            // Back Arrow Button
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 16.0, top: 4.0),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF58910F), size: 28),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            
            // Main Content Area
            Expanded(
              child: Stack(
                children: [
                  // โครงสร้างที่ Fix ไว้ ไม่ Scroll
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildMainCard(),
                      const SizedBox(height: 20),
                      _buildPaginationCircles(),
                      const SizedBox(height: 20),
                      // ให้ ContentBox กินพื้นที่ที่เหลือและ Scroll ได้
                      Expanded(
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator(color: Color(0xFF58910F)))
                            : _error != null
                                ? Center(child: Text('เกิดข้อผิดพลาด: $_error', style: const TextStyle(color: Colors.red)))
                                : _buildContentBox(),
                      ),
                    ],
                  ),

                  // ส่วนเครื่องมือปรับขนาดอักษร (ลอยตัวอยู่ด้านขวา)
                  Positioned(
                    right: 8,
                    top: 150, // ปรับให้อยู่ตรงรอยต่อระหว่างส่วนหัวและกล่องขาว
                    child: _buildFontSizeController(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      
      // ปุ่ม "ตกลง" และเลือกภาษา ซึ่งลอยอยู่ด้านล่าง
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _buildBottomActions(),
    );
  }

  Widget _buildMainCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // การ์ดสีเขียวอ่อน
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(left: 20, top: 24, bottom: 24, right: 100),
            decoration: BoxDecoration(
              color: const Color(0xFFE3ECCB), // สีเขียวสว่าง
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _medication?.tradeName ?? 'ชื่อทางการค้า',
                  style: const TextStyle(
                    color: Color(0xFF58910F), // สีเขียวเข้มของข้อความ
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Sukhumvit Set',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _medication?.genericName ?? 'ชื่อตามหลัก',
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Sukhumvit Set',
                  ),
                ),
                const SizedBox(height: 30), // พื้นที่ว่างเผื่อไว้ตามดีไซน์
              ],
            ),
          ),
          
          // วงกลมสีขาวมุมขวาบน
          Positioned(
            right: -10,
            top: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginationCircles() {
    // 1 2 3 3 5 (จากดีไซน์ แต่คิดว่าน่าจะเป็น 1 2 3 4 5)
    return Padding(
      padding: const EdgeInsets.only(right: 40.0), // เผื่อขวาไว้ไม่ให้แคบไป
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildCircleIndicator(1),
          const SizedBox(width: 8),
          _buildCircleIndicator(2),
          const SizedBox(width: 8),
          _buildCircleIndicator(3),
          const SizedBox(width: 8),
          _buildCircleIndicator(4),
          const SizedBox(width: 8),
          _buildCircleIndicator(5),
        ],
      ),
    );
  }

  Widget _buildCircleIndicator(int number) {
    bool isSelected = _selectedNumber == number;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedNumber = number;
        });
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey.withOpacity(0.8) : Colors.transparent,
          shape: BoxShape.circle,
          border: isSelected ? null : Border.all(color: Colors.grey.withOpacity(0.5), width: 1),
        ),
        child: Center(
          child: Text(
            number.toString(),
            style: const TextStyle(
              color: Color(0xFFF7B516), // สีส้มอมเหลือง
              fontSize: 18,
              fontWeight: FontWeight.bold,
              fontFamily: 'Sukhumvit Set',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContentBox() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(left: 16, right: 36, bottom: 80), // เว้นขวาให้ Font Controller และเว้นล่างให้ปุ่ม
      padding: const EdgeInsets.only(left: 16, top: 0, right: 16, bottom: 0),
      // ใช้ Clip.antiAlias เพื่อให้ขอบของ Scroll ไม่ทะลุ BorderRadius
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(32)),
      ),
      // ใส่ ScrollView ไว้ด้านใน
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(left: 16, top: 24, right: 16, bottom: 24),
        child: Text(
        _getContentText(),
        style: const TextStyle(
          color: Color(0xFF58910F),
          fontSize: 14,
          height: 1.8,
          fontFamily: 'Sukhumvit Set',
          fontWeight: FontWeight.w500,
        ),
        ),
      ),
    );
  }

  String _getContentText() {
    if (_medication == null) {
      return '1. ยานี้คือยาอะไร\n    1.1 ยานี้มีชื่อสามัญว่าอะไร\n    1.2 ยานี้ใช้เพื่ออะไร\n    1.3 ให้ระบุข้อมูลสำคัญอื่นๆ\n2. ข้อควรรู้ก่อนใช้ยา\n    2.1 ห้ามใช้ยานี้เมื่อไร\n    2.2 ข้อควรระวังเมื่อใช้ยานี้\n3. วิธีใช้ยา\n    3.1 ขนาดและวิธีใช้\n4. ข้อควรปฏิบัติระหว่างใช้ยา\n5. อันตรายที่อาจเกิดจากยา';
    }
    
    // เลือกเนื้อหามาแสดงตามแท็บหรือข้อมูลที่มี
    // ในตัวอย่างนี้ สมมติว่าเอามารวมๆ กันให้ดูก่อน
    final buf = StringBuffer();
    if (_medication!.clinicalKnowledge != null) {
      final ck = _medication!.clinicalKnowledge!;
      if (ck.indications != null) buf.writeln('ข้อบ่งใช้ (Indications):\n${ck.indications}\n');
      if (ck.dosageAdministration != null) buf.writeln('ขนาดยาและวิธีบริหารยา:\n${ck.dosageAdministration}\n');
      if (ck.contraindications != null) buf.writeln('ข้อห้ามใช้:\n${ck.contraindications}\n');
      if (ck.adverseReactions != null) buf.writeln('อาการไม่พึงประสงค์:\n${ck.adverseReactions}\n');
      if (ck.specialPrecautions != null) buf.writeln('ข้อควรระวัง:\n${ck.specialPrecautions}\n');
    }
    
    if (buf.isEmpty) {
      buf.writeln('กำลังรอข้อมูลทางการแพทย์เพิ่มเติมของยานี้...');
      buf.writeln('\nผู้ผลิต: ${_medication!.manufacturer ?? "-"}');
      buf.writeln('รูปแบบ: ${_medication!.dosageForm ?? "-"}');
      buf.writeln('ความแรง: ${_medication!.strength ?? "-"}');
    }

    return buf.toString();
  }

  Widget _buildFontSizeController() {
    return Container(
      width: 48,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // เครื่องหมายบวก (+)
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Color(0xFF6B6B6B)),
            onPressed: () {},
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            padding: EdgeInsets.zero,
          ),
          
          // ตัวอักษร S M L แบบมีวงกลมสีเทา
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: Color(0xFF8A8A8A), // สีเทา
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _textSize,
                style: const TextStyle(
                  color: Color(0xFFF7B516), // ตัว S สีเหลืองทอง
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  fontFamily: 'Sukhumvit Set',
                ),
              ),
            ),
          ),
          
          // เครื่องหมายลบ (-)
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFD6D6D6)), // สีเทาจางกว่า
            onPressed: () {},
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    return Padding(
      padding: const EdgeInsets.only(left: 24.0, right: 24.0, bottom: 20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Text ไทย / Eng
          const Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'ไทย',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                    fontFamily: 'Sukhumvit Set',
                  ),
                ),
                TextSpan(
                  text: '/Eng',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Sukhumvit Set',
                  ),
                ),
              ],
            ),
          ),
          
          // ปุ่ม "ตกลง" สีส้มเหลือง
          GestureDetector(
            onTap: () {
              // Action เมื่อกดตกลง
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF7B516), // สีเหลืองทอง
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'ตกลง',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Sukhumvit Set',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
