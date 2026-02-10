import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../services/service_locator.dart';
import '../../../auth/data/repositories/user_repository.dart';
import '../../../auth/data/models/user_model.dart';
import '../../data/models/health_info.dart';
import '../../data/repositories/health_repository.dart';
import '../widgets/gender_switch.dart';
import '../widgets/age_picker.dart';
import '../widgets/ruler_picker.dart';
import '../../../../shared/widgets/tlz_app_top_bar.dart';
import '../../../../core/constants/app_colors.dart';
import 'package:thai_buddhist_date/thai_buddhist_date.dart';
import 'package:thai_buddhist_date_pickers/thai_buddhist_date_pickers.dart';

class HealthDataEntryPage extends StatefulWidget {
  const HealthDataEntryPage({Key? key}) : super(key: key);

  @override
  State<HealthDataEntryPage> createState() => _HealthDataEntryPageState();
}

class _HealthDataEntryPageState extends State<HealthDataEntryPage> {
  // State
  String _gender = 'female';
  int? _age; // Nullable age, defaults to null (displayed as "-")
  double _height = 165.0; // cm
  double _weight = 60.0;  // kg
  DateTime? _originalBirthday; // Keep track of the DB birthday
  
  // UI State
  bool _isMetric = true; // true = Metric (cm/kg), false = Imperial (in/lb)
  bool _isLoading = true;
  bool _isSaving = false;
  
