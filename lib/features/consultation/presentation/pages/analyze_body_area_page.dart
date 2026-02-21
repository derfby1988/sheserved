import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/models/consultation_request_model.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';


class AnalyzeBodyAreaPage extends StatefulWidget {
  final ConsultationRequestModel request;

  const AnalyzeBodyAreaPage({super.key, required this.request});

  @override
  State<AnalyzeBodyAreaPage> createState() => _AnalyzeBodyAreaPageState();
}

class _AnalyzeBodyAreaPageState extends State<AnalyzeBodyAreaPage> {
  final List<int> _heightLevels = [110, 100, 80, 70, 60, 50];
  int? _selectedHeight;

  String get _gender {
    return widget.request.bodyArea['gender']?.toString().toLowerCase() ?? 'unknown';
  }

  String get _bodyModelUrl {
    if (_gender == 'male' || _gender == 'ชาย' || _gender == 'm') {
      return 'assets/models/male_anatomy.glb';
    }
    // Female Anatomy Placeholder
    return 'assets/models/female_anatomy.glb';
  }

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
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'ระบุ บริเวณที่พบอาการ',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.orangeAccent,
                ),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Mock body image
                // In production, we add a real anatomical wireframe image or 3D model (e.g., using `model_viewer_plus`) here.
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.55,
                  child: ModelViewer(
                    src: _bodyModelUrl,
                    alt: "A 3D model of human anatomy",
                    ar: false,
                    autoRotate: true,
                    cameraControls: true,
                    disableZoom: true,
                  ),
                ),
                // Height lines
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: _heightLevels.map((height) {
                        final isSelected = _selectedHeight == height;
                        final color = isSelected ? Colors.redAccent : Colors.grey.shade400;
                        
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedHeight = height;
                            });
                          },
                          child: Row(
                            children: [
                              Text(
                                '$height ซม.',
                                style: TextStyle(
                                  color: color,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Container(
                                  height: isSelected ? 3 : 1,
                                  color: color,
                                ),
                              ),
                            ],
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
                if (_selectedHeight == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('กรุณาระบุบริเวณที่พบอาการ')),
                  );
                  return;
                }
                
                // Update request object
                final updatedRequest = ConsultationRequestModel(
                  id: widget.request.id,
                  userId: widget.request.userId,
                  packageName: widget.request.packageName,
                  price: widget.request.price,
                  bodyArea: {
                    'gender': widget.request.bodyArea['gender'],
                    'height': _selectedHeight,
                  }, // Store selection
                  symptomsChart: widget.request.symptomsChart,
                  createdAt: widget.request.createdAt,
                  updatedAt: widget.request.updatedAt,
                );

                Navigator.pushNamed(context, '/chart-board', arguments: updatedRequest);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text('Next', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
