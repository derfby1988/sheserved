class HealthArticle {
  final String id;
  final String title;
  final String content;
  final String authorId;
  final String? authorName;
  final String? authorImage;
  final int viewCount;
  final int likeCount;
  final int shareCount;
  final int bookmarkCount;
  final String? category;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isBookmarked;
  final bool isLiked;

  HealthArticle({
    required this.id,
    required this.title,
    required this.content,
    required this.authorId,
    this.authorName,
    this.authorImage,
    this.viewCount = 0,
    this.likeCount = 0,
    this.shareCount = 0,
    this.bookmarkCount = 0,
    this.category,
    this.imageUrl,
    required this.createdAt,
    required this.updatedAt,
    this.isBookmarked = false,
    this.isLiked = false,
  });

  factory HealthArticle.fromJson(Map<String, dynamic> json) {
    final authorData = json['users'] as Map<String, dynamic>?;
    return HealthArticle(
      id: json['id'],
      title: json['title'],
      content: json['content'],
      authorId: json['author_id'],
      authorName: authorData != null ? authorData['username'] : null,
      authorImage: authorData != null ? authorData['profile_image_url'] : null,
      viewCount: json['view_count'] ?? 0,
      likeCount: json['like_count'] ?? 0,
      shareCount: json['share_count'] ?? 0,
      bookmarkCount: json['bookmark_count'] ?? 0,
      category: json['category'],
      imageUrl: json['image_url'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      isBookmarked: json['is_bookmarked'] == true,
      isLiked: json['is_liked'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'author_id': authorId,
      'view_count': viewCount,
      'like_count': likeCount,
      'share_count': shareCount,
      'bookmark_count': bookmarkCount,
      'category': category,
      'image_url': imageUrl,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  HealthArticle copyWith({
    String? id,
    String? title,
    String? content,
    String? authorId,
    String? authorName,
    String? authorImage,
    int? viewCount,
    int? likeCount,
    int? shareCount,
    int? bookmarkCount,
    String? category,
    String? imageUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isBookmarked,
    bool? isLiked,
  }) {
    return HealthArticle(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      authorId: authorId ?? this.authorId,
      authorName: authorName ?? this.authorName,
      authorImage: authorImage ?? this.authorImage,
      viewCount: viewCount ?? this.viewCount,
      likeCount: likeCount ?? this.likeCount,
      shareCount: shareCount ?? this.shareCount,
      bookmarkCount: bookmarkCount ?? this.bookmarkCount,
      category: category ?? this.category,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isBookmarked: isBookmarked ?? this.isBookmarked,
      isLiked: isLiked ?? this.isLiked,
    );
  }
}

class HealthArticleProduct {
  final String id;
  final String articleId;
  final String name;
  final String? url;
  final String? imageUrl;
  final String tagType;
  final String? taggedById;
  final bool isApproved;
  final DateTime createdAt;

  HealthArticleProduct({
    required this.id,
    required this.articleId,
    required this.name,
    this.url,
    this.imageUrl,
    required this.tagType,
    this.taggedById,
    this.isApproved = false,
    required this.createdAt,
  });

  factory HealthArticleProduct.fromJson(Map<String, dynamic> json) {
    return HealthArticleProduct(
      id: json['id'],
      articleId: json['article_id'],
      name: json['name'],
      url: json['url'],
      imageUrl: json['image_url'],
      tagType: json['tag_type'],
      taggedById: json['tagged_by_id'],
      isApproved: json['is_approved'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class HealthArticleComment {
  final String id;
  final String articleId;
  final String userId;
  final String? username;
  final String? userImage;
  final String? parentId;
  final String content;
  final int commentNumber;
  final int viewCount;
  final int likeCount;
  final DateTime createdAt;
  final bool isLiked; // Added
  final bool isBookmarked; // Added

  HealthArticleComment({
    required this.id,
    required this.articleId,
    required this.userId,
    this.username,
    this.userImage,
    this.parentId,
    required this.content,
    required this.commentNumber,
    this.viewCount = 0,
    this.likeCount = 0,
    required this.createdAt,
    this.isLiked = false, // Added
    this.isBookmarked = false, // Added
  });

  factory HealthArticleComment.fromJson(Map<String, dynamic> json) {
    final userData = json['users'] as Map<String, dynamic>?;
    
    // Check if the comment is liked by the current user 
    // This assumes the API returns a 'is_liked' boolean or we check if interactions list contains current user
    // For now, we look for a field 'is_liked' which we will populate in the repository
    final isLiked = json['is_liked'] == true;

    return HealthArticleComment(
      id: json['id'],
      articleId: json['article_id'],
      userId: json['user_id'],
      username: userData != null ? userData['username'] : null,
      userImage: userData != null ? userData['profile_image_url'] : null,
      parentId: json['parent_id'],
      content: json['content'],
      commentNumber: json['comment_number'],
      viewCount: json['view_count'] ?? 0,
      likeCount: json['like_count'] ?? 0,
      createdAt: DateTime.parse(json['created_at']),
      isLiked: json['is_liked'] == true,
      isBookmarked: json['is_bookmarked'] == true,
    );
  }

  HealthArticleComment copyWith({
    String? id,
    String? articleId,
    String? userId,
    String? username,
    String? userImage,
    String? parentId,
    String? content,
    int? commentNumber,
    int? viewCount,
    int? likeCount,
    DateTime? createdAt,
    bool? isLiked,
    bool? isBookmarked,
  }) {
    return HealthArticleComment(
      id: id ?? this.id,
      articleId: articleId ?? this.articleId,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      userImage: userImage ?? this.userImage,
      parentId: parentId ?? this.parentId,
      content: content ?? this.content,
      commentNumber: commentNumber ?? this.commentNumber,
      viewCount: viewCount ?? this.viewCount,
      likeCount: likeCount ?? this.likeCount,
      createdAt: createdAt ?? this.createdAt,
      isLiked: isLiked ?? this.isLiked,
      isBookmarked: isBookmarked ?? this.isBookmarked,
    );
  }
}
