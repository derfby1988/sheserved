import 'package:flutter/material.dart';
import '../../../../config/sync_config.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';

class VideoAdminPage extends StatefulWidget {
  const VideoAdminPage({super.key});

  @override
  State<VideoAdminPage> createState() => _VideoAdminPageState();
}

class _VideoAdminPageState extends State<VideoAdminPage> {
  late TextEditingController _cooldownController;
  late TextEditingController _maxSizeController;
  late TextEditingController _quotaController;
  late TextEditingController _maxRecordingController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _cooldownController = TextEditingController(text: SyncConfig.videoUploadCooldownSeconds.toString());
    _maxSizeController = TextEditingController(text: SyncConfig.maxVideoFileSizeMB.toString());
    _quotaController = TextEditingController(text: SyncConfig.dailyVideoUploadQuota.toString());
    _maxRecordingController = TextEditingController(text: SyncConfig.maxEmergencyRecordingSeconds.toString());
  }

  @override
  void dispose() {
    _cooldownController.dispose();
    _maxSizeController.dispose();
    _quotaController.dispose();
    _maxRecordingController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
      SyncConfig.videoUploadCooldownSeconds = int.tryParse(_cooldownController.text) ?? 3;
      SyncConfig.maxVideoFileSizeMB = int.tryParse(_maxSizeController.text) ?? 20;
      SyncConfig.dailyVideoUploadQuota = int.tryParse(_quotaController.text) ?? 50;
      SyncConfig.maxEmergencyRecordingSeconds = int.tryParse(_maxRecordingController.text) ?? 60;
    });

    try {
      await SyncConfig.saveToSupabase();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('บันทึกการตั้งค่าไปยังฐานข้อมูลเรียบร้อยแล้ว'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาด: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
      appBar: AppBar(
        title: const Text('Video System Admin'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Video Upload Controls', Icons.tune),
            const SizedBox(height: 16),
            _buildSettingCard(
              title: 'Upload Cooldown (Seconds)',
              subtitle: 'ระยะเวลารอระหว่างการอัปโหลดแต่ละครั้ง',
              controller: _cooldownController,
              icon: Icons.timer,
            ),
            const SizedBox(height: 16),
            _buildSettingCard(
              title: 'Max File Size (MB)',
              subtitle: 'ขนาดวิดีโอสูงสุดที่อนุญาตให้อัปโหลด',
              controller: _maxSizeController,
              icon: Icons.sd_storage,
            ),
            const SizedBox(height: 16),
            _buildSettingCard(
              title: 'Daily Upload Quota',
              subtitle: 'จำนวนครั้งสูงสุดที่อัปโหลดได้ต่อวัน/คน',
              controller: _quotaController,
              icon: Icons.assessment,
            ),
            const SizedBox(height: 16),
            _buildSettingCard(
              title: 'Max Emergency Recording (Seconds)',
              subtitle: 'เวลาบันทึก Emergency Video สูงสุด (วินาที) - ค่าเริ่มต้น 60',
              controller: _maxRecordingController,
              icon: Icons.videocam,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                      )
                    : const Text('บันทึกการตั้งค่า (Apply Now)'),
              ),
            ),
            const SizedBox(height: 24),
            _buildInfoCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppTextStyles.heading3.copyWith(color: AppColors.textPrimary),
        ),
      ],
    );
  }

  Widget _buildSettingCard({
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required IconData icon,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.divider.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(title, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: AppTextStyles.caption),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: AppColors.background,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue, size: 20),
              SizedBox(width: 8),
              Text('Cost Optimization Active', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'การจำกัดเหล่านี้ช่วยป้องกันการเรียกใช้ API ของ Bunny.net บ่อยเกินไป ซึ่งอาจส่งผลต่อค่าใช้จ่ายในช่วงพัฒนา (Development Phase)',
            style: AppTextStyles.caption.copyWith(color: Colors.blue[800]),
          ),
        ],
      ),
    );
  }
}
