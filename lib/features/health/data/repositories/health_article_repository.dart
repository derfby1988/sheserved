import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/health_article_models.dart';

class HealthArticleRepository {
  final SupabaseClient _client;

  HealthArticleRepository(this._client);

  /// Fetch the latest health article with author details
  Future<HealthArticle?> getLatestArticle({String? userId}) async {
    try {
      print('HealthArticleRepository: Fetching latest article for user: $userId...');
      final response = await _client
          .from('health_articles')
          .select('*, users(username, profile_image_url)')
          .order('created_at', ascending: false)
          .limit(1);

      print('HealthArticleRepository: Response: $response');
      
        if (response != null && (response as List).isNotEmpty) {
        final data = response.first;
        final currentUserId = userId;
        
        bool isBookmarked = false;
        bool isLiked = false;
        if (currentUserId != null) {
          try {
            // Fetch interactions for this user and this article
            final interactions = await _client
                .from('health_article_interactions')
                .select('type, comment_id')
                .eq('article_id', data['id'])
                .eq('user_id', currentUserId);
                
            if (interactions != null) {
              for (var i in (interactions as List)) {
                // Check comment_id locally for reliability
                final rawCommentId = i['comment_id'];
                if (rawCommentId != null && rawCommentId.toString().toLowerCase() != 'null') continue;

                final type = i['type'] as String;
                if (type == 'bookmark') isBookmarked = true;
                if (type == 'like') isLiked = true;
              }
            }
          } catch (e) {
            print('Repository: Error checking latest article interactions: $e');
          }
        }
        
        final jsonMap = Map<String, dynamic>.from(data);
        
        // Fetch real total likes for this article (Article + All Comments)
        try {
          final totalLikes = await _client
              .from('health_article_interactions')
              .select('id')
              .eq('article_id', data['id'])
              .eq('type', 'like')
              .not('comment_id', 'is', null); // Only likes from comments
          
          jsonMap['like_count'] = (totalLikes as List).length;
        } catch (e) {
          print('Repository: Error counting total likes for latest: $e');
        }

        // Fetch actual comment count
        try {
          final commentResult = await _client
              .from('health_article_comments')
              .select('id')
              .eq('article_id', data['id']);
          
          jsonMap['comment_count'] = (commentResult as List).length;
        } catch (e) {
          print('Repository: Error counting comments for latest: $e');
        }

        jsonMap.remove('health_article_interactions'); // Remove joined interactions data
        jsonMap['is_bookmarked'] = isBookmarked;
        jsonMap['is_liked'] = isLiked;
        return HealthArticle.fromJson(jsonMap);
      }
      
    } catch (e) {
      print('HealthArticleRepository: Error: $e');
      return null;
    }
  }

