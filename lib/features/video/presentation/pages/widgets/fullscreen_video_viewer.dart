import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../../../models/video_models.dart';
import '../../../../../services/service_locator.dart';
import '../../../../../services/auth_service.dart';
import '../../../../../services/websocket_service.dart';

/// FullscreenVideoViewer — แสดงวิดีโอเต็มจอตามแผน VIDEO_SYSTEM_PLAN.md ส่วน 3.1
///
/// Gestures:
///   - Single tap → play/pause
///   - Double tap → toggle Like
///   - Vertical swipe up/down → เปลี่ยนการ์ดเหตุการณ์ถัดไป/ก่อนหน้า
///   - Horizontal drag right → drag-to-dismiss
///   - ปุ่ม X → ปิดทันที
///
/// Overlay: ปุ่มปิด X, ชื่อเหตุการณ์, จำนวนผู้ชม, ยอดไลค์
class FullscreenVideoViewer extends StatefulWidget {
  /// รายการการ์ดเหตุการณ์ที่โหลดอยู่ (Trending)
  final List<Video> videos;

  /// index ของการ์ดปัจจุบันที่จะเปิด fullscreen
  final int initialIndex;

  /// โหลดหน้าถัดไปเมื่อปัดถึงท้ายรายการ
  final Future<void> Function()? onLoadMore;

  /// มีการ์ดเพิ่มเติมไหม
  final bool hasMore;

  /// รับ currentVideoId ล่าสุดเมื่อปิด fullscreen
  final void Function(String currentVideoId)? onDismissed;

  /// รับการแจ้งเตือนเมื่อเปลี่ยนการ์ด (เพื่อให้ parent sync ข้อมูล)
  final void Function(Video video)? onVideoChanged;

  const FullscreenVideoViewer({
    super.key,
    required this.videos,
    required this.initialIndex,
    this.onLoadMore,
    this.hasMore = false,
    this.onDismissed,
    this.onVideoChanged,
  });

  @override
  State<FullscreenVideoViewer> createState() => _FullscreenVideoViewerState();
}

