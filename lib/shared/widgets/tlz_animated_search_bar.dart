import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';

/// Animated Search Bar Color Theme
enum TlzSearchTheme {
  /// สำหรับพื้นหลังสีเข้ม (primary green)
  onPrimary,
  /// สำหรับพื้นหลังสีอ่อน (white/light)
  onLight,
}

/// Animated Search Bar Widget
/// - แสดงเป็น search bar ปกติเมื่อยังไม่ได้กด
/// - เมื่อกดจะแสดง overlay พร้อมช่องค้นหาและผลลัพธ์
/// - รองรับหลายธีมสี
class TlzAnimatedSearchBar extends StatefulWidget {
  final String? hintText;
  final TlzSearchTheme theme;
  final VoidCallback? onQRTap;
  final bool showQRButton;
  final List<String>? searchHistory;
  final List<Map<String, dynamic>>? suggestions;
  final Function(String query, List<Map<String, dynamic>> results)? onSearch;
  final Function(Map<String, dynamic> item)? onResultTap;

  const TlzAnimatedSearchBar({
    super.key,
    this.hintText,
    this.theme = TlzSearchTheme.onPrimary,
    this.onQRTap,
    this.showQRButton = true,
    this.searchHistory,
    this.suggestions,
    this.onSearch,
    this.onResultTap,
  });

  /// Factory สำหรับพื้นหลังสีเข้ม
  factory TlzAnimatedSearchBar.onPrimary({
    Key? key,
    String? hintText,
    VoidCallback? onQRTap,
    bool showQRButton = true,
    List<String>? searchHistory,
    List<Map<String, dynamic>>? suggestions,
    Function(String query, List<Map<String, dynamic>> results)? onSearch,
    Function(Map<String, dynamic> item)? onResultTap,
  }) {
    return TlzAnimatedSearchBar(
      key: key,
      hintText: hintText,
      theme: TlzSearchTheme.onPrimary,
      onQRTap: onQRTap,
      showQRButton: showQRButton,
      searchHistory: searchHistory,
      suggestions: suggestions,
      onSearch: onSearch,
      onResultTap: onResultTap,
    );
  }

  /// Factory สำหรับพื้นหลังสีอ่อน
  factory TlzAnimatedSearchBar.onLight({
    Key? key,
    String? hintText,
    VoidCallback? onQRTap,
    bool showQRButton = true,
    List<String>? searchHistory,
    List<Map<String, dynamic>>? suggestions,
    Function(String query, List<Map<String, dynamic>> results)? onSearch,
    Function(Map<String, dynamic> item)? onResultTap,
  }) {
    return TlzAnimatedSearchBar(
      key: key,
      hintText: hintText,
      theme: TlzSearchTheme.onLight,
      onQRTap: onQRTap,
      showQRButton: showQRButton,
      searchHistory: searchHistory,
      suggestions: suggestions,
      onSearch: onSearch,
      onResultTap: onResultTap,
    );
  }

  @override
  State<TlzAnimatedSearchBar> createState() => _TlzAnimatedSearchBarState();
}

