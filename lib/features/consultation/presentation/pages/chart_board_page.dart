import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/models/consultation_request_model.dart';

class ChartBoardPage extends StatefulWidget {
  final ConsultationRequestModel request;

  const ChartBoardPage({super.key, required this.request});

  @override
  State<ChartBoardPage> createState() => _ChartBoardPageState();
}

class _ChartBoardPageState extends State<ChartBoardPage> {
  // Mock nodes for the hexagon chart
  final List<String> painLevels = ['มากที่สุด', 'มาก', 'ปานกลาง', 'เล็กน้อย', 'ไม่มี'];
  String? _selectedPain;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.primary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Wrap(
                  spacing: 16.0,
                  runSpacing: 16.0,
                  alignment: WrapAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.greenAccent, width: 4),
                      ),
                      child: const Text(
                        'คุณรู้สึกเจ็บ\nประมาณไหน',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 16, width: double.infinity),
                    ...painLevels.map((level) {
                      final isSelected = _selectedPain == level;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedPain = level;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.greenAccent.withOpacity(0.2) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? Colors.green : Colors.grey.shade300,
                              width: 2,
                            ),
                          ),
                          child: Text(
                            level,
                            style: TextStyle(
                              color: isSelected ? Colors.green : Colors.black,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ),
          ),
          
          Expanded(
            flex: 4,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFF4A8B2C), // Based on mockup green block
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 100, left: 32, right: 32),
                child: Align(
                  alignment: Alignment.center,
                  child: GestureDetector(
                    onTap: _submitConsultationRequest,
                    child: Container(
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(40),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          )
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.grey),
                            ),
                            child: const Icon(Icons.check, color: Colors.green),
                          ),
                          const SizedBox(width: 24),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${widget.request.price.toInt()} บาท',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Text(
                                'ชำระค่าใช้จ่าย / ส่งคำปรึกษา',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _submitConsultationRequest() {
    if (_selectedPain == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาระบุระดับความรู้สึกเจ็บปวด')),
      );
      return;
    }

    // Usually we would submit this to the server/Supabase
    // Finalizing symptoms
    final finalSymptoms = {
      'pain_scale': _selectedPain,
    };

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    // Call Repository or Logic (Mocked delay here)
    Future.delayed(const Duration(seconds: 1), () {
      Navigator.pop(context); // close dialog
      
      // Navigate to chat or payment.
      // E.g. push back to home and show success, or push directly to a specific chat room.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('สร้างคำปรึกษาสำเร็จ!')),
      );
      
      // Let's go to Home for now
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    });
  }
}