  /// Fetch all health articles with author details with pagination
  Future<List<HealthArticle>> getAllArticles({
    String? category, 
    String? searchQuery,
    int page = 1, 
    int pageSize = 12,
    String? userId,
  }) async {
    try {
      print('HealthArticleRepository: Fetching articles from DB (Page $page) for user: $userId...');
      
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
          // 2. Check bookmark/like status for current user (Optimized with .in_)
          final currentUserId = userId;
          Set<String> bookmarkedArticleIds = {};
          Set<String> likedArticleIds = {};

          if (currentUserId != null) {
            try {
              // Extract article IDs to optimize query
              final articleIds = (response as List).map((e) => e['id'] as String).toList();
              
              if (articleIds.isNotEmpty) {
                final interactions = await _client
                    .from('health_article_interactions')
                    .select('article_id, type, comment_id')
                    .eq('user_id', currentUserId)
                    .filter('article_id', 'in', articleIds); // Fetch only relevant interactions

                if (interactions != null) {
                  print('DEBUG: Found ${(interactions as List).length} interactions for these ${articleIds.length} articles');
                  for (var i in (interactions as List)) {
                    // Filter locally for reliability
                    final rawCommentId = i['comment_id'];
                    // If it has a value, isn't 'null', AND isn't empty string -> It's a comment bookmark, skip it
                    if (rawCommentId != null && 
                        rawCommentId.toString().toLowerCase() != 'null' && 
                        rawCommentId.toString().trim().isNotEmpty) {
                      continue;
                    }

                    final articleId = i['article_id'].toString();
                    final type = i['type'] as String;
                    
                    if (type == 'bookmark') bookmarkedArticleIds.add(articleId);
                    if (type == 'like') likedArticleIds.add(articleId);
                  }
                }
              }
            } catch (e) {
              print('Repository: Error fetching article interactions: $e');
            }
          }

          dbArticles = (response as List).map((e) {
            final jsonMap = Map<String, dynamic>.from(e);
            final articleId = jsonMap['id'] as String;
            jsonMap['is_bookmarked'] = bookmarkedArticleIds.contains(articleId);
            jsonMap['is_liked'] = likedArticleIds.contains(articleId);
            return HealthArticle.fromJson(jsonMap);
          }).toList();

        // 3. Dynamically sum total likes (Article + All Comments) for real-time accuracy
        if (dbArticles.isNotEmpty) {
          try {
            final articleIds = dbArticles.map((e) => e.id).toList();
            // Fetch counts from interactions for true total
            final allLikes = await _client
                .from('health_article_interactions')
                .select('article_id')
                .filter('article_id', 'in', articleIds)
                .eq('type', 'like')
                .not('comment_id', 'is', null); // Only likes from comments (excludes Article level)
            
            if (allLikes != null) {
              final Map<String, int> totalLikesMap = {};
              for (var row in (allLikes as List)) {
                final aId = row['article_id'] as String;
                totalLikesMap[aId] = (totalLikesMap[aId] ?? 0) + 1;
              }
              
              dbArticles = dbArticles.map((article) {
                // Return the actual count from the interactions table
                return article.copyWith(
                  likeCount: totalLikesMap[article.id] ?? 0,
                );
              }).toList();
            }
          } catch (e) {
            print('Repository: Error summing total likes: $e');
          }
        }

        // 4. Dynamically count actual comments for each article
        if (dbArticles.isNotEmpty) {
          try {
            final articleIds = dbArticles.map((e) => e.id).toList();
            final commentCounts = await _client
                .from('health_article_comments')
                .select('article_id')
                .filter('article_id', 'in', articleIds);
            
            if (commentCounts != null) {
              final Map<String, int> commentCountMap = {};
              for (var row in (commentCounts as List)) {
                final aId = row['article_id'] as String;
                commentCountMap[aId] = (commentCountMap[aId] ?? 0) + 1;
              }
              
              dbArticles = dbArticles.map((article) {
                return article.copyWith(
                  commentCount: commentCountMap[article.id] ?? 0,
                );
              }).toList();
            }
          } catch (e) {
            print('Repository: Error counting comments: $e');
          }
        }
      }
      } catch (dbError) {
        print('HealthArticleRepository: DB Fetch Error: $dbError');
      }

