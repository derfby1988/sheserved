import 'package:flutter/material.dart';
import '../../../../shared/widgets/tlz_app_top_bar.dart';
import '../../../../shared/widgets/tlz_drawer.dart';
import 'medication_detail_page.dart';
import '../../../../services/service_locator.dart';
import '../../data/models/medication_models.dart';
import 'fda_search_page.dart';
import 'dart:async';

class PharmacyProductsPage extends StatefulWidget {
  const PharmacyProductsPage({super.key});

  @override
  State<PharmacyProductsPage> createState() => _PharmacyProductsPageState();
}

class _PharmacyProductsPageState extends State<PharmacyProductsPage> {
  bool _isGalleryView = true;
  bool _showFilter = false;
  
  bool _isLoading = true;
  String? _error;
  List<MedicationModel> _medications = [];

  int _currentPage = 1;
  static const int _pageSize = 20;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  final ScrollController _scrollController = ScrollController();

  // Filters State
  String? _searchQuery;
  String? _selectedCategoryId;
  double? _minPrice;
  double? _maxPrice;
  
  List<ProductCategoryModel> _categories = [];
  final TextEditingController _minPriceController = TextEditingController();
  final TextEditingController _maxPriceController = TextEditingController();
  
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchCategories();
    _fetchMedications();
  }

  Future<void> _fetchCategories() async {
    try {
      final repo = ServiceLocator.instance.pharmacyRepository;
      final categories = await repo.getCategories();
      if (mounted) {
        setState(() {
          _categories = categories;
        });
      }
    } catch (e) {
      debugPrint('Error loading categories: $e');
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMoreMedications();
    }
  }

  Future<void> _fetchMedications() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _currentPage = 1;
      _hasMore = true;
    });
    try {
      final repo = ServiceLocator.instance.pharmacyRepository;
      final userId = ServiceLocator.instance.currentUser?.id;
      final meds = await repo.getMedications(
        userId: userId, 
        page: _currentPage, 
        pageSize: _pageSize,
        searchQuery: _searchQuery,
        categoryId: _selectedCategoryId,
        minPrice: _minPrice,
        maxPrice: _maxPrice,
      );
      setState(() {
        _medications = meds;
        _isLoading = false;
        if (meds.length < _pageSize) {
          _hasMore = false;
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreMedications() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    
    setState(() {
      _isLoadingMore = true;
    });
    
    try {
      final repo = ServiceLocator.instance.pharmacyRepository;
      final userId = ServiceLocator.instance.currentUser?.id;
      final nextPage = _currentPage + 1;
      
      final moreMeds = await repo.getMedications(
        userId: userId, 
        page: nextPage, 
        pageSize: _pageSize,
        searchQuery: _searchQuery,
        categoryId: _selectedCategoryId,
        minPrice: _minPrice,
        maxPrice: _maxPrice,
      );
      
      setState(() {
        _currentPage = nextPage;
        if (moreMeds.length < _pageSize) {
          _hasMore = false;
        }
        _medications.addAll(moreMeds);
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF9EC43D), // สีเขียวพื้นหลังตามดีไซน์
      drawer: const TlzDrawer(),
      body: SafeArea(
        bottom: false, // เพื่อให้ส่วนที่กินไปด้านล่างได้เต็มที่
        child: Column(
          children: [
            // Top Bar
            TlzAppTopBar.onPrimary(
              notificationCount: 1,
              searchHintText: 'ค้นหาสินค้า...',
              onQRTap: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กำลังเปิดสแกน...')));
              },
              onSearch: (query, _) {
                if (_debounce?.isActive ?? false) _debounce!.cancel();
                _debounce = Timer(const Duration(milliseconds: 500), () {
                  setState(() {
                    _searchQuery = query.isEmpty ? null : query;
                    _currentPage = 1;
                    _hasMore = true;
                  });
                  _fetchMedications();
                });
              },
              onSearchSubmit: (query) {
                if (_debounce?.isActive ?? false) _debounce!.cancel();
                setState(() {
                  _searchQuery = query.isEmpty ? null : query;
                  _currentPage = 1;
                  _hasMore = true;
                });
                _fetchMedications(); // Refresh with new search
              },
              onNotificationTap: () {},
              onCartTap: () {},
            ),

            // Header Section (กันสาด & โลโก้ & แท็บ)
            _buildHeaderSection(),

            // Active Filters Section
            if (_selectedCategoryId != null || _minPrice != null || _maxPrice != null)
              _buildActiveFilters(),

            // Content Section
            Expanded(
              child: _showFilter
                  ? _buildFilterUI()
                  : (_isLoading
                      ? _buildSkeletonLoading()
                      : _error != null
                          ? Center(child: Text('เกิดข้อผิดพลาด: $_error', style: const TextStyle(color: Colors.white)))
                          : _medications.isEmpty
                              ? const Center(child: Text('ไม่มีข้อมูลยา', style: TextStyle(color: Colors.white, fontFamily: 'Sukhumvit Set')))
                              : Column(
                                  children: [
                                    Expanded(child: _isGalleryView ? _buildGalleryView() : _buildTagsView()),
                                    if (_isLoadingMore) 
                                      const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 16.0),
                                        child: CircularProgressIndicator(color: Colors.white),
                                      ),
                                  ],
                                )),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fda_search_btn',
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const FdaSearchPage()));
        },
        backgroundColor: Colors.white,
        icon: const Icon(Icons.verified, color: Colors.blue),
        label: const Text('ตรวจสอบบัญชียา อย.', style: TextStyle(color: Colors.blue, fontFamily: 'Sukhumvit Set', fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        // พื้นหลังเขียวและกันสาด
        Column(
          children: [
            // ช่องสำหรับให้กันสาดห้อย
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(4, (index) {
                return Container(
                  width: MediaQuery.of(context).size.width / 4,
                  height: 50,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(50),
                      bottomRight: Radius.circular(50),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),

        // วงกลม "ขายดีโปรโมชั่น" คร่อมกันสาด
        Positioned(
          top: 20,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(
              child: Text(
                'ขายดี\nโปรโมชั่น',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF58910F),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  fontFamily: 'Sukhumvit Set',
                ),
              ),
            ),
          ),
        ),

        // พื้นที่ดันสเปซสำหรับ Tabs และ Filter
        Container(
          height: 160,
          color: _showFilter ? Colors.white : Colors.transparent, // ถ้าโหมด Filter ให้พื้นหลังเริ่มขาว
        ),

        // ปุ่ม Tabs และ Filter (ลอยอยู่ด้านล่างของกล่อง Spacer)
        Positioned(
          bottom: 10,
          left: 16,
          right: 16,
          child: _showFilter 
            ? const SizedBox.shrink() // ถ้ากด Filter อาจจะซ่อนปุ่มแถบเดิม หรือวาง Filter ลอยไว้
            : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 48), // Spacer ชดเชยปุ่มฟิลเตอร์
                
                // กล่อง Gallery / Tags
                Expanded(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF8BAE32), // สีเขียวเข้มกว่าพื้นหลังนิดนึง
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFF58910F), width: 1),
                    ),
                    child: Row(
                      children: [
                        // Tab "Gallery"
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _isGalleryView = true;
                              _showFilter = false;
                            }),
                            child: Container(
                              decoration: BoxDecoration(
                                color: _isGalleryView
                                    ? const Color(0xFF58910F)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Center(
                                child: Text(
                                  'Gallery',
                                  style: TextStyle(
                                    color: _isGalleryView ? Colors.white : const Color(0xFFD6E3B5),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    fontFamily: 'Sukhumvit Set',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        
                        // Tab "Tags"
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _isGalleryView = false;
                              _showFilter = false;
                            }),
                            child: Container(
                              decoration: BoxDecoration(
                                color: !_isGalleryView
                                    ? const Color(0xFF58910F)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Center(
                                child: Text(
                                  'Tags',
                                  style: TextStyle(
                                    color: !_isGalleryView ? Colors.white : const Color(0xFFD6E3B5),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    fontFamily: 'Sukhumvit Set',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // ปุ่ม Filter
                GestureDetector(
                  onTap: () => setState(() => _showFilter = !_showFilter),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.filter_list,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
        ),

        // ปุ่มปิด Filter ลอยอยู่แทนกล่อง Tab เมื่อโหมด Filter ทำงาน
        if (_showFilter)
          Positioned(
            bottom: 15,
            right: 16,
            child: GestureDetector(
              onTap: () => setState(() => _showFilter = false),
              child: Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: Color(0xFF58910F), // เขียวเข้ม
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.filter_list_off,
                  color: Colors.white,
                ),
              ),
            ),
          )
      ],
    );
  }

  Widget _buildActiveFilters() {
    String? categoryName;
    if (_selectedCategoryId != null) {
      try {
        categoryName = _categories.firstWhere((cat) => cat.id == _selectedCategoryId).name;
      } catch (e) {
        categoryName = 'หมวดหมู่';
      }
    }

    String? priceRange;
    if (_minPrice != null || _maxPrice != null) {
      if (_minPrice != null && _maxPrice != null) priceRange = '${_minPrice!.toInt()}-${_maxPrice!.toInt()}฿';
      else if (_minPrice != null) priceRange = 'มากกว่า ${_minPrice!.toInt()}฿';
      else if (_maxPrice != null) priceRange = 'น้อยกว่า ${_maxPrice!.toInt()}฿';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: Colors.transparent,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (categoryName != null)
            Chip(
              label: Text(categoryName, style: const TextStyle(color: Colors.white, fontSize: 12)),
              backgroundColor: const Color(0xFF58910F),
              deleteIcon: const Icon(Icons.close, color: Colors.white, size: 16),
              onDeleted: () {
                setState(() {
                  _selectedCategoryId = null;
                  _currentPage = 1;
                  _hasMore = true;
                });
                _fetchMedications();
              },
            ),
          if (priceRange != null)
            Chip(
              label: Text(priceRange, style: const TextStyle(color: Colors.white, fontSize: 12)),
              backgroundColor: const Color(0xFF58910F),
              deleteIcon: const Icon(Icons.close, color: Colors.white, size: 16),
              onDeleted: () {
                setState(() {
                  _minPrice = null;
                  _maxPrice = null;
                  _minPriceController.clear();
                  _maxPriceController.clear();
                  _currentPage = 1;
                  _hasMore = true;
                });
                _fetchMedications();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSkeletonLoading() {
    return _isGalleryView ? _buildGallerySkeleton() : _buildTagsSkeleton();
  }

  Widget _buildGallerySkeleton() {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.62,
        crossAxisSpacing: 8,
        mainAxisSpacing: 12,
      ),
      itemCount: 12,
      itemBuilder: (context, index) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Container(height: 10, width: double.infinity, color: Colors.grey[300]),
                      Container(height: 10, width: 40, color: Colors.grey[300]),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(height: 12, width: 30, color: Colors.grey[300]),
                          Container(height: 16, width: 16, decoration: BoxDecoration(color: Colors.grey[300], shape: BoxShape.circle)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTagsSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          height: 160,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
                  ),
                ),
              ),
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 16, width: double.infinity, color: Colors.grey[300]),
                      const SizedBox(height: 8),
                      Container(height: 14, width: 100, color: Colors.grey[300]),
                      const Spacer(),
                      Row(
                        children: [
                          Container(height: 18, width: 50, color: Colors.grey[300]),
                          const Spacer(),
                          Container(height: 32, width: 80, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(8))),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGalleryView() {
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.62, // ปรับการยืดของการ์ดใน Grid (แนวตั้งยาวกว่าแนวนอน)
        crossAxisSpacing: 8,
        mainAxisSpacing: 12,
      ),
      itemCount: _medications.length,
      itemBuilder: (context, index) {
        final medication = _medications[index];
        final title = medication.tradeName;
        final category = medication.genericName ?? medication.dosageForm ?? 'ยา/เวชภัณฑ์';
        final price = medication.price ?? 0.00;
        final image = medication.imageUrl ?? 'https://placehold.co/150x200';
        
        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => MedicationDetailPage(medicationId: medication.id)),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF7F9EE), // สีพื้นหลังขาวขุ่น
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product Image
                Expanded(
                  flex: 3,
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                          image: DecorationImage(
                            image: NetworkImage(image),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Icon(
                          Icons.favorite,
                          color: index % 2 == 0 ? Colors.grey[400] : Colors.pink,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                // Details
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 10, fontFamily: 'Sukhumvit Set'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // ดาว
                        Row(
                          children: List.generate(5, (starIndex) => Icon(
                            Icons.star, 
                            color: starIndex < 4 ? Colors.amber : Colors.grey[300], 
                            size: 8,
                          )),
                        ),
                        // ราคา + ปุ่มรถเข็น
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$price บ.',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Sukhumvit Set'),
                            ),
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.grey,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.shopping_cart_outlined, color: Colors.white, size: 10),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTagsView() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      itemCount: _medications.length,
      itemBuilder: (context, index) {
        final medication = _medications[index];
        final title = medication.tradeName;
        final category = medication.genericName ?? medication.dosageForm ?? 'ยา/เวชภัณฑ์';
        final price = medication.price ?? 0.00;
        final rating = 5.0;
        final image = medication.imageUrl ?? 'https://placehold.co/150x200';

        return GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => MedicationDetailPage(medicationId: medication.id)),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            height: 160,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                // รูปด้านซ้าย
                Expanded(
                  flex: 4,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.blueAccent, // สีสมมติเพื่อแทนรูปถ่าย
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                      ),
                      image: DecorationImage(
                        image: NetworkImage(image),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                // บล็อกข้อมูลด้านขวาที่ซ้อนทับเข้ามา
                Expanded(
                  flex: 5,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF7F9EE),
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Sukhumvit Set'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.favorite_border, color: Colors.brown, size: 20),
                          ],
                        ),
                        Text(
                          category,
                          style: TextStyle(color: Colors.grey[500], fontSize: 14, fontFamily: 'Sukhumvit Set'),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Text(
                              rating.toString(),
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            const SizedBox(width: 4),
                            // ดาวเล็ก 1 ดวง
                            const Icon(Icons.star, color: Colors.amber, size: 14),
                            const Spacer(),
                            Text(
                              '$price บ.',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, fontFamily: 'Sukhumvit Set'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {},
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF58910F), // ปุ่มเขียวเข้ม
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text(
                              'ใส่ลงตะกร้า',
                              style: TextStyle(color: Colors.white, fontFamily: 'Sukhumvit Set'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterUI() {
    return Container(
      width: double.infinity,
      color: Colors.white, // ตามหน้าจอที่ 3 ที่เปลี่ยนเป็นพื้นหลังขาว
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // โชว์หมวดหมู่ที่ดึงมาจาก Database
                  if (_categories.isNotEmpty) ...[
                    const Text('หมวดหมู่', style: TextStyle(color: Color(0xFF58910F), fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _categories.map((cat) {
                        final isSelected = _selectedCategoryId == cat.id;
                        return ChoiceChip(
                          label: Text(cat.name, style: TextStyle(color: isSelected ? Colors.white : const Color(0xFF58910F))),
                          selected: isSelected,
                          selectedColor: const Color(0xFF58910F),
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: Color(0xFF58910F)),
                          onSelected: (selected) {
                            setState(() {
                              _selectedCategoryId = selected ? cat.id : null;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  const Text('ราคา', style: TextStyle(color: Color(0xFF58910F), fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _minPriceController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            hintText: 'ต่ำสุด',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text('-', style: TextStyle(color: Color(0xFF58910F), fontSize: 16)),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _maxPriceController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            hintText: 'สูงสุด',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.only(bottom: 24.0, top: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _selectedCategoryId = null;
                          _minPrice = null;
                          _maxPrice = null;
                          _minPriceController.clear();
                          _maxPriceController.clear();
                          _showFilter = false;
                          _currentPage = 1;
                          _hasMore = true;
                        });
                        _fetchMedications();
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF58910F)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                      ),
                      child: const Text('ล้างค่า', style: TextStyle(color: Color(0xFF58910F), fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _minPrice = double.tryParse(_minPriceController.text);
                          _maxPrice = double.tryParse(_maxPriceController.text);
                          _showFilter = false;
                          _currentPage = 1;
                          _hasMore = true;
                        });
                        _fetchMedications();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF58910F),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                      ),
                      child: const Text('ตกลง', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterIcon(IconData iconData, String title, {Color color = const Color(0xFF8BAE32)}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(iconData, color: color, size: 40),
        const SizedBox(height: 8),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFamily: 'Sukhumvit Set',
          ),
        ),
      ],
    );
  }
}
