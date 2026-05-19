import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/health_article_models.dart';

class HealthArticleRepository {
  final SupabaseClient _client;

  HealthArticleRepository(this._client);

  /// Fetch the latest health article with author details
  Future<HealthArticle?> getLatestArticle({String? userId}) async {
    try {
      debugPrint(
        'HealthArticleRepository: Fetching latest article for user: $userId...',
      );
      final response = await _client
          .from('health_articles')
          .select('*, users(username, profile_image_url)')
          .order('created_at', ascending: false)
          .limit(1);

      debugPrint('HealthArticleRepository: Response: $response');

      if ((response as List).isNotEmpty) {
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
                if (rawCommentId != null &&
                    rawCommentId.toString().toLowerCase() != 'null')
                  continue;

                final type = i['type'] as String;
                if (type == 'bookmark') isBookmarked = true;
                if (type == 'like') isLiked = true;
              }
            }
          } catch (e) {
            debugPrint(
              'Repository: Error checking latest article interactions: $e',
            );
          }
        }

        final jsonMap = Map<String, dynamic>.from(data);

        // Fetch real likes for this article (Article Head ONLY)
        try {
          final totalLikes = await _client
              .from('health_article_interactions')
              .select('id')
              .eq('article_id', data['id'])
              .eq('type', 'bookmark')
              .filter('comment_id', 'is', null); // ONLY Article-level likes

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

        jsonMap.remove(
          'health_article_interactions',
        ); // Remove joined interactions data
        jsonMap['is_bookmarked'] = isBookmarked;
        jsonMap['is_liked'] = isLiked;
        return HealthArticle.fromJson(jsonMap);
      }
    } catch (e) {
      debugPrint('HealthArticleRepository: Error: $e');
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
      debugPrint(
        'HealthArticleRepository: Fetching articles from DB (Page $page) for user: $userId...',
      );

      // 1. Get from Supabase
      List<HealthArticle> dbArticles = [];
      try {
        var query = _client
            .from('health_articles')
            .select('*, users(username, profile_image_url)');

        if (category != null &&
            category != 'ทั้งหมด' &&
            !['ยอดนิยม', 'ล่าสุด', 'แนะนำ'].contains(category)) {
          query = query.eq('category', category);
        }

        if (searchQuery != null && searchQuery.isNotEmpty) {
          query = query.or(
            'title.ilike.%$searchQuery%,content.ilike.%$searchQuery%',
          );
        }

        final response = await query.order('created_at', ascending: false);
        if ((response as List).isNotEmpty) {
          // 2. Check bookmark/like status for current user (Optimized with .in_)
          final currentUserId = userId;
          Set<String> bookmarkedArticleIds = {};
          Set<String> likedArticleIds = {};

          if (currentUserId != null) {
            try {
              // Extract article IDs to optimize query
              final articleIds = (response as List)
                  .map((e) => e['id'] as String)
                  .toList();

              if (articleIds.isNotEmpty) {
                final interactions = await _client
                    .from('health_article_interactions')
                    .select('article_id, type, comment_id')
                    .eq('user_id', currentUserId)
                    .filter(
                      'article_id',
                      'in',
                      articleIds,
                    ); // Fetch only relevant interactions

                if ((interactions as List).isNotEmpty) {
                  debugPrint(
                    'DEBUG: Found ${interactions.length} interactions for these ${articleIds.length} articles',
                  );
                  for (var i in interactions) {
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
              debugPrint('Repository: Error fetching article interactions: $e');
            }
          }

          dbArticles = (response as List).map((e) {
            final jsonMap = Map<String, dynamic>.from(e);
            final articleId = jsonMap['id'] as String;
            jsonMap['is_bookmarked'] = bookmarkedArticleIds.contains(articleId);
            jsonMap['is_liked'] = likedArticleIds.contains(articleId);
            return HealthArticle.fromJson(jsonMap);
          }).toList();

          // 3. Dynamically count Article Head likes for real-time accuracy
          if (dbArticles.isNotEmpty) {
            try {
              final articleIds = dbArticles.map((e) => e.id).toList();
              // Fetch counts from interactions for Article Head
              final allLikes = await _client
                  .from('health_article_interactions')
                  .select('article_id')
                  .filter('article_id', 'in', articleIds)
                  .eq('type', 'bookmark')
                  .filter('comment_id', 'is', null); // ONLY Article-level likes

              if ((allLikes as List).isNotEmpty) {
                final Map<String, int> totalLikesMap = {};
                for (var row in allLikes) {
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
              debugPrint('Repository: Error summing total likes: $e');
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

              if ((commentCounts as List).isNotEmpty) {
                final Map<String, int> commentCountMap = {};
                for (var row in commentCounts) {
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
              debugPrint('Repository: Error counting comments: $e');
            }
          }

          // 5. Final Sorting and Filtering based on requested filter
          if (category == 'ยอดนิยม') {
            // Filter out articles with 0 likes
            dbArticles = dbArticles.where((a) => a.likeCount > 0).toList();
            // Sort by total likes (sum of likes from all comments)
            dbArticles.sort((a, b) => b.likeCount.compareTo(a.likeCount));
          } else if (category == 'แนะนำ') {
            // Filter out articles with 0 comments
            dbArticles = dbArticles.where((a) => a.commentCount > 0).toList();
            // Sort by total comment count
            dbArticles.sort((a, b) => b.commentCount.compareTo(a.commentCount));
          } else {
            // Default sorting (Latest): Includes 'ล่าสุด', 'ทั้งหมด', and specific topic categories
            dbArticles.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          }
        }
      } catch (dbError) {
        debugPrint('HealthArticleRepository: DB Fetch Error: $dbError');
      }

      return dbArticles;
    } catch (e) {
      debugPrint('HealthArticleRepository: Critical Error: $e');
      return [];
    }
  }

  /// Fetch all health articles with author details with pagination
  Future<HealthArticle?> getArticleById(String id, {String? userId}) async {
    try {
      final response = await _client
          .from('health_articles')
          .select('*, users(username, profile_image_url)')
          .eq('id', id)
          .single();

      final currentUserId = userId;
      debugPrint('DEBUG: getArticleById - Article: $id, userId arg: $userId');

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

          if ((interactions as List).isNotEmpty) {
            debugPrint(
              'DEBUG: getArticleById - Found ${interactions.length} interactions for Article $id',
            );
            for (var i in interactions) {
              debugPrint('DEBUG: Interaction Record: $i');
              debugPrint(
                'DEBUG: comment_id raw value: ${i['comment_id']} (Type: ${i['comment_id'].runtimeType})',
              );

              // Check comment_id locally for reliability
              final rawCommentId = i['comment_id'];
              // If it has a value, isn't 'null', AND isn't empty string -> It's a comment
              if (rawCommentId != null &&
                  rawCommentId.toString().toLowerCase() != 'null' &&
                  rawCommentId.toString().trim().isNotEmpty) {
                debugPrint(
                  'DEBUG: Skipped because comment_id is comment: $rawCommentId',
                );
                continue;
              }

              final type = i['type'] as String;
              if (type == 'bookmark') {
                isBookmarked = true;
                debugPrint(
                  'DEBUG: HIT! Bookmark found. isBookmarked set to true.',
                );
              }
              if (type == 'like') isLiked = true;
            }
          }
        } catch (e) {
          debugPrint('Repository: Error checking article interactions: $e');
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
            .filter('comment_id', 'is', null); // ONLY Article-level likes

        jsonMap['like_count'] = (totalLikes as List).length;
      } catch (e) {
        debugPrint('Repository: Error counting total likes: $e');
      }

      // Fetch actual comment count
      try {
        final commentResult = await _client
            .from('health_article_comments')
            .select('id')
            .eq('article_id', id);

        jsonMap['comment_count'] = (commentResult as List).length;
      } catch (e) {
        debugPrint('Repository: Error counting comments: $e');
      }

      jsonMap['is_bookmarked'] = isBookmarked;
      jsonMap['is_liked'] = isLiked;
      return HealthArticle.fromJson(jsonMap);
    } catch (e) {
      debugPrint('Repository: Error in getArticleById: $e');
      return null;
    }
  }

  /// Fetch products for an article with tagger info
  Future<List<HealthArticleProduct>> getArticleProducts(
    String articleId,
  ) async {
    try {
      final response = await _client
          .from('health_article_products')
          .select('*, users!tagged_by_id(profession_id)')
          .eq('article_id', articleId)
          .order('created_at', ascending: false);

      if ((response as List).isNotEmpty) {
        return (response as List).map((e) {
          final jsonMap = Map<String, dynamic>.from(e);
          // Extract user category from joined users table
          if (jsonMap['users'] != null) {
            final professionId = jsonMap['users']['profession_id'];
            if (professionId == '00000000-0000-0000-0000-000000000001') {
              jsonMap['tagger_user_category'] = 'consumer';
            } else if (professionId == '00000000-0000-0000-0000-000000000002' ||
                professionId == '00000000-0000-0000-0000-000000000003') {
              jsonMap['tagger_user_category'] = 'provider';
            } else {
              jsonMap['tagger_user_category'] = 'other';
            }
          }
          return HealthArticleProduct.fromJson(jsonMap);
        }).toList();
      }

      return [];
    } catch (e) {
      debugPrint('Repository: Error fetching products: $e');
      return [];
    }
  }

  /// Request a tag for an article
  Future<bool> requestArticleProduct({
    required String articleId,
    required String userId,
    required String name,
    String? url,
    String? imageUrl,
    String tagType = 'product',
  }) async {
    try {
      // If the requester is the article author, auto-approve and set type to 'author'
      bool autoApprove = false;
      String actualTagType = tagType == 'product' ? 'user' : tagType;

      try {
        final articleResponse = await _client
            .from('health_articles')
            .select('author_id')
            .eq('id', articleId)
            .single();
        if (articleResponse != null && articleResponse['author_id'] == userId) {
          autoApprove = true;
          actualTagType = 'author';
        }
      } catch (e) {
        debugPrint(
          'Repository: Note - Could not verify author for auto-approve: $e',
        );
      }

      await _client.from('health_article_products').insert({
        'article_id': articleId,
        'tagged_by_id': userId,
        'name': name,
        'url': url,
        'image_url': imageUrl,
        'tag_type': actualTagType,
        'is_approved': autoApprove,
      });
      return true;
    } catch (e) {
      debugPrint('Repository: Error requesting product tag: $e');
      if (e is PostgrestException) {
        debugPrint(
          'Repository: DB Error Details: ${e.message} - ${e.details} - ${e.hint}',
        );
      }
      return false;
    }
  }

  /// Fetch pending tag requests for an author\'s articles
  Future<List<Map<String, dynamic>>> getPendingTagRequests(
    String authorId,
  ) async {
    try {
      // Get all articles for this author first
      final articlesResponse = await _client
          .from('health_articles')
          .select('id')
          .eq('author_id', authorId);

      final articlesList = articlesResponse as List;
      if (articlesList.isEmpty) return [];

      final articleIds = articlesList.map((e) => e['id'] as String).toList();

      // Get pending products for these articles using standard list filter
      final response = await _client
          .from('health_article_products')
          .select(
            '*, users!tagged_by_id(username, profile_image_url), health_articles(title)',
          )
          .filter('article_id', 'in', articleIds) // Use standard 'in' filter
          .eq('is_approved', false)
          .order('created_at', ascending: false);

      final responseList = response as List;
      return responseList.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Repository: Error fetching pending requests: $e');
      return [];
    }
  }

  /// Approve a tag request
  Future<bool> approveArticleProduct(String productId) async {
    try {
      await _client
          .from('health_article_products')
          .update({'is_approved': true})
          .eq('id', productId);
      return true;
    } catch (e) {
      debugPrint('Repository: Error approving product tag: $e');
      return false;
    }
  }

  /// Reject/Delete a tag request
  Future<bool> deleteArticleProduct(String productId) async {
    try {
      await _client
          .from('health_article_products')
          .delete()
          .eq('id', productId);
      return true;
    } catch (e) {
      debugPrint('Repository: Error deleting product tag: $e');
      return false;
    }
  }

  /// Fetch comments for an article with user details and pagination
  Future<List<HealthArticleComment>> getArticleComments(
    String articleId, {
    String? currentUserId, // Added to check for likes
    bool isArticleAuthor =
        false, // Whether the current user is the article author
    int page = 1,
    int pageSize = 10,
    String sort = 'oldest', // oldest, newest, likes, bookmarks
  }) async {
    try {
      final from = (page - 1) * pageSize;
      final to = from + pageSize - 1;

      // To handle hierarchy correctly during pagination, we paginate by ROOT comments
      // and then fetch all replies for those roots.

      // 1. Fetch Root Comments for this page
      dynamic rootQuery = _client
          .from('health_article_comments')
          .select('id')
          .eq('article_id', articleId)
          .filter('parent_id', 'is', null);

      if (sort == 'newest') {
        rootQuery = rootQuery.order('created_at', ascending: false);
      } else if (sort == 'likes') {
        rootQuery = rootQuery.order('like_count', ascending: false);
      } else if (sort == 'bookmarks') {
        rootQuery = rootQuery.order('bookmark_count', ascending: false);
      } else {
        rootQuery = rootQuery.order('comment_number', ascending: true);
      }

      final rootResponse = await rootQuery.range(from, to);

      if ((rootResponse as List).isEmpty) {
        return [];
      }

      final rootIds = rootResponse.map((e) => e['id'] as String).toList();

      // 2. Fetch all comments (roots + their replies)
      // We fetch where id in rootIds OR parent_id in rootIds
      dynamic query = _client
          .from('health_article_comments')
          .select('*, users(username, profile_image_url)')
          .or(
            'id.in.(${rootIds.map((id) => "\"$id\"").join(",")}),parent_id.in.(${rootIds.map((id) => "\"$id\"").join(",")})',
          );

      if (sort == 'newest') {
        query = query.order('created_at', ascending: false);
      } else if (sort == 'likes') {
        query = query.order('like_count', ascending: false);
      } else if (sort == 'bookmarks') {
        query = query.order('bookmark_count', ascending: false);
      } else {
        query = query.order('comment_number', ascending: true);
      }

      final response = await query;

      if ((response as List).isNotEmpty) {
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
                .not(
                  'comment_id',
                  'is',
                  null,
                ); // Only care about comment interactions here

            if ((interactions as List).isNotEmpty) {
              for (var i in interactions) {
                final cId = i['comment_id'] as String;
                final type = i['type'] as String;
                if (type == 'like') likedCommentIds.add(cId);
                if (type == 'bookmark') bookmarkedCommentIds.add(cId);
              }
            }
          } catch (e) {
            debugPrint(
              'Repository: Error fetching interactions for comments: $e',
            );
          }
        }

        // Filter comments based on visibility rules
        final filteredComments = response
            .where((e) {
              final isHidden = e['is_hidden'] == true;
              final commentUserId = e['user_id'] as String;

              // Article author sees everything
              if (isArticleAuthor) return true;

              // Comment author sees their own comments even if hidden
              if (currentUserId != null && commentUserId == currentUserId)
                return true;

              // Everyone else only sees non-hidden comments
              return !isHidden;
            })
            .map((e) {
              final commentId = e['id'] as String;
              final jsonMap = Map<String, dynamic>.from(e);

              // Hydrate status from our separate fetch
              jsonMap['is_liked'] = likedCommentIds.contains(commentId);
              jsonMap['is_bookmarked'] = bookmarkedCommentIds.contains(
                commentId,
              );

              return HealthArticleComment.fromJson(jsonMap);
            })
            .toList();

        return filteredComments;
      }

      return [];
    } catch (e) {
      debugPrint('Repository: Error fetching comments: $e');
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
      // 1. Fetch relevant interactions for this user/article/type
      final existingList = await _client
          .from('health_article_interactions')
          .select()
          .eq('user_id', userId)
          .eq('article_id', articleId)
          .eq('type', type);

      Map<String, dynamic>? targetInteraction;

      if ((existingList as List).isNotEmpty) {
        for (var i in existingList) {
          final cId = i['comment_id'];
          if (commentId == null) {
            if (cId == null ||
                cId.toString().toLowerCase() == 'null' ||
                cId.toString().trim().isEmpty) {
              targetInteraction = i;
              break;
            }
          } else {
            if (cId.toString() == commentId.toString()) {
              targetInteraction = i;
              break;
            }
          }
        }
      }

      bool isNowActive;
      if (targetInteraction != null) {
        // Remove if exists
        await _client
            .from('health_article_interactions')
            .delete()
            .eq('id', targetInteraction['id']);
        isNowActive = false;
        debugPrint(
          'Repository: Removed interaction $type for ${commentId ?? articleId}',
        );
      } else {
        // Add if not exists
        await _client.from('health_article_interactions').insert({
          'user_id': userId,
          'article_id': articleId,
          'comment_id': commentId,
          'type': type,
        });
        isNowActive = true;
        debugPrint(
          'Repository: Added interaction $type for ${commentId ?? articleId}',
        );
      }

      // 3. Update the specific target count column (Article or Comment)
      final specificCount = await _countInteractions(
        articleId: articleId,
        commentId: commentId,
        type: type,
      );

      await _updateCountColumn(
        articleId: articleId,
        commentId: commentId,
        type: type,
        count: specificCount,
      );

      // 4. If we liked/bookmarked a COMMENT, we do NOT change the article header count.
      // If we liked/bookmarked the ARTICLE head, the header is updated by step 3.

      return {
        'success': true,
        'isActive': isNowActive,
        'newCount': specificCount,
      };
    } catch (e) {
      debugPrint('Error toggling interaction: $e');
      return {'success': false, 'isActive': false, 'newCount': 0};
    }
  }

  /// Count the actual number of interactions of a given type on an article or comment
  Future<int> _countInteractions({
    required String articleId,
    String? commentId,
    required String type,
    bool totalForArticle = false,
  }) async {
    try {
      final query = _client
          .from('health_article_interactions')
          .select('comment_id')
          .eq('article_id', articleId)
          .eq('type', type);

      final interactions = await query;
      final interactionList = interactions as List;

      if (totalForArticle) {
        // Global total (Article + All Comments)
        return interactionList.length;
      }

      if (commentId == null) {
        // Article head only (where comment_id is null)
        return interactionList.where((i) {
          final cId = i['comment_id'];
          return cId == null ||
              cId.toString().toLowerCase() == 'null' ||
              cId.toString().trim().isEmpty;
        }).length;
      } else {
        // Specific comment only
        return interactionList.where((i) {
          final cId = i['comment_id'];
          return cId != null && cId.toString() == commentId.toString();
        }).length;
      }
    } catch (e) {
      debugPrint('Error counting interactions: $e');
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
      debugPrint(
        'Repository: Updated $columnName = $count for ${commentId ?? articleId}',
      );
    } catch (e) {
      debugPrint('Error updating count column: $e');
    }
  }

  /// Get total comment count for an article
  Future<int> getArticleCommentCount(
    String articleId, {
    bool rootsOnly = false,
  }) async {
    try {
      dynamic query = _client
          .from('health_article_comments')
          .select('id')
          .eq('article_id', articleId);

      if (rootsOnly) {
        query = query.filter('parent_id', 'is', null);
      }

      final response = await query.count(CountOption.exact);
      return response.count ?? 0;
    } catch (e) {
      debugPrint('Repository: Error getting comment count: $e');
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

      // Update the comment count in the health_articles table for fast sorting later
      try {
        final newCount = await getArticleCommentCount(articleId);
        await _client
            .from('health_articles')
            .update({'comment_count': newCount})
            .eq('id', articleId);
      } catch (updateError) {
        debugPrint(
          'Repository: Failed to sync comment count to article table: $updateError',
        );
      }

      return HealthArticleComment.fromJson(response);
    } catch (e) {
      debugPrint('Repository: Error posting comment: $e');
      return null;
    }
  }

  /// Update a comment
  Future<HealthArticleComment?> updateComment({
    required String commentId,
    required String content,
  }) async {
    try {
      // First, get the current comment to store the old content
      final currentComment = await _client
          .from('health_article_comments')
          .select()
          .eq('id', commentId)
          .single();

      final oldContent = currentComment['content'];
      final currentEditCount = currentComment['edit_count'] ?? 0;
      final newEditCount = currentEditCount + 1;

      // Create edit history record
      await _client.from('health_article_comment_history').insert({
        'comment_id': commentId,
        'old_content': oldContent,
        'new_content': content,
        'edit_number': newEditCount,
        'edited_at': DateTime.now().toIso8601String(),
      });

      // Update the comment with new content and increment edit count
      final response = await _client
          .from('health_article_comments')
          .update({'content': content, 'edit_count': newEditCount})
          .eq('id', commentId)
          .select('*, users(username, profile_image_url)')
          .single();

      return HealthArticleComment.fromJson(response);
    } catch (e) {
      debugPrint('Repository: Error updating comment: $e');
      return null;
    }
  }

  /// Get edit history for a comment
  Future<List<CommentEditHistory>> getCommentEditHistory(
    String commentId,
  ) async {
    try {
      final response = await _client
          .from('health_article_comment_history')
          .select()
          .eq('comment_id', commentId)
          .order('edit_number', ascending: true);

      if ((response as List).isNotEmpty) {
        return (response as List)
            .map((e) => CommentEditHistory.fromJson(e))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Repository: Error fetching comment edit history: $e');
      return [];
    }
  }

  /// Toggle comment visibility (for article authors)
  Future<bool> toggleCommentVisibility({
    required String commentId,
    required bool isHidden,
  }) async {
    try {
      await _client
          .from('health_article_comments')
          .update({'is_hidden': isHidden})
          .eq('id', commentId);
      return true;
    } catch (e) {
      debugPrint('Repository: Error toggling comment visibility: $e');
      return false;
    }
  }

  Future<HealthArticle?> createArticle({
    required String userId,
    required String title,
    required String content,
    String? imageUrl,
    List<Map<String, dynamic>>? products,
  }) async {
    try {
      debugPrint(
        'Repository: Attempting minimal insert for article. User: $userId',
      );

      final response = await _client
          .from('health_articles')
          .insert({
            'author_id': userId,
            'title': title,
            'content': content,
            'image_url': imageUrl,
            'category': 'ทั้งหมด',
          })
          .select('*, users(username, profile_image_url)')
          .single();

      final article = HealthArticle.fromJson(response);

      if (products != null && products.isNotEmpty) {
        final productsData = products
            .map(
              (p) => {...p, 'article_id': article.id, 'tagged_by_id': userId},
            )
            .toList();
        await _client.from('health_article_products').insert(productsData);
      }

      debugPrint('Repository: Success! Article ID: ${response['id']}');
      return article;
    } catch (e) {
      debugPrint('Repository: Error creating article: $e');
      if (e is PostgrestException) {
        debugPrint('Postgrest Details: ${e.message}, ${e.details}');

        // If it's a 42703 (Undefined Column), it confirms our theory
        if (e.code == '42703') {
          debugPrint(
            'REPOSITORY HINT: One or more columns like view_count/like_count might be missing in DB.',
          );
        }
      }
      rethrow; // Rethrow to let the UI catch and show the actual error
    }
  }

  /// Update article products / tags
  Future<bool> editArticleProducts({
    required String articleId,
    required String userId,
    required List<Map<String, dynamic>> products,
  }) async {
    try {
      // First, delete existing products added by this user
      await _client
          .from('health_article_products')
          .delete()
          .eq('article_id', articleId)
          .eq('tagged_by_id', userId);

      // Insert new products if any
      if (products.isNotEmpty) {
        final productsData = products
            .map((p) => {...p, 'article_id': articleId, 'tagged_by_id': userId})
            .toList();
        await _client.from('health_article_products').insert(productsData);
      }
      return true;
    } catch (e) {
      debugPrint('Repository: Error updating products: $e');
      return false;
    }
  }

  /// Update article content (edit only text, max 1 time)
  Future<bool> editArticleText({
    required HealthArticle article,
    required String newContent,
  }) async {
    try {
      // 1. Insert into history table
      await _client.from('health_article_edits').insert({
        'article_id': article.id,
        'old_content': article.content,
        'new_content': newContent,
        'edit_number': article.editCount + 1,
      });

      // 2. Update the article content and edit count
      await _client
          .from('health_articles')
          .update({'content': newContent, 'edit_count': article.editCount + 1})
          .eq('id', article.id);

      // 3. Fetch products tagged in the article
      final products = await getArticleProducts(article.id);

      // 4. Notify product owners (taggedById)
      final Set<String> notifiedUsers = {}; // Prevent duplicate notifications
      for (var product in products) {
        final targetUserId = product.taggedById;
        if (targetUserId != null &&
            targetUserId != article.authorId &&
            !notifiedUsers.contains(targetUserId)) {
          try {
            await _client.from('health_notifications').insert({
              'recipient_id': targetUserId,
              'type': 'article_edited',
              'message':
                  'บทความ "${article.title}" ที่คุณฝากสินค้าไว้มีการแก้ไขข้อความ',
              'article_id': article.id,
              'created_at': DateTime.now().toIso8601String(),
            });
            notifiedUsers.add(targetUserId);
          } catch (e) {
            debugPrint(
              'Repository: Failed to send notification to product owner ${product.taggedById}: $e',
            );
          }
        }
      }

      return true;
    } catch (e) {
      debugPrint('Repository: Error editing article text: $e');
      return false;
    }
  }

  Future<List<ArticleEditHistory>> getArticleEditHistory(
    String articleId,
  ) async {
    try {
      final response = await _client
          .from('health_article_edits')
          .select()
          .eq('article_id', articleId)
          .order('edited_at', ascending: false);

      if ((response as List).isNotEmpty) {
        return (response as List)
            .map((e) => ArticleEditHistory.fromJson(e))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Repository: Error fetching article edit history: $e');
      return [];
    }
  }

  Future<List<HealthArticle>> getBookmarkedArticles(String userId) async {
    try {
      // 1. Get bookmarked article IDs for the user
      final interactions = await _client
          .from('health_article_interactions')
          .select('article_id, created_at')
          .eq('user_id', userId)
          .eq('type', 'bookmark')
          .filter('comment_id', 'is', null) // Only article bookmarks
          .order('created_at', ascending: false);

      if ((interactions as List).isEmpty) {
        return [];
      }

      // Keep the mapping of article_id to interaction created_at to sort later
      final Map<String, DateTime> bookmarkDates = {};
      final List<String> articleIds = [];

      for (var i in (interactions as List)) {
        final aId = i['article_id'] as String;
        articleIds.add(aId);
        bookmarkDates[aId] = DateTime.parse(i['created_at']);
      }

      // 2. Fetch the actual articles
      final response = await _client
          .from('health_articles')
          .select('*, users(username, profile_image_url)')
          .filter('id', 'in', articleIds);

      if ((response as List).isNotEmpty) {
        List<HealthArticle> articles = (response as List).map((e) {
          final jsonMap = Map<String, dynamic>.from(e);
          jsonMap['is_bookmarked'] = true; // We know it's bookmarked

          return HealthArticle.fromJson(jsonMap);
        }).toList();

        // 3. Sort by bookmark date (newest first)
        articles.sort((a, b) {
          final dateA = bookmarkDates[a.id] ?? a.createdAt;
          final dateB = bookmarkDates[b.id] ?? b.createdAt;
          return dateB.compareTo(dateA);
        });

        return articles;
      }
      return [];
    } catch (e) {
      debugPrint('Repository: Error fetching bookmarked articles: $e');
      return [];
    }
  }
}
