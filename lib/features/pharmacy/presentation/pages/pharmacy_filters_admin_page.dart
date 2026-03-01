import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../data/models/medication_models.dart';
import '../../../../services/service_locator.dart';
import 'pharmacy_category_members_page.dart';

class PharmacyFiltersAdminPage extends StatefulWidget {
  const PharmacyFiltersAdminPage({super.key});

  @override
  State<PharmacyFiltersAdminPage> createState() => _PharmacyFiltersAdminPageState();
}

class _PharmacyFiltersAdminPageState extends State<PharmacyFiltersAdminPage> {
  bool _isLoading = true;
  List<ProductCategoryModel> _categories = [];
  String? _error;

  // สำหรับรายการยาที่ยังไม่ถูกจับเข้า category (Unmapped)
  List<MedicationModel> _unmappedMedications = [];
  bool _isLoadingUnmapped = false;
  int _unmappedPage = 1;
  bool _hasMoreUnmapped = true;
  final ScrollController _unmappedScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadUnmappedMedications();

    _unmappedScrollController.addListener(() {
      if (_unmappedScrollController.position.pixels >= _unmappedScrollController.position.maxScrollExtent - 100 
          && !_isLoadingUnmapped && _hasMoreUnmapped) {
        _loadUnmappedMedications(loadMore: true);
      }
    });
  }

  @override
  void dispose() {
    _unmappedScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repo = ServiceLocator.instance.pharmacyRepository;
      final categories = await repo.getCategories();
      categories.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
      setState(() {
        _categories = categories;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUnmappedMedications({bool loadMore = false}) async {
    if (loadMore) {
      _unmappedPage++;
    } else {
      _unmappedPage = 1;
      _unmappedMedications.clear();
      _hasMoreUnmapped = true;
      _isLoadingUnmapped = true;
    }

    if (!mounted) return;
    setState(() {});

    try {
      final repo = ServiceLocator.instance.pharmacyRepository;
      final results = await repo.getUnmappedMedications(page: _unmappedPage, pageSize: 20);
      
      if (!mounted) return;
      setState(() {
        if (results.isEmpty) {
          _hasMoreUnmapped = false;
        } else {
          _unmappedMedications.addAll(results);
          if (results.length < 20) {
            _hasMoreUnmapped = false;
          }
        }
      });
    } catch (e) {
      debugPrint('Error loading unmapped meds: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingUnmapped = false;
        });
      }
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    setState(() {
      final item = _categories.removeAt(oldIndex);
      _categories.insert(newIndex, item);
      for (int i = 0; i < _categories.length; i++) {
        _categories[i] = _categories[i].copyWith(displayOrder: i);
      }
    });

    try {
      final repo = ServiceLocator.instance.pharmacyRepository;
      for (final cat in _categories) {
        await repo.saveCategory(cat);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกการจัดเรียงเรียบร้อย', style: TextStyle(fontFamily: 'Sukhumvit Set'))),
        );
      }
    } catch (e) {
      _loadCategories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการบันทึก: $e', style: const TextStyle(fontFamily: 'Sukhumvit Set'))),
        );
      }
    }
  }

  Future<void> _deleteCategory(String id) async {
    try {
      final repo = ServiceLocator.instance.pharmacyRepository;
      await repo.deleteCategory(id);
      _loadCategories();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการลบ: $e')),
        );
      }
    }
  }

  void _showCategoryDialog([ProductCategoryModel? category]) {
    final nameController = TextEditingController(text: category?.name ?? '');
    final typeController = TextEditingController(text: category?.type ?? 'CATEGORY');
    bool isActive = category?.isActive ?? true;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Text(
                category == null ? 'เพิ่มตัวกรองใหม่' : 'แก้ไขตัวกรอง',
                style: AppTextStyles.heading3.copyWith(color: AppColors.primary, fontFamily: 'Sukhumvit Set'),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'ชื่อตัวกรอง (เช่น ยาอันตราย)'),
                      style: const TextStyle(fontFamily: 'Sukhumvit Set'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: typeController,
                      decoration: const InputDecoration(labelText: 'ประเภท (CATEGORY, TAG, PRICE_RANGE)'),
                      style: const TextStyle(fontFamily: 'Sukhumvit Set'),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('เปิดใช้งาน', style: TextStyle(fontFamily: 'Sukhumvit Set')),
                      value: isActive,
                      onChanged: (val) {
                        setStateDialog(() {
                          isActive = val;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey, fontFamily: 'Sukhumvit Set')),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('กรุณากรอกชื่อตัวกรอง', style: TextStyle(fontFamily: 'Sukhumvit Set'))),
                      );
                      return;
                    }
                    Navigator.pop(context);
                    
                    final newCategory = ProductCategoryModel(
                      id: category?.id ?? 'new_${DateTime.now().millisecondsSinceEpoch}',
                      name: nameController.text.trim(),
                      type: typeController.text.trim().isEmpty ? 'CATEGORY' : typeController.text.trim(),
                      displayOrder: category?.displayOrder ?? _categories.length,
                      isActive: isActive,
                    );

                    try {
                      final repo = ServiceLocator.instance.pharmacyRepository;
                      await repo.saveCategory(newCategory);
                      _loadCategories();
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('เกิดข้อผิดพลาด: $e', style: const TextStyle(fontFamily: 'Sukhumvit Set'))),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('บันทึก', style: TextStyle(color: Colors.white, fontFamily: 'Sukhumvit Set')),
                ),
              ],
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('จัดการตัวกรองยา & ความงาม', style: TextStyle(color: AppColors.textPrimary)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: Column(
        children: [
          // Section 1: Categories
          Expanded(
            flex: 2,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _error != null
                    ? Center(child: Text('เกิดข้อผิดพลาด: $_error', style: const TextStyle(color: Colors.red)))
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.all(16),
                  onReorder: _onReorder,
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    return Card(
                      key: ValueKey(cat.id),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      color: cat.isActive ? Colors.white : Colors.grey[200],
                      elevation: cat.isActive ? 1 : 0,
                      child: ListTile(
                        leading: const Icon(Icons.drag_handle, color: Colors.grey),
                        title: Text(
                          cat.name, 
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            decoration: cat.isActive ? TextDecoration.none : TextDecoration.lineThrough,
                            color: cat.isActive ? Colors.black : Colors.grey[600],
                            fontFamily: 'Sukhumvit Set',
                          ),
                        ),
                        subtitle: Text(
                          'Type: ${cat.type} | Order: ${cat.displayOrder}${!cat.isActive ? ' (ปิดใช้งาน)' : ''}',
                          style: TextStyle(
                            fontFamily: 'Sukhumvit Set',
                            color: cat.isActive ? Colors.grey[600] : Colors.grey[500],
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.people, color: Colors.blue), // เปลี่ยนไอคอนตามความเหมาะสม
                              tooltip: 'เรียกดูสมาชิกยา',
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => PharmacyCategoryMembersPage(category: cat),
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, color: AppColors.primary),
                              onPressed: () => _showCategoryDialog(cat),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('ยืนยันการลบ', style: TextStyle(fontFamily: 'Sukhumvit Set')),
                                    content: Text('คุณต้องการลบตัวกรอง "${cat.name}" ใช่หรือไม่?', style: const TextStyle(fontFamily: 'Sukhumvit Set')),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('ยกเลิก', style: TextStyle(fontFamily: 'Sukhumvit Set')),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          _deleteCategory(cat.id);
                                        },
                                        child: const Text('ลบ', style: TextStyle(color: Colors.red, fontFamily: 'Sukhumvit Set')),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ),
          
          // Section 2: Unmapped Medications
          if (_unmappedMedications.isNotEmpty || _isLoadingUnmapped)
            Container(
              height: 280, // กำหนดความสูงของพื้นที่นี้ให้มี Scrollbar ของตัวเอง
              decoration: const BoxDecoration(
                color: Color(0xFFF9FAFB),
                border: Border(top: BorderSide(color: Colors.black12, width: 1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'ยาและสินค้าที่ยังไม่ได้จัดหมวดหมู่',
                          style: TextStyle(fontFamily: 'Sukhumvit Set', fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          '${_unmappedMedications.length} รายการ',
                          style: const TextStyle(fontFamily: 'Sukhumvit Set', color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: _unmappedScrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _unmappedMedications.length + (_hasMoreUnmapped ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _unmappedMedications.length) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: CircularProgressIndicator(color: AppColors.primary),
                            ),
                          );
                        }

                        final med = _unmappedMedications[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            title: Text(med.tradeName, style: const TextStyle(fontFamily: 'Sukhumvit Set', fontWeight: FontWeight.bold)),
                            subtitle: Text(
                              '${med.genericName ?? "ไม่ระบุชื่อสามัญ"} | สถานะ: ${med.fdaRiskStatus ?? "-"}', 
                              style: const TextStyle(fontFamily: 'Sukhumvit Set', fontSize: 12)
                            ),
                            trailing: ElevatedButton(
                              onPressed: () => _showMappingDialog(med),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('จัดหมวด', style: TextStyle(color: Colors.white, fontFamily: 'Sukhumvit Set', fontSize: 12)),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCategoryDialog(),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showMappingDialog(MedicationModel med) {
    if (_categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณาสร้างหมวดหมู่ก่อน')));
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('เลือกหมวดหมู่ให้ "${med.tradeName}"', style: const TextStyle(fontFamily: 'Sukhumvit Set', fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                return ListTile(
                  title: Text(cat.name, style: const TextStyle(fontFamily: 'Sukhumvit Set')),
                  onTap: () async {
                    Navigator.pop(context);
                    // Add mapping
                    try {
                      final repo = ServiceLocator.instance.pharmacyRepository;
                      await repo.addCategoryMember(cat.id, med.id);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('เพิ่มยาลงหมวดหมู่ "${cat.name}" แล้ว', style: const TextStyle(fontFamily: 'Sukhumvit Set'))),
                        );
                      }
                      // Refresh unmapped list and categories
                      _loadUnmappedMedications();
                      _loadCategories();
                    } catch (e) {
                      if (mounted) {
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
                      }
                    }
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey, fontFamily: 'Sukhumvit Set')),
            ),
          ],
        );
      }
    );
  }
}
