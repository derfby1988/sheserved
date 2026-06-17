import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/body_region_model.dart';
import 'package:path/path.dart' as p;

class BodyRegionRepository {
  final SupabaseClient _client;
  static const String _tableName = 'body_regions';
  static const String _bucketName = 'body_region_images';

  BodyRegionRepository(this._client);

  Future<List<BodyRegionModel>> getAllRegions() async {
    try {
      final response = await _client
          .from(_tableName)
          .select()
          .order('display_order', ascending: true);
          
      return (response as List).map((json) => BodyRegionModel.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error getting body regions: $e');
      return [];
    }
  }

  Future<BodyRegionModel> createRegion(BodyRegionModel region, {File? iconImageFile, File? image2dFile, File? model3dFile}) async {
    try {
      String? iconImageUrl;
      String? image2dUrl;
      String? model3dUrl;

      if (iconImageFile != null) {
        iconImageUrl = await uploadFile(region.id, iconImageFile, 'icon');
      }
      if (image2dFile != null) {
        image2dUrl = await uploadFile(region.id, image2dFile, '2d');
      }
      if (model3dFile != null) {
        model3dUrl = await uploadFile(region.id, model3dFile, '3d');
      }

      final data = region.toJson();
      if (iconImageUrl != null) data['icon_image_url'] = iconImageUrl;
      if (image2dUrl != null) data['image_2d_url'] = image2dUrl;
      if (model3dUrl != null) data['model_3d_url'] = model3dUrl;

      final response = await _client.from(_tableName).insert(data).select().single();
      return BodyRegionModel.fromJson(response);
    } catch (e) {
      debugPrint('Error creating body region: $e');
      rethrow;
    }
  }

  Future<BodyRegionModel> updateRegion(String id, BodyRegionModel region, {File? iconImageFile, File? image2dFile, File? model3dFile, bool deleteIcon = false, bool delete2d = false, bool delete3d = false}) async {
    try {
      String? iconImageUrl = region.iconImageUrl;
      String? image2dUrl = region.image2dUrl;
      String? model3dUrl = region.model3dUrl;

      if (deleteIcon && iconImageUrl != null) {
        await _deleteFileFromUrl(iconImageUrl);
        iconImageUrl = null;
      } else if (iconImageFile != null) {
        if (iconImageUrl != null) await _deleteFileFromUrl(iconImageUrl);
        iconImageUrl = await uploadFile(id, iconImageFile, 'icon');
      }

      if (delete2d && image2dUrl != null) {
        await _deleteFileFromUrl(image2dUrl);
        image2dUrl = null;
      } else if (image2dFile != null) {
        if (image2dUrl != null) await _deleteFileFromUrl(image2dUrl);
        image2dUrl = await uploadFile(id, image2dFile, '2d');
      }

      if (delete3d && model3dUrl != null) {
        await _deleteFileFromUrl(model3dUrl);
        model3dUrl = null;
      } else if (model3dFile != null) {
        if (model3dUrl != null) await _deleteFileFromUrl(model3dUrl);
        model3dUrl = await uploadFile(id, model3dFile, '3d');
      }

      final data = region.toJson();
      data['icon_image_url'] = iconImageUrl;
      data['image_2d_url'] = image2dUrl;
      data['model_3d_url'] = model3dUrl;
      data['updated_at'] = DateTime.now().toIso8601String();

      final response = await _client.from(_tableName).update(data).eq('id', id).select().single();
      return BodyRegionModel.fromJson(response);
    } catch (e) {
      debugPrint('Error updating body region: $e');
      rethrow;
    }
  }

  Future<void> deleteRegion(String id) async {
    try {
      final region = await _client.from(_tableName).select().eq('id', id).single();
      if (region['icon_image_url'] != null) await _deleteFileFromUrl(region['icon_image_url']);
      if (region['image_2d_url'] != null) await _deleteFileFromUrl(region['image_2d_url']);
      if (region['model_3d_url'] != null) await _deleteFileFromUrl(region['model_3d_url']);
      
      await _client.from(_tableName).delete().eq('id', id);
    } catch (e) {
      debugPrint('Error deleting body region: $e');
      rethrow;
    }
  }

  Future<String> uploadFile(String regionId, File file, String type) async {
    final ext = p.extension(file.path);
    final fileName = '${regionId}_${type}_${DateTime.now().millisecondsSinceEpoch}$ext';
    
    await _client.storage.from(_bucketName).upload(fileName, file);
    return _client.storage.from(_bucketName).getPublicUrl(fileName);
  }

  Future<void> _deleteFileFromUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      final idx = pathSegments.indexOf(_bucketName);
      if (idx != -1 && idx + 1 < pathSegments.length) {
        final filePath = pathSegments.sublist(idx + 1).join('/');
        await _client.storage.from(_bucketName).remove([filePath]);
      }
    } catch (e) {
      debugPrint('Error deleting file: $e');
    }
  }

  Future<void> seedInitialRegions(List<BodyRegionModel> regions) async {
    try {
      final existing = await _client.from(_tableName).select('id');
      final List<String> existingIds = (existing as List).map((e) => e['id'] as String).toList();
      
      final List<Map<String, dynamic>> toInsert = [];
      for (var r in regions) {
        if (!existingIds.contains(r.id)) {
          toInsert.add(r.toJson());
        }
      }
      
      if (toInsert.isNotEmpty) {
        await _client.from(_tableName).insert(toInsert);
      }
    } catch (e) {
      debugPrint('Error seeding body regions: $e');
      rethrow;
    }
  }
}
