import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../admin/models/profession.dart';
import '../../../admin/data/repositories/profession_repository.dart';
import '../../../consultation/data/models/consultation_package.dart';
import '../../../../shared/widgets/tlz_drawer.dart';
import '../../../../shared/widgets/tlz_hamburger_menu.dart';

// ─── Package Admin Page ───────────────────────────────────────────────────────

class PackageAdminPage extends StatefulWidget {
  const PackageAdminPage({super.key});

  @override
  State<PackageAdminPage> createState() => _PackageAdminPageState();
}

class _PackageAdminPageState extends State<PackageAdminPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late List<ConsultationPackage> _packages;
  List<Profession> _providerProfessions = [];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _animController.forward();
    _packages = _buildDefaultPackages(); // show mock immediately
    _loadPackages(); // then load real data
    _loadProfessions();
  }

  /// โหลดแพ็คเกจจาก Supabase จริง
  Future<void> _loadPackages() async {
    try {
      final response = await Supabase.instance.client
          .from('consultation_packages')
          .select()
          .order('display_order');
      
      final List<ConsultationPackage> loaded = (response as List)
          .map((e) => ConsultationPackage.fromJson(Map<String, dynamic>.from(e)))
          .toList();
          
      if (mounted) {
        setState(() {
          _packages = loaded; // ใช้ข้อมูลจาก DB (อาจจะเป็นลิสต์ว่างถ้าลบออกหมดแล้ว)
        });
      }
    } catch (e) {
      debugPrint('Database error (Using mock fallback): $e');
      // หากเกิด error เช่น ตารางไม่มีอยู่จริง หรือยังไม่ได้รัน SQL ให้ใช้ Mock
      if (mounted && _packages.isEmpty) {
        setState(() => _packages = _buildDefaultPackages());
      }
    }
  }

  Future<void> _loadProfessions() async {
    try {
      final repo = ProfessionRepository(Supabase.instance.client);
      final allProfessions = await repo.getProfessionsByCategory(UserCategory.provider);
      if (mounted) {
        setState(() => _providerProfessions = allProfessions);
      }
    } catch (e) {
      debugPrint('Error loading professions for package editor: $e');
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  List<ConsultationPackage> _buildDefaultPackages() {
    final now = DateTime.now();
    return [
      ConsultationPackage(
        id: 'pkg_001',
        name: 'แพ็คเกจ ปรึกษาผู้เชี่ยวชาญระดับอาจารย์แพทย์ + AI',
        shortName: 'อาจารย์หมอ + AI',
        description: 'รับผลวิเคราะห์เบื้องต้นจาก Vega AI ก่อนพบอาจารย์หมอ',
        price: 3290.0,
        includesAI: true,
        isActive: true,
        displayOrder: 0,
        expertGroups: [
          ExpertGroup(id: 'eg_001', name: 'อาจารย์แพทย์', role: 'professor', maxExperts: 1, isRequired: true),
          ExpertGroup(id: 'eg_002', name: 'แพทย์ผู้ช่วย', role: Profession.doctorGpProfessionId, maxExperts: 2, isRequired: false),
        ],
        createdAt: now,
        updatedAt: now,
      ),
      ConsultationPackage(
        id: 'pkg_002',
        name: 'แพ็คเกจ สำหรับปรึกษาผู้เชี่ยวชาญระดับอาจารย์แพทย์',
        shortName: 'อาจารย์หมอ',
        description: 'ปรึกษาโดยตรงกับอาจารย์แพทย์ผู้เชี่ยวชาญ',
        price: 2990.0,
        includesAI: false,
        isActive: true,
        displayOrder: 1,
        expertGroups: [
          ExpertGroup(id: 'eg_003', name: 'อาจารย์แพทย์', role: 'professor', maxExperts: 1, isRequired: true),
        ],
        createdAt: now,
        updatedAt: now,
      ),
      ConsultationPackage(
        id: 'pkg_003',
        name: 'แพ็คเกจ สำหรับปรึกษาแพทย์เฉพาะทาง',
        shortName: 'หมอเฉพาะทาง',
        description: 'ปรึกษาแพทย์เฉพาะทางตามอาการที่ระบุ',
        price: 799.0,
        includesAI: false,
        isActive: true,
        displayOrder: 2,
        expertGroups: [
          ExpertGroup(id: 'eg_004', name: 'แพทย์เฉพาะทาง', role: Profession.doctorSpecialistProfessionId, maxExperts: 1, isRequired: true),
        ],
        createdAt: now,
        updatedAt: now,
      ),
      ConsultationPackage(
        id: 'pkg_004',
        name: 'แพ็คเกจ สำหรับปรึกษาแพทย์ทั่วไป/เภสัช',
        shortName: 'หมอ/เภสัช',
        description: 'ปรึกษาแพทย์ทั่วไปหรือเภสัชกร',
        price: 299.0,
        includesAI: false,
        isActive: true,
        displayOrder: 3,
        expertGroups: [
          ExpertGroup(id: 'eg_005', name: 'แพทย์ทั่วไป', role: Profession.doctorGpProfessionId, maxExperts: 2, isRequired: false),
          ExpertGroup(id: 'eg_006', name: 'เภสัชกร', role: Profession.pharmacistProfessionId, maxExperts: 2, isRequired: false),
        ],
        createdAt: now,
        updatedAt: now,
      ),
    ];
  }

  Color _tierColor(double price) {
    if (price >= 3000) return const Color(0xFFB8860B); // Gold
    if (price >= 700) return const Color(0xFF6A5ACD);  // Purple
    if (price >= 400) return const Color(0xFF2E8B57);  // Green
    return const Color(0xFF4682B4); // Blue
  }

  IconData _tierIcon(double price) {
    if (price >= 3000) return Icons.workspace_premium;
    if (price >= 700) return Icons.stars_outlined;
    if (price >= 400) return Icons.verified_outlined;
    return Icons.health_and_safety_outlined;
  }

  String _tierLabel(double price) {
    if (price >= 3000) return 'GOLD';
    if (price >= 700) return 'PREMIUM';
    if (price >= 400) return 'STANDARD';
    return 'BASIC';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      drawer: const TlzDrawer(),
      body: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: CustomScrollView(
          slivers: [
          // ── App Bar ──────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 140,
            floating: false,
            pinned: true,
            elevation: 0,
            backgroundColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF1a1a2e),
                      Color(0xFF16213e),
                      Color(0xFF0f3460),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 12),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Package Management',
                                  style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1.5),
                                ),
                                Text(
                                  'จัดการแพ็คเกจ',
                                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            leading: const TlzHamburgerMenu(),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: TextButton.icon(
                  onPressed: () => _showPackageEditor(context, null),
                  icon: const Icon(Icons.add_circle, color: Colors.white, size: 18),
                  label: const Text('เพิ่มแพ็คเกจ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.15),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ),
            ],
          ),

          // ── Summary Bar ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  _buildStatChip(
                    label: 'ทั้งหมด',
                    value: '${_packages.length}',
                    icon: Icons.dashboard_outlined,
                    color: const Color(0xFF5C6BC0),
                  ),
                  const SizedBox(width: 12),
                  _buildStatChip(
                    label: 'เปิดใช้',
                    value: '${_packages.where((p) => p.isActive).length}',
                    icon: Icons.check_circle_outline,
                    color: const Color(0xFF43A047),
                  ),
                  const SizedBox(width: 12),
                  _buildStatChip(
                    label: 'มี AI',
                    value: '${_packages.where((p) => p.includesAI).length}',
                    icon: Icons.auto_awesome,
                    color: const Color(0xFFAB47BC),
                  ),
                ],
              ),
            ),
          ),

          // ── Package List ─────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final pkg = _packages[index];
                  return _buildPackageCard(pkg, index);
                },
                childCount: _packages.length,
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    ),
  );
}

  Widget _buildStatChip({required String label, required String value, required IconData icon, required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
                Text(label, style: TextStyle(color: color.withOpacity(0.7), fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPackageCard(ConsultationPackage pkg, int index) {
    final tier = _tierColor(pkg.price);
    final tierIcon = _tierIcon(pkg.price);
    final tierLabel = _tierLabel(pkg.price);

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final delay = index * 0.1;
        final animValue = (_animController.value - delay).clamp(0.0, 1.0);
        return Opacity(
          opacity: animValue,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - animValue)),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: tier.withOpacity(0.12),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: tier.withOpacity(0.15)),
        ),
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                gradient: LinearGradient(
                  colors: [tier.withOpacity(0.08), tier.withOpacity(0.03)],
                ),
              ),
              child: Row(
                children: [
                  // Tier badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: tier,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(tierIcon, color: Colors.white, size: 12),
                        const SizedBox(width: 4),
                        Text(tierLabel, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Status toggle
                  GestureDetector(
                    onTap: () => setState(() => pkg.isActive = !pkg.isActive),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: pkg.isActive ? AppColors.success.withOpacity(0.1) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: pkg.isActive ? AppColors.success.withOpacity(0.3) : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6, height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: pkg.isActive ? AppColors.success : Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            pkg.isActive ? 'เปิดใช้' : 'ปิด',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: pkg.isActive ? AppColors.success : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (pkg.includesAI) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF7B2FF7), Color(0xFFDA44BB)]),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, color: Colors.white, size: 10),
                          SizedBox(width: 4),
                          Text('Vega AI', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ],

                  const Spacer(),

                  // Action buttons
                  Row(
                    children: [
                      _iconBtn(Icons.edit_outlined, tier, () => _showPackageEditor(context, pkg)),
                      const SizedBox(width: 4),
                      _iconBtn(Icons.delete_outline, Colors.redAccent, () => _confirmDelete(pkg)),
                    ],
                  ),
                ],
              ),
            ),

            // ── Body ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Package name
                  Text(
                    pkg.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1A1A2E)),
                  ),
                  if (pkg.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(pkg.description, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],

                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // Price + Details row
                  Row(
                    children: [
                      // Price
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ราคา', style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontWeight: FontWeight.w600, letterSpacing: 1)),
                          const SizedBox(height: 2),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _formatPrice(pkg.price),
                                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: tier),
                              ),
                              const Padding(
                                padding: EdgeInsets.only(bottom: 4, left: 4),
                                child: Text('฿', style: TextStyle(fontSize: 13, color: Colors.grey)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(width: 24),

                      // Expert groups
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('กลุ่มผู้เชี่ยวชาญ (${pkg.expertGroups.length} กลุ่ม)', style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontWeight: FontWeight.w600, letterSpacing: 1)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: pkg.expertGroups.map((g) => _expertChip(g, tier)).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }

  Widget _expertChip(ExpertGroup g, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_roleIcon(g.role), color: color, size: 11),
          const SizedBox(width: 4),
          Text(g.name, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
          if (g.maxExperts > 0) ...[
            const SizedBox(width: 4),
            Text('×${g.maxExperts}', style: TextStyle(fontSize: 9, color: color.withOpacity(0.7))),
          ],
          if (g.isRequired) ...[
            const SizedBox(width: 4),
            Icon(Icons.star, color: Colors.orange, size: 9),
          ],
        ],
      ),
    );
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'professor': return Icons.workspace_premium;
      case 'specialist': return Icons.biotech_outlined;
      case 'pharmacist': return Icons.medication_outlined;
      default: return Icons.medical_services_outlined;
    }
  }

  String _formatPrice(double price) {
    if (price >= 1000) {
      return '${(price / 1000).toStringAsFixed(price % 1000 == 0 ? 0 : 1)}K'.replaceAll('.0K', 'K');
    }
    return price.toInt().toString();
  }

  void _confirmDelete(ConsultationPackage pkg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool isDeleting = false;
        return StatefulBuilder(
          builder: (ctx, setDlgState) {

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text('ยืนยันการลบ'),
              ],
            ),
            content: Text('ต้องการลบแพ็คเกจ\n"${pkg.name}" หรือไม่?'),
            actions: [
              TextButton(
                onPressed: isDeleting ? null : () => Navigator.pop(ctx),
                child: const Text('ยกเลิก'),
              ),
              ElevatedButton(
                onPressed: isDeleting
                    ? null
                    : () async {
                        setDlgState(() => isDeleting = true);
                        try {
                          // ดำเนินการลบจากตารางจริง (Supabase) และตรวจสอบผล (ใช้ select เพื่อยืนยัน)
                          final deletedRows = await Supabase.instance.client
                              .from('consultation_packages')
                              .delete()
                              .eq('id', pkg.id)
                              .select();
                          
                          if (mounted) {
                            if (deletedRows.isNotEmpty) {
                              // ลบสำเร็จจริงใน DB
                              setState(() => _packages.removeWhere((p) => p.id == pkg.id));
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                                      const SizedBox(width: 10),
                                      Expanded(child: Text('ลบแพ็คเกจ "${pkg.shortName}" สำเร็จ')),
                                    ],
                                  ),
                                  backgroundColor: Colors.redAccent,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              );
                            } else {
                              // คำสั่งสำเร็จแต่ไม่มีแถวถูกลบ (อาจเพราะใช้ Mock data หรือสิทธิ์ไม่พอ)
                              setDlgState(() => isDeleting = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('ไม่พบข้อมูลในฐานข้อมูล (อาจเป็นข้อมูล Mock)'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            }
                          }
                        } catch (e) {
                          setDlgState(() => isDeleting = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('เกิดข้อผิดพลาดในการลบ: $e'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: isDeleting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('ลบ'),
              ),
            ],
          );
        },
      );
    },
  );
}

  void _showPackageEditor(BuildContext context, ConsultationPackage? existing) async {
    // Reload professions before showing the editor to catch any newly added ones
    await _loadProfessions();
    
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PackageEditorSheet(
        existing: existing,
        professions: _providerProfessions,
        onSave: (pkg) async {
          // Upsert to Supabase
          try {
            final data = pkg.toJson();
            if (existing == null) {
              data['created_at'] = pkg.createdAt.toIso8601String();
            }
            await Supabase.instance.client
                .from('consultation_packages')
                .upsert(data);
          } catch (e) {
            debugPrint('Failed to upsert package to Supabase (table may not exist): $e');
          }
          // Update local list regardless
          if (mounted) {
            setState(() {
              if (existing == null) {
                _packages.add(pkg);
              } else {
                final idx = _packages.indexWhere((p) => p.id == existing.id);
                if (idx != -1) _packages[idx] = pkg;
              }
            });
          }
        },
      ),
    );
  }
}

