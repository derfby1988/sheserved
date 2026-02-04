import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import 'home_painters.dart';

/// Map Background Widget พร้อม Skeleton Loader และ Error Handling
class HomeMapBackground extends StatefulWidget {
  final LatLng initialLocation;
  final double initialZoom;
  
  const HomeMapBackground({
    super.key,
    this.initialLocation = const LatLng(13.7563, 100.5018), // กรุงเทพมหานคร
    this.initialZoom = 13.0,
  });

  @override
  State<HomeMapBackground> createState() => _HomeMapBackgroundState();
}

class _HomeMapBackgroundState extends State<HomeMapBackground> 
    with SingleTickerProviderStateMixin {
  bool _isMapLoaded = false;
  bool _mapHasError = false;
  int _mapErrorCount = 0;
  static const int _maxMapErrors = 5;
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    
    _startMapLoading();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  void _startMapLoading() {
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted && !_mapHasError) {
        setState(() {
          _isMapLoaded = true;
        });
      }
    });
  }

  void _retryMapLoad() {
    setState(() {
      _isMapLoaded = false;
      _mapHasError = false;
      _mapErrorCount = 0;
    });
    _startMapLoading();
  }

  void _onMapTileError(TileImage tile, Object error, StackTrace? stackTrace) {
    _mapErrorCount++;
    debugPrint('Map tile error #$_mapErrorCount: $error');
    
    if (_mapErrorCount >= _maxMapErrors && mounted && !_mapHasError) {
      setState(() {
        _mapHasError = true;
        _isMapLoaded = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Skeleton Loader
        if (!_isMapLoaded && !_mapHasError) _buildMapSkeleton(),
        
        // Error UI
        if (_mapHasError) _buildMapError(),
        
        // Map with Blur Effect
        if (!_mapHasError)
          AnimatedOpacity(
            opacity: _isMapLoaded ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 500),
            child: ClipRect(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 2.0, sigmaY: 2.0),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: widget.initialLocation,
                    initialZoom: widget.initialZoom,
                    minZoom: 10.0,
                    maxZoom: 18.0,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.sheserved.app',
                      maxZoom: 19,
                      tileProvider: CancellableNetworkTileProvider(),
                      errorTileCallback: _onMapTileError,
                      evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
                    ),
                  ],
                ),
              ),
            ),
          ),
        
        // Overlay
        if (!_mapHasError)
          Container(
            decoration: BoxDecoration(
              color: AppColors.background.withOpacity(0.05),
            ),
          ),
      ],
    );
  }

  Widget _buildMapSkeleton() {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2 * _shimmerController.value, 0),
              end: Alignment(-1.0 + 2 * _shimmerController.value + 1, 0),
              colors: [
                AppColors.background,
                AppColors.background.withOpacity(0.5),
                AppColors.surface,
                AppColors.background.withOpacity(0.5),
                AppColors.background,
              ],
              stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
            ),
          ),
          child: Stack(
            children: [
              // Grid pattern
              CustomPaint(
                size: Size.infinite,
                painter: MapSkeletonPainter(
                  color: AppColors.border.withOpacity(0.3),
                ),
              ),
              // Loading indicator
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.shadow,
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'กำลังโหลดแผนที่...',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMapError() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.background,
            AppColors.background.withOpacity(0.8),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                Icons.map_outlined,
                size: 48,
                color: AppColors.textHint,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ไม่สามารถโหลดแผนที่ได้',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ต',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _retryMapLoad,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('ลองใหม่'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
