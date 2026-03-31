import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shimmer/shimmer.dart';

/// Widget สำหรับเลือก/บีบอัด/อัปโหลดและแสดงรูปภาพ
/// รองรับทั้ง local preview ก่อนอัปโหลด และ cached URL หลังอัปโหลด
class ImageUploadField extends StatefulWidget {
  /// Label ของฟิลด์
  final String label;

  /// จำเป็นต้องกรอกหรือไม่
  final bool isRequired;

  /// URL ของรูปที่มีอยู่แล้ว (กรณีแก้ไข)
  final String? initialUrl;

  /// Bucket ชื่อสำหรับ Supabase storage
  final String bucket;

  /// Path prefix สำหรับบันทึกไฟล์ใน bucket เช่น 'donation_requests/'
  final String pathPrefix;

  /// Callback เมื่ออัปโหลดสำเร็จ — คืน URL สาธารณะ
  final ValueChanged<String> onUploaded;

  /// Callback เมื่อลบรูป
  final VoidCallback? onRemoved;

  /// คุณภาพหลังบีบอัด (1-100, default 72)
  final int quality;

  /// ขนาดสูงสุดของด้านที่ยาวกว่า (px, default 1080)
  final int maxDimension;

  const ImageUploadField({
    super.key,
    required this.label,
    required this.bucket,
    required this.pathPrefix,
    required this.onUploaded,
    this.isRequired = false,
    this.initialUrl,
    this.onRemoved,
    this.quality = 72,
    this.maxDimension = 1080,
  });

  @override
  State<ImageUploadField> createState() => _ImageUploadFieldState();
}

class _ImageUploadFieldState extends State<ImageUploadField> {
  final _picker = ImagePicker();
  File? _localFile;
  String? _uploadedUrl;
  bool _isUploading = false;
  double _uploadProgress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _uploadedUrl = widget.initialUrl;
  }

  /// บีบอัดและอัปโหลดไฟล์
  Future<void> _pickAndUpload(ImageSource source) async {
    setState(() { _error = null; });
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 90, // pre-quality ก่อนบีบอัดเพิ่ม
      );
      if (picked == null) return;

      setState(() {
        _localFile = File(picked.path);
        _isUploading = true;
        _uploadProgress = 0.1;
      });

      // ── บีบอัดรูป ──
      final compressedBytes = await _compress(File(picked.path));
      setState(() => _uploadProgress = 0.4);

      // ── สร้าง unique path ──
      final ext = 'jpg'; // บังคับเป็น JPEG หลัง compress
      final rand = Random().nextInt(99999).toString().padLeft(5, '0');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${widget.pathPrefix}${ts}_$rand.$ext';

      // ── อัปโหลดไปยัง Supabase Storage ──
      final client = Supabase.instance.client;
      await client.storage.from(widget.bucket).uploadBinary(
        filePath,
        compressedBytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: true,
        ),
      );
      setState(() => _uploadProgress = 0.9);

      final publicUrl = client.storage.from(widget.bucket).getPublicUrl(filePath);
      setState(() {
        _uploadedUrl = publicUrl;
        _isUploading = false;
        _uploadProgress = 1.0;
      });
      widget.onUploaded(publicUrl);
    } catch (e) {
      setState(() {
        _isUploading = false;
        _error = 'อัปโหลดล้มเหลว: $e';
      });
    }
  }

  /// บีบอัดรูปโดยใช้ flutter_image_compress
  Future<Uint8List> _compress(File file) async {
    final tmpDir = await getTemporaryDirectory();
    final outPath = '${tmpDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      outPath,
      quality: widget.quality,
      minWidth: min(widget.maxDimension, 1080),
      minHeight: min(widget.maxDimension, 1080),
      format: CompressFormat.jpeg,
      keepExif: false,
    );

    if (result == null) {
      // fallback: ใช้ไฟล์ต้นฉบับ
      return await file.readAsBytes();
    }
    return await File(result.path).readAsBytes();
  }

  void _removeImage() {
    setState(() {
      _localFile = null;
      _uploadedUrl = null;
      _error = null;
    });
    widget.onRemoved?.call();
  }

  void _showSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'เลือกรูปภาพ',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: Colors.blue),
                ),
                title: const Text('ถ่ายภาพ'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUpload(ImageSource.camera);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: Colors.green),
                ),
                title: const Text('เลือกจากคลังรูป'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUpload(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _localFile != null || _uploadedUrl != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Label ──
        if (widget.label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              widget.label + (widget.isRequired ? ' *' : ''),
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

        // ── Preview / Upload Zone ──
        GestureDetector(
          onTap: _isUploading ? null : _showSourceDialog,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: hasImage ? 200 : 120,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _error != null
                    ? Colors.redAccent
                    : hasImage
                        ? Colors.transparent
                        : Colors.grey.shade300,
                width: 1.5,
              ),
              color: hasImage ? Colors.black : Colors.grey.shade50,
            ),
            child: hasImage
                ? _buildImagePreview()
                : _buildEmptyZone(),
          ),
        ),

        // ── Error ──
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),

        // ── Size hint ──
        if (!hasImage)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              'รูปจะถูกบีบอัดอัตโนมัติ (max ${widget.maxDimension}px, ${widget.quality}% quality)',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyZone() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.add_photo_alternate_rounded,
          size: 36,
          color: Colors.grey.shade400,
        ),
        const SizedBox(height: 8),
        Text(
          'แตะเพื่อเพิ่มรูปภาพ',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  Widget _buildImagePreview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── ภาพ (local file หรือ cached network) ──
          if (_localFile != null)
            Image.file(
              _localFile!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            )
          else if (_uploadedUrl != null)
            CachedNetworkImage(
              imageUrl: _uploadedUrl!,
              fit: BoxFit.cover,
              placeholder: (ctx, url) => Shimmer.fromColors(
                baseColor: Colors.grey.shade800,
                highlightColor: Colors.grey.shade600,
                child: Container(color: Colors.grey.shade800),
              ),
              errorWidget: (ctx, url, err) => const Center(
                child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 40),
              ),
              memCacheWidth: 800, // จำกัดขนาด cache ใน memory
            ),

          // ── Upload Progress Overlay ──
          if (_isUploading)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 60,
                      height: 60,
                      child: CircularProgressIndicator(
                        value: _uploadProgress,
                        strokeWidth: 5,
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${(_uploadProgress * 100).toInt()}%',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),

          // ── ปุ่มลบ ──
          if (!_isUploading)
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: _removeImage,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 18),
                ),
              ),
            ),

          // ── ปุ่มเปลี่ยนรูป (ตรงกลางล่าง) ──
          if (!_isUploading)
            Positioned(
              bottom: 8,
              right: 8,
              child: GestureDetector(
                onTap: _showSourceDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_rounded, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text('เปลี่ยน', style: TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),

          // ── ✅ Badge อัปโหลดสำเร็จ ──
          if (!_isUploading && _uploadedUrl != null)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade600,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_done_rounded, color: Colors.white, size: 12),
                    SizedBox(width: 4),
                    Text('อัปโหลดแล้ว', style: TextStyle(color: Colors.white, fontSize: 10)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
