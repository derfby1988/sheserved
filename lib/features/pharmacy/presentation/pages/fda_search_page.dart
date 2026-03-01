import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../data/models/medication_models.dart';
import '../../../../services/service_locator.dart';
import '../../data/services/fda_api_service.dart';

class FdaSearchPage extends StatefulWidget {
  final ProductCategoryModel? targetCategory; // ถ้ามี แปลว่าเป็นการนำเข้าโดยแอดมิน เพื่อจับยัดเข้า Category อัตโนมัติ

  const FdaSearchPage({super.key, this.targetCategory});

  @override
  State<FdaSearchPage> createState() => _FdaSearchPageState();
}

class _FdaSearchPageState extends State<FdaSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _results = []; // Can be FdaDrugModel or MedicationModel
  bool _isLoading = false;
  String? _error;
  Timer? _debounce;
  bool _isMasterDataMode = true; // Default to Master Data for speed

  // Selection & Filters
  final Set<dynamic> _selectedDrugs = {};
  String? _selectedClassFilter;
  String? _selectedKindFilter;

  @override
  void initState() {
    super.initState();
    if (widget.targetCategory != null && widget.targetCategory!.name.isNotEmpty) {
      _searchController.text = widget.targetCategory!.name;
      // Start with Master Data mode enabled
      _isMasterDataMode = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performSearch(widget.targetCategory!.name);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    if (query.trim().isEmpty) {
       setState(() {
         _results = [];
         _selectedDrugs.clear();
         _error = null;
         _selectedClassFilter = null;
         _selectedKindFilter = null;
       });
       return;
    }
    
    _debounce = Timer(const Duration(milliseconds: 800), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _results = [];
      _selectedDrugs.clear();
      _selectedClassFilter = null;
      _selectedKindFilter = null;
    });

    try {
       if (_isMasterDataMode) {
         final repo = ServiceLocator.instance.pharmacyRepository;
         final res = await repo.searchMasterMedications(query);
         setState(() => _results = res);
       } else {
         final apiService = ServiceLocator.instance.fdaApiService;
         final res = await apiService.searchDrugs(query);
         setState(() => _results = res);
       }
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

  Future<void> _importDrug(dynamic drug) async {
    if (widget.targetCategory == null) return;
    
    try {
      final repo = ServiceLocator.instance.pharmacyRepository;
      String name = "";
      if (drug is FdaDrugModel) {
        await repo.importDrugFromFda(drug, widget.targetCategory?.id);
        name = drug.productNameThai.isNotEmpty ? drug.productNameThai : drug.productNameEng;
      } else if (drug is MedicationModel) {
        if (widget.targetCategory?.id != null) {
          await repo.addCategoryMember(widget.targetCategory!.id, drug.id);
        }
        name = drug.tradeName;
      }
       
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('นำเข้า "$name" สำเร็จ!', style: const TextStyle(fontFamily: 'Sukhumvit Set'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('นำเข้าล้มเหลว: $e', style: const TextStyle(fontFamily: 'Sukhumvit Set'))),
        );
      }
    }
  }

  Future<void> _importSelectedDrugs() async {
    if (_selectedDrugs.isEmpty || widget.targetCategory == null) return;

    final drugsToImport = _selectedDrugs.toList();
    setState(() => _isLoading = true);

    int successCount = 0;
    int failCount = 0;

    for (var drug in drugsToImport) {
      try {
        final repo = ServiceLocator.instance.pharmacyRepository;
        if (drug is FdaDrugModel) {
          await repo.importDrugFromFda(drug, widget.targetCategory?.id);
        } else if (drug is MedicationModel) {
          if (widget.targetCategory?.id != null) {
            await repo.addCategoryMember(widget.targetCategory!.id, drug.id);
          }
        }
        successCount++;
      } catch (e) {
        failCount++;
      }
    }

    setState(() {
      _isLoading = false;
      _selectedDrugs.clear();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('นำเข้าสำเร็จ $successCount รายการ${failCount > 0 ? ", ล้มเหลว $failCount รายการ" : ""}', 
            style: const TextStyle(fontFamily: 'Sukhumvit Set')),
          backgroundColor: failCount > 0 ? Colors.orange : Colors.green,
        ),
      );
    }
  }

  List<dynamic> get _filteredResults {
    return _results.where((r) {
      if (r is FdaDrugModel) {
        final matchClass = _selectedClassFilter == null || r.categoryThai == _selectedClassFilter;
        final matchKind = _selectedKindFilter == null || r.riskStatusThai == _selectedKindFilter;
        return matchClass && matchKind;
      }
      // For MedicationModel, we don't have these filters yet from FDA, 
      // but we could filter by source_type if needed. For now, show all.
      return true;
    }).toList();
  }

  void _selectAll(List<dynamic> items) {
    setState(() {
      for (var item in items) {
        // Only select if not already mapped
        bool alreadyMapped = false;
        if (item is MedicationModel && widget.targetCategory != null && item.categories != null) {
          alreadyMapped = item.categories!.any((c) => c.id == widget.targetCategory!.id);
        }
        
        if (!alreadyMapped) {
          _selectedDrugs.add(item);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAdminMode = widget.targetCategory != null;
    final filtered = _filteredResults;
    
    // รายการหมวดหมู่มาตรฐานของ อย. เพื่อให้แอดมินเลือกดึงได้ง่ายขึ้น
    final List<String> commonClasses = ['ยาใช้ภายใน', 'ยาใช้ภายนอก', 'ยาใช้เฉพาะที่', 'ยาสำหรับสัตว์'];
    final List<String> commonKinds = ['ยาสามัญประจำบ้าน', 'ยาอันตราย', 'ยาควบคุมพิเศษ', 'ยาที่ไม่ใช่ยาอันตรายหรือยาควบคุมพิเศษ'];

    // รวบรวมหมวดหมู่เพิ่มจากผลการค้นหาจริง (ถ้ามีเฉพาะกรณี FDA)
    final Set<String> classOptions = {
      ...commonClasses, 
      ..._results.whereType<FdaDrugModel>().map((e) => e.categoryThai).where((e) => e.isNotEmpty)
    };
    final Set<String> kindOptions = {
      ...commonKinds, 
      ..._results.whereType<FdaDrugModel>().map((e) => e.riskStatusThai).where((e) => e.isNotEmpty)
    };

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isMasterDataMode ? 'ค้นหาฐานข้อมูล Master' : 'ค้นหาฐานข้อมูล อย. (Live)', 
              style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Sukhumvit Set', fontSize: 18)),
            if (isAdminMode) Text('เป้าหมาย: ${widget.targetCategory!.name}', style: const TextStyle(color: Colors.grey, fontSize: 12, fontFamily: 'Sukhumvit Set')),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          if (isAdminMode && _selectedDrugs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton.icon(
                onPressed: _isLoading ? null : _importSelectedDrugs,
                icon: const Icon(Icons.cloud_download, color: AppColors.primary),
                label: Text('นำเข้า (${_selectedDrugs.length})', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontFamily: 'Sukhumvit Set')),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Box - แสดงตลอดเวลา
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
            ),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'พิมพ์ชื่อยา หรือทะเบียน...',
                    hintStyle: const TextStyle(fontFamily: 'Sukhumvit Set'),
                    prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    suffixIcon: _searchController.text.isNotEmpty 
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18), 
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          }
                        ) 
                      : null,
                  ),
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildSourceToggle(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: _buildFilterDropdown(
                        value: _selectedClassFilter,
                        hint: 'ตัวเลือก: กลุ่ม',
                        items: classOptions.toList(),
                        onChanged: (val) {
                          setState(() => _selectedClassFilter = val);
                        },
                      ),
                    ),
                  ],
                ),
                if (filtered.isNotEmpty) 
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('พบ ${filtered.length} รายการ', style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'Sukhumvit Set')),
                        TextButton.icon(
                          onPressed: () => _selectAll(filtered),
                          icon: const Icon(Icons.select_all, size: 16),
                          label: const Text('เลือกทั้งหมด', style: TextStyle(fontSize: 12, fontFamily: 'Sukhumvit Set')),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _error != null
                 ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red, fontFamily: 'Sukhumvit Set')))
                 : filtered.isEmpty && _searchController.text.isNotEmpty
                     ? Center(
                         child: Column(
                           mainAxisSize: MainAxisSize.min,
                           children: [
                             const Icon(Icons.search_off, size: 64, color: Colors.grey),
                             const SizedBox(height: 16),
                             const Text('ไม่พบรายการที่ตรงเงื่อนไข', style: TextStyle(color: Colors.grey, fontFamily: 'Sukhumvit Set')),
                           ],
                         )
                       )
                     : _results.isEmpty
                         ? Center(
                             child: Column(
                               mainAxisSize: MainAxisSize.min,
                               children: [
                                  Icon(Icons.hub_outlined, size: 64, color: Colors.grey[300]),
                                  const SizedBox(height: 16),
                                  const Text('เลือกหมวดหมู่ด้านบนหรือพิมพ์เพื่อค้นหา', style: TextStyle(color: Colors.grey, fontFamily: 'Sukhumvit Set')),
                               ],
                             )
                           )
                         : ListView.builder(
                             padding: const EdgeInsets.only(top: 8, bottom: 80),
                             itemCount: filtered.length,
                             itemBuilder: (context, index) {
                               final r = filtered[index];
                               final isSelected = _selectedDrugs.contains(r);
                               String title = "";
                               String subtitle = "";
                               String status = "ACTIVE";
                               String license = "-";
                               String manufacturer = "-";
                               bool alreadyMapped = false;
                               
                               if (r is FdaDrugModel) {
                                 title = r.productNameThai.isEmpty ? r.productNameEng : r.productNameThai;
                                 subtitle = r.productNameEng;
                                 status = r.registrationStatus;
                                 license = r.licenseNo;
                                 manufacturer = r.manufacturer;
                               } else if (r is MedicationModel) {
                                 title = r.tradeName;
                                 subtitle = r.genericName ?? "";
                                 status = r.status;
                                 license = r.referenceCode ?? "-";
                                 manufacturer = r.manufacturer ?? "-";
                                 // Check if already in target category
                                 if (widget.targetCategory != null && r.categories != null) {
                                   alreadyMapped = r.categories!.any((c) => c.id == widget.targetCategory!.id);
                                 }
                               }

                               final isCancelled = status.contains('ยกเลิก');

                               return Container(
                                 margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                 decoration: BoxDecoration(
                                   color: isSelected ? AppColors.primary.withOpacity(0.05) : Colors.white,
                                   borderRadius: BorderRadius.circular(16),
                                   border: isSelected ? Border.all(color: AppColors.primary, width: 2) : Border.all(color: Colors.transparent),
                                   boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                                 ),
                                 child: CheckboxListTile(
                                   value: isSelected,
                                   activeColor: AppColors.primary,
                                   onChanged: isAdminMode && !alreadyMapped ? (val) {
                                     setState(() {
                                       if (val == true) _selectedDrugs.add(r);
                                       else _selectedDrugs.remove(r);
                                     });
                                   } : null,
                                   title: Row(
                                     children: [
                                       Expanded(
                                         child: Text(title, 
                                           style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Sukhumvit Set', fontSize: 15)),
                                       ),
                                       if (alreadyMapped)
                                         const Padding(
                                           padding: EdgeInsets.only(left: 4.0),
                                           child: Icon(Icons.check_circle, color: Colors.green, size: 16),
                                         ),
                                       const SizedBox(width: 4),
                                       Container(
                                         padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                         decoration: BoxDecoration(
                                           color: isCancelled ? Colors.red[50] : Colors.green[50],
                                           borderRadius: BorderRadius.circular(8),
                                         ),
                                         child: Text(status, 
                                           style: TextStyle(color: isCancelled ? Colors.red : Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                                       ),
                                     ],
                                   ),
                                   subtitle: Column(
                                     crossAxisAlignment: CrossAxisAlignment.start,
                                     children: [
                                       const SizedBox(height: 4),
                                       if (subtitle.isNotEmpty) Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
                                       const SizedBox(height: 2),
                                       Text(r is MedicationModel ? 'Source: Local' : 'Source: FDA API', style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.bold)),
                                       Text('ทะเบียน: $license', style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold, fontSize: 12)),
                                       Text('บริษัท: $manufacturer', style: const TextStyle(color: Colors.grey, fontSize: 11, fontFamily: 'Sukhumvit Set')),
                                     ],
                                   ),
                                   secondary: alreadyMapped ? const Icon(Icons.lock, color: Colors.grey, size: 20) : null,
                                 ),
                               );
                             },
                           )
          )
        ],
      )
    );
  }

  Widget _buildSourceToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _isMasterDataMode = true);
                if (_searchController.text.isNotEmpty) _performSearch(_searchController.text);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _isMasterDataMode ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text('Master', 
                    style: TextStyle(color: _isMasterDataMode ? Colors.white : AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _isMasterDataMode = false);
                if (_searchController.text.isNotEmpty) _performSearch(_searchController.text);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: !_isMasterDataMode ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text('FDA Live', 
                    style: TextStyle(color: !_isMasterDataMode ? Colors.white : AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String? value,
    required String hint,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(hint, style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'Sukhumvit Set')),
          isExpanded: true,
          items: [
            DropdownMenuItem<String>(value: null, child: Text('ทั้งหมด $hint', style: const TextStyle(fontSize: 12, fontFamily: 'Sukhumvit Set'))),
            ...items.map((item) => DropdownMenuItem(value: item, child: Text(item, style: const TextStyle(fontSize: 12, fontFamily: 'Sukhumvit Set')))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