class _FullscreenVideoViewerState extends State<FullscreenVideoViewer>
    with TickerProviderStateMixin {
  late int _currentIndex;
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  bool _hasError = false;
  bool _showOverlay = true;
  bool _isLiked = false;
  int _likeCount = 0;
  int _viewerCount = 0;
  String? _currentVideoId;
  StreamSubscription? _viewerCountSub;
  StreamSubscription? _likeToggledSub;
  StreamSubscription? _interactionSub;

  // Drag-to-dismiss state
  double _dragX = 0.0;
  late AnimationController _dragAnimController;
  Animation<double>? _dragAnim;

  // Single vs double tap detection
  Timer? _singleTapTimer;
  bool _isDoubleTap = false;

  // Loading more guard
  bool _isLoadingMore = false;

  // ✅ ป้องกันการนับ view ซ้ำ: การ์ดแรกที่เปิด fullscreen ไม่นับ view
  // (เพราะนับจากการ tap การ์ดใน Trending Panel แล้ว)
  // นับ view เฉพาะเมื่อปัดเปลี่ยนการ์ดใน fullscreen เท่านั้น
  bool _isInitialLoad = true;

  // ✅ Like animation — แสดงหัวใจลอยขึ้นเมื่อ like สำเร็จจาก DB
  late AnimationController _likeAnimController;
  Animation<double>? _likeAnim;
  Animation<Offset>? _likeOffsetAnim;
  int _likeAnimKey = 0; // เพื่อ force rebuild ของ animation layer

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.videos.length - 1);
    _dragAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _likeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _setupWebSocketListeners();
    _loadCurrentVideo();
  }

  void _setupWebSocketListeners() {
    final ws = WebSocketService();
    _viewerCountSub = ws.viewerCountStream.listen((data) {
      final vid = data['videoId']?.toString();
      if (vid == _currentVideoId && mounted) {
        setState(() => _viewerCount = (data['count'] as num?)?.toInt() ?? 0);
      }
    });
    _interactionSub = ws.videoInteractionStream.listen((data) {
      final vid = data['videoId']?.toString();
      if (vid == _currentVideoId && mounted) {
        final type = data['type']?.toString();
        if (type == 'like') {
          final liked = data['liked'] as bool?;
          final count = data['count'] as int?;
          setState(() {
            if (liked != null) _isLiked = liked;
            if (count != null) _likeCount = count;
          });
        } else if (type == 'view') {
          final count = data['count'] as int?;
          if (count != null) {
            setState(() => _viewerCount = count);
          }
        }
      }
    });
  }

  Future<void> _loadCurrentVideo() async {
    if (!mounted) return;
    if (_currentIndex < 0 || _currentIndex >= widget.videos.length) {
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
      return;
    }

    final video = widget.videos[_currentIndex];
    final newVideoId = video.id;

    // Leave previous room + record view for new card (เฉพาะเมื่อปัดเปลี่ยนการ์ด)
    // การ์ดแรกที่เปิด fullscreen ไม่นับ view เพราะนับจากการ tap ใน Trending Panel แล้ว
    if (_currentVideoId != null && _currentVideoId != newVideoId) {
      WebSocketService().leaveVideoRoom(_currentVideoId!);
    }
    if (_currentVideoId != newVideoId) {
      // join room เสมอ (เพื่อรับ real-time viewer/like count)
      WebSocketService().joinVideoRoom(newVideoId);
      // นับ view เฉพาะเมื่อไม่ใช่การโหลดครั้งแรก
      if (!_isInitialLoad) {
        WebSocketService().recordVideoView(newVideoId);
      }
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
      _currentVideoId = newVideoId;
      _viewerCount = video.viewerCount;
      _likeCount = video.likeCount;
    });

    // Notify parent
    widget.onVideoChanged?.call(video);

    // Dispose old controllers
    _disposeControllers();

    // Resolve URL
    String? url;
    bool isLocal = false;
    if (video.localFilePath != null &&
        video.localFilePath!.isNotEmpty &&
        await _fileExists(video.localFilePath!)) {
      url = video.localFilePath!;
      isLocal = true;
    } else if (video.bunnyUrl != null && video.bunnyUrl!.isNotEmpty) {
      url = ServiceLocator.instance.videoRepository.ensureFullUrl(
        video.bunnyUrl!,
      );
    } else if (video.localFilePath != null && video.localFilePath!.isNotEmpty) {
      url = video.localFilePath!;
      isLocal = true;
    }

    if (url == null) {
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
      return;
    }

    // Skip if it's an image, not a video
    final lower = url.toLowerCase();
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif')) {
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
      return;
    }

    try {
      final controller = isLocal
          ? VideoPlayerController.file(File(url))
          : VideoPlayerController.networkUrl(Uri.parse(url));
      _videoPlayerController = controller;

      await controller.initialize();
      if (!mounted || _videoPlayerController != controller) {
        controller.dispose();
        return;
      }

      final aspectRatio = controller.value.aspectRatio;
      setState(() {
        _chewieController = ChewieController(
          videoPlayerController: controller,
          aspectRatio: aspectRatio,
          autoPlay: true,
          looping: false,
          showControls: false,
          placeholder: Container(color: Colors.black),
          errorBuilder: (context, errorMessage) => Center(
            child: Text(
              errorMessage,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
        _isLoading = false;
      });

      controller.setVolume(1.0);
      controller.play();

      // โหลดการ์ดแรกเสร็จ → ปัดเปลี่ยนการ์ดถัดไปจะนับ view
      _isInitialLoad = false;

      // Load like status
      _loadLikeStatus(newVideoId);
    } catch (e) {
      debugPrint('[FullscreenVideoViewer] initialize error: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadLikeStatus(String videoId) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return;
    try {
      final liked = await ServiceLocator.instance.videoRepository.getLikeStatus(
        videoId,
        userId,
      );
      if (mounted && _currentVideoId == videoId) {
        setState(() => _isLiked = liked);
      }
    } catch (_) {}
  }

  Future<bool> _fileExists(String path) async {
    try {
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }

  void _disposeControllers() {
    _chewieController?.dispose();
    _chewieController = null;
    _videoPlayerController?.dispose();
    _videoPlayerController = null;
  }

  // ── Single tap → play/pause (with double-tap guard) ──
  void _handleSingleTap() {
    if (_isDoubleTap) return;
    _singleTapTimer?.cancel();
    _singleTapTimer = Timer(const Duration(milliseconds: 250), () {
      if (!_isDoubleTap && mounted) {
        final controller = _videoPlayerController;
        if (controller != null && controller.value.isInitialized) {
          setState(() => _showOverlay = !_showOverlay);
          if (controller.value.isPlaying) {
            controller.pause();
          } else {
            controller.play();
          }
        }
      }
    });
  }

  // ── Double tap → toggle Like ──
  Future<void> _handleDoubleTap() async {
    _isDoubleTap = true;
    _singleTapTimer?.cancel();
    if (_currentVideoId == null) {
      _resetDoubleTap();
      return;
    }
    final userId = AuthService.instance.currentUser?.id ?? 'anonymous';
    try {
      final result = await ServiceLocator.instance.videoRepository.toggleLike(
        _currentVideoId!,
        userId,
      );
      final liked = result['liked'] as bool? ?? !_isLiked;
      final count = result['count'] as int? ?? _likeCount;
      if (mounted) {
        setState(() {
          _isLiked = liked;
          _likeCount = count;
        });
        // Broadcast like-toggled to room (เหมือน _onLike ใน emergency_live_page)
        WebSocketService().sendVideoInteraction(
          _currentVideoId!,
          userId,
          'like',
          value: 0,
        );
        // ✅ แสดง animation เฉพาะเมื่อ like สำเร็จ (ไม่ใช่ unlike)
        if (liked) {
          _triggerLikeAnimation();
        }
      }
    } catch (e) {
      debugPrint('[FullscreenVideoViewer] toggleLike failed: $e');
    } finally {
      _resetDoubleTap();
    }
  }

  /// ✅ สร้าง animation หัวใจลอยขึ้น + เฟดออต
  void _triggerLikeAnimation() {
    _likeAnimKey++;
    _likeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _likeAnimController, curve: Curves.easeOut),
    );
    _likeOffsetAnim =
        Tween<Offset>(
          begin: const Offset(0, 0),
          end: const Offset(0, -120),
        ).animate(
          CurvedAnimation(parent: _likeAnimController, curve: Curves.easeOut),
        );
    _likeAnimController.forward(from: 0.0);
  }

  void _resetDoubleTap() {
    Future.delayed(const Duration(milliseconds: 300), () {
      _isDoubleTap = false;
    });
  }

  // ── Vertical swipe → เปลี่ยนการ์ด ──
  void _handleVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    // ปัดขึ้น (velocity ลบ) → การ์ดถัดไป (+1)
    // ปัดลง (velocity บวก) → การ์ดก่อนหน้า (-1)
    if (velocity < -200) {
      _changeCard(1);
    } else if (velocity > 200) {
      _changeCard(-1);
    }
  }

  Future<void> _changeCard(int delta) async {
    final newIndex = _currentIndex + delta;
    if (newIndex < 0) {
      // ไม่มีการ์ดก่อนหน้า
      _showNoMoreCardsSnackBar('ไม่มีเหตุการณ์ก่อนหน้า');
      return;
    }
    if (newIndex >= widget.videos.length) {
      // พยายามโหลดหน้าถัดไป
      if (widget.hasMore && widget.onLoadMore != null && !_isLoadingMore) {
        setState(() => _isLoadingMore = true);
        try {
          await widget.onLoadMore!();
        } catch (_) {}
        if (!mounted) return;
        setState(() => _isLoadingMore = false);
        // ตรวจอีกครั้งหลังโหลด
        if (newIndex < widget.videos.length) {
          _currentIndex = newIndex;
          await _loadCurrentVideo();
        } else {
          _showNoMoreCardsSnackBar('ไม่มีเหตุการณ์เพิ่มเติม');
        }
      } else {
        _showNoMoreCardsSnackBar('ไม่มีเหตุการณ์เพิ่มเติม');
      }
      return;
    }
    _currentIndex = newIndex;
    await _loadCurrentVideo();
  }

  void _showNoMoreCardsSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.black54,
      ),
    );
  }

  // ── Drag-to-dismiss ──
  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() => _dragX += details.delta.dx);
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    final threshold = MediaQuery.of(context).size.width * 0.25;
    if (_dragX > threshold || (details.primaryVelocity ?? 0) > 500) {
      // ปิด fullscreen
      _dismiss();
    } else {
      // Spring กลับ
      _dragAnim =
          Tween<double>(begin: _dragX, end: 0.0).animate(
            CurvedAnimation(parent: _dragAnimController, curve: Curves.easeOut),
          )..addListener(() {
            if (mounted) setState(() => _dragX = _dragAnim!.value);
          });
      _dragAnimController.forward(from: 0.0);
    }
  }

  void _dismiss() {
    if (_currentVideoId != null) {
      widget.onDismissed?.call(_currentVideoId!);
    }
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _singleTapTimer?.cancel();
    _dragAnimController.dispose();
    _likeAnimController.dispose();
    if (_currentVideoId != null) {
      WebSocketService().leaveVideoRoom(_currentVideoId!);
    }
    _viewerCountSub?.cancel();
    _interactionSub?.cancel();
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final translateX = _dragX;
    final dismissProgress = (_dragX / screenWidth).clamp(0.0, 1.0);
    final opacity = 1.0 - (dismissProgress * 0.5);

    return Scaffold(
      backgroundColor: Colors.black,
      body: WillPopScope(
        onWillPop: () async {
          _dismiss();
          return false;
        },
        child: GestureDetector(
          onTap: _handleSingleTap,
          onDoubleTap: _handleDoubleTap,
          onHorizontalDragUpdate: _handleHorizontalDragUpdate,
          onHorizontalDragEnd: _handleHorizontalDragEnd,
          onVerticalDragEnd: _handleVerticalDragEnd,
          behavior: HitTestBehavior.opaque,
          child: Transform.translate(
            offset: Offset(translateX, 0),
            child: SizedBox(
              width: screenWidth,
              child: Opacity(opacity: opacity, child: _buildContent()),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white70, size: 48),
            const SizedBox(height: 12),
            const Text(
              'ไม่สามารถเล่นวิดีโอนี้ได้',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            if (_currentIndex > 0)
              TextButton(
                onPressed: () => _changeCard(-1),
                child: const Text('ดูเหตุการณ์ก่อนหน้า'),
              ),
          ],
        ),
      );
    }

    final controller = _chewieController;
    if (controller == null) {
      return const Center(
        child: Text('ไม่มีวิดีโอ', style: TextStyle(color: Colors.white70)),
      );
    }

    final video = widget.videos[_currentIndex];

    return Stack(
      fit: StackFit.expand,
      children: [
        // Layer 1: Video (gesture อยู่ที่ GestureDetector ด้านนอก)
        Center(
          child: AspectRatio(
            aspectRatio: controller.aspectRatio ?? 16 / 9,
            child: Chewie(controller: controller),
          ),
        ),

        // Layer 2: Overlay (ปุ่มปิด, ชื่อเหตุการณ์, ผู้ชม, ไลค์)
        if (_showOverlay) _buildOverlay(video),

        // Layer 3: Loading more indicator
        if (_isLoadingMore)
          const Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white70,
                  strokeWidth: 2,
                ),
              ),
            ),
          ),

        // Layer 4: Like animation — หัวใจลอยขึ้นเมื่อ like สำเร็จ
        if (_likeAnim != null)
          Positioned.fill(
            key: ValueKey('like-anim-$_likeAnimKey'),
            child: IgnorePointer(
              child: Center(
                child: AnimatedBuilder(
                  animation: _likeAnimController,
                  builder: (context, child) {
                    final t = _likeAnim!.value;
                    final offset = _likeOffsetAnim!.value;
                    return Opacity(
                      opacity: (1.0 - t).clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: offset,
                        child: Transform.scale(
                          scale: 0.8 + (t * 0.6),
                          child: child,
                        ),
                      ),
                    );
                  },
                  child: const Icon(
                    Icons.favorite,
                    color: Colors.pinkAccent,
                    size: 80,
                    shadows: [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOverlay(Video video) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Stack(
          children: [
            // Top gradient + ปุ่มปิด + ชื่อเหตุการณ์
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 12,
                  right: 12,
                  bottom: 12,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    // ปุ่มปิด X
                    GestureDetector(
                      onTap: _dismiss,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // ชื่อเหตุการณ์
                    Expanded(
                      child: Text(
                        video.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'SukhumvitSet',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom gradient + จำนวนผู้ชม + ยอดไลค์
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    // จำนวนผู้ชม
                    const Icon(
                      Icons.visibility,
                      color: Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$_viewerCount ผู้ชม',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontFamily: 'SukhumvitSet',
                      ),
                    ),
                    const SizedBox(width: 16),
                    // ยอดไลค์
                    GestureDetector(
                      onTap: _handleDoubleTap,
                      child: Row(
                        children: [
                          Icon(
                            _isLiked ? Icons.favorite : Icons.favorite_border,
                            color: _isLiked
                                ? Colors.pinkAccent
                                : Colors.white70,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$_likeCount',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontFamily: 'SukhumvitSet',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // คำใบ้
                    Text(
                      'ปัดขวาเพื่อปิด • ปัดขึ้น/ลงเพื่อเปลี่ยนเหตุการณ์',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 11,
                        fontFamily: 'SukhumvitSet',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
