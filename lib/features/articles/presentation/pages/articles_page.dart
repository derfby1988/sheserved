import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../shared/widgets/widgets.dart';
import 'package:sheserved/services/service_locator.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/features/health/data/models/health_article_models.dart';
import 'package:sheserved/features/health/presentation/pages/health_article_page.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:sheserved/services/supabase_service.dart';
import 'dart:typed_data';

// ── Theme Colors ──
const Color _blue = Color(0xFF2563EB);
const Color _blueDark = Color(0xFF1E40AF);
const Color _bgPage = Color(0xFFF1F5F9);
const Color _cardWhite = Colors.white;

/// Helper class for Block-based Editor
class ArticleBlock {
  final String id;
  String type; // 'text' or 'image'
  String content;
  String alignment; // 'left', 'center', 'right', 'full'
  double height;
  TextEditingController? controller;
  FocusNode? focusNode;

  ArticleBlock({
    required this.id,
    required this.type,
    required this.content,
    this.alignment = 'center',
    this.height = 100,
    this.controller,
    this.focusNode,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'content': type == 'text' ? controller?.text ?? content : content,
    'alignment': alignment,
    'height': height,
  };
}

/// Articles Page - บทความเพื่อสุขภาพ
/// แสดงรายการบทความแนะนำโดยผู้เชี่ยวชาญ
class ArticlesPage extends StatefulWidget {
  const ArticlesPage({super.key});

  @override
  State<ArticlesPage> createState() => _ArticlesPageState();
}

class _ArticlesPageState extends State<ArticlesPage> {
  final ImagePicker _picker = ImagePicker();
  String _selectedFilter = 'ล่าสุด';
  String _searchQuery = '';
  final List<String> _filters = ['ล่าสุด', 'ยอดนิยม', 'แนะนำ'];
  
  final List<HealthArticle> _articles = [];
  final ScrollController _scrollController = ScrollController();
  
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  static const int _pageSize = 12;

  @override
  void initState() {
    super.initState();
    _loadInitialArticles();
    _scrollController.addListener(_onScroll);
    
    // Refresh articles when auth state changes
    AuthService.instance.addListener(_loadInitialArticles);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    AuthService.instance.removeListener(_loadInitialArticles);
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent * 0.8) {
      if (!_isLoadingMore && _hasMore) {
        _loadMoreArticles();
      }
    }
  }

