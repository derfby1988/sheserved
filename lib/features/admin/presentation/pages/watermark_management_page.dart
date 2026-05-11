import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sheserved/config/app_config.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/core/constants/app_text_styles.dart';
import 'package:sheserved/features/admin/data/repositories/watermark_repository.dart';

class WatermarkManagementPage extends StatefulWidget {
  const WatermarkManagementPage({Key? key}) : super(key: key);

  @override
  State<WatermarkManagementPage> createState() => _WatermarkManagementPageState();
}

class _WatermarkManagementPageState extends State<WatermarkManagementPage> {
  final WatermarkRepository _repository = WatermarkRepository();
  final ImagePicker _picker = ImagePicker();
  late ScaffoldMessengerState _scaffoldMessenger;
  
  bool _isLoading = true;
  bool _isSaving = false;
  
  // State variables
  bool _isEnabled = false;
  String _type = 'text';
  final TextEditingController _textController = TextEditingController();
  String? _imageUrl;
  String _position = 'bottom-right';
  String _animationType = 'none';
  double _opacity = 0.5;
  bool _showIncidentId = false;
  bool _showUploaderId = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ✅ บันทึกไว้ที่นี่ตาม Flutter docs เพื่อใช้ใน async method อย่างปลอดภัย
    _scaffoldMessenger = ScaffoldMessenger.of(context);
  }

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);
    final config = await _repository.getConfig();
    if (config != null) {
      setState(() {
        _isEnabled = config.isEnabled;
        _type = config.type;
        _textController.text = config.textContent ?? '';
        _imageUrl = config.imageUrl;
        _position = config.position;
        _animationType = config.animationType;
        _opacity = config.opacity;
        _showIncidentId = config.showIncidentId;
        _showUploaderId = config.showUploaderId;
      });
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);

    final config = WatermarkConfig(
      isEnabled: _isEnabled,
      type: _type,
      textContent: _textController.text,
      position: _position,
      animationType: _animationType,
      opacity: _opacity,
      showIncidentId: _showIncidentId,
      showUploaderId: _showUploaderId,
    );

    final result = await _repository.updateConfig(config);

    if (!mounted) return;
    setState(() => _isSaving = false);

    final success = result == null;
    _scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                success
                    ? 'บันทึกการตั้งค่าลายน้ำสำเร็จ ✅'
                    : 'บันทึกล้มเหลว: $result',
              ),
            ),
          ],
        ),
        backgroundColor: success ? AppColors.success : AppColors.error,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _pickAndUploadImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      // Validate PNG
      if (!image.path.toLowerCase().endsWith('.png')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('กรุณาอัปโหลดไฟล์ PNG เท่านั้น เพื่อความโปร่งใสของลายน้ำ'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      
      setState(() => _isSaving = true);
      final url = await _repository.uploadImage(File(image.path));
      setState(() => _isSaving = false);
      
      if (url != null) {
        setState(() => _imageUrl = url);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('อัปโหลดรูปภาพสำเร็จ'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('เกิดข้อผิดพลาดในการอัปโหลด'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('จัดการลายน้ำระบบ (Watermark)'),
        backgroundColor: AppColors.primary,
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _saveConfig,
              child: const Text('บันทึก', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Master Switch
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: SwitchListTile(
                title: const Text('เปิดใช้งานระบบลายน้ำ', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('เมื่อเปิด ทุกวิดีโอและภาพถ่ายที่อัปโหลดจะถูกประทับลายน้ำอัตโนมัติ'),
                value: _isEnabled,
                activeColor: AppColors.primary,
                onChanged: (val) => setState(() => _isEnabled = val),
              ),
            ),
            const SizedBox(height: 24),

            if (_isEnabled) ...[
              // Type Selection
              Text('ประเภทลายน้ำ (Watermark Type)', style: AppTextStyles.heading3),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('ข้อความ (Text)'),
                      value: 'text',
                      groupValue: _type,
                      onChanged: (val) => setState(() => _type = val!),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('รูปภาพ (Image)'),
                      value: 'image',
                      groupValue: _type,
                      onChanged: (val) => setState(() => _type = val!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Content Input
              if (_type == 'text') ...[
                TextField(
                  controller: _textController,
                  decoration: const InputDecoration(
                    labelText: 'ข้อความลายน้ำ',
                    border: OutlineInputBorder(),
                    hintText: 'เช่น Sheserved Official',
                  ),
                ),
              ] else ...[
                Center(
                  child: Column(
                    children: [
                      if (_imageUrl != null)
                        Container(
                          width: 150,
                          height: 150,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey.shade100, // checkered background normally
                          ),
                          child: Stack(
                            children: [
                              // Checkerboard pattern simulation for PNG transparency
                              Positioned.fill(
                                child: Wrap(
                                  children: List.generate(100, (index) => Container(
                                    width: 15,
                                    height: 15,
                                    color: (index % 2 == 0) ? Colors.white : Colors.grey.shade300,
                                  )),
                                ),
                              ),
                              Center(
                                child: Image.network(
                                  '${AppConfig.localApiUrl}$_imageUrl',
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, size: 50, color: Colors.grey),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          width: 150,
                          height: 150,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey.shade50,
                          ),
                          child: const Center(child: Text('ยังไม่มีรูปภาพ', style: TextStyle(color: Colors.grey))),
                        ),
                      ElevatedButton.icon(
                        onPressed: _pickAndUploadImage,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('อัปโหลดไฟล์ PNG'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('แนะนำ: ขนาดไฟล์ไม่เกิน 5MB และมีพื้นหลังโปร่งใส (Transparent)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              // Appearance Options
              Text('การแสดงผล (Appearance)', style: AppTextStyles.heading3),
              const SizedBox(height: 16),
              
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'ตำแหน่ง (Position)', border: OutlineInputBorder()),
                      value: _position,
                      items: const [
                        DropdownMenuItem(value: 'top-left', child: Text('มุมซ้ายบน')),
                        DropdownMenuItem(value: 'top-right', child: Text('มุมขวาบน')),
                        DropdownMenuItem(value: 'bottom-left', child: Text('มุมซ้ายล่าง')),
                        DropdownMenuItem(value: 'bottom-right', child: Text('มุมขวาล่าง')),
                        DropdownMenuItem(value: 'center', child: Text('ตรงกลาง')),
                      ],
                      onChanged: (val) => setState(() => _position = val!),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'การเคลื่อนไหว (Animation)', border: OutlineInputBorder()),
                      value: _animationType,
                      items: const [
                        DropdownMenuItem(value: 'none', child: Text('ไม่มี (อยู่นิ่ง)')),
                        DropdownMenuItem(value: 'marquee', child: Text('เลื่อนไปมา (Marquee)')),
                        DropdownMenuItem(value: 'bounce', child: Text('เด้งไปมา (Bounce)')),
                        DropdownMenuItem(value: 'random', child: Text('สุ่มตำแหน่ง (Random)')),
                      ],
                      onChanged: (val) => setState(() => _animationType = val!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              Text('ความโปร่งใส (Opacity): ${(_opacity * 100).toInt()}%'),
              Slider(
                value: _opacity,
                min: 0.1,
                max: 1.0,
                divisions: 9,
                activeColor: AppColors.primary,
                label: '${(_opacity * 100).toInt()}%',
                onChanged: (val) => setState(() => _opacity = val),
              ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              // Forensic Tracking
              Text('การติดตามและระบุตัวตน (Forensic Tracking)', style: AppTextStyles.heading3),
              const SizedBox(height: 8),
              const Text(
                'ระบบจะประทับข้อความขนาดเล็กและโปร่งแสงไว้ที่มุมล่างซ้ายของภาพ/วิดีโอ เพื่อให้สามารถสืบหาต้นตอในกรณีที่มีผู้นำภาพไปเผยแพร่ในทางที่ผิด',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              
              Card(
                elevation: 0,
                color: Colors.grey.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('แสดงรหัสเหตุการณ์ (Incident ID)'),
                      value: _showIncidentId,
                      activeColor: AppColors.primary,
                      onChanged: (val) => setState(() => _showIncidentId = val),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('แสดงรหัสผู้ร้องขอ/ไทยมุง (Uploader ID)'),
                      value: _showUploaderId,
                      activeColor: AppColors.primary,
                      onChanged: (val) => setState(() => _showUploaderId = val),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 40),
            ],
          ],
        ),
      ),
    );
  }
}
