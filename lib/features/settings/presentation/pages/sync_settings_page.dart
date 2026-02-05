import 'package:flutter/material.dart';
import '../../../../config/sync_config.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../services/service_locator.dart';

/// หน้าตั้งค่า Sync - ให้ร้านค้ากำหนดความถี่ sync ได้
class SyncSettingsPage extends StatefulWidget {
  const SyncSettingsPage({super.key});

  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage> {
  SyncModePreset _selectedPreset = SyncModePreset.standard;
  int _customInterval = 30;
  bool _useCustomInterval = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  void _loadCurrentSettings() {
    _customInterval = SyncConfig.syncIntervalSeconds;
    
    // Determine current preset
    if (!SyncConfig.enableAutoSync) {
      _selectedPreset = SyncModePreset.manual;
    } else if (_customInterval <= 15) {
      _selectedPreset = SyncModePreset.performance;
    } else if (_customInterval <= 30) {
      _selectedPreset = SyncModePreset.standard;
    } else {
      _selectedPreset = SyncModePreset.economy;
    }
  }

  void _applyPreset(SyncModePreset preset) {
    setState(() {
      _selectedPreset = preset;
      _useCustomInterval = false;
    });
    
    preset.apply();
    
    // Apply to sync service if available
    if (services.syncService != null) {
      services.syncService!.applySyncMode(preset);
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('เปลี่ยนเป็นโหมด ${preset.displayName}'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _applyCustomInterval() {
    setState(() {
      _useCustomInterval = true;
    });
    
    SyncConfig.syncIntervalSeconds = _customInterval;
    SyncConfig.enableAutoSync = true;
    
    if (services.syncService != null) {
      services.syncService!.changeSyncInterval(_customInterval);
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('ตั้งค่า sync ทุก $_customInterval วินาที'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ตั้งค่า Sync'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cost Warning Card
            _buildCostWarningCard(),
            
            const SizedBox(height: 24),
            
            // Preset Selection
            const Text(
              'เลือกโหมด Sync',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            
            ...SyncModePreset.values.map((preset) => _buildPresetCard(preset)),
            
            const SizedBox(height: 24),
            
            // Custom Interval
            _buildCustomIntervalSection(),
            
            const SizedBox(height: 24),
            
            // Current Stats
            _buildCurrentStatsCard(),
            
            const SizedBox(height: 24),
            
            // Manual Sync Button
            _buildManualSyncButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildCostWarningCard() {
    final isWarning = SyncConfig.isNearingFreeLimit;
    
    return Card(
      color: isWarning ? Colors.orange.shade50 : Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              isWarning ? Icons.warning : Icons.info_outline,
              color: isWarning ? Colors.orange : Colors.blue,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isWarning 
                        ? 'ใกล้ถึง limit ของ Free tier' 
                        : 'คำแนะนำการใช้งาน',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isWarning ? Colors.orange.shade800 : Colors.blue.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'แผนแนะนำ: ${SyncConfig.recommendedPlan}',
                    style: TextStyle(
                      color: isWarning ? Colors.orange.shade700 : Colors.blue.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetCard(SyncModePreset preset) {
    final isSelected = _selectedPreset == preset && !_useCustomInterval;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? AppColors.primary : Colors.grey.shade300,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () => _applyPreset(preset),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Radio<SyncModePreset>(
                value: preset,
                groupValue: _useCustomInterval ? null : _selectedPreset,
                onChanged: (value) {
                  if (value != null) _applyPreset(value);
                },
                activeColor: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preset.description,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _getCostColor(preset).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        preset.estimatedCost,
                        style: TextStyle(
                          color: _getCostColor(preset),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_circle,
                  color: AppColors.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getCostColor(SyncModePreset preset) {
    switch (preset) {
      case SyncModePreset.economy:
      case SyncModePreset.manual:
        return Colors.green;
      case SyncModePreset.standard:
        return Colors.orange;
      case SyncModePreset.performance:
        return Colors.red;
    }
  }

  Widget _buildCustomIntervalSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: _useCustomInterval,
                  onChanged: (value) {
                    setState(() {
                      _useCustomInterval = value ?? false;
                    });
                  },
                  activeColor: AppColors.primary,
                ),
                const Text(
                  'กำหนดเองเอง',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            if (_useCustomInterval) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Sync ทุก'),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                      controller: TextEditingController(
                        text: _customInterval.toString(),
                      ),
                      onChanged: (value) {
                        final parsed = int.tryParse(value);
                        if (parsed != null && parsed > 0) {
                          setState(() {
                            _customInterval = parsed;
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text('วินาที'),
                ],
              ),
              const SizedBox(height: 12),
              Slider(
                value: _customInterval.toDouble().clamp(5, 300),
                min: 5,
                max: 300,
                divisions: 59,
                label: '$_customInterval วินาที',
                activeColor: AppColors.primary,
                onChanged: (value) {
                  setState(() {
                    _customInterval = value.round();
                  });
                },
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('5 วินาที', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  Text('5 นาที', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _applyCustomInterval,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('บันทึกการตั้งค่า'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStatsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'สถิติการใช้งาน (ประมาณ)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            _buildStatRow('Sync ปัจจุบัน', '${SyncConfig.syncIntervalSeconds} วินาที'),
            _buildStatRow('Requests/วัน', '~${SyncConfig.estimatedDailyRequests.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}'),
            _buildStatRow('Requests/เดือน', '~${SyncConfig.estimatedMonthlyRequests.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}'),
            const Divider(),
            _buildStatRow('แผนแนะนำ', SyncConfig.recommendedPlan),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildManualSyncButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: () async {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('กำลัง Sync...'),
              duration: Duration(seconds: 1),
            ),
          );
          
          await services.forceSync();
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Sync เสร็จสมบูรณ์!'),
                backgroundColor: AppColors.success,
              ),
            );
          }
        },
        icon: const Icon(Icons.sync),
        label: const Text('Sync ตอนนี้'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }
}