  Future<void> _loadInitialArticles() async {
    setState(() {
      _isLoading = true;
      _articles.clear();
      _page = 1;
      _hasMore = true;
    });

    try {
      final currentUserId = ServiceLocator.instance.currentUser?.id;
      final articles = await ServiceLocator.instance.healthArticleRepository.getAllArticles(
        category: _selectedFilter,
        searchQuery: _searchQuery,
        page: _page,
        pageSize: _pageSize,
        userId: currentUserId,
      );

      if (mounted) {
        setState(() {
          _articles.addAll(articles);
          _isLoading = false;
          if (articles.length < _pageSize) {
            _hasMore = false;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการโหลดข้อมูล: $e')),
        );
      }
    }
  }

  Widget _buildAlignmentBtn(BuildContext context, StateSetter setDialogState, ArticleBlock block, String alignment, IconData icon) {
    final isActive = block.alignment == alignment;
    return IconButton(
      icon: Icon(icon, color: isActive ? AppColors.primary : Colors.grey, size: 20),
      onPressed: () => setDialogState(() => block.alignment = alignment),
    );
  }

  Future<String?> _pickAndUploadImage(BuildContext context, ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 100, // We'll compress manually for better control
      );
      
      if (image == null) return null;
      
      if (!mounted) return null;
      
      // Perform compression
      final Uint8List? compressedBytes = await FlutterImageCompress.compressWithFile(
        image.path,
        minWidth: 1024,
        minHeight: 1024,
        quality: 70,
        format: CompressFormat.jpeg,
      );

      if (compressedBytes == null) return null;
      
      final fileName = 'article_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      try {
        final url = await SupabaseService.uploadFile(
          bucket: 'images',
          path: 'articles/$fileName',
          fileBytes: compressedBytes,
          contentType: 'image/jpeg',
        );
        return url;
      } catch (e) {
        debugPrint('Upload failed with exception: $e');
        if (mounted) {
          String errorMsg = e.toString();
          if (errorMsg.contains('403')) {
            errorMsg = 'สิทธิ์ถูกปฏิเสธ (403): ตรวจสอบว่าล็อกอินหรือยัง หรือตรวจสอบ Storage Policy';
          } else if (errorMsg.contains('409')) {
            errorMsg = 'ไฟล์ซ้ำซ้อน (409): กรุณาลองใหม่ด้วยชื่อไฟล์อื่น';
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ $errorMsg'), 
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(label: 'ตกลง', textColor: Colors.white, onPressed: () {}),
            ),
          );
        }
        return null;
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red),
        );
      }
      return null;
    }
  }

  Future<void> _loadMoreArticles() async {
    setState(() => _isLoadingMore = true);

    try {
      _page++;
      final currentUserId = ServiceLocator.instance.currentUser?.id;
      final articles = await ServiceLocator.instance.healthArticleRepository.getAllArticles(
        category: _selectedFilter,
        searchQuery: _searchQuery,
        page: _page,
        pageSize: _pageSize,
        userId: currentUserId,
      );

      if (mounted) {
        setState(() {
          _articles.addAll(articles);
          _isLoadingMore = false;
          if (articles.length < _pageSize) {
            _hasMore = false;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _onFilterChanged(String? value) {
    if (value != null && value != _selectedFilter) {
      setState(() {
        _selectedFilter = value;
      });
      _loadInitialArticles();
    }
  }

  void _onSearch(String query, List<Map<String, dynamic>> results) {
    if (query != _searchQuery) {
      setState(() {
        _searchQuery = query;
      });
      _loadInitialArticles();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Set background to white/light-grey so the blue header's rounded corners show this color behind them
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: _bgPage, 
        drawer: const TlzDrawer(),
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            if (AuthService.instance.currentUser == null) {
              await Navigator.pushNamed(context, '/login');
              if (AuthService.instance.currentUser == null) return;
            }
            _showCreateArticleDialog();
          },
          backgroundColor: _blue,
          elevation: 4,
          child: const Icon(Icons.add, color: Colors.white),
        ),
        body: Column(
          children: [
          // Blue Header with Rounded Bottom Corners
          _buildCustomHeader(context),
          
          // Scrollable Content
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadInitialArticles,
              color: _blue,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  // Page Title
                  SliverToBoxAdapter(
                    child: _buildPageHeader(context),
                  ),
                  
                  // Filter Bar
                  SliverToBoxAdapter(
                    child: _buildFilterBar(context),
                  ),
                  
                  // Articles Grid
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    sliver: _isLoading 
                        ? SliverToBoxAdapter(child: _buildSkeletonGrid())
                        : _buildArticlesGrid(context),
                  ),

                  // Loading More Loader
                  if (_isLoadingMore)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: CircularProgressIndicator(color: _blue)),
                      ),
                    ),
                  
                  // Bottom spacing
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildCustomHeader(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final hasUser = user != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 24), // Space for the bottom curve
      decoration: const BoxDecoration(
        color: _blue,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(56)), // Large rounded corners
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // User Profile Pill
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  children: [
                    // Avatar
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        image: (hasUser && user.profileImageUrl != null && user.profileImageUrl!.isNotEmpty)
                            ? DecorationImage(
                                image: NetworkImage(user.profileImageUrl!), 
                                fit: BoxFit.cover,
                                onError: (_, __) {},
                              )
                            : null,
                      ),
                      child: (!hasUser || user.profileImageUrl == null || user.profileImageUrl!.isEmpty)
                          ? const Icon(Icons.person, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    // Heart Icon
                    InkWell(
                      onTap: () {
                        // Navigate to favorites
                      },
                      child: const Icon(Icons.favorite, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),

              // Notification Circle
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.shopping_bag_outlined, color: Colors.white),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Text(
                          '4',
                          style: TextStyle(
                            color: _blue,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateArticleDialog() {
    final titleController = TextEditingController();
    final List<ArticleBlock> blocks = [
      ArticleBlock(
        id: DateTime.now().toString(),
        type: 'text',
        content: '',
        controller: TextEditingController(),
        focusNode: FocusNode(),
      ),
    ];
    
    bool isSaving = false;
    List<String> productLinks = [];
    
    const int maxTitleLength = 100;
    const int maxImages = 10;

    // Formatting Helpers
    void formatText(ArticleBlock block, String prefix, String suffix) {
      final controller = block.controller;
      if (controller == null) return;
      
      final text = controller.text;
      final selection = controller.selection;
      
      if (selection.start == -1 || selection.end == -1) {
        // Just append if no selection
        controller.text = text + prefix + suffix;
        return;
      }

      final selectedText = text.substring(selection.start, selection.end);
      final newText = text.replaceRange(selection.start, selection.end, '$prefix$selectedText$suffix');
      
      controller.text = newText;
      controller.selection = TextSelection.collapsed(offset: selection.start + prefix.length + selectedText.length + suffix.length);
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          
          Widget buildBlock(ArticleBlock block, int index) {
            if (block.type == 'text') {
              return Container(
                key: ValueKey(block.id),
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.text_fields, size: 16, color: Colors.grey[400]),
                        const SizedBox(width: 8),
                        Text('ข้อความ (#${index + 1})', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        const Spacer(),
                        const Icon(Icons.drag_handle, size: 20, color: Colors.grey),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                          onPressed: () => setDialogState(() => blocks.removeAt(index)),
                        ),
                      ],
                    ),
                    TextField(
                      controller: block.controller,
                      focusNode: block.focusNode,
                      maxLines: null,
                      decoration: const InputDecoration(
                        hintText: 'เริ่มพิมพ์เนื้อหาที่นี่...',
                        border: InputBorder.none,
                      ),
                      style: const TextStyle(fontSize: 15, height: 1.6),
                    ),
                  ],
                ),
              );
            } else {
              final isLoading = block.content == 'LOADING';
              final isError = block.content == 'ERROR';
              
              Alignment widgetAlignment;
              double widgetWidth;
              switch (block.alignment) {
                case 'left': 
                  widgetAlignment = Alignment.centerLeft; 
                  widgetWidth = 0.6;
                  break;
                case 'right': 
                  widgetAlignment = Alignment.centerRight; 
                  widgetWidth = 0.6;
                  break;
                case 'center': 
                  widgetAlignment = Alignment.center; 
                  widgetWidth = 0.8;
                  break;
                default: 
                  widgetAlignment = Alignment.center; 
                  widgetWidth = 1.0;
              }

              return Column(
                key: ValueKey(block.id),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isLoading && !isError)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _buildAlignmentBtn(context, setDialogState, block, 'left', Icons.format_align_left),
                              _buildAlignmentBtn(context, setDialogState, block, 'center', Icons.format_align_center),
                              _buildAlignmentBtn(context, setDialogState, block, 'right', Icons.format_align_right),
                              _buildAlignmentBtn(context, setDialogState, block, 'full', Icons.format_align_justify),
                              const Spacer(),
                              Text('ความสูง: ${block.height.toInt()}px', 
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)
                              ),
                            ],
                          ),
                          SizedBox(
                            height: 30,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                              ),
                              child: Slider(
                                value: block.height,
                                min: 100,
                                max: 400,
                                divisions: 6,
                                activeColor: AppColors.primary,
                                inactiveColor: Colors.grey[300],
                                onChanged: (val) => setDialogState(() => block.height = val),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Align(
                    alignment: widgetAlignment,
                    child: FractionallySizedBox(
                      widthFactor: widgetWidth,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        height: block.height,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Stack(
                          children: [
                            if (isLoading)
                              const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(),
                                    SizedBox(height: 12),
                                    Text('กำลังอัปโหลด...', style: TextStyle(color: Colors.grey)),
                                  ],
                                ),
                              )
                            else if (isError)
                              Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.error_outline, color: Colors.red, size: 40),
                                    const SizedBox(height: 8),
                                    const Text('อัปโหลดไม่สำเร็จ', style: TextStyle(color: Colors.red)),
                                    TextButton(
                                      onPressed: () => setDialogState(() => blocks.removeAt(index)),
                                      child: const Text('ลบออก'),
                                    )
                                  ],
                                ),
                              )
                            else
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: CachedNetworkImage(
                                  imageUrl: block.content,
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                                  errorWidget: (context, url, error) => Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.broken_image, color: Colors.grey, size: 40),
                                      const SizedBox(height: 8),
                                      Text('โหลดรูปภาพไม่สำเร็จ', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                                      TextButton(
                                        onPressed: () => setDialogState(() {}),
                                        child: const Text('ลองใหม่'),
                                      )
                                    ],
                                  ),
                                ),
                              ),
                            if (!isLoading)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                  child: IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.white, size: 20),
                                    onPressed: () => setDialogState(() => blocks.removeAt(index)),
                                  ),
                                ),
                              ),
                            if (!isLoading)
                              const Center(child: Icon(Icons.drag_handle, color: Colors.white70, size: 40)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }
          }

          return GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
            child: Container(
              width: double.infinity,
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _blue,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.edit_note, color: Colors.white),
                        const SizedBox(width: 12),
                        Text(
                          'เขียนบทความแบบบล็อก',
                          style: AppTextStyles.heading5.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),

                  // Toolbar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: Colors.grey[100],
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _ToolbarButton(
                            icon: Icons.format_bold, 
                            tooltip: 'ตัวหนา',
                            onPressed: () {
                              final focused = blocks.firstWhere((b) => b.focusNode?.hasFocus ?? false, orElse: () => blocks.first);
                              formatText(focused, '**', '**');
                            },
                          ),
                          _ToolbarButton(
                            icon: Icons.format_underlined, 
                            tooltip: 'ขีดเส้นใต้',
                            onPressed: () {
                              final focused = blocks.firstWhere((b) => b.focusNode?.hasFocus ?? false, orElse: () => blocks.first);
                              formatText(focused, '<u>', '</u>');
                            },
                          ),
                          _ToolbarButton(
                            icon: Icons.border_color, 
                            tooltip: 'ไฮไลท์',
                            onPressed: () {
                              final focused = blocks.firstWhere((b) => b.focusNode?.hasFocus ?? false, orElse: () => blocks.first);
                              formatText(focused, '<mark>', '</mark>');
                            },
                          ),
                          _ToolbarButton(
                            icon: Icons.emoji_emotions_outlined, 
                            tooltip: 'ใส่อิโมจิ',
                            onPressed: () {
                              final focused = blocks.firstWhere((b) => b.focusNode?.hasFocus ?? false, orElse: () => blocks.first);
                              formatText(focused, '😊', '');
                            },
                          ),
                          const VerticalDivider(),
                          _ToolbarButton(
                            icon: Icons.add_comment_outlined, 
                            label: 'เพิ่มข้อความ',
                            color: Colors.green,
                            onPressed: () => setDialogState(() {
                              blocks.add(ArticleBlock(
                                id: DateTime.now().toString(),
                                type: 'text',
                                content: '',
                                controller: TextEditingController(),
                                focusNode: FocusNode(),
                              ));
                            }),
                          ),
                          _ToolbarButton(
                            icon: Icons.add_photo_alternate_outlined, 
                            label: 'เพิ่มรูปภาพ',
                            color: Colors.orange,
                            onPressed: () {
                              if (blocks.where((b) => b.type == 'image').length >= maxImages) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('คุณเพิ่มรูปภาพครบจำนวนที่กำหนดแล้ว')));
                                return;
                              }
                              
                              showModalBottomSheet(
                                context: context,
                                builder: (bottomSheetContext) => SafeArea(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ListTile(
                                        leading: const Icon(Icons.photo_library, color: _blue),
                                        title: const Text('เลือกจากคลังภาพ'),
                                        onTap: () async {
                                          Navigator.pop(bottomSheetContext);
                                          final tempId = DateTime.now().millisecondsSinceEpoch.toString();
                                          
                                          // Add temporary loading block
                                          setDialogState(() {
                                            blocks.add(ArticleBlock(
                                              id: tempId,
                                              type: 'image',
                                              content: 'LOADING', // Special flag
                                              alignment: 'center',
                                              height: 100,
                                            ));
                                          });

                                          final url = await _pickAndUploadImage(context, ImageSource.gallery);
                                          
                                          if (url != null) {
                                            setDialogState(() {
                                              final index = blocks.indexWhere((b) => b.id == tempId);
                                              if (index != -1) {
                                                blocks[index].content = url;
                                                blocks.insert(index + 1, ArticleBlock(
                                                  id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
                                                  type: 'text',
                                                  content: '',
                                                  controller: TextEditingController(),
                                                  focusNode: FocusNode(),
                                                ));
                                              }
                                            });
                                          } else {
                                            // ALWAYS remove the temporary loading block if we don't get a URL
                                            // The _pickAndUploadImage will show a SnackBar if there was a real error
                                            setDialogState(() {
                                              blocks.removeWhere((b) => b.id == tempId);
                                            });
                                          }
                                        },
                                      ),
                                      ListTile(
                                        leading: const Icon(Icons.camera_alt, color: Colors.orange),
                                        title: const Text('ถ่ายรูป'),
                                        onTap: () async {
                                          Navigator.pop(bottomSheetContext);
                                          final tempId = DateTime.now().millisecondsSinceEpoch.toString();
                                          
                                          setDialogState(() {
                                            blocks.add(ArticleBlock(
                                              id: tempId,
                                              type: 'image',
                                              content: 'LOADING',
                                              alignment: 'center',
                                              height: 100,
                                            ));
                                          });

                                          final url = await _pickAndUploadImage(context, ImageSource.camera);
                                          
                                          if (url != null) {
                                            setDialogState(() {
                                              final index = blocks.indexWhere((b) => b.id == tempId);
                                              if (index != -1) {
                                                blocks[index].content = url;
                                                blocks.insert(index + 1, ArticleBlock(
                                                  id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
                                                  type: 'text',
                                                  content: '',
                                                  controller: TextEditingController(),
                                                  focusNode: FocusNode(),
                                                ));
                                              }
                                            });
                                          } else {
                                            setDialogState(() {
                                              blocks.removeWhere((b) => b.id == tempId);
                                            });
                                          }
                                        },
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Content Area
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          const SizedBox(height: 16),
                          // Title (Fixed at top of content)
                          TextField(
                            controller: titleController,
                            maxLength: maxTitleLength,
                            decoration: InputDecoration(
                              hintText: 'หัวข้อบทความของคุณ...',
                              hintStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.grey),
                              counterText: '',
                              border: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey[300]!)),
                              focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: _blue, width: 2)),
                            ),
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          
                          // Blocks List
                          Expanded(
                            child: ReorderableListView.builder(
                              padding: const EdgeInsets.only(bottom: 100),
                              itemCount: blocks.length,
                              onReorder: (oldIndex, newIndex) {
                                setDialogState(() {
                                  if (newIndex > oldIndex) newIndex -= 1;
                                  final item = blocks.removeAt(oldIndex);
                                  blocks.insert(newIndex, item);
                                });
                              },
                              itemBuilder: (context, index) => buildBlock(blocks[index], index),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Footer Actions
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                      border: Border(top: BorderSide(color: Colors.grey[200]!)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: isSaving ? null : () => Navigator.pop(context),
                            child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              final String contentJson = jsonEncode(blocks.map((b) => b.toJson()).toList());
                              _showPreviewDialog(titleController.text, contentJson);
                            },
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: _blue),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('ดูตัวอย่าง', style: TextStyle(color: _blue, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: isSaving ? null : () async {
                              // Validation
                              if (titleController.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณากรอกหัวข้อบทความ')));
                                return;
                              }

                              setDialogState(() => isSaving = true);

                              try {
                                final repository = ServiceLocator.instance.healthArticleRepository;
                                final currentUser = AuthService.instance.currentUser;
                                
                                if (currentUser == null) {
                                  Navigator.pop(context);
                                  return;
                                }

                                // Serialize blocks to JSON
                                final String contentJson = jsonEncode(blocks.map((b) => b.toJson()).toList());
                                final firstImage = blocks.firstWhere((b) => b.type == 'image', orElse: () => ArticleBlock(id: '', type: '', content: '')).content;

                                final newArticle = await repository.createArticle(
                                  userId: currentUser.id,
                                  title: titleController.text.trim(),
                                  content: contentJson, // Save as JSON
                                  imageUrl: firstImage.isNotEmpty ? firstImage : null,
                                );

                                if (newArticle != null && mounted) {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => HealthArticlePage(article: newArticle)),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('เผยแพร่บทความสำเร็จ')));
                                  _loadInitialArticles();
                                }
                              } catch (e) {
                                if (mounted) {
                                  setDialogState(() => isSaving = false);
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ข้อผิดพลาด: $e'), backgroundColor: Colors.red));
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            child: isSaving 
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text('เผยแพร่บทความ', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        },
      ),
    );
  }
  // --- Sub Helper for Toolbar ---
  // (Moved below ArticlesPage class)




  Widget _buildPageHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'บทความเพื่อสุขภาพ',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B), // Dark text for white bg
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'รวบรวมสาระดีๆ จากผู้เชี่ยวชาญเพื่อคุณ',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    return Container(
      height: 44,
      margin: const EdgeInsets.only(top: 20, bottom: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _filters.length,
        itemBuilder: (context, index) {
          final filter = _filters[index];
          final bool isActive = _selectedFilter == filter;
          
          return GestureDetector(
            onTap: () {
              if (isActive) return;
              setState(() {
                _selectedFilter = filter;
                _loadInitialArticles();
              });
            },
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isActive ? _blue : Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isActive ? _blue : Colors.grey.shade200,
                ),
                boxShadow: isActive ? [
                  BoxShadow(
                    color: _blue.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ] : null,
              ),
              child: Text(
                filter,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.grey.shade600,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildArticlesGrid(BuildContext context) {
    if (_articles.isEmpty) {
      return const SliverFillRemaining(
        child: Center(child: Text('ไม่พบบทความ')),
      );
    }

    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.72,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => _buildArticleCard(context, _articles[index]),
        childCount: _articles.length,
      ),
    );
  }

  Widget _buildSkeletonGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.7,
        ),
        itemCount: 8,
        itemBuilder: (context, index) => _buildSkeletonCard(),
      ),
    );
  }

  Widget _buildSkeletonCard() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildArticleCard(BuildContext context, HealthArticle article) {
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => HealthArticlePage(article: article),
          ),
        );
        // Refresh when returning to update like counts/bookmark status
        if (mounted) {
          _loadInitialArticles();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Section
            Expanded(
              flex: 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: _blue.withOpacity(0.05),
                    ),
                    child: article.imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: article.imageUrl!,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Center(child: CircularProgressIndicator(color: _blue.withOpacity(0.3), strokeWidth: 2)),
                            errorWidget: (context, url, error) => const Icon(Icons.broken_image_outlined, color: Colors.grey),
                          )
                        : const Icon(Icons.article_outlined, color: _blue, size: 40),
                  ),
                  // Category Tag
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4),
                        ],
                      ),
                      child: Text(
                        article.category ?? 'สุขภาพ',
                        style: const TextStyle(
                          color: _blue, 
                          fontSize: 9, 
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Content Section
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                        height: 1.3,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        const Icon(Icons.favorite, size: 14, color: Colors.pinkAccent),
                        const SizedBox(width: 4),
                        Text(
                          '${article.likeCount}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.chat_bubble_outline, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          '${article.commentCount}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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
  }

  void _showPreviewDialog(String title, String contentJson) {
    showDialog(
      context: context,
      builder: (context) {
        final List<dynamic> blocks = jsonDecode(contentJson);
        final contentStyle = TextStyle(
          fontSize: 16, 
          height: 1.6, 
          color: Colors.black.withOpacity(0.8),
        );

        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('ตัวอย่างบทความ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _blue)),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.isEmpty ? '(ไม่มีหัวข้อ)' : title,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                        ),
                        const SizedBox(height: 20),
                        ...blocks.map((block) {
                          final type = block['type'];
                          final val = block['content'] as String;

                          if (type == 'text') {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: _RichTextRenderer(
                                text: val, 
                                style: contentStyle,
                              ),
                            );
                          } else if (type == 'image') {
                            final alignment = block['alignment'] ?? 'full';
                            final height = (block['height'] ?? 200).toDouble();
                            
                            Alignment widgetAlignment;
                            double widgetWidth;
                            switch (alignment) {
                              case 'left': widgetAlignment = Alignment.centerLeft; widgetWidth = 0.6; break;
                              case 'right': widgetAlignment = Alignment.centerRight; widgetWidth = 0.6; break;
                              case 'center': widgetAlignment = Alignment.center; widgetWidth = 0.8; break;
                              default: widgetAlignment = Alignment.center; widgetWidth = 1.0;
                            }

                            return Align(
                              alignment: widgetAlignment,
                              child: FractionallySizedBox(
                                widthFactor: widgetWidth,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 16),
                                  height: height,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    color: Colors.grey[100],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: CachedNetworkImage(
                                      imageUrl: val,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                                      errorWidget: (context, url, error) => const Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.broken_image, color: Colors.grey, size: 40),
                                            SizedBox(height: 8),
                                            Text('โหลดรูปภาพไม่สำเร็จ', style: TextStyle(color: Colors.grey)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        }).toList(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        );
      },
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final String? tooltip;
  final VoidCallback onPressed;
  final Color? color;

  const _ToolbarButton({
    required this.icon,
    this.label,
    this.tooltip,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      child: tooltip != null 
        ? IconButton(
            onPressed: onPressed,
            icon: Icon(icon, color: color ?? Colors.black87),
            tooltip: tooltip,
            visualDensity: VisualDensity.compact,
          )
        : TextButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 20, color: color),
            label: Text(label!, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
    );
  }
}


class _RichTextRenderer extends StatelessWidget {
  final String text;
  final TextStyle style;
  final int? maxLines;

  const _RichTextRenderer({required this.text, required this.style, this.maxLines});

  @override
  Widget build(BuildContext context) {
    List<TextSpan> spans = [];
    final regExp = RegExp(r'(\*\*.*?\*\*|<u>.*?</u>|<mark>.*?</mark>)');
    int lastMatchEnd = 0;
    final matches = regExp.allMatches(text).toList();
    
    if (matches.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: maxLines != null ? TextOverflow.ellipsis : null);
    }

    for (final match in matches) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(text: text.substring(lastMatchEnd, match.start), style: style));
      }
      final matchText = match.group(0)!;
      if (matchText.startsWith('**')) {
        spans.add(TextSpan(text: matchText.substring(2, matchText.length - 2), style: style.copyWith(fontWeight: FontWeight.bold)));
      } else if (matchText.startsWith('<u>')) {
        spans.add(TextSpan(text: matchText.substring(3, matchText.length - 4), style: style.copyWith(decoration: TextDecoration.underline)));
      } else if (matchText.startsWith('<mark>')) {
        spans.add(TextSpan(
          text: matchText.substring(6, matchText.length - 7),
          style: style.copyWith(backgroundColor: const Color(0xFFF1AE27).withOpacity(0.4), color: Colors.black, fontWeight: FontWeight.bold),
        ));
      }
      lastMatchEnd = match.end;
    }
    if (lastMatchEnd < text.length) spans.add(TextSpan(text: text.substring(lastMatchEnd), style: style));

    return Text.rich(TextSpan(children: spans), style: style, maxLines: maxLines, overflow: maxLines != null ? TextOverflow.ellipsis : null);
  }
}

