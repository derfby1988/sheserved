import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/video/models/video_models.dart';

Map<String, dynamic> videoJson({
  String? categoryId,
  String? categoryName,
  Map<String, dynamic>? donationCategories,
}) => {
  'id': 'video-1',
  'user_id': 'user-1',
  'type': 'emergency',
  'title': 'Emergency Incident',
  'status': 'ready',
  'created_at': '2026-10-04T08:00:00Z',
  'category_id': categoryId,
  'category_name': categoryName,
  'donation_categories': donationCategories,
};

void main() {
  group('Emergency video category names', () {
    test('parses the API category_name field', () {
      final video = Video.fromJson(
        videoJson(categoryId: 'category-1', categoryName: 'อุบัติเหตุ'),
      );

      expect(video.categoryId, 'category-1');
      expect(video.categoryName, 'อุบัติเหตุ');
    });

    test('parses the Supabase donation_categories relation', () {
      final video = Video.fromJson(
        videoJson(
          categoryId: 'category-1',
          categoryName: '  ',
          donationCategories: {'name': 'ไฟไหม้'},
        ),
      );

      expect(video.categoryName, 'ไฟไหม้');
    });

    test('canonical category names override stale API names by ID', () {
      final videos = [
        Video.fromJson(
          videoJson(categoryId: 'category-1', categoryName: 'เหตุฉุกเฉิน'),
        ),
        Video.fromJson(
          videoJson(categoryId: 'category-2', categoryName: 'ชื่อเดิม'),
        ),
      ];

      final resolved = resolveEmergencyVideoCategoryNames(videos, {
        'category-1': 'อุบัติเหตุ',
      });

      expect(resolved[0].categoryName, 'อุบัติเหตุ');
      expect(resolved[1].categoryName, 'ชื่อเดิม');
      expect(videos[0].categoryName, 'เหตุฉุกเฉิน');
    });
  });
}
