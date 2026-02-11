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

  /// Fetch all health articles with author details with pagination
  Future<List<HealthArticle>> getAllArticles({
    String? category, 
    String? searchQuery,
    int page = 1, 
    int pageSize = 12,
  }) async {
    try {
      print('HealthArticleRepository: Fetching articles from DB and Mocks (Page $page)...');
      
      // 1. Get from Supabase
      List<HealthArticle> dbArticles = [];
      try {
        var query = _client
            .from('health_articles')
            .select('*, users(username, profile_image_url)');
        
        if (category != null && category != 'ทั้งหมด' && 
            !['ยอดนิยม', 'ล่าสุด', 'แนะนำ'].contains(category)) {
          query = query.eq('category', category);
        }

        if (searchQuery != null && searchQuery.isNotEmpty) {
          query = query.or('title.ilike.%$searchQuery%,content.ilike.%$searchQuery%');
        }

        final response = await query.order('created_at', ascending: false);
        if (response != null) {
          dbArticles = (response as List).map((e) => HealthArticle.fromJson(e)).toList();
        }
      } catch (dbError) {
        print('HealthArticleRepository: DB Fetch Error (falling back to mocks): $dbError');
      }

      // 2. Get Mock Articles
      var mockArticles = _getMockArticlesList();
      
      // 3. Filter Mocks
      if (category != null && category != 'ทั้งหมด') {
        if (['ยอดนิยม', 'ล่าสุด', 'แนะนำ'].contains(category)) {
          // Special tags logic (for demo, just scramble or take specific range)
          if (category == 'ยอดนิยม') mockArticles.sort((a, b) => b.viewCount.compareTo(a.viewCount));
          if (category == 'ล่าสุด') mockArticles.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        } else {
          mockArticles = mockArticles.where((a) => a.category == category).toList();
        }
      }
      
      if (searchQuery != null && searchQuery.isNotEmpty) {
        final query = searchQuery.toLowerCase();
        mockArticles = mockArticles.where((a) => 
          a.title.toLowerCase().contains(query) || 
          a.content.toLowerCase().contains(query)).toList();
      }

      // 4. Combine (DB First, then Mocks)
      final List<HealthArticle> allCombined = [...dbArticles, ...mockArticles];
      
      // 5. Apply Pagination
      final start = (page - 1) * pageSize;
      if (start >= allCombined.length) return [];
      final end = start + pageSize;
      
      return allCombined.sublist(
        start, 
        end > allCombined.length ? allCombined.length : end
      );
    } catch (e) {
      print('HealthArticleRepository: Critical Error: $e');
      return [];
    }
  }

  List<HealthArticle> _getMockArticlesList() {
    final List<HealthArticle> baseArticles = [
      _getMockArticle().copyWith(
        id: 'mock-article-1',
        title: 'เคล็ดลับการดูแลสุขภาพเชิงรุกสำหรับผู้หญิง: เริ่มต้นวันนี้เพื่ออนาคตที่ยั่งยืน',
        category: 'สุขภาพผู้หญิง',
      ),
      _getMockArticle().copyWith(
        id: 'mock-article-2',
        title: 'การตรวจสุขภาพเบื้องต้นที่บ้าน: สิ่งที่คุณควรรู้',
        category: 'สมรรถภาพทางกาย',
        imageUrl: 'https://images.unsplash.com/photo-1576091160550-217359f4ecf8?q=80&w=1000',
      ),
      _getMockArticle().copyWith(
        id: 'mock-article-3',
        title: 'อาหาร 10 ชนิดบำรุงหัวใจและหลอดเลือด',
        category: 'โภชนาการ',
        imageUrl: 'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?q=80&w=1000',
      ),
      _getMockArticle().copyWith(
        id: 'mock-article-4',
        title: 'โยคะลดปวดหลังจากการทำงาน (Office Syndrome)',
        category: 'สมรรถภาพทางกาย',
        imageUrl: 'https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?q=80&w=1000',
      ),
      _getMockArticle().copyWith(
        id: 'mock-article-5',
        title: 'การนอนหลับที่มีคุณภาพสำคัญต่อสมองอย่างไร',
        category: 'สุขภาพจิต',
        imageUrl: 'https://images.unsplash.com/photo-1541781774459-bb2af2f05b55?q=80&w=1000',
      ),
    ];

    final List<HealthArticle> allArticles = [...baseArticles];
    
    // Generate 35 more articles for pagination testing (Total 40)
    final categories = ['โภชนาการ', 'สมรรถภาพทางกาย', 'สุขภาพจิต', 'สุขภาพผู้หญิง', 'ความงามและผิวพรรณ', 'การแพทย์'];
    final titles = [
      'วิตามินที่จำเป็นสำหรับวัยทำงาน',
      'วิธีลดน้ำหนักแบบยั่งยืน',
      'การดูแลหัวใจด้วยการเดิน',
      'สมุนไพรไทยแก้เจ็บคอร้อนใน',
      'เทคนิคการหายใจลดความเครียด',
      'สัญญาณเตือนโรคมะเร็ง',
      'การกินแบบ Intermittent Fasting (IF)',
      'โปรตีนพืช vs โปรตีนสัตว์',
      'การดูแลสายตาจากหน้าจอคอมพิวเตอร์',
      'วิธีเลือกครีมกันแดดให้เหมาะกับผิว',
    ];

    for (int i = 6; i <= 40; i++) {
      allArticles.add(
        _getMockArticle().copyWith(
          id: 'mock-article-$i',
          title: '${titles[i % titles.length]} (Part ${i ~/ 10 + 1}) #$i',
          category: categories[i % categories.length],
          imageUrl: 'https://picsum.photos/seed/art$i/800/600',
          viewCount: 100 + (i * 20),
          likeCount: 10 + (i % 30),
          createdAt: DateTime.now().subtract(Duration(days: i)),
        ),
      );
    }

    return allArticles;
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
      if (id.startsWith('mock-')) {
        final allMocks = await getAllArticles();
        return allMocks.firstWhere((element) => element.id == id, orElse: () => _getMockArticle());
      }
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
      if (articleId.startsWith('mock-')) {
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
        ];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Fetch comments for an article with user details and pagination
  Future<List<HealthArticleComment>> getArticleComments(
    String articleId, {
    int page = 1,
    int pageSize = 10,
  }) async {
    try {
      final from = (page - 1) * pageSize;
      final to = from + pageSize - 1;

      final response = await _client
          .from('health_article_comments')
          .select('*, users(username, profile_image_url)')
          .eq('article_id', articleId)
          .order('created_at', ascending: false)
          .range(from, to);

      if (response != null && (response as List).isNotEmpty) {
        return (response as List)
            .map((e) => HealthArticleComment.fromJson(e))
            .toList();
      }

      // Fallback to mock comments
      if (articleId.startsWith('mock-')) {
        final allComments = _getMockComments(articleId);
        final start = (page - 1) * pageSize;
        if (start >= allComments.length) return [];
        final end = start + pageSize;
        return allComments.sublist(start, end > allComments.length ? allComments.length : end);
      }
      return [];
    } catch (e) {
      if (articleId.startsWith('mock-')) {
        return _getMockComments(articleId).take(pageSize).toList();
      }
      return [];
    }
  }

  List<HealthArticleComment> _getMockComments(String articleId) {
    // Generate 12-25 comments for each mock article
    final count = articleId == 'mock-article-1' ? 25 : 12;
    return List.generate(count, (i) {
      return HealthArticleComment(
        id: 'mock-c-$articleId-$i',
        articleId: articleId,
        userId: 'u$i',
        username: 'สมาชิกหมายเลข ${100 + i}',
        content: i % 2 == 0 
          ? 'ข้อมูลมีประโยชน์มากครับ ขอบคุณสำหรับการแบ่งปันสาระดีๆ แบบนี้' 
          : 'อยากให้ทำบทความเกี่ยวกับหัวข้อนี้เพิ่มเติมจังเลยค่ะ สนใจมาก',
        commentNumber: i + 1,
        likeCount: (10 - i).clamp(0, 50),
        createdAt: DateTime.now().subtract(Duration(hours: i * 2)),
      );
    });
  }

  /// Get total comment count for an article
  Future<int> getArticleCommentCount(String articleId) async {
    try {
      final response = await _client
          .from('health_article_comments')
          .select('id')
          .eq('article_id', articleId);
      
      if (response != null && (response as List).isNotEmpty) {
        return (response as List).length;
      }
      
      if (articleId.startsWith('mock-')) {
        return _getMockComments(articleId).length;
      }
      return 0;
    } catch (e) {
      if (articleId.startsWith('mock-')) {
        return _getMockComments(articleId).length;
      }
      return 0;
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
