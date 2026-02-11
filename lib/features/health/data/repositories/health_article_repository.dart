import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/health_article_models.dart';

class HealthArticleRepository {
  final SupabaseClient _client;

  HealthArticleRepository(this._client);

  /// Fetch the latest health article with author details
  Future<HealthArticle?> getLatestArticle() async {
    try {
      print('HealthArticleRepository: Fetching latest article...');
      final response = await _client
          .from('health_articles')
          .select('*, users(username, profile_image_url)')
          .order('created_at', ascending: false)
          .limit(1);

      print('HealthArticleRepository: Response: $response');
      
      if (response != null && (response as List).isNotEmpty) {
        return HealthArticle.fromJson(response.first);
      }
      
      // Fallback to mock data if DB is empty for development
      print('HealthArticleRepository: No article found in DB, using mock data');
      return _getMockArticle();
    } catch (e) {
      print('HealthArticleRepository: Error: $e');
      // Fallback to mock data on error as well for development
      return _getMockArticle();
    }
  }

  HealthArticle _getMockArticle() {
    return HealthArticle(
      id: 'mock-article-1',
      title: 'เคล็ดลับการดูแลสุขภาพเชิงรุกสำหรับผู้หญิง: เริ่มต้นวันนี้เพื่ออนาคตที่ยั่งยืน',
      content: 'การดูแลสุขภาพเชิงรุก (Proactive Health) คือหัวใจสำคัญของการมีชีวิตที่ยืนยาวและมีคุณภาพ โดยเฉพาะในผู้หญิงที่มีการเปลี่ยนแปลงของฮอร์โมนและร่างกายแตกต่างกันไปในแต่ละช่วงวัย บทความนี้จะเจาะลึก 5 เคล็ดลับที่จะช่วยให้คุณก้าวทันปัญหาสุขภาพก่อนที่จะสายเกินไป...\n\n1. ตรวจสุขภาพสม่ำเสมอ\n2. อาหารที่สมดุล\n3. การออกกำลังกายที่เหมาะสม\n4. การจัดการความเครียด\n5. การนอนหลับที่มีคุณภาพ',
      authorId: 'mock-author-1',
      authorName: 'พญ. สมศรี สวยงาม',
      authorImage: 'https://i.pravatar.cc/150?u=mock-author',
      imageUrl: 'https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?q=80&w=1000',
      viewCount: 1250,
      likeCount: 45,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      updatedAt: DateTime.now().subtract(const Duration(days: 2)),
    );
  }

  /// Fetch article by ID
  Future<HealthArticle?> getArticleById(String id) async {
    try {
      final response = await _client
          .from('health_articles')
          .select('*, users(username, profile_image_url)')
          .eq('id', id)
          .single();

      return HealthArticle.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  /// Fetch products for an article
  Future<List<HealthArticleProduct>> getArticleProducts(String articleId) async {
    try {
      final response = await _client
          .from('health_article_products')
          .select()
          .eq('article_id', articleId)
          .order('created_at', ascending: false);

      if (response != null && (response as List).isNotEmpty) {
        return (response as List)
            .map((e) => HealthArticleProduct.fromJson(e))
            .toList();
      }
      
      // Fallback to mock brands/products
      if (articleId == 'mock-article-1') {
        return [
          HealthArticleProduct(
            id: 'p1',
            articleId: articleId,
            name: 'วิตามิน C 1000mg',
            imageUrl: 'https://images.unsplash.com/photo-1550575110-59f2394d1450?q=80&w=200',
            tagType: 'author',
            isApproved: true,
            createdAt: DateTime.now(),
          ),
          HealthArticleProduct(
            id: 'p2',
            articleId: articleId,
            name: 'อาหารเสริม Zinc',
            imageUrl: 'https://images.unsplash.com/photo-1584017962801-debd996a7c37?q=80&w=200',
            tagType: 'sponsor',
            isApproved: true,
            createdAt: DateTime.now(),
          ),
          HealthArticleProduct(
            id: 'p3',
            articleId: articleId,
            name: 'โปรตีนพืช',
            imageUrl: 'https://images.unsplash.com/photo-1593095948071-474c5cc2989d?q=80&w=200',
            tagType: 'user',
            isApproved: true,
            createdAt: DateTime.now(),
          ),
          HealthArticleProduct(
            id: 'p4',
            articleId: articleId,
            name: 'น้ำมันปลา Omega-3',
            imageUrl: 'https://images.unsplash.com/photo-1514733670139-4d87a1941d55?q=80&w=200',
            tagType: 'author',
            isApproved: true,
            createdAt: DateTime.now(),
          ),
        ];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Fetch comments for an article with user details
  Future<List<HealthArticleComment>> getArticleComments(String articleId) async {
    try {
      final response = await _client
          .from('health_article_comments')
          .select('*, users(username, profile_image_url)')
          .eq('article_id', articleId)
          .order('created_at', ascending: false);

      if (response != null && (response as List).isNotEmpty) {
        return (response as List)
            .map((e) => HealthArticleComment.fromJson(e))
            .toList();
      }

      // Fallback to mock comments
      if (articleId == 'mock-article-1') {
        return [
          HealthArticleComment(
            id: 'c1',
            articleId: articleId,
            userId: 'u1',
            username: 'สมชาย รักเรียน',
            content: 'ข้อมูลนี้ยอดเยี่ยมมากครับ ผมกำลังมองหาวิธีดูแลตัวเองอยู่พอดี ขอบคุณคุณหมอมากครับที่เอามาแบ่งปัน',
            commentNumber: 1,
            likeCount: 12,
            createdAt: DateTime.now().subtract(const Duration(hours: 5)),
          ),
          HealthArticleComment(
            id: 'c2',
            articleId: articleId,
            userId: 'u2',
            username: 'วิภาดา พัฒนา',
            content: 'บทความละเอียดมากค่ะ อยากทราบข้อมูลเรื่องการจัดการความเครียดเพิ่มเติมจังเลยค่ะ',
            commentNumber: 2,
            likeCount: 8,
            createdAt: DateTime.now().subtract(const Duration(hours: 3)),
          ),
        ];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Post a comment
  Future<HealthArticleComment?> postComment({
    required String articleId,
    required String userId,
    required String content,
    String? parentId,
    required int commentNumber,
  }) async {
    try {
      final response = await _client
          .from('health_article_comments')
          .insert({
            'article_id': articleId,
            'user_id': userId,
            'content': content,
            'parent_id': parentId,
            'comment_number': commentNumber,
          })
          .select('*, users(username, profile_image_url)')
          .single();

      return HealthArticleComment.fromJson(response);
    } catch (e) {
      return null;
    }
  }
}
