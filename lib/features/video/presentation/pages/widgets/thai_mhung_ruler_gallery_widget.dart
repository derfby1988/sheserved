import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../../services/service_locator.dart';
import '../../../../../services/websocket_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ThaiMhungRulerPhoto {
  final String id;
  final String photoUrl;
  final DateTime createdAt;

  ThaiMhungRulerPhoto({required this.id, required this.photoUrl, required this.createdAt});

  factory ThaiMhungRulerPhoto.fromJson(Map<String, dynamic> json) {
    // ใช้ VideoRepository เพื่อ normalize URL เสมอ (กรณี realtime payload ส่งเป็น relative path)
    final url = ServiceLocator.instance.videoRepository.ensureFullUrl(json['photo_url']?.toString() ?? '');
    return ThaiMhungRulerPhoto(
      id: json['id']?.toString() ?? '',
      photoUrl: url,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
    );
  }
}

class ThaiMhungRulerGalleryWidget extends StatefulWidget {
  final String videoId;
  final double height;
  
  const ThaiMhungRulerGalleryWidget({
    super.key,
    required this.videoId,
    required this.height,
  });

  @override
  State<ThaiMhungRulerGalleryWidget> createState() => _ThaiMhungRulerGalleryWidgetState();
}

class _ThaiMhungRulerGalleryWidgetState extends State<ThaiMhungRulerGalleryWidget> {
  final List<ThaiMhungRulerPhoto> _photos = [];
  bool _isLoading = true;
  RealtimeChannel? _subscription;
  int _currentIndex = 0;
  final FixedExtentScrollController _scrollController = FixedExtentScrollController();
  
  final Set<String> _newItemIds = {};

  @override
  void initState() {
    super.initState();
    _fetchPhotos();
    _subscribeToNewPhotos();
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
                _photos.insert(_currentIndex, newPhoto);
                _newItemIds.add(newPhoto.id);
                
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.animateToItem(
                      _currentIndex,
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
      _fetchPhotos();
      _subscribeToNewPhotos();
    }
  }

  @override
  void dispose() {
    if (_subscription != null) {
      Supabase.instance.client.removeChannel(_subscription!);
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _showLightbox(String imageUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                color: Colors.transparent,
                child: Center(
                  child: InteractiveViewer(
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const CircularProgressIndicator(color: Colors.pinkAccent);
                      },
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.white, size: 50),
                    ),
                  ),
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
      return Container(
        height: widget.height,
        width: 70,
        margin: const EdgeInsets.only(left: 4),
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_library_outlined, color: Colors.white10, size: 20),
              SizedBox(height: 4),
              Text('ไม่มีรูป', style: TextStyle(color: Colors.white10, fontSize: 8)),
            ],
          ),
        ),
      );
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
                      _showLightbox(photo.photoUrl);
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
