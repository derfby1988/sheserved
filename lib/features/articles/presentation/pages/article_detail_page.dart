import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../shared/widgets/widgets.dart';
import 'package:sheserved/features/health/data/models/health_article_models.dart';

/// Article Detail Page - หน้ารายละเอียดบทความ
class ArticleDetailPage extends StatefulWidget {
  final HealthArticle article;

  const ArticleDetailPage({
    super.key,
    required this.article,
  });

  @override
  State<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends State<ArticleDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedContentTab = 0;
  String _commentFilter = 'สนใจมากที่สุด';

  final List<String> _tabs = ['หัวข้อ', 'สินค้า', 'ความคิดเห็น', 'เกี่ยวกับฉัน'];
  final List<String> _contentTabs = ['รายการ 1', 'รายการ 2', 'รายการ 3'];

  // Mock comments data
  final List<Map<String, dynamic>> _comments = [
    {
      'id': '1',
      'user': 'สมาชิกหมายเลข xxx',
      'date': 'พฤหัสบดี 18 เม.ย. 64',
      'content': 'Reply...........................................................',
      'likes': 90,
      'comments': 78,
      'shares': 12,
      'bookmarks': 34,
      'replies': [
        {
          'id': '1-1',
          'user': 'สมาชิกหมายเลข xxx',
          'date': 'จันทร์ 18 เม.ย. 64',
          'content': 'Reply...........................................................',
          'likes': 90,
          'comments': 78,
          'shares': 12,
          'bookmarks': 34,
        },
      ],
    },
    {
      'id': '2',
      'user': 'สมาชิกหมายเลข xxx',
      'date': 'จันทร์ 18 เม.ย. 64',
      'content': 'Reply...........................................................',
      'likes': 90,
      'comments': 78,
      'shares': 12,
      'bookmarks': 34,
      'replies': [],
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const TlzDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation Bar
            _buildTopNavigationBar(context),
            
            // Main Content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Article Content Section
                    _buildArticleContent(context),
                    
                    // Content Tabs
                    _buildContentTabs(context),
                    
                    // Comments Section
                    _buildCommentsSection(context),
                    
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopNavigationBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.background,
      child: Column(
        children: [
          // Search Bar Row
          TlzAppTopBar.onPrimary(
            notificationCount: 1,
            searchHintText: 'ค้นหา...',
            onQRTap: () {},
            onNotificationTap: () {},
            onCartTap: () {},
          ),
          
          const SizedBox(height: 8),
          
          // Tab Bar
          Row(
            children: [
              // Back Button
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.arrow_back,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
              ),
              
              // Tabs
              Expanded(
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    labelColor: AppColors.textPrimary,
                    unselectedLabelColor: AppColors.textSecondary,
                    labelStyle: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    unselectedLabelStyle: AppTextStyles.caption,
                    indicator: BoxDecoration(
                      color: AppColors.primaryLight.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    tabs: _tabs.map((tab) => Tab(text: tab)).toList(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildArticleContent(BuildContext context) {
    final dateFormat = DateFormat('EEEE d เม.ย. yy', 'th');
    
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author Header
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundImage: widget.article.authorImage != null 
                  ? NetworkImage(widget.article.authorImage!)
                  : null,
                child: widget.article.authorImage == null 
                  ? const Icon(Icons.person)
                  : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.article.authorName ?? 'Expert',
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Expert in Women Health',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Title
              Expanded(
                child: Text(
                  widget.article.title,
                  style: AppTextStyles.heading5.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              
              // Date & Bookmark
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    color: AppColors.primary,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    dateFormat.format(widget.article.createdAt),
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.bookmark_border,
                      color: AppColors.textSecondary,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 4),
          
          // Views & Comments
          Text(
            '${widget.article.viewCount} เปิดดู   ${widget.article.likeCount} ถูกใจ',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          
          const SizedBox(height: 16),
          
          if (widget.article.imageUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                widget.article.imageUrl!,
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          // Detail Content
          Text(
            widget.article.content,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildDottedLine() {
    return Row(
      children: List.generate(50, (index) {
        return Expanded(
          child: Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            color: index % 2 == 0 
              ? AppColors.textHint.withOpacity(0.5)
              : Colors.transparent,
          ),
        );
      }),
    );
  }

  Widget _buildContentTabs(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: List.generate(_contentTabs.length, (index) {
          final isSelected = _selectedContentTab == index;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedContentTab = index;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected 
                    ? AppColors.primaryLight.withOpacity(0.5)
                    : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected 
                      ? AppColors.primary
                      : AppColors.border,
                  ),
                ),
                child: Text(
                  _contentTabs[index],
                  style: AppTextStyles.bodySmall.copyWith(
                    color: isSelected 
                      ? AppColors.primary
                      : AppColors.textSecondary,
                    fontWeight: isSelected 
                      ? FontWeight.bold
                      : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCommentsSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Comments Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'การแสดงความคิดเห็น',
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              // Filter
              GestureDetector(
                onTap: () {
                  // Show filter options
                },
                child: Row(
                  children: [
                    Text(
                      _commentFilter,
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.orange,
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.orange,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Comments List
          ..._comments.map((comment) => _buildCommentCard(comment)),
        ],
      ),
    );
  }

  Widget _buildCommentCard(Map<String, dynamic> comment) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main Comment
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Comment Label
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'ความคิดเห็นที่ ${comment['id']}',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Content
                    Text(
                      comment['content'],
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    
                    // Dotted lines
                    ...List.generate(3, (index) => Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _buildDottedLine(),
                    )),
                    
                    const SizedBox(height: 12),
                    
                    // User Info & Stats
                    Row(
                      children: [
                        // User Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                comment['user'],
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    color: AppColors.primary,
                                    size: 12,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    comment['date'],
                                    style: AppTextStyles.caption.copyWith(
                                      color: AppColors.textSecondary,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        
                        // Stats
                        _buildStatIcon(Icons.favorite, comment['likes']),
                        const SizedBox(width: 8),
                        _buildStatIcon(Icons.chat_bubble, comment['comments']),
                        const SizedBox(width: 8),
                        _buildStatIcon(Icons.refresh, comment['shares']),
                        const SizedBox(width: 8),
                        _buildStatIcon(Icons.bookmark, comment['bookmarks']),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Scroll to top button (for first comment)
              if (comment['id'] == '1' && (comment['replies'] as List).isNotEmpty)
                Positioned(
                  right: 16,
                  bottom: -20,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.arrow_upward,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                ),
            ],
          ),
        ),
        
        // Replies
        if ((comment['replies'] as List).isNotEmpty)
          ...((comment['replies'] as List).map((reply) => 
            _buildReplyCard(reply, comment['id'])
          )),
      ],
    );
  }

  Widget _buildReplyCard(Map<String, dynamic> reply, String parentId) {
    return Container(
      margin: const EdgeInsets.only(left: 24, bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reply Label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withOpacity(0.3),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'ความคิดเห็นที่ $parentId - ${reply['id'].toString().split('-').last}',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.primary,
              ),
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Content
          Text(
            reply['content'],
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          
          // Dotted lines
          ...List.generate(2, (index) => Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _buildDottedLine(),
          )),
          
          const SizedBox(height: 12),
          
          // User Info & Stats
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // User Info
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reply['user'],
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        color: AppColors.primary,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        reply['date'],
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              
              const Spacer(),
              
              // Stats
              _buildStatIcon(Icons.favorite, reply['likes']),
              const SizedBox(width: 8),
              _buildStatIcon(Icons.chat_bubble, reply['comments']),
              const SizedBox(width: 8),
              _buildStatIcon(Icons.refresh, reply['shares']),
              const SizedBox(width: 8),
              _buildStatIcon(Icons.bookmark, reply['bookmarks']),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatIcon(IconData icon, int count) {
    return Row(
      children: [
        Icon(
          icon,
          color: AppColors.primary,
          size: 14,
        ),
        const SizedBox(width: 2),
        Text(
          '$count',
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textSecondary,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}
