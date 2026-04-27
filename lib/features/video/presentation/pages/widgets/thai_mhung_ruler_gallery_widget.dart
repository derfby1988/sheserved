import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../../services/service_locator.dart';
import '../../../../../services/websocket_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../../config/app_config.dart';
class ThaiMhungRulerPhoto {
  final String id;
  final String photoUrl;
  final DateTime createdAt;
  final double? latitude;
  final double? longitude;

  ThaiMhungRulerPhoto({
    required this.id, 
    required this.photoUrl, 
    required this.createdAt,
    this.latitude,
    this.longitude,
  });

  factory ThaiMhungRulerPhoto.fromJson(Map<String, dynamic> json) {
    // ใช้ VideoRepository เพื่อ normalize URL เสมอ (กรณี realtime payload ส่งเป็น relative path)
    final url = ServiceLocator.instance.videoRepository.ensureFullUrl(json['photo_url']?.toString() ?? '');
    return ThaiMhungRulerPhoto(
      id: json['id']?.toString() ?? '',
      photoUrl: url,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
      latitude: json['latitude'] != null ? double.tryParse(json['latitude'].toString()) : null,
      longitude: json['longitude'] != null ? double.tryParse(json['longitude'].toString()) : null,
    );
  }
}

class ThaiMhungRulerGalleryWidget extends StatefulWidget {
  final String videoId;
  final double height;
  final bool canViewUnblurred;
  final void Function(int index, String photoUrl)? onPhotoTap;
  final void Function(int index, String photoUrl)? onPhotoChanged;
  final void Function(ThaiMhungRulerPhoto photo)? onNewPhotoArrived;

  const ThaiMhungRulerGalleryWidget({
    super.key,
    required this.videoId,
    required this.height,
    this.canViewUnblurred = false,
    this.onPhotoTap,
    this.onPhotoChanged,
    this.onNewPhotoArrived,
  });

  @override
  State<ThaiMhungRulerGalleryWidget> createState() => ThaiMhungRulerGalleryWidgetState();
}

class ThaiMhungRulerGalleryWidgetState extends State<ThaiMhungRulerGalleryWidget> {
  final List<ThaiMhungRulerPhoto> _photos = [];
  bool _isLoading = true;
  RealtimeChannel? _subscription;
  StreamSubscription? _wsPhotoSub;
  Timer? _pollTimer;
  int _currentIndex = 0;
  final FixedExtentScrollController _scrollController = FixedExtentScrollController();
  
  final Set<String> _newItemIds = {};

  @override
  void initState() {
    super.initState();
    _fetchPhotos();
    _subscribeToNewPhotos();
    _subscribeToWebSocketPhotos();
    _startPolling();
  }