class _TlzAnimatedSearchBarState extends State<TlzAnimatedSearchBar>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _searchBarKey = GlobalKey();

  // Colors based on theme
  Color get _backgroundColor => widget.theme == TlzSearchTheme.onPrimary
      ? AppColors.primaryLight.withOpacity(0.3)
      : AppColors.surface;

  Color get _iconColor => widget.theme == TlzSearchTheme.onPrimary
      ? AppColors.textOnPrimary
      : AppColors.textSecondary;

  Color get _hintColor => widget.theme == TlzSearchTheme.onPrimary
      ? AppColors.textOnPrimary.withOpacity(0.6)
      : AppColors.textHint;

  Color get _borderColor => widget.theme == TlzSearchTheme.onPrimary
      ? AppColors.textOnPrimary.withOpacity(0.1)
      : AppColors.border;

  void _showSearchOverlay() {
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideSearchOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _createOverlayEntry() {
    return OverlayEntry(
      builder: (context) => _SearchOverlay(
        layerLink: _layerLink,
        hintText: widget.hintText ?? 'ค้นหา...',
        searchHistory: widget.searchHistory ?? _defaultSearchHistory,
        suggestions: widget.suggestions ?? _defaultSuggestions,
        onClose: _hideSearchOverlay,
        onSearch: widget.onSearch,
        onResultTap: widget.onResultTap,
      ),
    );
  }

  // Default mock data
  List<String> get _defaultSearchHistory => [
    'พาราเซตามอล',
    'ร้านยาใกล้ฉัน',
    'หมอผิวหนัง',
  ];

  List<Map<String, dynamic>> get _defaultSuggestions => [
    {'icon': Icons.local_pharmacy, 'title': 'ร้านยา', 'subtitle': 'ค้นหาร้านยาใกล้คุณ'},
    {'icon': Icons.medical_services, 'title': 'ปรึกษาแพทย์', 'subtitle': 'พบแพทย์ออนไลน์'},
    {'icon': Icons.spa, 'title': 'นวดสปา', 'subtitle': 'บริการนวดและสปา'},
  ];

  @override
  void dispose() {
    _hideSearchOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        key: _searchBarKey,
        onTap: _showSearchOverlay,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: _backgroundColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _borderColor, width: 1),
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Icon(Icons.search, color: _iconColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.hintText ?? 'ค้นหา...',
                  style: TextStyle(color: _hintColor, fontSize: 14),
                ),
              ),
              if (widget.showQRButton)
                GestureDetector(
                  onTap: widget.onQRTap,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Icon(Icons.qr_code_scanner, color: _iconColor, size: 20),
                  ),
                ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Search Overlay - แสดงเมื่อกดที่ search bar
class _SearchOverlay extends StatefulWidget {
  final LayerLink layerLink;
  final String hintText;
  final List<String> searchHistory;
  final List<Map<String, dynamic>> suggestions;
  final VoidCallback onClose;
  final Function(String query, List<Map<String, dynamic>> results)? onSearch;
  final Function(Map<String, dynamic> item)? onResultTap;

  const _SearchOverlay({
    required this.layerLink,
    required this.hintText,
    required this.searchHistory,
    required this.suggestions,
    required this.onClose,
    this.onSearch,
    this.onResultTap,
  });

  @override
  State<_SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<_SearchOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  
  String _query = '';
  List<Map<String, dynamic>> _searchResults = [];
  List<String> _localHistory = [];

