import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/service_locator.dart';
import '../../../auth/data/repositories/user_repository.dart';
import '../../../auth/data/models/user_model.dart';
import '../../data/models/health_info.dart';
import '../../data/repositories/health_repository.dart';
import '../widgets/gender_switch.dart';
import '../widgets/age_picker.dart';
import '../widgets/ruler_picker.dart';

class HealthDataEntryPage extends StatefulWidget {
  const HealthDataEntryPage({Key? key}) : super(key: key);

  @override
  State<HealthDataEntryPage> createState() => _HealthDataEntryPageState();
}

class _HealthDataEntryPageState extends State<HealthDataEntryPage> {
  // Form State
  String _gender = 'female';
  int _age = 25;
  double _height = 165.0;
  double _weight = 60.0;
  
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }

  Future<void> _loadExistingData() async {
    try {
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

      final healthRepo = ServiceLocator.instance.healthRepository;
      final healthInfo = await healthRepo.getHealthInfo(user.id);

      if (mounted) {
        setState(() {
          if (healthInfo != null) {
            _gender = healthInfo.gender;
            _age = healthInfo.age;
            _height = healthInfo.height;
            _weight = healthInfo.weight;
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

  void _onGenderChanged(String gender) {
    setState(() {
      _gender = gender;
    });
  }

  void _onAgeChanged(int age) {
    setState(() {
      _age = age;
    });
  }

  void _onHeightChanged(double height) {
    setState(() {
      _height = height;
    });
  }

  void _onWeightChanged(double weight) {
    setState(() {
      _weight = weight;
    });
  }

  double get _calculatedBMI {
    final heightM = _height / 100;
    return _weight / (heightM * heightM);
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
    setState(() {
      _isSaving = true;
    });

    try {
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

      final healthInfo = HealthInfo(
        gender: _gender,
        age: _age,
        height: _height,
        weight: _weight,
        bmi: _calculatedBMI,
      );

      final userRepository = ServiceLocator.instance.userRepository;
      final healthRepository = ServiceLocator.instance.healthRepository;
      
      // Check if profile exists
      ConsumerProfile? profile = await userRepository.getConsumerProfile(user.id);
      
      if (profile != null) {
        // Update existing
        await healthRepository.updateHealthInfo(user.id, healthInfo);
      } else {
        // Create new profile first
        await userRepository.createConsumerProfile(
          userId: user.id,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF5A7E28)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'ข้อมูลสุขภาพ',
          style: TextStyle(
            color: Color(0xFF333333),
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFFD4AF37)),
            onPressed: () {},
          ),
          IconButton(
             icon: const Icon(Icons.shopping_cart_outlined, color: Colors.grey),
             onPressed: () {},
          )
        ],
      ),
      body: _isLoading 
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF679E83)),
              ),
            )
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 10),
                          
                          // Title
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
                          
                          // Gender
                          GenderSwitch(
                            selectedGender: _gender,
                            onChanged: _onGenderChanged,
                          ),
                          
                          const SizedBox(height: 36),
                          
                          // Age
                          AgePicker(
                            initialAge: _age,
                            onChanged: _onAgeChanged,
                          ),

                          const SizedBox(height: 36),

                          // Height
                          RulerPicker(
                            label: 'ส่วนสูง',
                            unit: 'เซนติเมตร',
                            minValue: 100,
                            maxValue: 250,
                            initialValue: _height,
                            onChanged: _onHeightChanged,
                          ),

                          const SizedBox(height: 36),

                          // Weight
                          RulerPicker(
                            label: 'น้ำหนัก',
                            unit: 'กิโลกรัม',
                            minValue: 30,
                            maxValue: 200,
                            initialValue: _weight,
                            onChanged: _onWeightChanged,
                          ),
                          
                          const SizedBox(height: 32),
                          
                          // BMI Preview Card
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
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _submitData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF679E83),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          elevation: 4,
                          shadowColor: const Color(0xFF679E83).withOpacity(0.4),
                        ),
                        child: _isSaving 
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Text(
                                  'บันทึกข้อมูล',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
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
