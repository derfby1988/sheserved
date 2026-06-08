import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../../services/service_locator.dart';
import 'thai_mhung_gallery_widget.dart';

class ThaiMhungPhotoDetailDialog extends StatelessWidget {
  final ThaiMhungPhoto photo;

  const ThaiMhungPhotoDetailDialog({
    super.key,
    required this.photo,
  });

  /// Static helper to show the dialog
  static Future<void> show(BuildContext context, ThaiMhungPhoto photo) {
    return showDialog(
      context: context,
      builder: (context) => ThaiMhungPhotoDetailDialog(photo: photo),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: ServiceLocator.instance.videoRepository.ensureFullUrl(photo.url),
                fit: BoxFit.contain,
                placeholder: (context, url) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40.0),
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  height: 300,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.broken_image, color: Colors.white54, size: 60),
                        SizedBox(height: 10),
                        Text('ไม่สามารถโหลดรูปภาพได้', style: TextStyle(color: Colors.white54)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (photo.userName != null)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'รายงานโดย: ${photo.userName}',
                  style: const TextStyle(
                    color: Colors.white, 
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
