import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../data/models/medication_models.dart';
import '../../../../services/service_locator.dart';
import 'fda_search_page.dart';
import 'dart:async';

class PharmacyCategoryMembersPage extends StatefulWidget {
  final ProductCategoryModel category;

  const PharmacyCategoryMembersPage({super.key, required this.category});

  @override
  State<PharmacyCategoryMembersPage> createState() => _PharmacyCategoryMembersPageState();
}

class _PharmacyCategoryMembersPageState extends State<PharmacyCategoryMembersPage> {
  bool _isLoading = true;
  String? _error;
  List<MedicationModel> _members = [];
  List<MedicationModel> _searchResults = [];
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repo = ServiceLocator.instance.pharmacyRepository;
      final members = await repo.getCategoryMembers(widget.category.id);
      setState(() {
        _members = members;
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

  Future<void> _searchMedications(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final repo = ServiceLocator.instance.pharmacyRepository;
      // TODO: Replace with an actual search endpoint/method if available, or fetch a chunk.
      // For now, assuming getMedications can handle search query
      final results = await repo.getMedications(searchQuery: query, page: 1, pageSize: 20);
      setState(() {
        _searchResults = results;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ค้นหาล้มเหลว: $e', style: const TextStyle(fontFamily: 'Sukhumvit Set'))));
      }
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  Future<void> _addMember(MedicationModel medication) async {
    try {
      final repo = ServiceLocator.instance.pharmacyRepository;
      await repo.addCategoryMember(widget.category.id, medication.id);
      _searchController.clear();
      setState(() {
        _searchResults = [];
      });
      _loadMembers();
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('เพิ่มยาลงในหมวดหมู่เรียบร้อย', style: TextStyle(fontFamily: 'Sukhumvit Set'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e', style: const TextStyle(fontFamily: 'Sukhumvit Set'))));
      }
    }
  }

  Future<void> _removeMember(MedicationModel medication) async {
    try {
      final repo = ServiceLocator.instance.pharmacyRepository;
      await repo.removeCategoryMember(widget.category.id, medication.id);
      _loadMembers();
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ลบยาออกจากหมวดหมู่เรียบร้อย', style: TextStyle(fontFamily: 'Sukhumvit Set'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e', style: const TextStyle(fontFamily: 'Sukhumvit Set'))));
      }
    }
  }


  void _showAddMemberDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Text('เพิ่มยาลงหมวดหมู่ "${widget.category.name}"', style: AppTextStyles.heading3.copyWith(color: AppColors.primary, fontFamily: 'Sukhumvit Set')),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        labelText: 'ค้นหาชื่อยา (Trade Name / Generic Name)',
                        prefixIcon: Icon(Icons.search),
                      ),
                      style: const TextStyle(fontFamily: 'Sukhumvit Set'),
                      onChanged: (value) {
                         if (_debounce?.isActive ?? false) _debounce!.cancel();
                         _debounce = Timer(const Duration(milliseconds: 500), () {
                            _searchMedications(value).then((_) {
                              if (mounted) setStateDialog(() {});
                            });
                         });
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_isSearching)
                      const CircularProgressIndicator()
                    else if (_searchController.text.isNotEmpty && _searchResults.isEmpty)
                      const Text('ไม่พบยาที่ค้นหา', style: const TextStyle(fontFamily: 'Sukhumvit Set'))
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final med = _searchResults[index];
                            final isAlreadyMember = _members.any((m) => m.id == med.id);
                            return ListTile(
                              title: Text(med.tradeName, style: const TextStyle(fontFamily: 'Sukhumvit Set', fontWeight: FontWeight.bold)),
                              subtitle: Text(med.genericName ?? 'ไม่ระบุชื่อสามัญ', style: const TextStyle(fontFamily: 'Sukhumvit Set', fontSize: 12)),
                              trailing: isAlreadyMember 
                                ? const Icon(Icons.check_circle, color: Colors.green)
                                : ElevatedButton(
                                  onPressed: () {
                                     Navigator.pop(context);
                                     _addMember(med);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4)
                                  ),
                                  child: const Text('เพิ่ม', style: TextStyle(color: Colors.white, fontFamily: 'Sukhumvit Set', fontSize: 12)),
                                ),
                            );
                          },
                        ),
                      )
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchResults = [];
                    });
                     Navigator.pop(context);
                  },
                  child: const Text('ปิด', style: TextStyle(color: Colors.grey, fontFamily: 'Sukhumvit Set')),
                ),
              ],
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('สมาชิกยา: ${widget.category.name}', style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Sukhumvit Set')),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_download, color: Colors.blue),
            tooltip: 'นำเข้าจากฐานข้อมูล อย.',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FdaSearchPage(targetCategory: widget.category),
                ),
              );
              _loadMembers(); // Refresh after returning
            },
          ),
        ],
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
        : _error != null
            ? Center(child: Text('เกิดข้อผิดพลาด: $_error', style: const TextStyle(color: Colors.red, fontFamily: 'Sukhumvit Set')))
            : _members.isEmpty 
                ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.medication, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      const Text('ยังไม่มียาในหมวดหมู่นี้', style: TextStyle(color: Colors.grey, fontFamily: 'Sukhumvit Set', fontSize: 16)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _showAddMemberDialog,
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text('เพิ่มยา', style: TextStyle(color: Colors.white, fontFamily: 'Sukhumvit Set')),
                         style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      )
                    ],
                  ),
                )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _members.length,
                    itemBuilder: (context, index) {
                      final med = _members[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(8),
                              image: med.imageUrl != null ? DecorationImage(
                                image: NetworkImage(med.imageUrl!),
                                fit: BoxFit.cover,
                              ) : null
                            ),
                            child: med.imageUrl == null ? const Icon(Icons.medication, color: Colors.grey) : null,
                          ),
                          title: Text(med.tradeName, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Sukhumvit Set')),
                          subtitle: Text(med.genericName ?? 'ไม่ระบุ', style: const TextStyle(fontFamily: 'Sukhumvit Set', color: Colors.grey)),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('ยืนยันการนำออก', style: TextStyle(fontFamily: 'Sukhumvit Set')),
                                  content: Text('คุณต้องการนำยา "${med.tradeName}" ออกจากหมวดหมู่ใช่หรือไม่?', style: const TextStyle(fontFamily: 'Sukhumvit Set')),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('ยกเลิก', style: TextStyle(fontFamily: 'Sukhumvit Set')),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        _removeMember(med);
                                      },
                                      child: const Text('นำออก', style: TextStyle(color: Colors.red, fontFamily: 'Sukhumvit Set')),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
      floatingActionButton: _members.isNotEmpty ? FloatingActionButton.extended(
        onPressed: _showAddMemberDialog,
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('เพิ่มยา', style: TextStyle(color: Colors.white, fontFamily: 'Sukhumvit Set')),
      ) : null,
    );
  }
}
