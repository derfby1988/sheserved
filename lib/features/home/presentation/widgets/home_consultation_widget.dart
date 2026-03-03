import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../features/auth/data/repositories/user_repository.dart';
import '../../../../features/consultation/data/repositories/consultation_repository.dart';
import 'home_painters.dart';
import '../../../../services/auth_service.dart';

/// Consultation Widget - วงกลมปรึกษาแพทย์และเภสัช
/// รองรับ 2 โหมด: ปกติ (Full) และ ย่อขนาด (Mini)
class HomeConsultationWidget extends StatefulWidget {
  final VoidCallback? onTap;
  final int? availableCount;
  final bool useRealtime;
  final bool isMini;
  final double? overrideSize;

  const HomeConsultationWidget({
    super.key,
    this.onTap,
    this.availableCount,
    this.useRealtime = true,
    this.isMini = false,
    this.overrideSize,
  });

  @override
  State<HomeConsultationWidget> createState() => _HomeConsultationWidgetState();
}

class _HomeConsultationWidgetState extends State<HomeConsultationWidget> 
    with TickerProviderStateMixin {
  int _count = 0;
  
  late AnimationController _rotationController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Scale animation for tactile feedback
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;
  
  // Ratio animation like Health Card
  late AnimationController _ratioController;
  late Animation<double> _ratioAnimation;
  double _currentRatio = 1.0;
  
  // Real-time Streams
  Stream<Map<String, int>>? _providerStream;
  Stream<int>? _recipientStream;

  @override
  void initState() {
    super.initState();
    
    // Rotation for dotted circle
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    // Pulse for online sticker
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.1, end: 0.8).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Scale effect on tap
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );
    _scaleAnimation = _scaleController;

    // Ratio animation (0.0 to 1.0)
    _ratioController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _ratioAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ratioController, curve: Curves.fastOutSlowIn),
    );

    if (widget.availableCount != null) {
      _count = widget.availableCount!;
      _updateRatio(_count, 0);
    } else if (widget.useRealtime) {
      _initStreams();
      _loadInitialData();
    }

    // Listen for auth changes to refresh counts immediately (e.g. after provider login)
    AuthService.instance.addListener(_handleAuthChange);
  }

  void _handleAuthChange() {
    if (mounted) {
      debugPrint('HomeConsultationWidget: Auth change detected, RE-INITIALIZING streams and refreshing...');
      setState(() {
        _initStreams(); // Connect new streams as auth context might have changed (RLS)
        _loadInitialData();
      });
    }
  }

  void _initStreams() {
    debugPrint('HomeConsultationWidget: Initializing real-time streams (Providers & Recipients)...');
    final userRepo = UserRepository(Supabase.instance.client);
    final consulRepo = ConsultationRepository(Supabase.instance.client);
    
    _providerStream = userRepo.watchOnlineProviderCounts();
    _recipientStream = consulRepo.watchActiveRecipientCount();
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_handleAuthChange);
    _rotationController.dispose();
    _pulseController.dispose();
    _scaleController.dispose();
    _ratioController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) => _scaleController.reverse();
  void _onTapUp(TapUpDetails details) => _scaleController.forward();
  void _onTapCancel() => _scaleController.forward();

  Future<void> _loadInitialData() async {
    try {
      final userRepo = UserRepository(Supabase.instance.client);
      final consulRepo = ConsultationRepository(Supabase.instance.client);
      
      final providerCount = await userRepo.getTotalOnlineProviderCount();
      final recipientCount = await consulRepo.getActiveRecipientCount();
      
      if (mounted) {
        setState(() {
          _count = providerCount;
          _updateRatio(providerCount, recipientCount);
        });
      }
    } catch (e) {
      if (mounted) setState(() {});
    }
  }

  void _updateRatio(int providers, int recipients) {
    double ratio = 1.0;
    if (providers + recipients > 0) {
      ratio = providers / (providers + recipients);
    } else if (providers == 0 && recipients == 0) {
      ratio = 1.0; // Default to full green if empty
    }
    
    _ratioAnimation = Tween<double>(
      begin: _ratioAnimation.value,
      end: ratio,
    ).animate(CurvedAnimation(parent: _ratioController, curve: Curves.easeOutCubic));
    
    _ratioController.reset();
    _ratioController.forward();
    _currentRatio = ratio;
  }

  /// คำนวณ Base Size ตาม mode
  double _calculateBaseSize(BuildContext context) {
    if (widget.overrideSize != null) {
      return widget.overrideSize!;
    }
    if (widget.isMini) {
      return 90.0; // ขนาดจิ๋วสำหรับ Mini Mode
    }
    final screenWidth = MediaQuery.of(context).size.width;
    final widgetSize = screenWidth * 0.72;
    return widgetSize.clamp(200.0, 320.0);
  }

  @override
  Widget build(BuildContext context) {
    final baseSize = _calculateBaseSize(context);
    final isMini = widget.isMini || baseSize < 150;
    final innerSize = baseSize * 0.85;
    final dottedSize = innerSize * 0.92;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: isMini ? 0 : 16),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Animated Ratio Border (Like Health Card Score)
              if (!isMini)
                AnimatedBuilder(
                  animation: _ratioAnimation,
                  builder: (context, child) {
                    return SizedBox(
                      width: baseSize,
                      height: baseSize,
                      child: CustomPaint(
                        painter: RatioCirclePainter(
                          providerRatio: _ratioAnimation.value,
                          providerColor: AppColors.primary.withOpacity(0.4),
                          recipientColor: AppColors.accent.withOpacity(0.4),
                          providerLabel: 'ผู้ให้บริการ',
                          recipientLabel: 'รอปรึกษา',
                          strokeWidth: 14 * (baseSize / 280),
                        ),
                      ),
                    );
                  },
                ),
              
              // Decoration Ring Elements (ซ่อนใน Mini Mode)
              if (!isMini)
                SizedBox(
                  width: baseSize,
                  height: baseSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      _buildRingDot(baseSize, 0, 18),
                      _buildRingDot(baseSize, 180, 18),
                    ],
                  ),
                ),
              
              // Inner UI Area
              Container(
                width: isMini ? baseSize : innerSize,
                height: isMini ? baseSize : innerSize,
                decoration: BoxDecoration(
                  color: AppColors.backgroundWhite,
                  shape: BoxShape.circle,
                  boxShadow: isMini
                    ? [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Inner Dotted Line (Animated Spinning) - ซ่อนใน Mini Mode
                    if (!isMini)
                      RotationTransition(
                        turns: _rotationController,
                        child: SizedBox(
                          width: dottedSize,
                          height: dottedSize,
                          child: CustomPaint(
                            painter: DottedCirclePainter(
                              color: AppColors.textHint.withOpacity(0.3),
                              strokeWidth: 1.5,
                              dashWidth: 4,
                              dashSpace: 3,
                            ),
                          ),
                        ),
                      ),
                    
                    // Content
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Combined Stream for Providers & Recipients
                        widget.useRealtime && widget.availableCount == null && _providerStream != null
                          ? StreamBuilder<Map<String, int>>(
                              stream: _providerStream,
                              builder: (context, providerSnapshot) {
                                return StreamBuilder<int>(
                                  stream: _recipientStream,
                                  builder: (context, recipientSnapshot) {
                                    final providers = providerSnapshot.hasData 
                                      ? providerSnapshot.data!.values.fold<int>(0, (a, b) => a + b)
                                      : _count;
                                    final recipients = recipientSnapshot.data ?? 0;
                                    
                                    if (providerSnapshot.hasData) {
                                      debugPrint('HomeConsultationWidget: Stream update - providers: $providers, recipients: $recipients');
                                    }
                                    
                                    // Update ratio animation target if changed
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      if (!mounted) return;
                                      double newRatio = (providers + recipients > 0) 
                                        ? providers / (providers + recipients) 
                                        : 1.0;
                                      if ((newRatio - _currentRatio).abs() > 0.01) {
                                        _updateRatio(providers, recipients);
                                      }
                                    });

                                    return isMini 
                                      ? _buildMiniContent(providers, baseSize)
                                      : _buildMainContent(providers, baseSize);
                                  }
                                );
                              }
                            )
                          : isMini
                            ? _buildMiniContent(_count, baseSize)
                            : _buildMainContent(_count, baseSize),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper เพื่อสร้างจุดประดับตามจุดต่างๆ ของวงกลม
  Widget _buildRingDot(double size, double angleInDegrees, double offset) {
    return Positioned(
      // คำนวณตำแหน่งจุดประดับ (Simplified Position)
      top: angleInDegrees == 0 ? offset : null,
      bottom: angleInDegrees == 180 ? offset : null,
      left: angleInDegrees == 90 ? offset : null,
      right: angleInDegrees == 270 ? offset : null,
      child: Container(
        width: 16 * (size/280), // ขนาดจุดแปรผันตามขนาด Widget
        height: 16 * (size/280),
        decoration: const BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  /// Mini Mode Content - แสดงเฉพาะไอคอน + จุดออนไลน์ + ตัวเลข
  Widget _buildMiniContent(int onlineCount, double baseSize) {
    final isOffline = onlineCount == 0;
    final scale = baseSize / 90.0; // scale จากขนาดฐาน 90px

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Stethoscope Icon - ขนาดเล็กลง
        Icon(
          Icons.medical_services,
          size: (24 * scale).clamp(16.0, 32.0),
          color: isOffline ? AppColors.textHint : AppColors.primary,
        ),
        SizedBox(height: 2 * scale),
        // Online Count with Pulsating Dot
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  width: 6 * scale,
                  height: 6 * scale,
                  decoration: BoxDecoration(
                    color: onlineCount > 0 ? AppColors.success : AppColors.textHint,
                    shape: BoxShape.circle,
                    boxShadow: onlineCount > 0 ? [
                      BoxShadow(
                        color: AppColors.success.withOpacity(_pulseAnimation.value),
                        blurRadius: 6 * _pulseAnimation.value + 1,
                        spreadRadius: 1 * _pulseAnimation.value,
                      )
                    ] : null,
                  ),
                );
              },
            ),
            SizedBox(width: 3 * scale),
            Text(
              '$onlineCount',
              style: TextStyle(
                fontSize: (11 * scale).clamp(8.0, 14.0),
                fontWeight: FontWeight.bold,
                color: onlineCount > 0 ? AppColors.success : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMainContent(int onlineCount, double baseSize) {
    final isOffline = onlineCount == 0;
    final iconSize = 56 * (baseSize / 280);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Stethoscope Icon
        Icon(
          Icons.medical_services,
          size: iconSize,
          color: isOffline ? AppColors.textHint : AppColors.textPrimary,
        ),
        
        SizedBox(height: 16 * (baseSize / 280)),
        
        // Title
        Text(
          'ปรึกษา',
          style: AppTextStyles.heading3.copyWith(
            color: isOffline ? AppColors.textSecondary : AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        
        SizedBox(height: 6 * (baseSize / 280)),
        
        // Subtitle
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: AppTextStyles.bodyMedium.copyWith(
              color: isOffline ? AppColors.textHint : AppColors.textPrimary,
            ),
            children: [
              const TextSpan(text: 'แพทย์ '),
              TextSpan(
                text: '&',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const TextSpan(text: ' เภสัช'),
            ],
          ),
        ),
        
        SizedBox(height: 12 * (baseSize / 280)),
        
        // Status Messaging (Empty State UX)
        Text(
          isOffline ? 'ขณะนี้อยู่นอกเวลาทำการ' : 'พร้อมให้บริการขณะนี้',
          style: AppTextStyles.caption.copyWith(
            color: isOffline ? AppColors.error.withOpacity(0.7) : AppColors.textSecondary,
            fontWeight: isOffline ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        
        if (isOffline)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              'ฝากข้อความทิ้งไว้ได้เลย',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
                fontSize: 10,
              ),
            ),
          ),
        
        SizedBox(height: 8 * (baseSize / 280)),
        
        // Online Count Display
        _buildOnlineCount(onlineCount, baseSize),
      ],
    );
  }

  Widget _buildOnlineCount(int onlineCount, double baseSize) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Pulsating Online Dot
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: onlineCount > 0 ? AppColors.success : AppColors.textHint,
                shape: BoxShape.circle,
                boxShadow: onlineCount > 0 ? [
                  BoxShadow(
                    color: AppColors.success.withOpacity(_pulseAnimation.value),
                    blurRadius: 10 * _pulseAnimation.value + 2,
                    spreadRadius: 2 * _pulseAnimation.value,
                  )
                ] : null,
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        Text(
          '$onlineCount ราย',
          style: AppTextStyles.bodySmall.copyWith(
            color: onlineCount > 0 ? AppColors.success : AppColors.textSecondary,
            fontWeight: onlineCount > 0 ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