  @override
  void initState() {
    super.initState();
    _localHistory = List.from(widget.searchHistory);
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();

    // Auto focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _query = value;
      if (value.isNotEmpty) {
        _searchResults = _generateMockResults(value);
      } else {
        _searchResults = [];
      }
    });

    // Callback
    if (widget.onSearch != null) {
      widget.onSearch!(_query, _searchResults);
    }
  }

  void _onSearchSubmitted(String value) {
    if (value.isNotEmpty && !_localHistory.contains(value)) {
      setState(() {
        _localHistory.insert(0, value);
        if (_localHistory.length > 10) {
          _localHistory.removeLast();
        }
      });
    }
  }

  List<Map<String, dynamic>> _generateMockResults(String query) {
    final lowerQuery = query.toLowerCase();
    final allResults = [
      {'type': 'pharmacy', 'icon': Icons.local_pharmacy, 'title': 'ร้านยา เภสัชกรเอก', 'subtitle': 'ห่างจากคุณ 500 เมตร', 'rating': 4.8},
      {'type': 'pharmacy', 'icon': Icons.local_pharmacy, 'title': 'ร้านยา ฟาสซิโน', 'subtitle': 'ห่างจากคุณ 1.2 กม.', 'rating': 4.5},
      {'type': 'doctor', 'icon': Icons.person, 'title': 'นพ.สมชาย ใจดี', 'subtitle': 'อายุรกรรม • พร้อมให้บริการ', 'rating': 4.9},
      {'type': 'medicine', 'icon': Icons.medication, 'title': 'พาราเซตามอล 500mg', 'subtitle': 'ยาแก้ปวด ลดไข้', 'price': '฿35'},
      {'type': 'medicine', 'icon': Icons.medication, 'title': 'วิตามินซี 1000mg', 'subtitle': 'เสริมภูมิคุ้มกัน', 'price': '฿120'},
      {'type': 'clinic', 'icon': Icons.local_hospital, 'title': 'คลินิกหมอสุข', 'subtitle': 'เปิด 09:00-20:00', 'rating': 4.7},
    ];

    return allResults
        .where((item) =>
            item['title'].toString().toLowerCase().contains(lowerQuery) ||
            item['subtitle'].toString().toLowerCase().contains(lowerQuery) ||
            item['type'].toString().toLowerCase().contains(lowerQuery))
        .toList();
  }

  void _selectHistoryItem(String item) {
    _searchController.text = item;
    _onSearchChanged(item);
  }

  void _removeHistoryItem(String item) {
    setState(() {
      _localHistory.remove(item);
    });
  }

  void _clearAllHistory() {
    setState(() {
      _localHistory.clear();
    });
  }

  void _close() async {
    await _animationController.reverse();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              // Background overlay
              GestureDetector(
                onTap: _close,
                child: Container(
                  color: Colors.black.withOpacity(0.5 * _fadeAnimation.value),
                ),
              ),

              // Search panel
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    alignment: Alignment.topCenter,
                    child: _buildSearchPanel(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchPanel() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                // Glass effect - โปร่งใสแบบแก้ว
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.5),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Search input row
                  _buildSearchInput(),

                  // Divider - glass style
                  Container(
                    height: 1,
                    color: Colors.grey.withOpacity(0.2),
                  ),

                  // Content (history, suggestions, or results)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.6,
                    ),
                    child: _buildContent(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchInput() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Back button - glass style
          GestureDetector(
            onTap: _close,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.grey.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.arrow_back,
                color: AppColors.textPrimary.withOpacity(0.8),
                size: 20,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Search field - glass style
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.grey.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Icon(Icons.search, color: AppColors.textSecondary.withOpacity(0.7), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _focusNode,
                      onChanged: _onSearchChanged,
                      onSubmitted: _onSearchSubmitted,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: widget.hintText,
                        hintStyle: TextStyle(
                          color: AppColors.textHint,
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                    ),
                  ),
                  if (_query.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Icon(
                          Icons.close,
                          color: AppColors.textHint,
                          size: 18,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_query.isNotEmpty && _searchResults.isNotEmpty) {
      return _buildSearchResults();
    } else if (_query.isNotEmpty && _searchResults.isEmpty) {
      return _buildNoResults();
    } else {
      return _buildDefaultContent();
    }
  }

  Widget _buildDefaultContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // History
          if (_localHistory.isNotEmpty) ...[
            _buildSectionHeader('ประวัติการค้นหา', onClear: _clearAllHistory),
            const SizedBox(height: 12),
            _buildHistoryChips(),
            const SizedBox(height: 20),
          ],

          // Suggestions
          _buildSectionHeader('แนะนำสำหรับคุณ'),
          const SizedBox(height: 12),
          ...widget.suggestions.map((item) => _buildSuggestionItem(item)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {VoidCallback? onClear}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: AppTextStyles.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        if (onClear != null)
          GestureDetector(
            onTap: onClear,
            child: Text(
              'ล้างทั้งหมด',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHistoryChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _localHistory.map((item) {
        return GestureDetector(
          onTap: () => _selectHistoryItem(item),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  item,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _removeHistoryItem(item),
                  child: Icon(Icons.close, size: 12, color: AppColors.textHint),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSuggestionItem(Map<String, dynamic> item) {
    return GestureDetector(
      onTap: () {
        _searchController.text = item['title'] as String;
        _onSearchChanged(item['title'] as String);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                item['icon'] as IconData,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['title'] as String,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    item['subtitle'] as String,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      shrinkWrap: true,
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final item = _searchResults[index];
        return _buildResultItem(item);
      },
    );
  }

  Widget _buildResultItem(Map<String, dynamic> item) {
    return GestureDetector(
      onTap: () {
        if (widget.onResultTap != null) {
          widget.onResultTap!(item);
        }
        _close();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _getTypeColor(item['type'] as String).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                item['icon'] as IconData,
                color: _getTypeColor(item['type'] as String),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['title'] as String,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item['subtitle'] as String,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (item['rating'] != null)
              Row(
                children: [
                  const Icon(Icons.star, size: 14, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text(
                    item['rating'].toString(),
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            else if (item['price'] != null)
              Text(
                item['price'] as String,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'pharmacy':
        return AppColors.primary;
      case 'doctor':
        return Colors.blue;
      case 'medicine':
        return Colors.orange;
      case 'clinic':
        return Colors.purple;
      default:
        return AppColors.primary;
    }
  }

  Widget _buildNoResults() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 48, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text(
            'ไม่พบผลการค้นหา',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'ลองค้นหาด้วยคำอื่น',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }
}
