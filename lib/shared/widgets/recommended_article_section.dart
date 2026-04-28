import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import 'widgets.dart';
import '../../features/health/data/models/health_article_models.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Recommended Section Widget - แนะนำโดยผู้เชี่ยวชาญ
class RecommendedArticleSection extends StatefulWidget {
  final VoidCallback? onMoreTap;
  final Function(HealthArticle article)? onItemTap;
  final Function(HealthArticle article)? onBookmarkTap;
  final List<HealthArticle> articles;
  
  // Pagination
  final VoidCallback? onLoadMore;
  final bool hasMore;
  final bool isLoadingMore;

  const RecommendedArticleSection({
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
  State<RecommendedArticleSection> createState() => _RecommendedArticleSectionState();
}

class _RecommendedArticleSectionState extends State<RecommendedArticleSection> {
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
                  'แนะนำโดยผู้เชี่ยวชาญ',
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
        
        // Horizontal Scrollable List
        SizedBox(
          height: 180,
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: widget.articles.length + (widget.isLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index < widget.articles.length) {
                final article = widget.articles[index];
                return GestureDetector(
                  onTap: () => widget.onItemTap?.call(article),
                  child: _buildRecommendedCard(article),
                );
              } else {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: CupertinoActivityIndicator(radius: 12.0),
                  ),
                );
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendedCard(HealthArticle article) {
    return Container(
      width: 340,
      height: 164,
      margin: const EdgeInsets.only(right: 12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 1. Background Card ขาว (ฐานรองด้านหลัง)
          //    ขอบบนเริ่มที่ 10% ของความสูงการ์ดเขียว
          Positioned(
            left: 32,
            top: 23,
            child: Container(
              width: 324,
              height: 155,
              decoration: ShapeDecoration(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(29),
                ),
                shadows: const [
                  BoxShadow(
                    color: Color(0x3F000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                    spreadRadius: 0,
                  )
                ],
              ),
            ),
          ),

          // 2. พื้นที่รูปภาพ/ไอคอน — Figma layer `bk` (Subtract boolean)
          //    Rounded Rect (158×141) มุม 3 ด้านโค้ง + มุมล่างขวาตัดเฉียง
          Positioned(
            left: 16,
            top: 9,
            child: ClipPath(
              clipper: const _LeafShapeClipper(),
              child: Container(
                width: 158,
                height: 141,
                decoration: BoxDecoration(
                  color: AppColors.primary, // สีเขียวเป็น fallback
                  image: article.imageUrl != null
                    ? DecorationImage(
                        image: CachedNetworkImageProvider(article.imageUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
                ),
                child: Stack(
                  children: [
                    if (article.imageUrl == null)
                      const Center(
                        child: Icon(
                          Icons.image,
                          size: 48,
                          color: Colors.white70,
                        ),
                      ),
                    // Ribbon Bookmark
                    Positioned(
                      top: 0,
                      left: 16, // ย้ายไปชิดมุมบนซ้ายตามคำขอ
                      child: RibbonBookmark(
                        isBookmarked: article.isBookmarked,
                        inactiveColor: Colors.white38,
                        onTap: () => widget.onBookmarkTap?.call(article),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 3. หัวข้อ + เนื้อหา (ชิดขวาของการ์ดขาว, กว้าง 50%)
          Positioned(
            left: 194,
            top: 23,
            child: SizedBox(
              width: 154, // ~50% ของการ์ดขาว (324/2 - 8 padding)
              height: 147,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, right: 8, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // หัวข้อบทความ — จำกัด 1 บรรทัด
                    Text(
                      article.title,
                      style: const TextStyle(
                        color: Color(0xFF171717), // เปลี่ยนสีหัวข้อตามคำขอ (#171717)
                        fontSize: 16,
                        fontFamily: 'Sukhumvit Set',
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // เนื้อหาบทความ — สูงสุด 3 บรรทัด + "อ่านต่อ" สีทองหากเกิน
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          const contentStyle = TextStyle(
                            color: Color(0xFF733737), // เปลี่ยนสีเนื้อหาตามคำขอ (#733737)
                            fontSize: 14,
                            fontFamily: 'Sukhumvit Set',
                            fontWeight: FontWeight.w500,
                          );
                          // ตรวจว่าข้อความเกิน 3 บรรทัดหรือไม่
                          final textPainter = TextPainter(
                            text: TextSpan(text: article.content, style: contentStyle),
                            maxLines: 3,
                            textDirection: TextDirection.ltr,
                          )..layout(maxWidth: constraints.maxWidth);
                          final isOverflow = textPainter.didExceedMaxLines;

                          return Stack(
                            clipBehavior: Clip.none, // ยอมให้ข้อความล้นกรอบ Stack ออกมาได้เล็กน้อย
                            children: [
                              Text(
                                article.content,
                                style: contentStyle,
                                maxLines: 3,
                                overflow: TextOverflow.clip,
                              ),
                              if (isOverflow)
                                Positioned(
                                  bottom: -7, // ปรับขยับลงมาด้านล่างนิดหน่อยตามคำขอ
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.only(left: 20),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.white.withOpacity(0),
                                          Colors.white.withOpacity(0.85),
                                        ],
                                        stops: const [0.0, 0.35],
                                      ),
                                    ),
                                    child: const Text(
                                      'อ่านต่อ',
                                      style: TextStyle(
                                        color: Color(0xFFD4A017), // สีเหลืองทอง
                                        fontSize: 10,
                                        fontFamily: 'Sukhumvit Set',
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 4. ชื่อทางการค้า / ชื่อผู้แต่ง (ย้ายมาอยู่ขอบด้านล่าง สูงกว่าขอบล่าง Layer 2)
          Positioned(
            left: 28, // ชิงซ้ายเหลื่อมจากขอบของรูปเล็กน้อย (Layer 2 เริ่มที่ 16)
            bottom: 32, // ขอบล่าง Layer 2 อยู่ที่ bottom: 14 ดังนั้น bottom: 24 จะสูงกว่าขอบล่าง 10px
            child: SizedBox(
              width: 158 * 0.5, // กำหนดความกว้าง 50% ของ Layer 2
              child: Align(
                alignment: Alignment.centerLeft, // จัดข้อความให้อยู่ชิดซ้าย
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    article.authorName ?? 'ผู้เชี่ยวชาญ',
                    style: const TextStyle(
                      color: Colors.white, // เปลี่ยนสีข้อความเป็นสีขาว
                      fontSize: 26,
                      fontFamily: 'Sukhumvit Set',
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1, // ปรับลดขนาดอัตโนมัติหากเกินความกว้าง 50%
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom Clipper สำหรับสร้างรูปทรง Figma layer `bk` (Subtract boolean operation)
/// Rounded Rectangle มุมซ้ายบน/ขวาบน/ซ้ายล่างโค้ง ~20px 
/// มุมล่างขวาถูกตัดเฉียงออกด้วยสี่เหลี่ยมเอียง (40.53×100.48)
class _LeafShapeClipper extends CustomClipper<Path> {
  const _LeafShapeClipper();

  @override
  Path getClip(Size size) {
    const double r = 32.0; // เพิ่มรัศมีความโค้งมนตามคำขอ
    final w = size.width;
    final h = size.height;

    final path = Path();

    // มุมซ้ายบน (โค้ง)
    path.moveTo(0, r);
    path.quadraticBezierTo(0, 0, r, 0);

    // ขอบบนตรงไปมุมขวาบน
    path.lineTo(w - r, 0);
    // มุมขวาบน (โค้ง)
    path.quadraticBezierTo(w, 0, w, r);

    // ขอบขวาลงมาถึงจุดเริ่มตัดเฉียง (ประมาณ 60% ของความสูง)
    path.lineTo(w, h * 0.60);

    // เส้นเฉียงตัดมุมล่างขวา → ไปที่ขอบล่าง (ประมาณ 60% ของความกว้าง)
    path.lineTo(w * 0.60, h);

    // ขอบล่างตรงกลับไปมุมซ้ายล่าง
    path.lineTo(r, h);
    // มุมซ้ายล่าง (โค้ง)
    path.quadraticBezierTo(0, h, 0, h - r);

    // ขอบซ้ายกลับขึ้นไปมุมซ้ายบน
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
