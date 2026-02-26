import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/models/consultation_request_model.dart';
import '../../data/models/consultation_package.dart';
import '../../../../services/service_locator.dart';


class PackageHealthCarePage extends StatefulWidget {
  const PackageHealthCarePage({super.key});

  @override
  State<PackageHealthCarePage> createState() => _PackageHealthCarePageState();
}
class _PackageHealthCarePageState extends State<PackageHealthCarePage> {
  // List of packages loaded from DB
  List<Map<String, dynamic>> _packages = [];
  int _selectedIndex = 0;
  bool _isLoading = true;
  String _gender = 'unknown';
  late FixedExtentScrollController _scrollController;

  /// ดึงข้อมูลแพ็คเกจจริงจาก Supabase
  Future<void> _loadLivePackages() async {
    try {
      final response = await Supabase.instance.client
          .from('consultation_packages')
          .select()
          .eq('is_active', true)
          .order('display_order');

      final List<ConsultationPackage> livePks = (response as List)
          .map((e) => ConsultationPackage.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      if (mounted) {
        setState(() {
          _packages = livePks.map((p) {
            // สร้างรายการรายละเอียดจาก description และ expertGroups
            List<String> details = [];
            if (p.description.isNotEmpty) {
               // แยกตามบรรทัดหรือจุดไข่ปลา
               details.addAll(p.description.split('\n').where((s) => s.trim().isNotEmpty));
            }
            
            // เพิ่มข้อมูลกลุ่มผู้เชี่ยวชาญถ้าไม่มีใน description
            for (var group in p.expertGroups) {
              if (group.isRequired) {
                details.add('รวมผู้เชี่ยวชาญ: ${group.name}');
              }
            }
            
            if (p.includesAI) {
                details.add('ระบบวิเคราะห์อาการด้วย Vega AI');
            }

            // ถ้าไม่มีรายละเอียดยังคงใส่ mock รายละเอียดไว้บ้างให้สวยงาม
            if (details.isEmpty) {
              details = ['ปรึกษาผ่านวิดีโอคอล', 'สรุปผลการวินิจฉัย'];
            }

            return {
              'id': p.id,
              'name': p.name,
              'short': p.shortName,
              'price': p.price,
              'useAI': p.includesAI,
              'details': details,
            };
          }).toList();
          
          if (_packages.isNotEmpty) {
             // เลือกตัวที่ถูกที่สุดเป็นค่าเริ่มต้น (หรือตัวที่มีราคา 299 ตามเดิมถ้าหาเจอ)
             _selectedIndex = _packages.indexWhere((p) => p['price'] == 299.0);
             if (_selectedIndex == -1) _selectedIndex = _packages.length - 1; 
             
             // อัปเดตตำแหน่งวงล้อ
             _scrollController.jumpToItem(_selectedIndex);
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading live packages: $e');
      // Fallback to static mock if DB fails
      if (mounted) {
        setState(() {
           _packages = _getMockPackages();
           _selectedIndex = 3;
           _scrollController.jumpToItem(_selectedIndex);
        });
      }
    }
  }

  List<Map<String, dynamic>> _getMockPackages() {
    return [
      {
        'name': 'แพ็คเกจ ปรึกษาผู้เชี่ยวชาญระดับอาจารย์แพทย์ + AI',
        'short': 'อาจารย์หมอ + AI',
        'price': 3290.0,
        'useAI': true,
        'details': ['ปรึกษาอาจารย์แพทย์ผ่านวิดีโอคอล 20 นาที', 'ระบบวิเคราะห์อาการด้วย AI ระดับสูง']
      },
      {
        'name': 'แพ็คเกจ สำหรับปรึกษาผู้เชี่ยวชาญระดับอาจารย์แพทย์',
        'short': 'อาจารย์หมอ',
        'price': 2990.0,
        'useAI': false,
        'details': ['ปรึกษาอาจารย์แพทย์ผ่านวิดีโอคอล 15 นาที']
      },
      {
        'name': 'แพ็คเกจ สำหรับปรึกษาแพทย์เฉพาะทาง',
        'short': 'หมอเฉพาะทาง',
        'price': 799.0,
        'useAI': false,
        'details': ['ปรึกษาแพทย์เฉพาะทางผ่านวิดีโอคอล 15 นาที']
      },
      {
        'name': 'แพ็คเกจ สำหรับปรึกษาแพทย์ทั่วไป/เภสัช',
        'short': 'หมอ/เภสัช',
        'price': 299.0,
        'useAI': false,
        'details': ['ปรึกษาแพทย์หรือเภสัชกรผ่านแชท/เสียง']
      },
    ];
  }

  @override
  void initState() {
    super.initState();
    _scrollController = FixedExtentScrollController(initialItem: _selectedIndex);
    
    // Safety check: ensure user is logged in
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (ServiceLocator.instance.currentUser == null) {
        Navigator.pushReplacementNamed(
          context, 
          '/login', 
          arguments: '/package-healthcare'
        );
        return;
      }
      await _loadLivePackages(); // Load real packages first
      _loadGender();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
  Future<void> _loadGender() async {
    try {
      final user = ServiceLocator.instance.currentUser;
      if (user != null) {
        final profile = await ServiceLocator.instance.userRepository.getConsumerProfile(user.id);
        if (profile != null && profile.healthInfo != null && profile.healthInfo!.isNotEmpty) {
          final gender = profile.healthInfo!['gender']?.toString().toLowerCase() ?? 'unknown';
          if (mounted) {
            setState(() {
              _gender = gender;
              _isLoading = false;
            });
            return;
          }
        } else {
          // No health info, redirect to Health Data Entry
          if (mounted) {
            Navigator.pushReplacementNamed(
              context, 
              '/health-data-entry',
              arguments: { 'redirect': '/package-healthcare' }
            );
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading gender: $e');
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Color get _themeColor {
    if (_gender == 'female' || _gender == 'หญิง' || _gender == 'f') return Colors.pinkAccent;
    if (_gender == 'male' || _gender == 'ชาย' || _gender == 'm') return Colors.blueAccent;
    return AppColors.primary; // default green
  }
  
  String get _genderText {
    if (_gender == 'female' || _gender == 'หญิง' || _gender == 'f') return 'สำหรับคุณผู้หญิง';
    if (_gender == 'male' || _gender == 'ชาย' || _gender == 'm') return 'สำหรับคุณผู้ชาย';
    return 'สำหรับปรึกษาผู้เชี่ยวชาญ';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_packages.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('ไม่พบแพ็คเกจ')),
        body: const Center(child: Text('ขณะนี้ยังไม่มีแพ็คเกจที่เปิดใช้งาน')),
      );
    }

    final selectedPackage = _packages[_selectedIndex];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: _themeColor),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline, color: Colors.orangeAccent),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.shopping_cart_outlined, color: Colors.grey),
            onPressed: () {},
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Column(
                  children: [
                    Text(
                      'แพ็คเกจ',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: _themeColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _genderText,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // This is a simplified simulation of the radial wheel
                    // In a real complete app, we'd use a CustomPainter or ListWheelScrollView configured horizontally/radially.
                    // Glassmorphism Radial Wheel Background
                    Positioned(
                      left: -MediaQuery.of(context).size.width * 0.4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(MediaQuery.of(context).size.width),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            width: MediaQuery.of(context).size.width * 1.1,
                            height: MediaQuery.of(context).size.width * 1.1,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _themeColor.withValues(alpha: 0.05),
                              border: Border.all(color: _themeColor.withValues(alpha: 0.15), width: 2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: -MediaQuery.of(context).size.width * 0.2,
                      child: Container(
                        width: MediaQuery.of(context).size.width * 0.65,
                        height: MediaQuery.of(context).size.width * 0.65,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.4),
                          boxShadow: [
                            BoxShadow(
                              color: _themeColor.withValues(alpha: 0.08),
                              blurRadius: 30,
                              spreadRadius: 5,
                            )
                          ],
                        ),
                      ),
                    ),
                    // Value Display
                    Positioned(
                      right: 40,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                width: 24,
                                height: 2,
                                color: _themeColor,
                                margin: const EdgeInsets.only(bottom: 12, right: 8),
                              ),
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: (selectedPackage['price'] as double)),
                                duration: const Duration(milliseconds: 600),
                                curve: Curves.easeOutCubic,
                                builder: (context, value, child) {
                                  return Text(
                                    value.toStringAsFixed(0),
                                    style: TextStyle(
                                      fontSize: 48,
                                      fontWeight: FontWeight.bold,
                                      color: _themeColor,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const Text(
                            'บาท',
                            style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 20),
                          // Package details list
                          ... (selectedPackage['details'] as List<String>).map((detail) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  detail,
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                  textAlign: TextAlign.right,
                                ),
                                const SizedBox(width: 6),
                                Icon(Icons.check_circle_outline, size: 12, color: _themeColor),
                              ],
                            ),
                          )),
                        ],
                      ),
                    ),
                    
                    // Simple text representation for scrolling logic UI
                    Positioned(
                      left: 60,
                      child: SizedBox(
                        height: 300,
                        width: 150,
                        child: ListWheelScrollView(
                          controller: _scrollController,
                          itemExtent: 70,
                          perspective: 0.005,
                          physics: const FixedExtentScrollPhysics(),
                          offAxisFraction: -0.5,
                          squeeze: 1.2,
                          onSelectedItemChanged: (index) {
                            setState(() {
                              _selectedIndex = index;
                            });
                          },
                          children: _packages.map((pkg) {
                            final idx = _packages.indexOf(pkg);
                            final isSel = idx == _selectedIndex;
                            return Center(
                              child: Text(
                                pkg['short'],
                                style: TextStyle(
                                  fontSize: isSel ? 18 : 14,
                                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                  color: isSel ? Colors.grey.shade800 : Colors.grey.shade400,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: ElevatedButton(
                  onPressed: () {
                    // Start building the empty request object and pass to next page
                    final request = ConsultationRequestModel(
                      id: '',
                      userId: '', // populated at the end
                      packageId: selectedPackage['id'],
                      packageName: selectedPackage['name'],
                      price: selectedPackage['price'],
                      bodyArea: {'gender': _gender}, // pass down gender
                      useAI: selectedPackage['useAI'] ?? false,
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                    );
                    Navigator.pushNamed(context, '/analyze-body', arguments: request);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text('Next', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
