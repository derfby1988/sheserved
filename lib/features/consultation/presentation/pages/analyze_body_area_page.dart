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
    return 'assets/models/female_anatomy.glb';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundWhite,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                ),
              ],
            ),
            child: const Icon(Icons.arrow_back, color: AppColors.primary, size: 20),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart_outlined, color: AppColors.cartIcon),
            onPressed: () {},
          ),
          const SizedBox(width: 8),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Column(
        children: [
          const SizedBox(height: 100),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'ระบุ บริเวณที่พบอาการ',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.accent,
                      ),
                    ),
                    Container(
                      height: 3,
                      width: 60,
                      decoration: BoxDecoration(
                        gradient: AppColors.goldGradient,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Stylized Silhouette Background
                Positioned.fill(
                  child: CustomPaint(
                    painter: _BodySilhouettePainter(
                      color: AppColors.primary.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                
                // 3D Model Viewer
                Center(
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: ModelViewer(
                      src: _bodyModelUrl,
                      alt: "A 3D model of human anatomy",
                      ar: false,
                      autoRotate: false,
                      cameraControls: true,
                      disableZoom: true,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                ),

                // Height Selection Overlay
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 30),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: _heightLevels.map((height) {
                        final isSelected = _selectedHeight == height;
                        
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedHeight = height;
                            });
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 60,
                                  child: Text(
                                    '$height ซม.',
                                    style: TextStyle(
                                      color: isSelected ? AppColors.primary : Colors.grey.shade400,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                      fontSize: isSelected ? 16 : 14,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    height: isSelected ? 2 : 0.5,
                                    decoration: BoxDecoration(
                                      gradient: isSelected 
                                          ? AppColors.primaryGradient 
                                          : LinearGradient(colors: [Colors.grey.shade300, Colors.grey.shade100]),
                                      borderRadius: BorderRadius.circular(1),
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    width: 12,
                                    height: 12,
                                    decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
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
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: () {
                  if (_selectedHeight == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('กรุณาระบุบริเวณที่พบอาการ'),
                        backgroundColor: AppColors.primary,
                      ),
                    );
                    return;
                  }
                  
                  final updatedRequest = ConsultationRequestModel(
                    id: widget.request.id,
                    userId: widget.request.userId,
                    packageName: widget.request.packageName,
                    price: widget.request.price,
                    bodyArea: {
                      'gender': _gender,
                      'height': _selectedHeight,
                    },
                    symptomsChart: widget.request.symptomsChart,
                    createdAt: widget.request.createdAt,
                    updatedAt: widget.request.updatedAt,
                  );

                  Navigator.pushNamed(context, '/chart-board', arguments: updatedRequest);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'ถัดไป',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

/// A CustomPainter that draws a stylized human silhouette as a fallback/decoration
class _BodySilhouettePainter extends CustomPainter {
  final Color color;
  _BodySilhouettePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    final center = size.width / 2;
    final h = size.height;
    
    // Head
    path.addOval(Rect.fromCenter(center: Offset(center, h * 0.1), width: size.width * 0.15, height: size.width * 0.18));
    
    // Neck
    path.moveTo(center - size.width * 0.04, h * 0.18);
    path.lineTo(center + size.width * 0.04, h * 0.18);
    path.lineTo(center + size.width * 0.08, h * 0.22);
    path.lineTo(center - size.width * 0.08, h * 0.22);
    path.close();

    // Torso
    path.moveTo(center - size.width * 0.2, h * 0.22);
    path.quadraticBezierTo(center, h * 0.2, center + size.width * 0.2, h * 0.22); // Shoulders
    path.lineTo(center + size.width * 0.15, h * 0.5); // Waist
    path.lineTo(center - size.width * 0.15, h * 0.5);
    path.close();

    // Legs
    path.moveTo(center - size.width * 0.15, h * 0.5);
    path.lineTo(center - size.width * 0.02, h * 0.5);
    path.lineTo(center - size.width * 0.05, h * 0.9);
    path.lineTo(center - size.width * 0.18, h * 0.9);
    path.close();
    
    path.moveTo(center + size.width * 0.15, h * 0.5);
    path.lineTo(center + size.width * 0.02, h * 0.5);
    path.lineTo(center + size.width * 0.05, h * 0.9);
    path.lineTo(center + size.width * 0.18, h * 0.9);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

