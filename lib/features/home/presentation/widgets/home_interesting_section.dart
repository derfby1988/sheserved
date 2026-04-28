import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../health/data/models/health_article_models.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Interesting Section Widget - น่าสนใจ
class HomeInterestingSection extends StatefulWidget {
  final VoidCallback? onMoreTap;
  final Function(HealthArticle article)? onItemTap;
  final Function(HealthArticle article)? onBookmarkTap;
  final List<HealthArticle> articles;
  
  // Pagination
  final VoidCallback? onLoadMore;
  final bool hasMore;
  final bool isLoadingMore;

  const HomeInterestingSection({
    super.key,
    this.onMoreTap,
    this.onItemTap,
    this.onBookmarkTap,
    required this.articles,
    this.onLoadMore,
    this.hasMore = false,
    this.isLoadingMore = false,
  });

  @override
  State<HomeInterestingSection> createState() => _HomeInterestingSectionState();
}

class _HomeInterestingSectionState extends State<HomeInterestingSection> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (widget.onLoadMore != null && 
        widget.hasMore && 
        !widget.isLoadingMore &&
        _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      widget.onLoadMore!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'น่าสนใจ',
                  style: AppTextStyles.heading5.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: widget.onMoreTap,
                child: Text(
                  'เพิ่มเติม',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Cards - Fixed width, horizontal scroll
        SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < widget.articles.length; i++) ...[
                GestureDetector(
                  onTap: () => widget.onItemTap?.call(widget.articles[i]),
                  child: _buildInterestingCard(widget.articles[i]),
                ),
                if (i < widget.articles.length - 1 || widget.isLoadingMore) 
                  const SizedBox(width: 12),
              ],
              if (widget.isLoadingMore)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: CupertinoActivityIndicator(radius: 12.0),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInterestingCard(HealthArticle article) {
    return Container(
      width: 312,
      height: 160,
      margin: const EdgeInsets.only(right: 12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 1. พื้นหลังการ์ดสีขาว (Frame หลักของข้อมูล) 276x150
          Positioned(
            left: 0,
            bottom: 0,
            child: Container(
              width: 276,
              height: 150,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A000000), // เงาบางๆ 10%
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              // เผื่อขวาไว้ 100px เพื่อไม่ให้ข้อความทับรูปวงกลมที่ลอยอยู่ 
              // และปรับลด top/bottom เพื่อไม่ให้ล้น
              padding: const EdgeInsets.only(left: 20, top: 10, bottom: 10, right: 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title
                  Text(
                    article.title.isNotEmpty ? article.title : 'รายการที่ ${article.id.hashCode % 100}',
                    style: const TextStyle(
                      fontFamily: 'Sukhumvit Set',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5B8E21),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  
                  Text(
                    article.category ?? '100 - 200 น.',
                    style: const TextStyle(
                      fontFamily: 'Sukhumvit Set',
                      fontSize: 13,
                      color: Color(0xFF8B8B8B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  
                  // Stars
                  Row(
                    children: List.generate(5, (index) => const Padding(
                      padding: EdgeInsets.only(right: 2),
                      child: Icon(
                        Icons.star,
                        color: Color(0xFFC0CA33),
                        size: 15,
                      ),
                    )),
                  ),
                  const SizedBox(height: 2),
                  
                  // Add to Cart Button 
                  Container(
                    width: 72,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF8A8A8A), // สีเทา
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.add_shopping_cart, // ไอคอนตะกร้าแบบมีบวก
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // 2. รูปภาพวงกลม (Circle Image) 129x129
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: 129,
              height: 129,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x33000000), // เงา 20%
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ClipOval(
                child: article.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: article.imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const CupertinoActivityIndicator(),
                      errorWidget: (context, url, error) => const Icon(Icons.image, color: Colors.grey, size: 40),
                    )
                  : const Center(child: Icon(Icons.image, color: Colors.grey, size: 40)),
              ),
            ),
          ),

          // 3. ป้าย Bookmark (เปลี่ยนเป็นรูปหัวใจบนรูปวงกลมมุมขวาบน)
          Positioned(
            right: 10,
            top: 10,
            child: GestureDetector(
              onTap: () => widget.onBookmarkTap?.call(article),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8), // เพิ่มความโปร่งใส (80%)
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1A000000), // เงาบางๆ 10%
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  article.isBookmarked ? Icons.favorite : Icons.favorite_border,
                  color: article.isBookmarked ? const Color(0xFFE91E63) : const Color(0xFFBDBDBD), // สีชมพูแดงตอนที่กด แล้วเป็นสีเทาตอนไม่ได้กด
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
