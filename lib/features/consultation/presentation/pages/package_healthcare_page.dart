import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/models/consultation_request_model.dart';
import '../../../../services/service_locator.dart';


class PackageHealthCarePage extends StatefulWidget {
  const PackageHealthCarePage({super.key});

  @override
  State<PackageHealthCarePage> createState() => _PackageHealthCarePageState();
}

class _PackageHealthCarePageState extends State<PackageHealthCarePage> {
  // Mock packages for demonstration
  final List<Map<String, dynamic>> _packages = [
    {'name': 'แพ็คเกจ สำหรับปรึกษาผู้เชี่ยวชาญระดับอาจารย์แพทย์', 'short': 'อาจารย์หมอ', 'price': 2990.0},
    {'name': 'แพ็คเกจ สำหรับปรึกษาแพทย์เฉพาะทาง', 'short': 'หมอเฉพาะทาง', 'price': 799.0},
    {'name': 'แพ็คเกจ สำหรับปรึกษาแพทย์ทั่วไป/เภสัช', 'short': 'หมอ/เภสัช', 'price': 299.0},
  ];

  int _selectedIndex = 2; // Default to 299.0
  bool _isLoading = true;
  String _gender = 'unknown';

  @override
  void initState() {
    super.initState();
    _loadGender();
  }

  Future<void> _loadGender() async {
    try {
      final user = ServiceLocator.instance.currentUser;
      if (user != null) {
        final profile = await ServiceLocator.instance.userRepository.getConsumerProfile(user.id);
        if (profile != null && profile.healthInfo != null) {
          final gender = profile.healthInfo!['gender']?.toString().toLowerCase() ?? 'unknown';
          if (mounted) {
            setState(() {
              _gender = gender;
              _isLoading = false;
            });
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
                    Positioned(
                      left: -MediaQuery.of(context).size.width * 0.4,
                      child: Container(
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.width,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey.shade300, width: 2),
                        ),
                      ),
                    ),
                    Positioned(
                      left: -MediaQuery.of(context).size.width * 0.25,
                      child: Container(
                        width: MediaQuery.of(context).size.width * 0.7,
                        height: MediaQuery.of(context).size.width * 0.7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey.shade200,
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
                              Text(
                                '${selectedPackage['price']}',
                                style: TextStyle(
                                  fontSize: 48,
                                  fontWeight: FontWeight.bold,
                                  color: _themeColor, 
                                ),
                              ),
                            ],
                          ),
                          const Text(
                            'บาท',
                            style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.bold),
                          ),
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
                      packageId: null,
                      packageName: selectedPackage['name'],
                      price: selectedPackage['price'],
                      bodyArea: {'gender': _gender}, // pass down gender
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
