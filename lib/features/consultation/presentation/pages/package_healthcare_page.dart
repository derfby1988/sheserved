import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
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
  bool _isPackagesLoading = false;
  String _gender = 'unknown';
  late FixedExtentScrollController _scrollController;
  double _scrollOffset = 0.0; // To track fractional scroll

  /// ดึงข้อมูลแพ็คเกจจริงจาก Supabase
  Future<void> _loadLivePackages() async {
    try {
      final response = await Supabase.instance.client
          .from('consultation_packages')
          .select()
          .eq('is_active', true)
          .order('price'); // เรียงจากราคาถูกที่สุดไปแพงที่สุด

      final List<ConsultationPackage> livePks = (response as List)
          .map(
            (e) => ConsultationPackage.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList();

      if (mounted) {
        setState(() {
          _packages = livePks.map((p) {
            // สร้างรายการรายละเอียดจาก description และ expertGroups
            List<String> details = [];
            if (p.description.isNotEmpty) {
              // แยกตามบรรทัดหรือจุดไข่ปลา
              details.addAll(
                p.description.split('\n').where((s) => s.trim().isNotEmpty),
              );
            }

            // เพิ่มข้อมูลกลุ่มผู้เชี่ยวชาญถ้าไม่มีใน description
            for (var group in p.expertGroups) {
              if (group.isRequired) {
                details.add(group.name);
              }
            }

            if (p.includesAI) {
              details.add('ระบบวิเคราะห์อาการด้วย Vega AI');
            }

            // Always add Medical Tools for consultation packages
            details.add('เครื่องมือแพทย์ (ใบสั่งยา/สรุปผล)');

            // ถ้าไม่มีรายละเอียดยังคงใส่ mock รายละเอียดไว้บ้างให้สวยงาม
            if (details.length <= 1) { // 1 because we just added Medical Tools
              details.insert(0, 'ปรึกษาผ่านวิดีโอคอล');
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
            _selectedIndex = 0;

            // ลูกเล่น: สั่งหมุนวงล้อโชว์ หลังจากหน้าจอพร้อมแล้ว
            Future.delayed(const Duration(milliseconds: 500), () async {
              if (mounted && _scrollController.hasClients) {
                // วาร์ปไปที่ตำแหน่งไกลออกไป 2 ช่วง เพื่อให้เห็นการหมุนที่ยาวขึ้น
                final spinOffset = _packages.length * 2;
                _scrollController.jumpToItem(spinOffset);

                // หน่วงเสี้ยววินาทีก่อนเริ่มหมุนกลับอย่างนุ่มนวล
                await Future.delayed(const Duration(milliseconds: 50));

                if (mounted && _scrollController.hasClients) {
                  _scrollController.animateToItem(
                    0,
                    duration: const Duration(
                      milliseconds: 2200,
                    ), // เพิ่มเวลาหมุนให้นุ่มนวลขึ้น
                    curve: Curves.easeOutQuart,
                  );
                }
              }
            });
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
        'details': [
          'ปรึกษาอาจารย์แพทย์ผ่านวิดีโอคอล 20 นาที',
          'ระบบวิเคราะห์อาการด้วย AI ระดับสูง',
          'เครื่องมือแพทย์ (ใบสั่งยา/สรุปผล)',
        ],
      },
      {
        'name': 'แพ็คเกจ สำหรับปรึกษาผู้เชี่ยวชาญระดับอาจารย์แพทย์',
        'short': 'อาจารย์หมอ',
        'price': 2990.0,
        'useAI': false,
        'details': [
          'ปรึกษาอาจารย์แพทย์ผ่านวิดีโอคอล 15 นาที',
          'เครื่องมือแพทย์ (ใบสั่งยา/สรุปผล)',
        ],
      },
      {
        'name': 'แพ็คเกจ สำหรับปรึกษาแพทย์เฉพาะทาง',
        'short': 'หมอเฉพาะทาง',
        'price': 799.0,
        'useAI': false,
        'details': [
          'ปรึกษาแพทย์เฉพาะทางผ่านวิดีโอคอล 15 นาที',
          'เครื่องมือแพทย์ (ใบสั่งยา/สรุปผล)',
        ],
      },
      {
        'name': 'แพ็คเกจ สำหรับปรึกษาแพทย์ทั่วไป/เภสัช',
        'short': 'หมอ/เภสัช',
        'price': 299.0,
        'useAI': false,
        'details': [
          'ปรึกษาแพทย์หรือเภสัชกรผ่านแชท/เสียง',
          'เครื่องมือแพทย์ (ใบสั่งยา/สรุปผล)',
        ],
      },
    ];
  }

  @override
  void initState() {
    super.initState();
    _scrollController = FixedExtentScrollController(
      initialItem: _selectedIndex,
    );
    _scrollController.addListener(_onWheelScroll);

    // Safety check: ensure user is logged in
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final user = ServiceLocator.instance.currentUser;
      if (user == null) {
        Navigator.pushReplacementNamed(
          context,
          '/login',
          arguments: '/package-healthcare',
        );
        return;
      }

      // Check if skipProviderCheck flag is set (for patient flow from drawer)
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      final skipProviderCheck = args?['skipProviderCheck'] == true;

      // ✅ เพิ่มการตรวจสอบว่า user เป็น provider หรือไม่
      // ถ้าย้อนกลับมาหลังจาก login (redirected) จะได้ไม่หลุดไปหน้าสุขภาพ
      // แต่ถ้า skipProviderCheck == true จะไม่ redirect provider ไป Dashboard
      if (!skipProviderCheck) {
        try {
          final localUser = await ServiceLocator.instance.userRepository.getUserById(user.id);
          if (localUser != null && localUser.professionId != null) {
            final professionRepo = ServiceLocator.instance.professionRepository;
            final profession = await professionRepo.getProfessionById(localUser.professionId!);

            if (profession != null && profession.category.isConsultationProvider) {
              if (mounted) {
                // เป็นผู้ให้บริการ -> เด้งไป Dashboard ทันที แทนที่จะโชว์หน้า Package หรือกรอกข้อมูลสุขภาพ
                Navigator.pushReplacementNamed(context, '/health-program-requests');
              }
              return;
            }
          }
        } catch (e) {
          debugPrint('PackageHealthCarePage Provider Check Error: $e');
        }
      }

      setState(() => _isLoading = false);

      setState(() => _isPackagesLoading = true);
      await _loadLivePackages(); // Load real packages first
      if (mounted) setState(() => _isPackagesLoading = false);

      _loadGender();
    });
  }

  void _onWheelScroll() {
    if (mounted) {
      setState(() {
        // Updated to match itemExtent 80
        _scrollOffset = _scrollController.offset / 80.0;
      });
    }
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
        final profile = await ServiceLocator.instance.userRepository
            .getConsumerProfile(user.id);
        if (profile != null &&
            profile.healthInfo != null &&
            profile.healthInfo!.isNotEmpty) {
          final gender =
              profile.healthInfo!['gender']?.toString().toLowerCase() ??
              'unknown';
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
              arguments: {'redirect': '/package-healthcare'},
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
    if (_gender == 'female' || _gender == 'หญิง' || _gender == 'f')
      return Colors.pinkAccent;
    if (_gender == 'male' || _gender == 'ชาย' || _gender == 'm')
      return Colors.blueAccent;
    return AppColors.primary; // default green
  }

  String get _genderText {
    if (_gender == 'female' || _gender == 'หญิง' || _gender == 'f')
      return 'สำหรับคุณผู้หญิง';
    if (_gender == 'male' || _gender == 'ชาย' || _gender == 'm')
      return 'สำหรับคุณผู้ชาย';
    return 'สำหรับปรึกษาผู้เชี่ยวชาญ';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_packages.isEmpty) {
      if (_isPackagesLoading) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }
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
            icon: const Icon(
              Icons.chat_bubble_outline,
              color: Colors.orangeAccent,
            ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
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
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final height = constraints.maxHeight;
                    final wheelRadius = width * 0.78;
                    final centerX =
                        -width * 0.42; // Center off-screen to the left
                    final centerY = height * 0.5;
                    // DYNAMIC: one slice per real package (no hardcoded 10).
                    // This keeps the wheel proportional to the actual number
                    // of packages managed in the system and prevents the
                    // labels from repeating.
                    final slices = _packages.length;
                    final spacingAngle = (math.pi * 2) / slices;

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // 1. Large Glass Glow (Outer Atmosphere)
                        Positioned(
                          left: centerX - wheelRadius * 1.2,
                          top: centerY - wheelRadius * 1.2,
                          child: Container(
                            width: wheelRadius * 2.4,
                            height: wheelRadius * 2.4,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  _themeColor.withOpacity(0.1),
                                  _themeColor.withOpacity(0.05),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),

                        // 2. Wheel Hub & Spokes (The visual mechanical wheel)
                        Positioned(
                          left: centerX - wheelRadius,
                          top: centerY - wheelRadius,
                          child: Transform.rotate(
                            // SYNC: Use the same spacingAngle as labels for perfect rotation
                            angle: -_scrollOffset * spacingAngle,
                            child: _WheelVisual(
                              radius: wheelRadius,
                              color: _themeColor,
                              slices: slices,
                            ),
                          ),
                        ),

                        // 2. Package Labels on the rim (Fill all slots)
                        for (var i = 0; i < slices; i++)
                          _buildCurvedLabel(
                            context: context,
                            index: i,
                            name: _packages[i]['short'],
                            centerX: centerX,
                            centerY: centerY,
                            radius: wheelRadius - 40,
                            slices: slices,
                          ),

                        // Selection pointer: fixed marker at angle 0 (right of
                        // the wheel) showing exactly which slice is selected.
                        Positioned(
                          left: centerX + wheelRadius - 6,
                          top: centerY - 6,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _themeColor,
                              boxShadow: [
                                BoxShadow(
                                  color: _themeColor.withOpacity(0.5),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),

                        // 3. INFO PANEL (Price + details) — fixed on the right,
                        // synced to the selected slice via _selectedIndex so it
                        // can never drift from the wheel. Details are rendered
                        // as vertical glass cards (not along the arc) so they
                        // never overlap regardless of package/detail count.
                        Positioned(
                          right: 12,
                          top: 0,
                          bottom: 0,
                          width: width * 0.52,
                          child: _buildInfoPanel(selectedPackage),
                        ),

                        // 4. Invisible ListWheelScrollView for Physics/Gestures (LOOPING)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (notification) {
                              if (notification is ScrollEndNotification) {
                                // Final snap synchronization
                                if (_scrollController.hasClients) {
                                  final snappedIndex =
                                      _scrollController.selectedItem;
                                  setState(() {
                                    _scrollOffset = snappedIndex.toDouble();
                                    _selectedIndex =
                                        snappedIndex % _packages.length;
                                  });
                                }
                              }
                              return false;
                            },
                            child: ListWheelScrollView.useDelegate(
                              controller: _scrollController,
                              itemExtent: 80, // Substantial 80px snap
                              perspective: 0.005,
                              physics: const FixedExtentScrollPhysics(),
                              onSelectedItemChanged: (index) {
                                setState(() {
                                  _selectedIndex = index % _packages.length;
                                });
                              },
                              childDelegate: ListWheelChildBuilderDelegate(
                                builder: (context, index) =>
                                    const SizedBox(height: 80),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
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
                    Navigator.pushNamed(
                      context,
                      '/analyze-body',
                      arguments: request,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text(
                    'Next',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCurvedLabel({
    required BuildContext context,
    required int index,
    required String name,
    required double centerX,
    required double centerY,
    required double radius,
    required int slices,
  }) {
    // DYNAMIC slices = number of packages. Single source of truth
    // (_scrollOffset) drives both the wheel rotation and these labels, so the
    // selected label always sits exactly at the pointer (angle 0).
    final spacingAngle = (math.pi * 2) / slices;
    final currentOffset = _scrollOffset % slices;

    // Relative angle: distance of this slice from the pointer (angle 0).
    double angle = (index - currentOffset) * spacingAngle;

    // IMPORTANT: Wrap angle to keep items looping on the circle [-PI, PI]
    while (angle > math.pi) {
      angle -= 2 * math.pi;
    }
    while (angle < -math.pi) {
      angle += 2 * math.pi;
    }

    if (angle.abs() > math.pi / 2.2) return const SizedBox.shrink();

    final isSelected = index % _packages.length == _selectedIndex;

    // AUTO-FIT FONT SIZE:
    // We have a width budget of about 80% of the slice arc width
    final arcWidthAvailable = radius * (spacingAngle * 0.82);
    final text = name;

    // Base font size is larger for better visibility
    double fontSize = isSelected ? 26 : 18;
    final estimatedWidth = text.length * fontSize * 0.72;
    if (estimatedWidth > arcWidthAvailable) {
      fontSize = arcWidthAvailable / (text.length * 0.72);
    }

    final x = centerX + radius * math.cos(angle);
    final y = centerY + radius * math.sin(angle);

    return Positioned(
      left: x - 100, // Perfectly center 200-width box at x
      top: y - 25, // Perfectly center 50-height box at y
      child: Transform.rotate(
        angle: angle, // Rotate block to match circle tangent
        child: Opacity(
          opacity: (1.0 - (angle.abs() / (math.pi / 2))).clamp(0.0, 1.0),
          child: SizedBox(
            width: 200,
            height: 50,
            child: CustomPaint(
              painter: _CurvedTextPainter(
                text: name,
                radius: radius,
                style: TextStyle(
                  fontFamily: 'SukhumvitSet',
                  color: isSelected ? _themeColor : Colors.grey.shade600,
                  fontSize: fontSize,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                  letterSpacing: 1.0,
                  shadows: isSelected
                      ? [
                          Shadow(
                            color: _themeColor.withOpacity(0.3),
                            blurRadius: 8,
                          ),
                          const Shadow(color: Colors.white, blurRadius: 2),
                        ]
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Right-side info panel: package name, big synced price, and detail glass
  /// cards stacked vertically. Driven by _selectedIndex so it can never drift
  /// from the wheel and the cards never overlap (no arc math).
  Widget _buildInfoPanel(Map<String, dynamic> pkg) {
    final price = (pkg['price'] as double).toStringAsFixed(0);
    final details = (pkg['details'] as List<String>);
    final useAI = pkg['useAI'] == true;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          pkg['short']?.toString() ?? '',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: _themeColor,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  price,
                  style: TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w900,
                    color: _themeColor,
                    height: 1.0,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'บาท',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          ],
        ),
        if (useAI) ...[const SizedBox(height: 8), _buildAiBadge()],
        const SizedBox(height: 16),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final d in details) _buildDetailCard(d),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAiBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _themeColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _themeColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 14, color: _themeColor),
          const SizedBox(width: 4),
          Text(
            'Vega AI',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _themeColor,
            ),
          ),
        ],
      ),
    );
  }

  /// A real frosted-glass card (BackdropFilter blur) for a single detail line.
  Widget _buildDetailCard(String detail) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.45),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.6)),
              boxShadow: [
                BoxShadow(
                  color: _themeColor.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle, size: 16, color: _themeColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF333333),
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Painter to draw text following an arc
class _CurvedTextPainter extends CustomPainter {
  final String text;
  final double radius;
  final TextStyle style;

  _CurvedTextPainter({
    required this.text,
    required this.radius,
    required this.style,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final chars = text.split('');

    // Pre-measure each glyph so arc placement matches exactly and the whole
    // string is centered on the tangent point (angle 0). This fixes the old
    // estimate (length * fontSize * 0.8) that made text drift off-center.
    final widths = <double>[];
    double totalWidth = 0;
    for (final char in chars) {
      textPainter.text = TextSpan(text: char, style: style);
      textPainter.layout();
      widths.add(textPainter.width);
      totalWidth += textPainter.width;
    }

    final totalAngle = totalWidth / radius;
    double cursor = -totalAngle / 2; // left edge of the centered string

    for (var i = 0; i < chars.length; i++) {
      final w = widths[i];
      final angle = cursor + (w / radius) / 2; // center of this glyph

      textPainter.text = TextSpan(text: chars[i], style: style);
      textPainter.layout();

      final x = radius * math.cos(angle);
      final y = radius * math.sin(angle);

      canvas.save();
      canvas.translate(size.width / 2 + (x - radius), size.height / 2 + y);
      canvas.rotate(angle + math.pi / 2); // Rotate char to face center
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2),
      );
      canvas.restore();

      cursor += w / radius;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// The Mechanical Wheel Design (Spokes & Rim)
class _WheelVisual extends StatelessWidget {
  final double radius;
  final Color color;
  final int slices;

  const _WheelVisual({
    required this.radius,
    required this.color,
    required this.slices,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      child: CustomPaint(
        painter: _WheelPainter(color: color, slices: slices),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final Color color;
  final int slices;

  _WheelPainter({required this.color, required this.slices});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final innerRadius = outerRadius - 45;

    // --- 1. GLASS RIM EFFECT ---
    // Outer shadow/thickness
    final rimPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, outerRadius, rimPaint);

    // Inner glow of the rim
    final rimGlowPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          color.withOpacity(0.3),
          Colors.white.withOpacity(0.1),
          color.withOpacity(0.3),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: outerRadius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;
    canvas.drawCircle(center, outerRadius - 5, rimGlowPaint);

    // --- 2. SEMI-TRANSPARENT GLASS BODY ---
    final bodyPaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white.withOpacity(0.05), color.withOpacity(0.1)],
      ).createShader(Rect.fromCircle(center: center, radius: outerRadius))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, outerRadius, bodyPaint);

    // --- 3. MECHANICAL SPOKES (10 FIXED CAKE SLICES) ---
    final spokePaint = Paint()
      ..color = color.withOpacity(0.15)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final sliceAngle = (math.pi * 2) / slices;

    // We put spokes at the edge of each of the 10 slices
    // Spokes are at: base - sliceAngle/2, base + sliceAngle/2
    for (var i = 0; i < slices; i++) {
      final angle = (i * sliceAngle) + (sliceAngle / 2);

      final start = Offset(
        center.dx + (innerRadius - 60) * math.cos(angle),
        center.dy + (innerRadius - 60) * math.sin(angle),
      );
      final end = Offset(
        center.dx + outerRadius * math.cos(angle),
        center.dy + outerRadius * math.sin(angle),
      );

      canvas.drawLine(start, end, spokePaint);
      canvas.drawCircle(end, 2.5, Paint()..color = color.withOpacity(0.25));
    }

    // --- 4. CENTER HUB (Glass Jewel Look) ---
    // Hub Base
    canvas.drawCircle(
      center,
      70,
      Paint()..color = Colors.white.withOpacity(0.3),
    );

    // Hub Inner Shadow (Depth)
    final hubShadowPaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.transparent, color.withOpacity(0.2)],
        stops: [0.7, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: 70));
    canvas.drawCircle(center, 70, hubShadowPaint);

    // Ultimate Center Glow
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [color.withOpacity(0.4), Colors.transparent],
      ).createShader(Rect.fromCircle(center: center, radius: 40));
    canvas.drawCircle(center, 40, glowPaint);

    // Specular highlight (Glass shine)
    final highlightPaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center.translate(-15, -15), 8, highlightPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
