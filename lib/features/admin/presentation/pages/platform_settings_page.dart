import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/tlz_drawer.dart';
import '../../../../shared/widgets/tlz_hamburger_menu.dart';
import '../../../../services/platform_service.dart';
import 'package:flutter/foundation.dart';

class PlatformSettingsPage extends StatefulWidget {
  const PlatformSettingsPage({super.key});

  @override
  State<PlatformSettingsPage> createState() => _PlatformSettingsPageState();
}

class _PlatformSettingsPageState extends State<PlatformSettingsPage> {
  // Metrics data
  List<Map<String, dynamic>> _metrics = [];
  bool _isLoadingMetrics = true;

  // Mock Settings
  bool _webLiveMap = false;
  bool _iosLiveMap = true;
  bool _androidLiveMap = true;
  
  final TextEditingController _imageUrlCtrl = TextEditingController(
    text: 'https://images.unsplash.com/photo-1526778548025-fa2f459cd5c1?auto=format&fit=crop&q=80&w=1000'
  );

  @override
  void initState() {
    super.initState();
    _webLiveMap = PlatformService.isWebMapEnabled;
    _loadMetrics();
  }

  Future<void> _loadMetrics() async {
    setState(() => _isLoadingMetrics = true);
    final data = await PlatformService.getMetrics();
    if (mounted) {
      setState(() {
        _metrics = data;
        _isLoadingMetrics = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      drawer: const TlzDrawer(),
      body: SafeArea(
        top: false, // ให้ AppBar ทะลุขึ้นไปถึง Status Bar ได้เพื่อความสวยงาม
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildUsageStats(),
                  const SizedBox(height: 24),
                  _buildCostWarningCard(),
                  const SizedBox(height: 24),
                  _buildPlatformCard(
                    title: 'Web Platform (Browser)',
                    icon: Icons.language,
                    color: Colors.blue,
                    isEnabled: _webLiveMap,
                    onChanged: (v) {
                      setState(() => _webLiveMap = v);
                      PlatformService.setWebMapEnabled(v);
                    },
                    description: 'แนะนำให้ปิดบน Web เพื่อลดค่าใช้จ่าย Google Maps JS API และเพิ่มความเร็วในการโหลดหน้าแรก',
                    child: _webLiveMap ? Column(
                      children: [
                        const Divider(height: 32),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('เปิดใช้งานแยกรายหน้าจอ:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 12),
                        _buildSubToggle(
                          title: 'หน้าหลัก (Home Map)',
                          value: PlatformService.shouldShowLiveMap(pageName: 'home'),
                          onChanged: (v) => setState(() => PlatformService.updateWebMapSetting('home', v)),
                        ),
                        _buildSubToggle(
                          title: 'หน้ากู้ภัย (Rescue Map)',
                          value: PlatformService.shouldShowLiveMap(pageName: 'rescue'),
                          onChanged: (v) => setState(() => PlatformService.updateWebMapSetting('rescue', v)),
                        ),
                        _buildSubToggle(
                          title: 'หน้าเหตุฉุกเฉิน (Emergency Map)',
                          value: PlatformService.shouldShowLiveMap(pageName: 'emergency'),
                          onChanged: (v) => setState(() => PlatformService.updateWebMapSetting('emergency', v)),
                        ),
                      ],
                    ) : null,
                  ),
                  const SizedBox(height: 16),
                  _buildPlatformCard(
                    title: 'iOS Platform',
                    icon: Icons.apple,
                    color: Colors.grey.shade800,
                    isEnabled: _iosLiveMap,
                    onChanged: (v) => setState(() => _iosLiveMap = v),
                    description: 'ใช้งาน Google Maps SDK สำหรับ iOS (ฟรีตามโควต้า Native)',
                  ),
                  const SizedBox(height: 16),
                  _buildPlatformCard(
                    title: 'Android Platform',
                    icon: Icons.android,
                    color: Colors.green,
                    isEnabled: _androidLiveMap,
                    onChanged: (v) => setState(() => _androidLiveMap = v),
                    description: 'ใช้งาน Google Maps SDK สำหรับ Android (ฟรีตามโควต้า Native)',
                  ),
                  const SizedBox(height: 32),
                  _buildSaveButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildSubToggle({required String title, required bool value, required ValueChanged<bool> onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, color: Colors.black87)),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _buildUsageStats() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'สถิติการใช้งานแผนที่ (Real-time Usage)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              IconButton(
                onPressed: _loadMetrics,
                icon: const Icon(Icons.refresh, color: Colors.white70, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoadingMetrics)
            const Center(child: CircularProgressIndicator(color: Colors.white24))
          else if (_metrics.isEmpty)
            const Center(child: Text('ยังไม่มีข้อมูลการใช้งาน', style: TextStyle(color: Colors.white54)))
          else
            Column(
              children: _metrics.map((m) {
                final platform = m['platform']?.toString().toUpperCase() ?? 'UNKNOWN';
                final metricName = m['metric_name']?.toString() ?? 'unknown';
                final count = int.tryParse(m['count']?.toString() ?? '0') ?? 0;
                final isWeb = platform == 'WEB';
                
                // สกัดชื่อหน้าจอจาก metric_name (เช่น map_load_home -> HOME)
                final pageName = metricName.replaceAll('map_load_', '').toUpperCase();
                final displayLabel = pageName == 'TOTALS_TOTAL' ? 'TOTAL ALL' : '$platform ($pageName)';

                final estimatedCost = isWeb ? (count / 1000) * 7.0 : 0.0;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isWeb ? Colors.blue.withOpacity(0.1) : Colors.white10,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isWeb ? Icons.language : (platform == 'IOS' ? Icons.apple : Icons.android),
                          color: isWeb ? Colors.blueAccent : Colors.white,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayLabel,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            if (isWeb)
                              const Text(
                                'Google Maps JS API',
                                style: TextStyle(color: Colors.white54, fontSize: 9),
                              ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$count Loads',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          if (isWeb)
                            Text(
                              'Est. \$${estimatedCost.toStringAsFixed(2)}',
                              style: const TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 120,
      pinned: true,
      elevation: 0,
      backgroundColor: const Color(0xFF1a1a2e),
      centerTitle: true,
      leading: const Padding(
        padding: EdgeInsets.all(8.0),
        child: TlzHamburgerMenu(),
      ),
      title: const Text(
        'Platform Settings', 
        style: TextStyle(
          color: Colors.white, 
          fontWeight: FontWeight.bold, 
          fontSize: 18,
          letterSpacing: 0.5,
        )
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCostWarningCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.monetization_on_outlined, color: Colors.orange.shade800, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'วิเคราะห์ค่าใช้จ่าย (Estimated Cost)',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade900),
                ),
                const SizedBox(height: 4),
                const Text(
                  'การเปิดแผนที่บน Web มีค่าใช้จ่าย ~\$7 ต่อ 1,000 loads หากมีคนเข้าชมวันละ 100 คน จะเสียค่าใช้จ่ายประมาณ 600-700 บาท/เดือน',
                  style: TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformCard({
    required String title,
    required IconData icon,
    required Color color,
    required bool isEnabled,
    required ValueChanged<bool> onChanged,
    required String description,
    Widget? child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(isEnabled ? 'Live Map (Interactive)' : 'Static Placeholder', 
                      style: TextStyle(color: isEnabled ? AppColors.success : Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Switch.adaptive(
                value: isEnabled, 
                onChanged: onChanged,
                activeColor: AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(description, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4)),
          
          if (!isEnabled) ...[
            const SizedBox(height: 20),
            const Text('Fallback Image Preview:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
                image: DecorationImage(
                  image: NetworkImage(_imageUrlCtrl.text),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.1), BlendMode.darken),
                ),
              ),
              child: const Center(
                child: Icon(Icons.image_outlined, color: Colors.white54, size: 40),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _imageUrlCtrl,
              decoration: InputDecoration(
                labelText: 'URL รูปภาพทดแทน',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ],
          if (child != null) child,
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกการตั้งค่าแพลตฟอร์มสำเร็จ'), backgroundColor: AppColors.success),
        );
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: const Text('Save Configuration', style: TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}