  // Controllers & Keys
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _agePickerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingData() async {
    // Check Auth first
    final user = ServiceLocator.instance.currentUser;
    if (user == null) {
      if (mounted) {
        Navigator.pushReplacementNamed(
          context, 
          '/login',
          arguments: '/health-data-entry',
        );
      }
      return;
    }

    try {
      // Simulate network delay for shimmer effect demo
      await Future.delayed(const Duration(milliseconds: 1500));


      final healthRepo = ServiceLocator.instance.healthRepository;
      // Fetch profile which includes birthday and health_info
      final profile = await healthRepo.getConsumerProfileWithHealth(user.id);

      if (mounted) {
        setState(() {
            if (profile != null) {
              _originalBirthday = profile.birthday;
              
              // Priority: Calculated from Birthday > Existing Health Info > Default
              
              // 1. Try to calculate age from birthday
              if (profile.birthday != null) {
                _age = _calculateAge(profile.birthday!);
              } 
              // 2. Fallback to existing health info if available and birthday is missing
              else if (profile.healthInfo != null && profile.healthInfo!['age'] != null) {
                _age = profile.healthInfo!['age'];
              }

              // Load other health info if available
              if (profile.healthInfo != null) {
                _gender = profile.healthInfo!['gender'] ?? 'female';
                _height = (profile.healthInfo!['height'] as num?)?.toDouble() ?? 160.0;
                _weight = (profile.healthInfo!['weight'] as num?)?.toDouble() ?? 50.0;
              }
            }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  int _calculateAge(DateTime birthDate) {
    final today = DateTime.now();
    int age = today.year - birthDate.year;
    if (today.month < birthDate.month || 
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  void _onGenderChanged(String gender) {
    setState(() {
      _gender = gender;
    });
  }

  void _onAgeChanged(int? age) {
    setState(() {
      _age = age;
    });
  }

  void _onHeightChanged(double height) {
    setState(() {
      if (_isMetric) {
        _height = height;
      } else {
        // Convert inches to cm for storage
        _height = height * 2.54;
      }
    });
  }

  void _onWeightChanged(double weight) {
    setState(() {
      if (_isMetric) {
        _weight = weight;
      } else {
        // Convert lbs to kg for storage
        _weight = weight * 0.453592;
      }
    });
  }
  
  void _toggleUnit() {
    setState(() {
      _isMetric = !_isMetric;
    });
  }

  double get _calculatedBMI {
    // Always use stored metric values for calculation
    final heightM = _height / 100;
    return _weight / (heightM * heightM);
  }
  
  // Helper getters for display values
  double get _displayHeight {
    if (_isMetric) return _height;
    return _height / 2.54; // cm to inches
  }
  
  double get _displayWeight {
    if (_isMetric) return _weight;
    return _weight / 0.453592; // kg to lbs
  }

  String get _bmiCategory {
    final bmi = _calculatedBMI;
    if (bmi < 18.5) return 'น้ำหนักต่ำกว่าเกณฑ์';
    if (bmi < 23) return 'น้ำหนักปกติ';
    if (bmi < 25) return 'น้ำหนักเกิน';
    if (bmi < 30) return 'อ้วนระดับ 1';
    return 'อ้วนระดับ 2';
  }

  Color get _bmiColor {
    final bmi = _calculatedBMI;
    if (bmi < 18.5) return Colors.orange;
    if (bmi < 23) return Colors.green;
    if (bmi < 25) return Colors.orange;
    return Colors.red;
  }

  Future<void> _submitData() async {
    final user = ServiceLocator.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อนดำเนินการ')),
        );
        Navigator.pushReplacementNamed(
          context,
          '/login',
          arguments: '/health-data-entry',
        );
      }
      return;
    }

    // VALIDATION: Ensure age is selected
    if (_age == null) {
      if (mounted) {
        // Auto scroll to AgePicker
        Scrollable.ensureVisible(
          _agePickerKey.currentContext!,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.white),
                SizedBox(width: 8),
                Expanded(child: Text('กรุณาระบุอายุ เพื่อคำนวณข้อมูลสุขภาพ')),
              ],
            ),
            backgroundColor: Colors.yellow[800],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      return;
    }

    try {
      // BIRTHDAY SYNC LOGIC - Do this BEFORE setting _isSaving = true
      // to avoid UI conflict with the loading overlay on web
      final userRepository = ServiceLocator.instance.userRepository;
      final healthRepository = ServiceLocator.instance.healthRepository;
      
      DateTime? birthdayToSave = _originalBirthday;
      int calculatedAgeFromOriginal = _originalBirthday != null ? _calculateAge(_originalBirthday!) : -1;

      // Only sync if age is selected and different from current record
      if (_age != null && _age != calculatedAgeFromOriginal) {
        final DateTime? confirmedDate = await _showBirthdayConfirmationDialog();
        if (confirmedDate == null) {
          // User cancelled the dialog, just abort
          return;
        }
        birthdayToSave = confirmedDate;
      }

      // NOW set saving state for actual DB operation
      if (mounted) {
        setState(() {
          _isSaving = true;
        });
      }

      final healthInfo = HealthInfo(
        gender: _gender,
        age: _age,
        height: _height,
        weight: _weight,
        bmi: _calculatedBMI,
      );

      // Check if profile exists
      ConsumerProfile? profile = await userRepository.getConsumerProfile(user.id);
      
      if (profile != null) {
        // Update existing health_info + birthday column
        await userRepository.updateConsumerProfile(user.id, {
          'health_info': healthInfo.toJson(),
          'birthday': birthdayToSave?.toIso8601String(),
        });
        
        // Ensure health score is recalculated in metadata (handled by repo usually)
        await healthRepository.updateHealthInfo(user.id, healthInfo);
      } else {
        // Create new profile
        await userRepository.createConsumerProfile(
          userId: user.id,
          birthday: birthdayToSave,
          healthInfo: healthInfo.toJson(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(child: Text('บันทึกข้อมูลเรียบร้อยแล้ว')),
              ],
            ),
            backgroundColor: const Color(0xFF5B9A8B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Navigator.pushReplacementNamed(context, '/health'); 
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<DateTime?> _showBirthdayConfirmationDialog() async {
    // Generate a default date based on the age selected (e.g., Today's date Y years ago)
    final now = DateTime.now();
    final effectiveAge = _age ?? 25;
    DateTime initialDate = _originalBirthday ?? DateTime(now.year - effectiveAge, now.month, now.day);
    
    // Ensure initialDate is reasonable if selected age changed
    if (_calculateAge(initialDate) != effectiveAge) {
      initialDate = DateTime(now.year - effectiveAge, now.month, now.day);
    }

    DateTime selectedDate = initialDate;

    return await showDialog<DateTime>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.cake, color: Color(0xFF5B9A8B)),
                  SizedBox(width: 10),
                  Text('ยืนยันวันเกิดของคุณ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('อายุที่คุณเลือก ไม่ตรงกับวันเกิดที่เคยบันทึกไว้ หรืออาจยังไม่เคยกรอก'),
                  const SizedBox(height: 16),
                  const Text('กรุณาเลือกวันเกิดที่ถูกต้อง เพื่อให้เราคำนวณคะแนนสุขภาพได้แม่นยำที่สุด:', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      // 1. Show Year Picker first for easier navigation
                      final int? selectedYear = await _showThaiYearPicker(context, selectedDate.year);
                      if (selectedYear == null) return;
                      
                      final DateTime dateWithNewYear = DateTime(
                        selectedYear,
                        selectedDate.month,
                        selectedDate.day,
                      );

                      // 2. Show Month/Day Picker (Thai version)
                      final DateTime? picked = await showThaiDatePicker(
                        context,
                        initialDate: dateWithNewYear,
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                        era: Era.be,
                        locale: 'th_TH',
                      );
                      
                      if (picked != null) {
                        setDialogState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFF5B9A8B)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${selectedDate.day}/${selectedDate.month}/${selectedDate.year + 543}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Icon(Icons.calendar_today, size: 20, color: Color(0xFF5B9A8B)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('อายุที่คำนวณได้: ${_calculateAge(selectedDate)} ปี', 
                      style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF5B9A8B))),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(selectedDate),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5B9A8B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('ยืนยันและบันทึก', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          }
        );
      },
    );
  }

  Future<int?> _showThaiYearPicker(BuildContext context, int initialYear) async {
    final int currentYearBE = DateTime.now().year + 543;
    final int startYearBE = initialYear + 543;
    
    return showDialog<int>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('เลือกปี พ.ศ.', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2,
              ),
              itemCount: currentYearBE - (1900 + 543) + 1,
              itemBuilder: (context, index) {
                final yearBE = currentYearBE - index;
                final bool isSelected = yearBE == startYearBE;
                return InkWell(
                  onTap: () => Navigator.pop(context, yearBE - 543),
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF5B9A8B) : null,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF5B9A8B).withOpacity(0.3)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$yearBE',
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // 1. Top Navigation Bar (Fixed)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: TlzAppTopBar.onLight(
                    leading: BackButton(
                      color: const Color(0xFF5A7E28),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    searchHintText: 'ค้นหาเมนูอาหารเพื่อสุขภาพ...',
                    onQRTap: () {},
                    onNotificationTap: () {},
                    onCartTap: () {},
                  ),
                ),
                
                // 2. Page Header & Unit Toggle
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'ข้อมูลสุขภาพ',
                        style: TextStyle(
                          color: Color(0xFF333333),
                          fontWeight: FontWeight.w600,
                          fontSize: 20,
                        ),
                      ),
                      TextButton(
                        onPressed: _toggleUnit,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF5A7E28),
                          backgroundColor: const Color(0xFF5A7E28).withOpacity(0.1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        child: Text(
                          _isMetric ? 'Metric' : 'Imperial',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                Expanded(
                  child: _isLoading
                      ? _buildShimmerLoading()
                      : SingleChildScrollView(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFF679E83).withOpacity(0.1),
                                      const Color(0xFF679E83).withOpacity(0.05),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: const Text(
                                  'ลักษณะทางกายภาพ',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF333333),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 32),
                              GenderSwitch(
                                selectedGender: _gender,
                                onChanged: _onGenderChanged,
                              ),
                              const SizedBox(height: 36),
                              Container(
                                key: _agePickerKey,
                                child: AgePicker(
                                  initialAge: _age,
                                  onChanged: _onAgeChanged,
                                ),
                              ),
                              const SizedBox(height: 36),
                              RulerPicker(
                                key: ValueKey('height_$_isMetric'),
                                label: 'ส่วนสูง',
                                unit: _isMetric ? 'เซนติเมตร' : 'นิ้ว',
                                minValue: _isMetric ? 100 : 39,
                                maxValue: _isMetric ? 250 : 98,
                                initialValue: double.parse(_displayHeight.toStringAsFixed(1)),
                                step: _isMetric ? 1 : 0.5,
                                onChanged: _onHeightChanged,
                              ),
                              const SizedBox(height: 36),
                              RulerPicker(
                                key: ValueKey('weight_$_isMetric'),
                                label: 'น้ำหนัก',
                                unit: _isMetric ? 'กิโลกรัม' : 'ปอนด์',
                                minValue: _isMetric ? 30 : 66,
                                maxValue: _isMetric ? 200 : 440,
                                initialValue: double.parse(_displayWeight.toStringAsFixed(1)),
                                step: _isMetric ? 1 : 1,
                                onChanged: _onWeightChanged,
                              ),
                              const SizedBox(height: 32),
                              _buildBMIPreviewCard(),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                ),
                
                // Next Button
                Container(
                  padding: const EdgeInsets.all(24.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.75,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF87B17F), Color(0xFF007FAD)],
                        ),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF007FAD).withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _submitData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Text(
                              'บันทึกข้อมูล',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.check_circle_outline, size: 22),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Global Loading Overlay
            if (_isSaving)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          color: Color(0xFF679E83),
                          strokeWidth: 3,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'กำลังบันทึกข้อมูล...',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF679E83),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 10),
            // Title Placeholder
            Container(
              width: 200,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            const SizedBox(height: 32),
            // Gender Placeholder
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(width: 80, height: 80, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                const SizedBox(width: 24),
                Container(width: 80, height: 80, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
              ],
            ),
            const SizedBox(height: 36),
            // Age Placeholder
            Container(width: 100, height: 40, color: Colors.white),
            const SizedBox(height: 16),
            Container(width: double.infinity, height: 120, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16))),
            const SizedBox(height: 36),
            // Ruler Placeholder 1
            Container(width: 100, height: 24, color: Colors.white),
            const SizedBox(height: 8),
            Container(width: double.infinity, height: 130, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16))),
            const SizedBox(height: 36),
            // Ruler Placeholder 2
            Container(width: 100, height: 24, color: Colors.white),
            const SizedBox(height: 8),
            Container(width: double.infinity, height: 130, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16))),
          ],
        ),
      ),
    );
  }

  Widget _buildBMIPreviewCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _bmiColor.withOpacity(0.1),
            _bmiColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _bmiColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ค่า BMI ของคุณ',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _bmiCategory,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _bmiColor,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: _bmiColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _calculatedBMI.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: _bmiColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // BMI Scale Indicator
          _buildBMIScaleIndicator(),
        ],
      ),
    );
  }

  Widget _buildBMIScaleIndicator() {
    final bmi = _calculatedBMI.clamp(15.0, 40.0);
    final position = ((bmi - 15) / 25).clamp(0.0, 1.0);
    
    return Column(
      children: [
        Stack(
          children: [
            // Scale Background
            Container(
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF4FC3F7), // Underweight
                    Color(0xFF81C784), // Normal
                    Color(0xFFFFD54F), // Overweight
                    Color(0xFFFF8A65), // Obese 1
                    Color(0xFFE57373), // Obese 2
                  ],
                  stops: [0.0, 0.32, 0.4, 0.6, 1.0],
                ),
              ),
            ),
            // Position Indicator
            Positioned(
              left: position * (MediaQuery.of(context).size.width - 80) - 8,
              top: -4,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: _bmiColor, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: _bmiColor.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Scale Labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('15', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            Text('18.5', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            Text('23', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            Text('25', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            Text('30', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            Text('40', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
          ],
        ),
      ],
    );
  }
}