      return dbArticles;
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
  Future<HealthArticle?> getArticleById(String id, {String? userId}) async {
    try {
      final response = await _client
          .from('health_articles')
          .select('*, users(username, profile_image_url)')
          .eq('id', id)
          .single();

      final currentUserId = userId;
      print('DEBUG: getArticleById - Article: $id, userId arg: $userId');
      
      bool isBookmarked = false;
      bool isLiked = false;
      
      if (currentUserId != null) {
        try {
          // Fetch all interactions for this user and article
          final interactions = await _client
              .from('health_article_interactions')
              .select() // Select ALL fields including comment_id
              .eq('article_id', id)
              .eq('user_id', currentUserId);
              
          if (interactions != null) {
            print('DEBUG: getArticleById - Found ${(interactions as List).length} interactions for Article $id');
            for (var i in (interactions as List)) {
              print('DEBUG: Interaction Record: $i');
              print('DEBUG: comment_id raw value: ${i['comment_id']} (Type: ${i['comment_id'].runtimeType})');

              // Check comment_id locally for reliability
              final rawCommentId = i['comment_id'];
              // If it has a value, isn't 'null', AND isn't empty string -> It's a comment
              if (rawCommentId != null && 
                  rawCommentId.toString().toLowerCase() != 'null' && 
                  rawCommentId.toString().trim().isNotEmpty) {
                 print('DEBUG: Skipped because comment_id is comment: $rawCommentId');
                 continue;
              }

              final type = i['type'] as String;
              if (type == 'bookmark') {
                 isBookmarked = true;
                 print('DEBUG: HIT! Bookmark found. isBookmarked set to true.');
              }
              if (type == 'like') isLiked = true;
            }
          } else {
             print('DEBUG: getArticleById - No interactions found (null response)');
          }
        } catch (e) {
          print('Repository: Error checking article interactions: $e');
        }
      }
      
      final jsonMap = Map<String, dynamic>.from(response);
    
    // Fetch real total likes for this article (Article + All Comments)
    try {
      final totalLikes = await _client
          .from('health_article_interactions')
          .select('id')
          .eq('article_id', id)
          .eq('type', 'like')
          .not('comment_id', 'is', null); // Only likes from comments
      
      jsonMap['like_count'] = (totalLikes as List).length;
    } catch (e) {
      print('Repository: Error counting total likes: $e');
    }

    // Fetch actual comment count
    try {
      final commentResult = await _client
          .from('health_article_comments')
          .select('id')
          .eq('article_id', id);
      
      jsonMap['comment_count'] = (commentResult as List).length;
    } catch (e) {
      print('Repository: Error counting comments: $e');
    }

    jsonMap['is_bookmarked'] = isBookmarked;
    jsonMap['is_liked'] = isLiked;
      return HealthArticle.fromJson(jsonMap);
    } catch (e) {
      print('Repository: Error in getArticleById: $e');
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
      
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Fetch comments for an article with user details and pagination
  Future<List<HealthArticleComment>> getArticleComments(
    String articleId, {
    String? currentUserId, // Added to check for likes
    int page = 1,
    int pageSize = 10,
    String sort = 'oldest', // oldest, newest, likes, bookmarks
  }) async {
    try {
      final from = (page - 1) * pageSize;
      final to = from + pageSize - 1;

      // Select comments with user details
      dynamic query = _client
          .from('health_article_comments')
          .select('*, users(username, profile_image_url)')
          .eq('article_id', articleId);
          
      // Apply sorting
      if (sort == 'newest') {
        query = query.order('created_at', ascending: false);
      } else if (sort == 'likes') {
        query = query.order('like_count', ascending: false);
      } else if (sort == 'bookmarks') {
        // Assuming bookmark_count exists in the table as per model
        query = query.order('bookmark_count', ascending: false);
      } else {
        // Default: 'oldest' (by comment_number ascending as requested)
        query = query.order('comment_number', ascending: true);
      }
      
      final response = await query.range(from, to);

      if (response != null && (response as List).isNotEmpty) {
        // Fetch all interactions for this user on this article (efficient simplified query)
        Set<String> likedCommentIds = {};
        Set<String> bookmarkedCommentIds = {};
        
        if (currentUserId != null) {
          try {
            final interactions = await _client
                .from('health_article_interactions')
                .select('comment_id, type')
                .eq('article_id', articleId)
                .eq('user_id', currentUserId)
                .not('comment_id', 'is', null); // Only care about comment interactions here
                
            if (interactions != null) {
              for (var i in (interactions as List)) {
                final cId = i['comment_id'] as String;
                final type = i['type'] as String;
                if (type == 'like') likedCommentIds.add(cId);
                if (type == 'bookmark') bookmarkedCommentIds.add(cId);
              }
            }
          } catch (e) {
            print('Repository: Error fetching interactions for comments: $e');
          }
        }

        return (response as List).map((e) {
          final commentId = e['id'] as String;
          final jsonMap = Map<String, dynamic>.from(e);
          
          // Hydrate status from our separate fetch
          jsonMap['is_liked'] = likedCommentIds.contains(commentId);
          jsonMap['is_bookmarked'] = bookmarkedCommentIds.contains(commentId);
          
          return HealthArticleComment.fromJson(jsonMap);
        }).toList();
      }

      return [];
    } catch (e) {
      print('Repository: Error fetching comments: $e');
      return [];
    }
  }

  /// Toggle interaction (like, bookmark, share)
  /// Returns a Map with:
  ///   'success': bool - whether the operation succeeded
  ///   'isActive': bool - whether the interaction is now active (true) or removed (false)
  ///   'newCount': int - the new total count for this interaction type on the target
  Future<Map<String, dynamic>> toggleInteraction({
    required String articleId,
    String? commentId,
    required String userId,
    required String type,
  }) async {
    try {
      // 1. Fetch all interactions for this user/article/type (without comment filter first)
      final existingList = await _client
          .from('health_article_interactions')
          .select()
          .eq('user_id', userId)
          .eq('article_id', articleId)
          .eq('type', type);
      
      Map<String, dynamic>? targetInteraction;

      if (existingList != null) {
        for (var i in (existingList as List)) {
          final cId = i['comment_id'];
          // Robust check for matching comment_id
          if (commentId == null) {
            // Looking for article interaction (comment_id should be null, "null", or empty)
            if (cId == null || 
                cId.toString().toLowerCase() == 'null' || 
                cId.toString().trim().isEmpty) {
              targetInteraction = i;
              break;
            }
          } else {
            // Looking for comment interaction
            if (cId.toString() == commentId.toString()) {
              targetInteraction = i;
              break;
            }
          }
        }
      }
      
      if (targetInteraction != null) {
        // 2. Remove if exists
        await _client
            .from('health_article_interactions')
            .delete()
            .eq('id', targetInteraction['id']);
        
        print('Repository: Removed interaction $type for ${commentId ?? articleId}');

        // 3. Update counts
      final newCount = await _countInteractions(
        articleId: articleId, commentId: commentId, type: type,
      );
      await _updateCountColumn(
        articleId: articleId, commentId: commentId, type: type, count: newCount,
      );

      // If it's a 'like', also ensure the ARTICLE's total count is updated
      int finalReturnCount = newCount;
      if (type == 'like') {
        final totalArticleLikes = await _countInteractions(
          articleId: articleId, 
          type: 'like', 
          totalForArticle: true,
        );
        
        // Update the article table with the total
        await _updateCountColumn(
          articleId: articleId, 
          commentId: null, 
          type: 'like', 
          count: totalArticleLikes,
        );

        // If we are liking the article directly, return the total count
        if (commentId == null) {
          finalReturnCount = totalArticleLikes;
        }
      }

      return {'success': true, 'isActive': false, 'newCount': finalReturnCount};
    } else {
      // 2. Add if not exists
      await _client.from('health_article_interactions').insert({
        'user_id': userId,
        'article_id': articleId,
        'comment_id': commentId,
        'type': type,
      });
      print('Repository: Added interaction $type for ${commentId ?? articleId}');

      // 3. Update counts
      final newCount = await _countInteractions(
        articleId: articleId, commentId: commentId, type: type,
      );
      await _updateCountColumn(
        articleId: articleId, commentId: commentId, type: type, count: newCount,
      );

      // If it's a 'like', also ensure the ARTICLE's total count is updated
      int finalReturnCount = newCount;
      if (type == 'like') {
        final totalArticleLikes = await _countInteractions(
          articleId: articleId, 
          type: 'like', 
          totalForArticle: true,
        );
        
        // Update the article table with the total
        await _updateCountColumn(
          articleId: articleId, 
          commentId: null, 
          type: 'like', 
          count: totalArticleLikes,
        );

        // If we are liking the article directly, return the total count
        if (commentId == null) {
          finalReturnCount = totalArticleLikes;
        }
      }

      return {'success': true, 'isActive': true, 'newCount': finalReturnCount};
    }
    } catch (e) {
      print('Error toggling interaction: $e');
      return {'success': false, 'isActive': false, 'newCount': 0};
    }
  }

  /// Count the actual number of interactions of a given type on an article or comment
  Future<int> _countInteractions({
    required String articleId,
    String? commentId,
    required String type,
    bool totalForArticle = false, // Added parameter
  }) async {
    try {
      final interactions = await _client
          .from('health_article_interactions')
          .select('comment_id')
          .eq('article_id', articleId)
          .eq('type', type);

      if (interactions == null) return 0;

      final interactionList = interactions as List;
      
      if (totalForArticle) {
        // Return total count for the article (ONLY from Comments, as requested)
        return interactionList.where((i) {
          final cId = i['comment_id'];
          return cId != null && 
                 cId.toString().toLowerCase() != 'null' && 
                 cId.toString().trim().isNotEmpty;
        }).length;
      }

      if (commentId == null) {
        // Count article interactions (where comment_id is null-ish)
        return interactionList.where((i) {
          final cId = i['comment_id'];
          return cId == null || 
                 cId.toString().toLowerCase() == 'null' || 
                 cId.toString().trim().isEmpty;
        }).length;
      } else {
        // Count specific comment interactions
        return interactionList.where((i) {
          final cId = i['comment_id'];
          return cId != null && cId.toString() == commentId.toString();
        }).length;
      }
    } catch (e) {
      print('Error counting interactions: $e');
      return 0;
    }
  }

  /// Directly update the count column in the target table
  Future<void> _updateCountColumn({
    required String articleId,
    String? commentId,
    required String type,
    required int count,
  }) async {
    try {
      final columnName = '${type}_count'; // like_count or bookmark_count

      if (commentId != null) {
        await _client
            .from('health_article_comments')
            .update({columnName: count})
            .eq('id', commentId);
      } else {
        await _client
            .from('health_articles')
            .update({columnName: count})
            .eq('id', articleId);
      }
      print('Repository: Updated $columnName = $count for ${commentId ?? articleId}');
    } catch (e) {
      print('Error updating count column: $e');
    }
  }

  List<HealthArticleComment> _getMockComments(String articleId) {
    // Generate 12-25 comments for each mock article
    final count = articleId == 'mock-article-1' ? 25 : 12;
    return List.generate(count, (i) {
      // Logic reversed to match "ascending=true" (Oldest First)
      // i=0 is Comment #1, should be oldest (e.g. 5 days ago)
      // i=count-1 is Comment #N, should be newest (e.g. today)
      final hoursAgo = (count - 1 - i) * 2;
      
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
        createdAt: DateTime.now().subtract(Duration(hours: hoursAgo)),
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
      return 0;
    } catch (e) {
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