// ─── Package Editor Bottom Sheet ──────────────────────────────────────────────

class PackageEditorSheet extends StatefulWidget {
  final ConsultationPackage? existing;
  final Function(ConsultationPackage) onSave;
  final List<Profession> professions; // Real profession list from DB

  const PackageEditorSheet({
    super.key,
    this.existing,
    required this.onSave,
    this.professions = const [],
  });

  @override
  State<PackageEditorSheet> createState() => _PackageEditorSheetState();
}

class _PackageEditorSheetState extends State<PackageEditorSheet> {
  late TextEditingController _nameCtrl;
  late TextEditingController _shortNameCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _priceCtrl;
  late bool _includesAI;
  late bool _isActive;
  late List<ExpertGroup> _expertGroups;
  late TextEditingController _sessionMinsCtrl;
  late TextEditingController _expireMinsCtrl;

  @override
  void initState() {
    super.initState();
    final pkg = widget.existing;
    _nameCtrl = TextEditingController(text: pkg?.name ?? '');
    _shortNameCtrl = TextEditingController(text: pkg?.shortName ?? '');
    _descCtrl = TextEditingController(text: pkg?.description ?? '');
    _priceCtrl = TextEditingController(text: pkg != null ? pkg.price.toInt().toString() : '');
    _includesAI = pkg?.includesAI ?? false;
    _isActive = pkg?.isActive ?? true;
    _expertGroups = List.from(pkg?.expertGroups ?? []);
    _sessionMinsCtrl = TextEditingController(text: pkg != null ? pkg.sessionMinutes.toString() : '15');
    _expireMinsCtrl = TextEditingController(text: pkg != null ? pkg.expireMinutes.toString() : '120');
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _shortNameCtrl.dispose();
    _descCtrl.dispose(); _priceCtrl.dispose();
    _sessionMinsCtrl.dispose(); _expireMinsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.6,
        maxChildSize: 0.97,
        builder: (ctx, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF7F9FC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),

            // Title bar
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1a1a2e), Color(0xFF0f3460)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(isEditing ? Icons.edit_outlined : Icons.add_circle_outline, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isEditing ? 'แก้ไขแพ็คเกจ' : 'เพิ่มแพ็คเกจใหม่',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E)),
                  ),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
            ),
            const Divider(height: 1),

            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.all(24),
                children: [
                  // ── Basic Info ──────────────────────────────────────────
                  _sectionHeader('ข้อมูลพื้นฐาน', Icons.info_outline),
                  const SizedBox(height: 12),
                  _inputField(_nameCtrl, 'ชื่อแพ็คเกจ (เต็ม)', 'เช่น แพ็คเกจ ปรึกษาผู้เชี่ยวชาญระดับอาจารย์แพทย์'),
                  const SizedBox(height: 12),
                  _inputField(_shortNameCtrl, 'ชื่อย่อ (แสดงบน Wheel)', 'เช่น อาจารย์หมอ + AI'),
                  const SizedBox(height: 12),
                  _inputField(_descCtrl, 'คำอธิบาย', 'อธิบายสั้นๆ ว่าแพ็คเกจนี้เหมาะกับใคร', maxLines: 2),
                  const SizedBox(height: 24),

                  // ── Price ───────────────────────────────────────────────
                  _sectionHeader('ราคา', Icons.payments_outlined),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _priceCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            labelText: 'ราคา (บาท)',
                            prefixIcon: const Icon(Icons.currency_exchange, size: 18),
                            suffixText: '฿',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                            filled: true, fillColor: Colors.white,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Price Preview
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1a1a2e),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            Text(
                              _priceCtrl.text.isEmpty ? '-' : '฿${_priceCtrl.text}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            const Text('ราคา', style: TextStyle(color: Colors.white54, fontSize: 10)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ── AI & Status ─────────────────────────────────────────
                  _sectionHeader('การตั้งค่า', Icons.tune),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          value: _isActive,
                          onChanged: (v) => setState(() => _isActive = v),
                          title: const Text('เปิดใช้งานแพ็คเกจ', style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(_isActive ? 'ลูกค้าสามารถเลือกแพ็คเกจนี้ได้' : 'ซ่อนแพ็คเกจนี้จากลูกค้า', style: const TextStyle(fontSize: 12)),
                          secondary: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _isActive ? AppColors.success.withOpacity(0.1) : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.power_settings_new, color: _isActive ? AppColors.success : Colors.grey, size: 20),
                          ),
                          activeColor: AppColors.success,
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        SwitchListTile(
                          value: _includesAI,
                          onChanged: (v) => setState(() => _includesAI = v),
                          title: const Row(
                            children: [
                              Text('รวม Vega AI', style: TextStyle(fontWeight: FontWeight.w600)),
                              SizedBox(width: 8),
                              _AIBadge(),
                            ],
                          ),
                          subtitle: const Text('เพิ่ม AI Pre-Consultation ก่อนพบแพทย์', style: TextStyle(fontSize: 12)),
                          secondary: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              gradient: _includesAI
                                  ? const LinearGradient(colors: [Color(0xFF7B2FF7), Color(0xFFDA44BB)])
                                  : null,
                              color: _includesAI ? null : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.auto_awesome, color: _includesAI ? Colors.white : Colors.grey, size: 20),
                          ),
                          activeColor: const Color(0xFF7B2FF7),
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(16))),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // ── Time Configuration ───────────────────────────────────
                  _sectionHeader('การตั้งค่าเวลา (นาที)', Icons.timer_outlined),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _inputField(
                          _sessionMinsCtrl, 
                          'เวลาปรึกษา', 
                          'เช่น 15', 
                          icon: Icons.hourglass_top_outlined,
                          isNumber: true,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _inputField(
                          _expireMinsCtrl, 
                          'เวลาหมดอายุคำขอ', 
                          'เช่น 120', 
                          icon: Icons.history_toggle_off_outlined,
                          isNumber: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '* เวลาปรึกษาจะเริ่มนับเมื่อทีมผู้เชี่ยวชาญเข้าร่วมครบ\n* คำขอจะถูกยกเลิกอัตโนมัติหากไม่มีแพทย์รับงานภายในเวลาที่กำหนด',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500, height: 1.5),
                  ),
                  const SizedBox(height: 24),

                  // ── Expert Groups ────────────────────────────────────────
                  Row(
                    children: [
                      Expanded(child: _sectionHeader('กลุ่มผู้เชี่ยวชาญ (${_expertGroups.length} กลุ่ม)', Icons.groups_outlined)),
                      TextButton.icon(
                        onPressed: _addExpertGroup,
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        label: const Text('เพิ่มกลุ่ม', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF0f3460),
                          backgroundColor: const Color(0xFF0f3460).withOpacity(0.05),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_expertGroups.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200, style: BorderStyle.solid),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.group_add_outlined, size: 40, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          Text('ยังไม่มีกลุ่มผู้เชี่ยวชาญ', style: TextStyle(color: Colors.grey.shade400)),
                          const SizedBox(height: 4),
                          Text('กดปุ่ม "เพิ่มกลุ่ม" เพื่อกำหนดผู้เชี่ยวชาญที่จะให้บริการ', style: TextStyle(fontSize: 11, color: Colors.grey.shade400), textAlign: TextAlign.center),
                        ],
                      ),
                    )
                  else
                    ..._expertGroups.asMap().entries.map((e) => _buildExpertGroupCard(e.key, e.value)),

                  const SizedBox(height: 32),

                  // ── Save Button ──────────────────────────────────────────
                  ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1a1a2e),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(isEditing ? Icons.save_outlined : Icons.add_circle_outline, size: 20),
                        const SizedBox(width: 8),
                        Text(isEditing ? 'บันทึกการเปลี่ยนแปลง' : 'สร้างแพ็คเกจใหม่', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);
}

  Widget _buildExpertGroupCard(int idx, ExpertGroup group) {
    // Look up profession name from loaded professions list by role (which stores profession id)
    final professionName = widget.professions
        .where((p) => p.id == group.role)
        .map((p) => p.name)
        .firstOrNull ?? _roleDisplayNameForGroup(group.role);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Role Icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0f3460).withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_roleIconForGroup(group.role), color: const Color(0xFF0f3460), size: 20),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Row(
                  children: [
                    _groupBadge(professionName, Colors.indigo),
                    const SizedBox(width: 6),
                    _groupBadge('Max: ${group.maxExperts == -1 ? "∞" : group.maxExperts}', Colors.teal),
                    if (group.isRequired) ...[
                      const SizedBox(width: 6),
                      _groupBadge('บังคับ', Colors.orange),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Edit / Delete
          Row(
            children: [
              InkWell(
                onTap: () => _editExpertGroup(idx, group),
                borderRadius: BorderRadius.circular(8),
                child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.edit_outlined, size: 16, color: Colors.grey)),
              ),
              InkWell(
                onTap: () => setState(() => _expertGroups.removeAt(idx)),
                borderRadius: BorderRadius.circular(8),
                child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.close, size: 16, color: Colors.redAccent)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _groupBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w700)),
    );
  }

  IconData _roleIconForGroup(String role) {
    switch (role) {
      case 'professor': return Icons.workspace_premium;
      case 'specialist': return Icons.biotech_outlined;
      case 'pharmacist': return Icons.medication_outlined;
      default: return Icons.medical_services_outlined;
    }
  }

  String _roleDisplayNameForGroup(String role) {
    switch (role) {
      case 'professor':
        return 'อาจารย์แพทย์';
      case Profession.doctorGpProfessionId:
        return 'แพทย์ทั่วไป';
      case Profession.doctorSpecialistProfessionId:
        return 'แพทย์เฉพาะทาง';
      case Profession.pharmacistProfessionId:
        return 'เภสัชกร';
      default:
        return role;
    }
  }

  Widget _professionIconWidget(String? iconName) {
    final IconData icon;
    switch (iconName) {
      case 'local_hospital': icon = Icons.local_hospital; break;
      case 'medical_services': icon = Icons.medical_services; break;
      case 'store': icon = Icons.store; break;
      case 'person': icon = Icons.person; break;
      case 'delivery_dining': icon = Icons.delivery_dining; break;
      case 'engineering': icon = Icons.engineering; break;
      case 'gavel': icon = Icons.gavel; break;
      case 'school': icon = Icons.school; break;
      case 'spa': icon = Icons.spa; break;
      default: icon = Icons.work_outline;
    }
    return Icon(icon, size: 16, color: const Color(0xFF0f3460));
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF0f3460)),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E), letterSpacing: 0.3)),
      ],
    );
  }

  Widget _inputField(TextEditingController ctrl, String label, String hint, {int maxLines = 1, IconData? icon, bool isNumber = false}) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: isNumber ? TextInputType.number : (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
      inputFormatters: isNumber ? [FilteringTextInputFormatter.digitsOnly] : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
        prefixIcon: icon != null ? Icon(icon, size: 18) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        filled: true,
        fillColor: Colors.white,
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
    );
  }

  void _addExpertGroup() => _showGroupDialog(null, null);
  void _editExpertGroup(int idx, ExpertGroup g) => _showGroupDialog(idx, g);

  void _showGroupDialog(int? editIdx, ExpertGroup? existing) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    // Use the first loaded profession id as default if available
    final availableProfessions = widget.professions;
    String role = existing?.role ?? 
        (availableProfessions.isNotEmpty ? availableProfessions.first.id : '');
    int maxExperts = existing?.maxExperts ?? 1;
    bool isRequired = existing?.isRequired ?? false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final bool isNameValid = nameCtrl.text.trim().isNotEmpty;

          return GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.opaque,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  Icon(editIdx == null ? Icons.group_add : Icons.edit_note, color: const Color(0xFF1a1a2e)),
                  const SizedBox(width: 12),
                  Text(editIdx == null ? 'เพิ่มกลุ่มผู้เชี่ยวชาญ' : 'แก้ไขกลุ่ม'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    autofocus: editIdx == null,
                    decoration: InputDecoration(
                      labelText: 'ชื่อหน้ากลุ่ม',
                      hintText: 'เช่น ทีมแพทย์เฉพาะทาง',
                      prefixIcon: const Icon(Icons.badge_outlined, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    onChanged: (v) => setDlgState(() {}), // Trigger bit rebuild for validation
                  ),
                  const SizedBox(height: 16),
                  // Dynamic dropdown from real Professions table (provider category)
                  availableProfessions.isEmpty
                  ? Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange.shade700, size: 16),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'กำลังโหลดกลุ่มอาชีพ หรือยังไม่มีข้อมูลในระบบ\nกรุณาเพิ่มอาชีพในหน้า "จัดการอาชีพ" ก่อน',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    )
                  : DropdownButtonFormField<String>(
                      value: availableProfessions.any((p) => p.id == role) || role == 'professor'
                          ? role
                          : availableProfessions.first.id,
                      decoration: InputDecoration(
                        labelText: 'กลุ่มอาชีพ (จากหน้าจัดการอาชีพ)',
                        prefixIcon: const Icon(Icons.groups_outlined, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      items: [
                        if (!availableProfessions.any((p) => p.id == 'professor' || p.professionCode == 'professor'))
                          DropdownMenuItem<String>(
                            value: 'professor',
                            child: Row(
                              children: [
                                Icon(_roleIconForGroup('professor'), size: 18, color: const Color(0xFF0f3460)),
                                const SizedBox(width: 8),
                                const Text('อาจารย์แพทย์', style: TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                        ...availableProfessions.map((p) {
                        return DropdownMenuItem<String>(
                          value: p.id,
                          child: Row(
                            children: [
                              _professionIconWidget(p.iconName),
                              const SizedBox(width: 8),
                              Text(
                                p.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                              if (p.isBuiltIn) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('Built-in', style: TextStyle(fontSize: 8, color: Colors.grey)),
                                ),
                              ],
                            ],
                          ),
                        );
                      }),
                      ].toList(),
                      onChanged: (v) => setDlgState(() => role = v ?? role),
                    ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('จำนวนสูงสุด:', style: TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: maxExperts > 1 ? () => setDlgState(() => maxExperts--) : null,
                  ),
                  Text('$maxExperts', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => setDlgState(() => maxExperts++),
                  ),
                ],
              ),
                SwitchListTile(
                  value: isRequired,
                  onChanged: (v) => setDlgState(() => isRequired = v),
                  title: const Text('บังคับต้องมีกลุ่มนี้', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  subtitle: const Text('ต้องมีผู้เชี่ยวชาญกลุ่มนี้อย่างน้อย 1 คน', style: TextStyle(fontSize: 11)),
                  activeColor: Colors.orange,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('ยกเลิก', style: TextStyle(color: Colors.grey.shade600)),
              ),
              ElevatedButton(
                onPressed: !isNameValid ? null : () {
                  final g = ExpertGroup(
                    id: existing?.id ?? 'eg_${DateTime.now().millisecondsSinceEpoch}',
                    name: nameCtrl.text.trim(),
                    role: role,
                    maxExperts: maxExperts,
                    isRequired: isRequired,
                  );
                  setState(() {
                    if (editIdx == null) _expertGroups.add(g);
                    else _expertGroups[editIdx] = g;
                  });
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1a1a2e),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  elevation: 0,
                  minimumSize: const Size(100, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('บันทึก', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    ),
  );
}

  void _save() {
    if (_nameCtrl.text.isEmpty || _priceCtrl.text.isEmpty || _shortNameCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกข้อมูลที่จำเป็นให้ครบ'), backgroundColor: Colors.orange),
      );
      return;
    }

    final now = DateTime.now();
    final pkg = ConsultationPackage(
      id: widget.existing?.id ?? 'pkg_${now.millisecondsSinceEpoch}',
      name: _nameCtrl.text.trim(),
      shortName: _shortNameCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      price: double.tryParse(_priceCtrl.text) ?? 0.0,
      includesAI: _includesAI,
      isActive: _isActive,
      expertGroups: _expertGroups,
      displayOrder: widget.existing?.displayOrder ?? 999,
      sessionMinutes: int.tryParse(_sessionMinsCtrl.text) ?? 15,
      expireMinutes: int.tryParse(_expireMinsCtrl.text) ?? 120,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );

    widget.onSave(pkg);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${widget.existing == null ? "สร้าง" : "แก้ไข"}แพ็คเกจ "${pkg.shortName}" สำเร็จ'),
        backgroundColor: AppColors.success,
      ),
    );
  }
}

// ── AI Badge ─────────────────────────────────────────────────────────────────

class _AIBadge extends StatelessWidget {
  const _AIBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF7B2FF7), Color(0xFFDA44BB)]),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text('AI', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
    );
  }
}