  /// ✅ Fallback Polling: ทุก 5 วินาทีจะเช็คว่ามีภาพใหม่ไหม (กรณี WebSocket/Supabase Realtime ไม่ทำงาน)
  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pollForNewPhotos();
    });
  }

  Future<void> _pollForNewPhotos() async {
    if (!mounted) return;
    try {
      final repo = ServiceLocator.instance.videoRepository;
      final results = await repo.getThaiMhungGalleryPhotos(widget.videoId);
      final newPhotos = results.map((e) => ThaiMhungRulerPhoto.fromJson(e)).toList();
      
      if (newPhotos.length > _photos.length && mounted) {
        // มีภาพใหม่เข้ามา!
        final existingUrls = _photos.map((p) => p.photoUrl).toSet();
        final arrivedPhotos = newPhotos.where((p) => !existingUrls.contains(p.photoUrl)).toList();

        if (arrivedPhotos.isNotEmpty) {
          setState(() {
            for (final photo in arrivedPhotos) {
              _photos.insert(0, photo);
              _newItemIds.add(photo.id);
            }
          });

          // แจ้งภาพล่าสุดที่เข้ามาขึ้นไปแสดงบนแผนที่
          final lastArrived = arrivedPhotos.first;
          if (widget.onNewPhotoArrived != null) {
            widget.onNewPhotoArrived!(lastArrived);
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateToItem(
                0,
                duration: const Duration(milliseconds: 800),
                curve: Curves.elasticOut,
              );
            }
          });

          Future.delayed(const Duration(seconds: 5), () {
            if (mounted) {
              setState(() {
                for (final photo in arrivedPhotos) {
                  _newItemIds.remove(photo.id);
                }
              });
            }
          });
        }
      }
    } catch (e) {
      debugPrint('[Gallery Poll] Error: $e');
    }
  }

  /// ✅ ช่องทาง Real-time หลัก: รับภาพใหม่ผ่าน WebSocket (เร็ว + เสถียร)
  void _subscribeToWebSocketPhotos() {
    _wsPhotoSub = WebSocketService().thaiMhungPhotoStream.listen((data) {
      final incidentId = data['incidentId']?.toString() ?? data['video_id']?.toString() ?? '';
      if (incidentId != widget.videoId) return; // ไม่ใช่ incident เดียวกัน

      final photoUrl = ServiceLocator.instance.videoRepository.ensureFullUrl(
        data['photo_url']?.toString() ?? '',
      );
      if (photoUrl.isEmpty) return;

      // ป้องกันซ้ำ (กรณี Supabase Realtime ก็ส่งมาด้วย)
      final isDuplicate = _photos.any((p) => p.photoUrl == photoUrl);
      if (isDuplicate) return;

      final newPhoto = ThaiMhungRulerPhoto(
        id: data['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
        photoUrl: photoUrl,
        createdAt: data['created_at'] != null ? DateTime.tryParse(data['created_at']) ?? DateTime.now() : DateTime.now(),
        latitude: data['latitude'] != null ? double.tryParse(data['latitude'].toString()) : null,
        longitude: data['longitude'] != null ? double.tryParse(data['longitude'].toString()) : null,
      );

      if (mounted) {
        setState(() {
          _photos.insert(0, newPhoto);
          _newItemIds.add(newPhoto.id);

          if (widget.onNewPhotoArrived != null) {
            widget.onNewPhotoArrived!(newPhoto);
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateToItem(
                0,
                duration: const Duration(milliseconds: 800),
                curve: Curves.elasticOut,
              );
              Future.delayed(const Duration(seconds: 5), () {
                if (mounted) setState(() => _newItemIds.remove(newPhoto.id));
              });
            }
          });
        });
      }
    });
  }

  Future<void> _fetchPhotos() async {
    try {
      final repo = ServiceLocator.instance.videoRepository;
      final results = await repo.getThaiMhungGalleryPhotos(widget.videoId);

      if (mounted) {
        setState(() {
          _photos.clear();
          _photos.addAll(results.map((e) => ThaiMhungRulerPhoto.fromJson(e)).toList());
          _isLoading = false;
        });
        
        if (_photos.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpToItem(0);
            }
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeToNewPhotos() {
    _subscription = Supabase.instance.client
        .channel('public:thai_mhung_photos:${widget.videoId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'thai_mhung_photos',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq, 
            column: 'video_id', 
            value: widget.videoId
          ),
          callback: (payload) {
            final newPhoto = ThaiMhungRulerPhoto.fromJson(payload.newRecord);
            if (mounted) {
              setState(() {
                // ภาพใหม่ให้ไปแทรกที่ตำแหน่งแรกสุดเสมอ (บนสุด)
                _photos.insert(0, newPhoto);
                _newItemIds.add(newPhoto.id);
                
                if (widget.onNewPhotoArrived != null) {
                  widget.onNewPhotoArrived!(newPhoto);
                }
                
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    // เลื่อนโฟกัสไปที่ภาพบนสุด (Index 0) แทนที่ตำแหน่งเดิม
                    _scrollController.animateToItem(
                      0,
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.elasticOut,
                    );
                    
                    Future.delayed(const Duration(seconds: 5), () {
                      if (mounted) {
                        setState(() {
                          _newItemIds.remove(newPhoto.id);
                        });
                      }
                    });
                  }
                });
              });
            }
          },
        )
        .subscribe();
  }

  @override
  void didUpdateWidget(ThaiMhungRulerGalleryWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) {
      if (_subscription != null) {
        Supabase.instance.client.removeChannel(_subscription!);
      }
      _wsPhotoSub?.cancel();
      _pollTimer?.cancel();
      _fetchPhotos();
      _subscribeToNewPhotos();
      _subscribeToWebSocketPhotos();
      _startPolling();
    }
  }

  @override
  void dispose() {
    if (_subscription != null) {
      Supabase.instance.client.removeChannel(_subscription!);
    }
    _wsPhotoSub?.cancel();
    _pollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void animateToIndex(int index) {
    if (!mounted || _photos.isEmpty || index < 0 || index >= _photos.length) return;
    if (_scrollController.hasClients) {
      _scrollController.animateToItem(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void showLightbox(int initialIndex) {
    if (!mounted || _photos.isEmpty) return;
    
    // ประกาศ PageController เพื่อให้ PageView เริ่มต้นที่รูปที่กด
    final PageController pageController = PageController(initialPage: initialIndex);
    int currentViewIndex = initialIndex;

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    color: Colors.transparent,
                    child: Center(
                      child: PageView.builder(
                        controller: pageController,
                        itemCount: _photos.length,
                        onPageChanged: (idx) {
                          setModalState(() {
                            currentViewIndex = idx;
                          });
                          // ขยับ Ruler ข้างหลังตามรูปที่ดูอยู่ด้วย (Optional Sync)
                          if (_scrollController.hasClients) {
                             _scrollController.animateToItem(
                               idx,
                               duration: const Duration(milliseconds: 300),
                               curve: Curves.easeOut,
                             );
                          }
                        },
                        itemBuilder: (context, index) {
                          final pUrl = _photos[index].photoUrl;
                          return InteractiveViewer(
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // ✅ แสดงภาพตรงๆ: ใบหน้าถูกเบลอโดย Server (deface) มาแล้ว
                                // ไม่ต้องเบลอซ้ำที่ client ไม่ว่าจะมีสิทธิ์หรือไม่ก็ตาม
                                Image.network(
                                  pUrl,
                                  fit: BoxFit.contain,
                                  loadingBuilder: (context, child, progress) {
                                    if (progress == null) return child;
                                    return const CircularProgressIndicator(color: Colors.pinkAccent);
                                  },
                                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.white, size: 50),
                                ),
                                // 🛡️ Badge แจ้งว่าใบหน้าถูกปกป้องโดย Server-side Face Blur
                                Positioned(
                                  bottom: 16,
                                  right: 16,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.face_retouching_off, color: Colors.white70, size: 14),
                                        SizedBox(width: 4),
                                        Text(
                                          'สงวนสิทธิ์ภาพบุคคล',
                                          style: TextStyle(color: Colors.white70, fontSize: 11, decoration: TextDecoration.none),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ]
                            )
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              // ตัวนับภาพ (Image Counter)
              Positioned(
                top: 50,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${currentViewIndex + 1} / ${_photos.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, decoration: TextDecoration.none),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return SizedBox(
        height: widget.height,
        width: 60,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24)),
      );
    }

    if (_photos.isEmpty) {
      return const SizedBox.shrink(); // ซ่อนไปเลยถ้ายังไม่มีภาพ
    }

    final double itemHeight = widget.height * 0.25; 

    return Container(
      height: widget.height,
      width: 70, 
      margin: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            child: Container(
              height: itemHeight - 10,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(color: Colors.pinkAccent.withOpacity(0.4), width: 1),
                ),
                gradient: LinearGradient(
                  colors: [
                    Colors.pinkAccent.withOpacity(0.1),
                    Colors.transparent,
                    Colors.pinkAccent.withOpacity(0.1),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          
          ListWheelScrollView.useDelegate(
            controller: _scrollController,
            itemExtent: itemHeight,
            diameterRatio: 1.5,
            perspective: 0.003,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (index) {
              setState(() => _currentIndex = index);
              if (widget.onPhotoChanged != null && _photos.isNotEmpty) {
                 widget.onPhotoChanged!(index, _photos[index].photoUrl);
              }
            },
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: _photos.length,
              builder: (context, index) {
                final photo = _photos[index];
                final isSelected = index == _currentIndex;
                final isNew = _newItemIds.contains(photo.id);

                return GestureDetector(
                  onTap: () {
                    if (isSelected) {
                      if (widget.onPhotoTap != null) {
                        widget.onPhotoTap!(index, photo.photoUrl);
                      } else {
                        showLightbox(index);
                      }
                    } else {
                      _scrollController.animateToItem(
                        index,
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutBack,
                      );
                    }
                  },
                  child: AnimatedScale(
                    scale: isSelected ? 1.05 : 0.85,
                    duration: const Duration(milliseconds: 300),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isNew 
                            ? Colors.yellowAccent 
                            : isSelected ? Colors.white70 : Colors.white10,
                          width: isNew ? 2 : (isSelected ? 1.5 : 0.5),
                        ),
                        boxShadow: isNew 
                            ? [BoxShadow(color: Colors.yellowAccent.withOpacity(0.5), blurRadius: 12, spreadRadius: 2)] 
                            : (isSelected ? [const BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 2))] : []),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // ✅ แสดงภาพตรงๆ: ใบหน้าถูกเบลอโดย Server (deface) มาแล้ว
                          // ไม่ต้องเบลอซ้ำทั้งภาพ — เพื่อให้เห็นรายละเอียดเหตุการณ์ได้ชัดเจน
                          Image.network(
                            photo.photoUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return Container(color: Colors.black12);
                            },
                            errorBuilder: (context, error, stackTrace) => Container(
                              color: Colors.grey[900],
                              child: const Icon(Icons.broken_image, color: Colors.white24, size: 20),
                            ),
                          ),
                          // 🛡️ Badge แจ้งว่าใบหน้าถูกปกป้องโดย Server-side Face Blur
                          Positioned(
                            bottom: 2,
                            right: 2,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Icon(Icons.face_retouching_off, color: Colors.white70, size: 10),
                            ),
                          ),
                          if (isNew)
                            Positioned(
                              top: 2,
                              left: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.yellowAccent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'หมูงใหม่',
                                  style: TextStyle(
                                    color: Colors.black, 
                                    fontWeight: FontWeight.bold, 
                                    fontSize: 8,
                                    fontFamily: 'Sukhumvit Set'
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
