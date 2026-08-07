import 'dart:ui';
import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../services/service_locator.dart';
import '../../data/models/health_article_models.dart';
import '../../../pharmacy/presentation/pages/pharmacy_products_page.dart';
import '../pages/health_article_page.dart';

/// SliverPersistentHeader delegate for the horizontal product pills section.
class ProductSectionDelegate extends SliverPersistentHeaderDelegate {
  final List<HealthArticleProduct> products;
  final String authorId;
  final VoidCallback onRequestTag;
  final Key? key;

  ProductSectionDelegate({
    required this.products,
    required this.authorId,
    required this.onRequestTag,
    this.key,
  });

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Stack(
      children: [
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              key: key,
              height: 60,
              color: Colors.white.withOpacity(0.05),
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 60, right: 16),
                itemCount: products.isEmpty ? 3 : products.length,
                itemBuilder: (context, index) {
                  String label = 'รายการ ${index + 1}';

                  Color baseColor = const Color(0xFFFDE4D3);
                  Color textColor = const Color(0xFFD3856E);

                  if (index < products.length) {
                    final p = products[index];
                    label = p.name;

                    if (!p.isApproved) {
                      baseColor = Colors.grey[200]!;
                      textColor = Colors.grey[600]!;
                      label = '$label (รออนุมัติ)';
                    } else if (p.taggedById == authorId) {
                      baseColor = const Color(0xFFCDE4F5);
                      textColor = const Color(0xFF5D9CDB);
                    } else if (p.taggerUserCategory == 'provider') {
                      baseColor = const Color(0xFFFEF3D3);
                      textColor = const Color(0xFFF1AE27);
                    } else {
                      baseColor = const Color(0xFFFDE4D3);
                      textColor = const Color(0xFFD3856E);
                    }
                  } else {
                    final colors = [
                      const Color(0xFFCDE4F5),
                      const Color(0xFFFEF3D3),
                      const Color(0xFFFDE4D3),
                    ];
                    final textColors = [
                      const Color(0xFF5D9CDB),
                      const Color(0xFFF1AE27),
                      const Color(0xFFD3856E),
                    ];
                    baseColor = colors[index % colors.length];
                    textColor = textColors[index % textColors.length];
                  }

                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              PharmacyProductsPage(initialSearchQuery: label),
                        ),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      constraints: const BoxConstraints(maxWidth: 180),
                      decoration: BoxDecoration(
                        color: baseColor.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white54, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (index < products.length &&
                              products[index].taggedById == authorId)
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Icon(
                                Icons.verified,
                                size: 14,
                                color: Color(0xFF5D9CDB),
                              ),
                            ),
                          Flexible(
                            child: Text(
                              label,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'SukhumvitSet',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        Positioned(
          left: 12,
          top: 10,
          child: GestureDetector(
            onTap: onRequestTag,
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  double get maxExtent => 60;

  @override
  double get minExtent => 60;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      true;
}

/// Custom painter for the bookmark ribbon shape.
class RibbonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFF1AE27)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(size.width / 2, size.height * 0.8);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

/// Renders rich text with **bold**, <u>underline</u>, <mark>highlight</mark> support.
/// Also supports diff rendering when [oldText] is provided.
class RichTextRenderer extends StatelessWidget {
  final String text;
  final String? oldText;
  final TextStyle style;
  final int? maxLines;
  final void Function(String current, String original)? onDiffTap;

  const RichTextRenderer({
    super.key,
    required this.text,
    required this.style,
    this.maxLines,
    this.oldText,
    this.onDiffTap,
  });

  @override
  Widget build(BuildContext context) {
    if (oldText != null && oldText != text) {
      final diffs = diff(oldText!, text);
      cleanupSemantic(diffs);

      List<InlineSpan> spans = [];
      for (var d in diffs) {
        if (d.operation == 0) {
          spans.add(TextSpan(text: d.text, style: style));
        } else if (d.operation == 1) {
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: GestureDetector(
                onTap: onDiffTap != null
                    ? () => onDiffTap!(text, oldText!)
                    : null,
                child: Text(
                  d.text,
                  style: style.copyWith(
                    color: style.color?.withOpacity(0.5) ?? Colors.grey,
                  ),
                ),
              ),
            ),
          );
        }
      }

      return Text.rich(
        TextSpan(children: spans),
        style: style,
        maxLines: maxLines,
        overflow: maxLines != null ? TextOverflow.ellipsis : null,
      );
    }

    List<TextSpan> spans = [];

    final regExp = RegExp(r'(\*\*.*?\*\*|<u>.*?</u>|<mark>.*?</mark>)');
    int lastMatchEnd = 0;

    final matches = regExp.allMatches(text).toList();

    if (matches.isEmpty) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: maxLines != null ? TextOverflow.ellipsis : null,
      );
    }

    for (final match in matches) {
      if (match.start > lastMatchEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastMatchEnd, match.start),
            style: style,
          ),
        );
      }

      final matchText = match.group(0)!;
      if (matchText.startsWith('**')) {
        spans.add(
          TextSpan(
            text: matchText.substring(2, matchText.length - 2),
            style: style.copyWith(fontWeight: FontWeight.bold),
          ),
        );
      } else if (matchText.startsWith('<u>')) {
        spans.add(
          TextSpan(
            text: matchText.substring(3, matchText.length - 4),
            style: style.copyWith(decoration: TextDecoration.underline),
          ),
        );
      } else if (matchText.startsWith('<mark>')) {
        spans.add(
          TextSpan(
            text: matchText.substring(6, matchText.length - 7),
            style: style.copyWith(
              backgroundColor: const Color(0xFFF1AE27).withOpacity(0.4),
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      }

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastMatchEnd), style: style));
    }

    return Text.rich(
      TextSpan(children: spans),
      style: style,
      maxLines: maxLines,
    );
  }
}

/// Dialog showing the user's bookmarked articles.
class BookmarkedArticlesDialog extends StatefulWidget {
  const BookmarkedArticlesDialog({super.key});

  @override
  State<BookmarkedArticlesDialog> createState() =>
      _BookmarkedArticlesDialogState();
}

class _BookmarkedArticlesDialogState extends State<BookmarkedArticlesDialog> {
  bool _isLoading = true;
  List<HealthArticle> _articles = [];

  @override
  void initState() {
    super.initState();
    _fetchBookmarks();
  }

  Future<void> _fetchBookmarks() async {
    final user = ServiceLocator.instance.currentUser;
    if (user != null) {
      final repo = ServiceLocator.instance.healthArticleRepository;
      final articles = await repo.getBookmarkedArticles(user.id);
      if (mounted) {
        setState(() {
          _articles = articles;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
      'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year + 543}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'บทความที่บันทึกไว้',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            else if (_articles.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text(
                    'ยังไม่มีบทความที่บันทึกไว้',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                ),
                child: Scrollbar(
                  thumbVisibility: _articles.length > 5,
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _articles.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final article = _articles[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 8,
                        ),
                        title: Text(
                          article.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            'วันที่สร้างบทความ: ${_formatDate(article.createdAt)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  HealthArticlePage(article: article),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
