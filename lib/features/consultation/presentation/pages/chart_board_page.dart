import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import '../../data/models/consultation_request_model.dart';
import '../../data/models/consultation_entry.dart';
import '../../../../features/chat/data/models/chat_models.dart';
import '../../data/models/consultation_package.dart';
import '../widgets/package_wheel_selector.dart';
import '../../../../features/admin/models/profession.dart';
import 'prescription_editor_page.dart';
import 'consultation_note_editor_page.dart';
import '../widgets/timer_badge_widget.dart';
import '../widgets/body_map_summary_widget.dart';
import '../widgets/action_buttons_widget.dart';
import '../widgets/chat_input_bar_widget.dart';
import '../widgets/mini_voice_player.dart';
import '../controllers/session_timer_controller.dart';
import '../controllers/professions_refresh_controller.dart';
import '../utils/timer_formatter.dart';
import '../utils/chart_metric_helpers.dart';
import '../utils/body_area_formatter.dart';
import '../utils/expert_status_helpers.dart';
import '../mixins/health_permission_mixin.dart';
import '../widgets/health_data/expert_status_banner.dart';
import '../widgets/health_data/health_permission_status_banner.dart';
import '../widgets/health_data/pain_level_selector.dart';
import '../widgets/health_data/payment_card.dart';
import '../widgets/health_data/prescription_card.dart';
import '../widgets/health_data/summary_card.dart';
import '../widgets/health_data/message_bubble.dart';
import '../widgets/health_data/health_data_error_view.dart';
import '../widgets/health_data/granted_health_sections.dart';

class ChartBoardPage extends StatefulWidget {
  final ConsultationRequestModel? request;
  final ConsultationEntry? entry; // For active consultations
  final bool readOnly; // true = ดูอย่างเดียว ไม่สามารถดำเนินการได้

  const ChartBoardPage({
    super.key,
    this.request,
    this.entry,
    this.readOnly = false,
  });

  @override
  State<ChartBoardPage> createState() => _ChartBoardPageState();
}

class _ChartBoardPageState extends State<ChartBoardPage>
    with TickerProviderStateMixin, WidgetsBindingObserver, HealthPermissionMixin {
  final _chatRepository = ServiceLocator.instance.chatRepository;
  final _currentUser = AuthService.instance.currentUser;
  final TextEditingController _msgController = TextEditingController();

  @override
  bool get isProvider => _isProvider;

  @override
  String? get activeConsultationId => _activeConsultationId;
  final ScrollController _scrollController = ScrollController();
  final _audioRecorder = AudioRecorder();

  String? _consultationRoomId;
  String? _activeConsultationId;

  late final ValueNotifier<List<ChatMessage>> _messagesNotifier;
  late final ValueNotifier<bool> _isChatLoadingNotifier;
  late final ValueNotifier<bool> _isRecordingNotifier;
  late final ValueNotifier<bool> _isSendingNotifier;
  bool _isConsultationActive = false; // Locked until paid (for patient)
  bool _isHeaderExpanded = true;
  bool _isProvider = false;
  bool _hasSubmitted = false; // true = ผู้ป่วยกด "ยืนยันและส่งคำรักษา" แล้ว → back ไปหน้า profile/history

  StreamSubscription? _messagesSub;
  List<ConsultationPackage> _availablePackages = [];
  ConsultationPackage? _selectedPackage;
  bool _isLoadingPackages = false;

  // --- Session Timer Features ---
  late final SessionTimerController _timerController;
  bool _hasReviewed = false;

  // --- Expert Status ---
  List<Map<String, dynamic>> _expertStatuses = [];
  StreamSubscription? _expertStatusSub;

  // --- Professions (for accurate icons/colors from admin settings) ---
  List<Profession> _professions = [];
  late final ProfessionsRefreshController _professionsRefreshController;
  Map<String, dynamic>? _consultationData;

  // --- Room Status ---
  StreamSubscription? _roomSub;
  StreamSubscription? _consultationSub;
  DateTime? _roomStartedAt;

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  String? _selectedPain;

  @override
  void initState() {
    super.initState();
    // Robust provider check (matches Dashboard logic)
    final professionId = _currentUser?.professionId;
    _isProvider = professionId != null && 
                  professionId != '00000000-0000-0000-0000-000000000001';
    
    // Auto-detect initial state
    // NOTE: Don't set _isConsultationActive here — let _initChat determine
    // from real payment_status to avoid hiding the pain selector prematurely.
    if (widget.entry != null) {
      _isHeaderExpanded = false;
      _selectedPain = widget.entry!.symptomsChart['pain_level']?.toString();
    } else if (widget.request?.symptomsChart['pain_level'] != null) {
      _selectedPain = widget.request!.symptomsChart['pain_level']?.toString();
    }

    _messagesNotifier = ValueNotifier([]);
    _isChatLoadingNotifier = ValueNotifier(true);
    _isRecordingNotifier = ValueNotifier(false);
    _isSendingNotifier = ValueNotifier(false);
    _timerController = SessionTimerController(onExpired: _onSessionExpired);

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _initChat();
    _loadPackages();
    _loadProfessions();
    _professionsRefreshController = ProfessionsRefreshController(onRefresh: _loadProfessions);
    _professionsRefreshController.start();
    WidgetsBinding.instance.addObserver(this);
    initHealthPermission();
  }

  void _startTimer() {
    debugPrint('[ChartBoard] _startTimer called, _isTimerRunning=${_timerController.isRunning.value}, remaining=${_timerController.remainingSeconds.value}');
    _timerController.start();
  }

  Future<void> _onSessionExpired() async {
    // 1. Update DB to lock the room
    if (_consultationRoomId != null) {
      try {
        await Supabase.instance.client
            .from('chat_rooms')
            .update({
              'is_active': false,
              'ended_at': DateTime.now().toIso8601String(),
            })
            .eq('id', _consultationRoomId!);
      } catch (e) {
        debugPrint('Error closing session in DB: $e');
      }
    }

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('หมดเวลาการปรึกษา'),
          content: const Text('การปรึกษาในเซสชั่นนี้สิ้นสุดลงแล้ว'),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                if (!_isProvider && !_hasReviewed) {
                  _showRatingDialog();
                } else {
                  Navigator.pop(context);
                }
              },
              child: const Text('รับทราบ'),
            ),
          ],
        ),
      );
    }
  }

  void _showRatingDialog() {
    int localRating = 5;
    final TextEditingController commentCtrl = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('ให้คะแนนการปรึกษา'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('คุณพอใจกับการให้บริการครั้งนี้เพียงใด?'),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final starIndex = index + 1;
                  return IconButton(
                    icon: Icon(
                      starIndex <= localRating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 32,
                    ),
                    onPressed: () {
                      setDialogState(() => localRating = starIndex);
                    },
                  );
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: commentCtrl,
                decoration: const InputDecoration(
                  hintText: 'เขียนข้อความแนะนำ (ถ้ามี)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ภายหลัง'),
            ),
            ElevatedButton(
              onPressed: () async {
                await _submitReview(localRating, commentCtrl.text);
                if (mounted) {
                  Navigator.pop(ctx); // Close dialog
                  Navigator.pop(context); // Exit room
                }
              },
              child: const Text('ส่งคะแนน'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReview(int rating, String comment) async {
    final consultationId = widget.entry?.id ?? widget.request?.id;
    final currentUserId = _currentUser?.id;
    if (consultationId == null || currentUserId == null) return;

    try {
      // Find the provider (first one for now)
      final providerData = _expertStatuses.firstWhere(
        (e) => e['providerId'] != null,
        orElse: () => {},
      );
      final providerId = providerData['providerId'];

      if (providerId == null) return;

      await Supabase.instance.client.from('consultation_reviews').insert({
        'consultation_id': consultationId,
        'patient_id': currentUserId,
        'provider_id': providerId,
        'rating': rating,
        'comment': comment,
      });

      if (mounted) {
        setState(() => _hasReviewed = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ขอบคุณสำหรับการให้คะแนน')),
        );
      }
    } catch (e) {
      debugPrint('Error submitting review: $e');
    }
  }

  Future<void> _loadPackages() async {
    // Load packages for ALL users (including providers) so expert group banner works
    setState(() => _isLoadingPackages = true);
    try {
      final response = await Supabase.instance.client
          .from('consultation_packages')
          .select()
          .eq('is_active', true)
          .order('price');

      final pks = (response as List)
          .map((e) => ConsultationPackage.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      if (mounted) {
        setState(() {
          _availablePackages = pks;
          _isLoadingPackages = false;
        });

        _syncSelectedPackageFromConsultation();

        // If expert statuses already loaded, re-merge with package groups to show waiting icons
        if (_expertStatuses.isNotEmpty && _selectedPackage != null) {
          final joined = _expertStatuses.where((e) => e['status'] == 'joined').toList();
          final merged = _mergeWithPackageGroups(joined);
          setState(() => _expertStatuses = merged);
        }
      }
    } catch (e) {
      debugPrint('Error loading packages: $e');
      if (mounted) setState(() => _isLoadingPackages = false);
    }
  }

  Future<void> _loadProfessions() async {
    try {
      final professions = await ServiceLocator.instance.professionRepository.getAllProfessions();
      if (mounted) {
        setState(() => _professions = professions);
      }
      debugPrint('[ChartBoard] _loadProfessions: loaded ${professions.length} professions');
    } catch (e) {
      debugPrint('[ChartBoard] Error loading professions: $e');
    }
  }

  String? _canonicalPackageId() {
    final entryPackageId = widget.entry?.packageId?.trim();
    if (entryPackageId != null && entryPackageId.isNotEmpty) return entryPackageId;

    final requestPackageId = widget.request?.packageId?.trim();
    if (requestPackageId != null && requestPackageId.isNotEmpty) return requestPackageId;

    final consultPackageId = _consultationData?['package_id']?.toString().trim();
    if (consultPackageId != null && consultPackageId.isNotEmpty) return consultPackageId;

    return null;
  }

  void _syncSelectedPackageFromConsultation() {
    final targetPackageId = _canonicalPackageId();
    if (targetPackageId == null) {
      debugPrint('[ChartBoard] _syncSelectedPackageFromConsultation: no canonical packageId yet');
      return;
    }

    final matched = _availablePackages.where((p) => p.id == targetPackageId).toList();
    if (matched.isNotEmpty) {
      if (_selectedPackage?.id != matched.first.id) {
        debugPrint('[ChartBoard] _syncSelectedPackageFromConsultation: selected package => ${matched.first.name} ($targetPackageId)');
      }
      _selectedPackage = matched.first;
    } else {
      debugPrint('[ChartBoard] _syncSelectedPackageFromConsultation: packageId=$targetPackageId not found in active packages');
      _selectedPackage = null;
    }
  }


  Future<void> _initChat() async {
    _isChatLoadingNotifier.value = true;

    try {
      final currentUserId = _currentUser?.id;
      final supabase = Supabase.instance.client;

      if (currentUserId == null) {
        _isChatLoadingNotifier.value = false;
        return;
      }

      // 1. Determine Room ID & Consultation ID
      String? consultationId = _activeConsultationId;
      if (consultationId == null) {
        if (widget.entry != null) {
          consultationId = widget.entry!.id;
        } else if (widget.request != null) {
          consultationId = widget.request!.id;
        }
      }

      if (consultationId == null || consultationId.isEmpty) {
        _isChatLoadingNotifier.value = false;
        setState(() => _isConsultationActive = false);
        return;
      }

      final roomId = 'consult_$consultationId';
      setState(() {
        _consultationRoomId = roomId;
        _activeConsultationId = consultationId;
      });

      await _ensureConsultationRoom(
        roomId,
        currentUserId,
        consultationId: consultationId,
        title: widget.entry?.packageName ?? widget.request?.packageName,
      );

      await loadLatestPermission();

      // 2. Fetch Consultation & Room Details
      final results = await Future.wait([
        supabase.from('consultation_requests').select().eq('id', consultationId).maybeSingle(),
        supabase.from('chat_rooms').select().eq('id', roomId).maybeSingle(),
      ]);

      final consultData = results[0];
      final roomData = results[1];

      if (consultData != null) {
        if (mounted) {
          setState(() => _consultationData = consultData as Map<String, dynamic>);
        }
        _syncSelectedPackageFromConsultation();
        final status = consultData['status'] as String? ?? 'pending';
        
        if (mounted) {
          setState(() {
            // Patient needs to confirm first, Providers can always see if they are assigned
            _isConsultationActive = (status == 'in_progress') || _isProvider;
            
            if (consultData['package_id'] != null && _selectedPackage == null) {
              // Try to find in loaded packages later
            }
          });
        }

        // Subscribe to consultation updates so patient sees provider_id / status changes
        _consultationSub = supabase
            .from('consultation_requests')
            .stream(primaryKey: ['id'])
            .eq('id', consultationId)
            .listen((updatedList) {
              if (updatedList.isEmpty) return;
              final updated = updatedList.first;
              final newProviderId = updated['provider_id'] as String?;
              final oldProviderId = _consultationData?['provider_id'] as String?;
              debugPrint('[ChartBoard] consultation_requests realtime update: provider_id=$newProviderId (was $oldProviderId), status=${updated['status']}');
              if (mounted) {
                setState(() {
                  _consultationData = updated;
                  final newStatus = updated['status'] as String? ?? 'pending';
                  _isConsultationActive = (newStatus == 'in_progress') || _isProvider;
                });
              }
              // Re-fetch expert statuses when provider_id or status changes
              final cid = consultationId;
              final newStatus = updated['status'] as String? ?? 'pending';
              final oldStatus = _consultationData?['status'] as String? ?? 'pending';
              
              if ((newProviderId != oldProviderId || newStatus != oldStatus) && cid != null && cid.isNotEmpty) {
                debugPrint('[ChartBoard] provider_id or status changed → re-fetching expert statuses');
                _fetchExpertStatuses(cid);
              }
            });
      }

      if (roomData != null) {
        final startedAtStr = roomData['started_at'] as String?;
        final sessionMins = (roomData['session_minutes'] as int?) ?? 15;
        final isActive = roomData['is_active'] as bool? ?? true;

        if (startedAtStr != null) {
          _roomStartedAt = DateTime.parse(startedAtStr);
        }

        if (startedAtStr != null && isActive) {
          final startedAt = DateTime.parse(startedAtStr);
          final now = DateTime.now();
          final elapsedSeconds = now.difference(startedAt).inSeconds;
          final totalSeconds = sessionMins * 60;

          if (mounted) {
            _timerController.remainingSeconds.value = (totalSeconds - elapsedSeconds).clamp(0, totalSeconds);
            // ❌ ไม่เริ่ม timer ตรงนี้ — ต้องรอ _fetchExpertStatuses หรือ stream ตรวจสอบ expert ครบก่อน
          }
        }

        // Subscribe to room updates so timer reacts when started_at / is_active changes
        _roomSub = supabase
            .from('chat_rooms')
            .stream(primaryKey: ['id'])
            .eq('id', roomId)
            .listen((roomList) {
              if (roomList.isEmpty) return;
              final updatedRoom = roomList.first;
              final newStartedAt = updatedRoom['started_at'] as String?;
              final newIsActive = updatedRoom['is_active'] as bool? ?? true;
              final newSessionMins = (updatedRoom['session_minutes'] as int?) ?? 15;

              if (newStartedAt != null) {
                _roomStartedAt = DateTime.parse(newStartedAt);
              }

              if (newStartedAt != null && newIsActive) {
                final startedAt = DateTime.parse(newStartedAt);
                final now = DateTime.now();
                final elapsed = now.difference(startedAt).inSeconds;
                final total = newSessionMins * 60;
                final remaining = (total - elapsed).clamp(0, total);

                if (mounted) {
                  _timerController.remainingSeconds.value = remaining;
                  // ❌ ไม่เริ่ม timer แค่เพราะ room มี started_at — ต้องรอ expert ครบก่อน
                  // Timer จะเริ่มจาก expert status stream เมื่อ _hasAllRequiredExpertsJoined() == true
                }
              } else if (!newIsActive && _timerController.isRunning.value) {
                _timerController.stop();
              }
            });
      }

      // 3. Subscribe to Expert Statuses (Priority 2)
      debugPrint('[ChartBoard] _initChat about to call _fetchExpertStatuses with consultationId=$consultationId');
      _fetchExpertStatuses(consultationId);
      _expertStatusSub = supabase
          .from('consultation_room_experts')
          .stream(primaryKey: ['id'])
          .eq('consultation_id', consultationId)
          .listen((data) {
            if (mounted) {
              final joined = data.map((e) => {
                'role': e['expert_group_role'],
                'name': e['expert_group_name'],
                'status': e['status'],
                'providerId': e['provider_id'],
                'isRequired': e['is_required'] as bool? ?? false,
                'joinedAt': e['joined_at'],
                'providerAvatarUrl': e['provider_avatar_url'] ?? e['provider_image_url'] ?? e['avatar_url'] ?? e['profile_image_url'],
                'expertGroupIcon': e['expert_group_icon'] ?? e['category_icon'] ?? e['group_icon'] ?? e['icon'],
              }).toList();
              // Merge with package groups to show waiting groups too
              final merged = _mergeWithPackageGroups(joined);
              setState(() {
                _expertStatuses = merged;
              });
            }
            // Start timer only when ALL required experts have joined (per improvement plan)
            // ✅ ใช้ _expertStatuses (merged กับ package groups) ไม่ใช่ data (raw DB)
            final requiredExperts = _expertStatuses.where((e) => e['isRequired'] == true).toList();
            final allRequiredJoined = requiredExperts.isNotEmpty &&
                requiredExperts.every((e) => e['status'] == 'joined' || e['joinedAt'] != null);
            // Fallback: if no required experts defined yet, start when ANY expert joins
            final anyJoined = _expertStatuses.any((e) => e['status'] == 'joined' || e['joinedAt'] != null);
            final shouldStart = allRequiredJoined || (requiredExperts.isEmpty && anyJoined);
            debugPrint('[ChartBoard] stream _expertStatuses.length=${_expertStatuses.length}, required=${requiredExperts.length}, allRequiredJoined=$allRequiredJoined, anyJoined=$anyJoined, _isTimerRunning=${_timerController.isRunning.value}, remaining=${_timerController.remainingSeconds.value}');
            if (shouldStart && !_timerController.isRunning.value && _timerController.remainingSeconds.value > 0) {
              debugPrint('[ChartBoard] >>> Starting timer from stream (all required joined)');
              _startTimer();
            }
          });

      // 4. Load Messages
      final messages = await _chatRepository.getMessages(roomId);

      if (mounted) {
        _messagesNotifier.value = messages;
        _isChatLoadingNotifier.value = false;

        // Subscribe to messages
        _messagesSub = _chatRepository.streamMessages(roomId).listen((updatedMessages) {
          if (mounted) {
            _messagesNotifier.value = updatedMessages;
            _scrollToBottom();
          }
        });

        _fadeController.forward();
        _slideController.forward();
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('ChartBoardPage: Init error: $e');
      if (mounted) _isChatLoadingNotifier.value = false;
    }
  }

  Future<void> _fetchExpertStatuses(String consultationId) async {
    try {
      debugPrint('[ChartBoard] _fetchExpertStatuses START for consultationId=$consultationId');
      final data = await Supabase.instance.client
          .from('consultation_room_experts')
          .select()
          .eq('consultation_id', consultationId);

      debugPrint('[ChartBoard] _fetchExpertStatuses rows=${(data as List).length}');
      for (final row in data) {
        debugPrint('[ChartBoard] expert raw row: $row');
      }

      List<Map<String, dynamic>> mapped = (data as List).map((e) => {
        'role': e['expert_group_role'],
        'name': e['expert_group_name'],
        'status': e['status'],
        'providerId': e['provider_id'],
        'isRequired': e['is_required'] as bool? ?? false,
        'joinedAt': e['joined_at'],
        'providerAvatarUrl': e['provider_avatar_url'] ?? e['provider_image_url'] ?? e['avatar_url'] ?? e['profile_image_url'],
        'expertGroupIcon': e['expert_group_icon'] ?? e['category_icon'] ?? e['group_icon'] ?? e['icon'],
      }).toList();

      // Fallback 0: ensure rows exist from package data (trigger safety net)
      if (mapped.isEmpty && _consultationData?['package_id'] != null) {
        debugPrint('[ChartBoard] consultation_room_experts empty — calling ensureRoomExperts');
        final repo = ServiceLocator.instance.consultationRepository;
        await repo.ensureRoomExperts(
          consultationId: consultationId,
          packageId: _consultationData!['package_id'] as String,
          roomId: _consultationData!['room_id'] as String?,
        );
        // Re-query after insert
        final refreshed = await Supabase.instance.client
            .from('consultation_room_experts')
            .select()
            .eq('consultation_id', consultationId);
        if ((refreshed as List).isNotEmpty) {
          debugPrint('[ChartBoard] ensureRoomExperts succeeded, re-query got ${refreshed.length} rows');
          mapped = (refreshed as List).map((e) => {
            'role': e['expert_group_role'],
            'name': e['expert_group_name'],
            'status': e['status'],
            'providerId': e['provider_id'],
            'isRequired': e['is_required'] as bool? ?? false,
            'joinedAt': e['joined_at'],
            'providerAvatarUrl': e['provider_avatar_url'] ?? e['provider_image_url'] ?? e['avatar_url'] ?? e['profile_image_url'],
            'expertGroupIcon': e['expert_group_icon'] ?? e['category_icon'] ?? e['group_icon'] ?? e['icon'],
          }).toList();
        }
      }

      // Fallback 1: query chat_room_members + users
      if (mapped.isEmpty) {
        debugPrint('[ChartBoard] consultation_room_experts empty — falling back to chat_room_members');
        final roomId = 'consult_$consultationId';
        final members = await Supabase.instance.client
            .from('chat_room_members')
            .select('user_id, role, joined_at, users!inner(first_name, last_name, profile_image_url)')
            .eq('room_id', roomId)
            .eq('role', 'doctor');

        debugPrint('[ChartBoard] fallback chat_room_members rows=${(members as List).length}');
        for (final row in members) {
          debugPrint('[ChartBoard] fallback raw row: $row');
        }

        final fallback = (members as List).map((e) {
          final user = e['users'] as Map<String, dynamic>? ?? {};
          final firstName = user['first_name'] as String? ?? '';
          final lastName = user['last_name'] as String? ?? '';
          final name = '$firstName $lastName'.trim().isEmpty ? 'ผู้ให้คำปรึกษา' : '$firstName $lastName'.trim();
          return {
            'role': e['role'] ?? 'doctor',
            'name': name,
            'status': 'joined',
            'providerId': e['user_id'],
            'isRequired': false,
            'joinedAt': e['joined_at'],
            'providerAvatarUrl': user['profile_image_url'],
            'expertGroupIcon': null,
          };
        }).toList();

        mapped = fallback;
      }

      // Fallback 2: if still empty, use provider_id from consultation_data directly
      if (mapped.isEmpty && _consultationData?['provider_id'] != null) {
        debugPrint('[ChartBoard] chat_room_members also empty — falling back to provider_id from consultation_data');
        final providerId = _consultationData!['provider_id'] as String;
        final user = await Supabase.instance.client
            .from('users')
            .select('first_name, last_name, profile_image_url, profession_id')
            .eq('id', providerId)
            .maybeSingle();

        debugPrint('[ChartBoard] provider query result: $user');

        if (user != null) {
          final firstName = user['first_name'] as String? ?? '';
          final lastName = user['last_name'] as String? ?? '';
          final name = '$firstName $lastName'.trim().isEmpty ? 'ผู้ให้คำปรึกษา' : '$firstName $lastName'.trim();

          // หา profession เพื่อใช้ role ที่ตรงกับ package expert groups
          final professionId = user['profession_id'] as String?;
          String role = 'doctor';
          if (professionId != null && professionId.isNotEmpty) {
            final prof = await ServiceLocator.instance.professionRepository
                .getProfessionById(professionId)
                .catchError((e) => null);
            if (prof != null) {
              final profName = prof.name.toLowerCase();
              if (profName.contains('เภสัช') || profName.contains('pharmacist')) {
                role = 'pharmacist';
              } else if (profName.contains('เฉพาะทาง') || profName.contains('specialist')) {
                role = 'specialist';
              } else if (profName.contains('อาจารย์') || profName.contains('professor')) {
                role = 'professor';
              } else if (profName.contains('หมอ') || profName.contains('แพทย์') || profName.contains('doctor')) {
                role = 'doctor';
              }
            }
          }

          mapped = [{
            'role': role,
            'name': name,
            'status': 'joined',
            'providerId': providerId,
            'isRequired': true,
            'joinedAt': _consultationData!['updated_at'],
            'providerAvatarUrl': user['profile_image_url'],
            'expertGroupIcon': null,
          }];
        }
      }

      // Client-side safety net: ถ้า provider_id ถูก set แล้วแต่ไม่มี expert ไหน joined → force joined
      if (_consultationData?['provider_id'] != null) {
        final providerId = _consultationData!['provider_id'] as String;
        final hasJoined = mapped.any((e) => e['status'] == 'joined');
        if (!hasJoined) {
          debugPrint('[ChartBoard] SAFETY NET: provider_id=$providerId set but no joined expert — forcing joined');
          bool found = false;
          for (final expert in mapped) {
            if (expert['providerId'] == providerId) {
              expert['status'] = 'joined';
              expert['joinedAt'] = _consultationData!['updated_at'] ?? DateTime.now().toIso8601String();
              found = true;
              break;
            }
          }
          if (!found && mapped.isNotEmpty) {
            // ไม่เจอ provider ใน mapped → อัปเดตแถว waiting แรกให้เป็น joined
            mapped.first['status'] = 'joined';
            mapped.first['providerId'] = providerId;
            mapped.first['joinedAt'] = _consultationData!['updated_at'] ?? DateTime.now().toIso8601String();
          }
        }
      }

      // Merge with package expert groups to show waiting groups with grey icons
      final merged = _mergeWithPackageGroups(mapped);
      debugPrint('[ChartBoard] _fetchExpertStatuses merged length=${merged.length} (joined=${mapped.where((e) => e['status'] == 'joined').length}, waiting=${merged.length - mapped.where((e) => e['status'] == 'joined').length})');

      if (mounted) {
        setState(() {
          _expertStatuses = merged;
        });
      }

      // Start timer only when ALL required experts have joined (per improvement plan)
      // ✅ ใช้ _expertStatuses (merged กับ package groups) ไม่ใช่ mapped (raw joined)
      final requiredExperts = _expertStatuses.where((e) => e['isRequired'] == true).toList();
      final allRequiredJoined = requiredExperts.isNotEmpty &&
          requiredExperts.every((e) => e['status'] == 'joined' || e['joinedAt'] != null);
      // Fallback: if no required experts defined yet, start when ANY expert joins
      final anyJoined = _expertStatuses.any((e) => e['status'] == 'joined' || e['joinedAt'] != null);
      final shouldStart = allRequiredJoined || (requiredExperts.isEmpty && anyJoined);
      debugPrint('[ChartBoard] initial fetch _expertStatuses.length=${_expertStatuses.length}, required=${requiredExperts.length}, allRequiredJoined=$allRequiredJoined, anyJoined=$anyJoined, _isTimerRunning=${_timerController.isRunning.value}, remaining=${_timerController.remainingSeconds.value}');
      if (shouldStart && !_timerController.isRunning.value && _timerController.remainingSeconds.value > 0) {
        debugPrint('[ChartBoard] >>> Starting timer from initial fetch (all required joined)');
        _startTimer();
      }
    } catch (e, st) {
      debugPrint('Error fetching expert statuses: $e');
      debugPrint('$st');
    }
  }

  /// Ensure the consultation chat room exists in chat_rooms table
  Future<void> _ensureConsultationRoom(
    String roomId,
    String currentUserId,
    {String? consultationId, String? title}
  ) async {
    try {
      final supabase = Supabase.instance.client;
      // Check if room already exists
      final existing = await supabase
          .from('chat_rooms')
          .select('id, participant_ids, room_type')
          .eq('id', roomId)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));

      if (existing == null) {
        // Create room with the current user's ID as participant
        await supabase
            .from('chat_rooms')
            .insert({
              'id': roomId,
              'participant_ids': [currentUserId],
              'room_type': 'consultation',
              if (consultationId != null) 'consultation_id': consultationId,
              if (title != null && title.isNotEmpty) 'title': title,
              'last_message': null,
              'is_active': true,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .timeout(const Duration(seconds: 5));
        debugPrint('ChartBoardPage: Created consultation room: $roomId');
      } else {
        final participants = List<String>.from(existing['participant_ids'] ?? []);
        var shouldUpdate = false;
        if (!participants.contains(currentUserId)) {
          participants.add(currentUserId);
          shouldUpdate = true;
        }

        final updates = <String, dynamic>{
          'room_type': 'consultation',
          'is_active': true,
          'updated_at': DateTime.now().toIso8601String(),
        };
        if (consultationId != null) updates['consultation_id'] = consultationId;
        if (title != null && title.isNotEmpty) updates['title'] = title;
        if (shouldUpdate) updates['participant_ids'] = participants;

        if (shouldUpdate || (existing['room_type'] ?? existing['roomType']) != 'consultation') {
          await supabase
              .from('chat_rooms')
              .update(updates)
              .eq('id', roomId)
              .timeout(const Duration(seconds: 5));
          debugPrint('ChartBoardPage: Updated consultation room $roomId with participants=$participants');
        } else {
          debugPrint('ChartBoardPage: Room already exists: $roomId');
        }
      }
    } catch (e) {
      debugPrint('ChartBoardPage: Could not ensure room (non-blocking): $e');
      // Non-blocking — messages can still be sent even if room record fails
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });
  }



  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _isSendingNotifier.value) return;

    _isSendingNotifier.value = true;

    final roomId = _consultationRoomId ?? 'consultation_demo';

    final message = ChatMessage(
      id: const Uuid().v4(),
      roomId: roomId,
      senderId: _currentUser?.id ?? 'demo_user',
      content: text,
      createdAt: DateTime.now(),
      type: 'text',
      status: MessageStatus.sent,
    );

    _msgController.clear();
    // Optimistic update — show immediately
    _messagesNotifier.value = [..._messagesNotifier.value, message];
    _scrollToBottom();

    try {
      await _chatRepository.sendMessage(message);
    } catch (e) {
      debugPrint('Send error: $e');
      // Keep message shown even if send fails (offline mode)
    }

    if (mounted) _isSendingNotifier.value = false;
  }

  Future<void> _sendSpecialMessage(String type, String content) async {
    if (_isSendingNotifier.value) return;
    _isSendingNotifier.value = true;

    final roomId = _consultationRoomId ?? 'consultation_demo';
    final message = ChatMessage(
      id: const Uuid().v4(),
      roomId: roomId,
      senderId: _currentUser?.id ?? 'demo_user',
      content: content,
      createdAt: DateTime.now(),
      type: type,
      status: MessageStatus.sent,
    );

    try {
      await _chatRepository.sendMessage(message);
      if (mounted) _messagesNotifier.value = [..._messagesNotifier.value, message];
      _scrollToBottom();
    } catch (e) {
      debugPrint('Special send error: $e');
    }

    if (mounted) _isSendingNotifier.value = false;
  }

  Future<File> _processImagePDPA(File originalFile) async {
    // 1. Detect faces using Google ML Kit
    final inputImage = InputImage.fromFile(originalFile);
    final options = FaceDetectorOptions(
      enableContours: false,
      enableClassification: false,
      performanceMode: FaceDetectorMode.fast,
    );
    final faceDetector = FaceDetector(options: options);
    final faces = await faceDetector.processImage(inputImage);
    faceDetector.close();

    // 2. Load image for Canvas
    final data = await originalFile.readAsBytes();
    final ui.Image image = await decodeImageFromList(data);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawImage(image, Offset.zero, Paint());

    // 3. Blur faces
    final censorPaint = Paint()
      ..color = Colors.grey.shade400.withOpacity(0.95)
      ..style = PaintingStyle.fill;

    // Optional: Add some slight blur to the edges of the censor oval
    final maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    censorPaint.maskFilter = maskFilter;

    for (Face face in faces) {
      final rect = face.boundingBox;
      // Expand the rect slightly to cover the whole head/hair
      final expandedRect = Rect.fromLTRB(
        rect.left - (rect.width * 0.1),
        rect.top - (rect.height * 0.2),
        rect.right + (rect.width * 0.1),
        rect.bottom + (rect.height * 0.1),
      );
      canvas.drawOval(expandedRect, censorPaint);
    }

    // 4. Draw Watermark
    final now = DateTime.now();
    final thaiMonths = [
      'ม.ค.',
      'ก.พ.',
      'มี.ค.',
      'เม.ย.',
      'พ.ค.',
      'มิ.ย.',
      'ก.ค.',
      'ส.ค.',
      'ก.ย.',
      'ต.ค.',
      'พ.ย.',
      'ธ.ค.',
    ];
    final thaiDays = ['อา.', 'จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.'];
    final dayName = thaiDays[now.weekday % 7];
    final day = now.day.toString().padLeft(2, '0');
    final month = thaiMonths[now.month - 1];
    final year = ((now.year + 543) % 100).toString();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final text = ' $dayName.$day.$month$year $timeStr ';

    final fontSize = image.width * 0.04;
    final textStyle = ui.TextStyle(
      color: Colors.white.withOpacity(0.9),
      fontSize: fontSize,
      background: Paint()..color = Colors.black54,
    );
    final paragraphStyle = ui.ParagraphStyle(textAlign: TextAlign.right);
    final paragraphBuilder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(textStyle)
      ..addText(' [Sheserved Private] $text ');
    final paragraph = paragraphBuilder.build()
      ..layout(ui.ParagraphConstraints(width: image.width.toDouble()));

    canvas.drawParagraph(paragraph, Offset(0, image.height - (fontSize * 1.5)));

    // 5. Export from Canvas
    final picture = recorder.endRecording();
    final watermarkedImage = await picture.toImage(image.width, image.height);
    final byteData = await watermarkedImage.toByteData(
      format: ui.ImageByteFormat.png,
    );

    // 6. Compress Image to reduce size
    final tempDir = await getTemporaryDirectory();
    final targetPath =
        '${tempDir.path}/processed_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final compressedBytes = await FlutterImageCompress.compressWithList(
      byteData!.buffer.asUint8List(),
      minWidth: 1080,
      minHeight: 1080,
      quality: 60,
      format: CompressFormat.jpeg,
    );

    final finalFile = File(targetPath);
    await finalFile.writeAsBytes(compressedBytes);

    return finalFile;
  }

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );

    if (image != null && mounted) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('กำลังเบลอใบหน้าและอัปโหลด...'),
            ],
          ),
        ),
      );

      File file = File(image.path);
      try {
        file = await _processImagePDPA(file);
      } catch (e) {
        debugPrint('PDPA process error: $e');
      }

      final roomId = _consultationRoomId ?? 'consultation_demo';
      final url = await _chatRepository.uploadFile(file, 'chat/$roomId');

      if (!mounted) return;
      Navigator.pop(context); // Close dialog

      if (url != null) {
        final message = ChatMessage(
          id: const Uuid().v4(),
          roomId: roomId,
          senderId: _currentUser?.id ?? 'demo_user',
          content: '[รูปภาพ]',
          createdAt: DateTime.now(),
          type: 'image',
          attachmentUrl: url,
          attachmentType: 'image/png',
          status: MessageStatus.sent,
        );
        await _chatRepository.sendMessage(message);
        if (mounted) _messagesNotifier.value = [..._messagesNotifier.value, message];
        _scrollToBottom();
      }
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        final path =
            '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(const RecordConfig(), path: path);
        if (mounted) _isRecordingNotifier.value = true;
      }
    } catch (e) {
      debugPrint('Record start error: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      if (mounted) _isRecordingNotifier.value = false;

      if (path != null && _currentUser != null) {
        final file = File(path);
        final roomId = _consultationRoomId ?? 'consultation_demo';
        final url = await _chatRepository.uploadFile(file, 'chat/$roomId');

        if (url != null) {
          final message = ChatMessage(
            id: const Uuid().v4(),
            roomId: roomId,
            senderId: _currentUser!.id,
            content: '[ข้อความเสียง]',
            createdAt: DateTime.now(),
            type: 'voice',
            attachmentUrl: url,
            status: MessageStatus.sent,
          );
          await _chatRepository.sendMessage(message);
          if (mounted) _messagesNotifier.value = [..._messagesNotifier.value, message];
          _scrollToBottom();
        }
      }
    } catch (e) {
      debugPrint('Record stop error: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadProfessions();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _professionsRefreshController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _msgController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    _messagesSub?.cancel();
    _expertStatusSub?.cancel();
    _roomSub?.cancel();
    _consultationSub?.cancel();
    disposeHealthPermission();
    _messagesNotifier.dispose();
    _isChatLoadingNotifier.dispose();
    _isRecordingNotifier.dispose();
    _isSendingNotifier.dispose();
    _timerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasSubmitted,
      onPopInvokedWithResult: (didPop, result) {
        if (_hasSubmitted && !didPop) {
          // ผู้ป่วยกด "ยืนยันและส่งคำรักษา" แล้ว → back ไปหน้า profile/history
          // แทนที่จะ pop กลับไปหน้า analyze-body
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/profile',
            (route) => route.isFirst,
            arguments: {'tabIndex': 2}, // แถบ "ประวัติปรึกษา" (สำหรับ consumer ทั่วไป)
          );
        }
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFE8F5DA), Color(0xFFF5FAF0), Color(0xFFFFFFFF)],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            titleSpacing: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A4D10), size: 20),
              onPressed: () {
                if (_hasSubmitted) {
                  // หลังส่งคำรักษาแล้ว → ไปหน้า profile/history แทน analyze-body
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/profile',
                    (route) => route.isFirst,
                    arguments: {'tabIndex': 2},
                  );
                } else {
                  Navigator.pop(context);
                }
              },
            ),
          title: Row(
            children: [
              Flexible(child: FittedBox(child: _buildTimerBadge())),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.entry?.patientName ?? "ปรึกษาผู้เชี่ยวชาญ",
                      style: const TextStyle(
                        color: Color(0xFF1A4D10),
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      widget.readOnly
                          ? 'ห้องปรึกษา (โหมดดูอย่างเดียว)'
                          : (_isProvider
                              ? "ห้องปรึกษา (มุมมองแพทย์)"
                              : "กลุ่มผู้เชี่ยวชาญที่เข้าร่วม"),
                      style: TextStyle(
                        color: widget.readOnly
                            ? Colors.grey.shade600
                            : Colors.grey.shade500,
                        fontSize: 10,
                        fontWeight: widget.readOnly ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            _buildActionButtons(),
          ],
        ),
        body: Column(
          children: [
            // Health Data Permission Status Banner — Doctor side only (ซ่อนในโหมดดูอย่างเดียว)
            if (_isProvider && !widget.readOnly && permissionRequest != null)
              HealthPermissionStatusBanner(
                request: permissionRequest!,
                onViewData: openGrantedDataSheet,
              ),
            ExpertStatusBanner(
              expertStatuses: _expertStatuses,
              professions: _professions,
            ),
            _buildBodyMapSummary(),
            // Pain level selector for patients before payment/activation
            if (!_isProvider && !_hasSubmitted && (_consultationData?['status'] ?? 'pending') == 'pending')
              PainLevelSelector(
                selectedPain: _selectedPain,
                onSelected: (pain) => setState(() => _selectedPain = pain),
              ),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF9FBF8),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                ),
                child: _buildMessagesList(),
              ),
            ),
            // Payment card for patients before payment/activation
            if (!_isProvider && !_hasSubmitted && (_consultationData?['status'] ?? 'pending') == 'pending')
              PaymentCard(
                isReady: _selectedPain != null,
                price: (widget.entry?.price ?? widget.request?.price ?? 0).toInt(),
                onSubmit: _submitConsultationRequest,
              ),
            _buildChatInput(),
          ],
        ),
      ),
    ),
    ),
    );
  }

  void _showFinishDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการจบงาน'),
        content: const Text('คุณได้ให้คำแนะนำครบถ้วนแล้วใช่หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // Logic to finish job
              final consultationId = widget.entry?.id;
              if (consultationId != null) {
                final repo = ServiceLocator.instance.consultationRepository;
                await repo.updateStatus(consultationId, 'completed');
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    return AnimatedBuilder(
      animation: Listenable.merge([_messagesNotifier, _isChatLoadingNotifier]),
      builder: (context, child) {
        if (_isChatLoadingNotifier.value) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  strokeWidth: 2,
                ),
                const SizedBox(height: 12),
                Text(
                  'กำลังเชื่อมต่อห้องแชท...',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
            ),
          );
        }

        final messages = _messagesNotifier.value;
        return FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                if (messages.isEmpty) return const SizedBox.shrink();
                final msg = messages[index];
                final isMe = msg.senderId == (_currentUser?.id ?? 'demo_user');
                return MessageBubble(
                  message: msg,
                  isMe: isMe,
                  onViewPrescription: () => _viewPrescriptionDetails(msg.attachmentUrl),
                  onViewSummary: () => _viewSummaryDetails(msg.attachmentUrl),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildChatInput() {
    final status = _consultationData?['status'] as String? ?? 'pending';
    final isChatActive = _isProvider || _hasSubmitted || status == 'in_progress';
    debugPrint('[ChartBoard] _buildChatInput: _isProvider=$_isProvider status=$status isChatActive=$isChatActive _consultationData=$_consultationData');
    return ChatInputBarWidget(
      controller: _msgController,
      isProvider: _isProvider,
      isChatActive: isChatActive,
      isSending: _isSendingNotifier,
      isRecording: _isRecordingNotifier,
      readOnly: widget.readOnly,
      onSend: _sendMessage,
      onStartRecording: _startRecording,
      onStopRecording: _stopRecording,
      onPickImage: _pickAndSendImage,
      onShowAttachmentMenu: _showAttachmentMenu,
      onTextChanged: (_) => setState(() {}),
    );
  }

  void _submitConsultationRequest() async {
    if (_selectedPain == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณาระบุระดับความรู้สึกเจ็บปวดก่อนครับ'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    try {
      final currentUserId = _currentUser?.id;
      if (currentUserId == null) {
        throw Exception('กรุณาเลือกเข้าสู่ระบบใหม่อีกครั้ง');
      }

      // 1. Prepare final data
      final finalSymptomsChart = Map<String, dynamic>.from(
        widget.entry?.symptomsChart ?? widget.request?.symptomsChart ?? {},
      );
      finalSymptomsChart['pain_level'] = _selectedPain;

      // 2. Save to Repository
      final repo = ServiceLocator.instance.consultationRepository;
      String consultationId;

      if (widget.entry != null) {
        // Update existing consultation + mark as active/confirmed
        consultationId = widget.entry!.id;
        await repo.updateRequest(consultationId, {
          'symptoms_chart': finalSymptomsChart,
          'status': 'in_progress',
        });
      } else if (widget.request != null) {
        // Create new consultation request (provider should see it as pending)
        debugPrint(
          'ChartBoard: creating consultation request packageId=${widget.request!.packageId}, packageName=${widget.request!.packageName}, status=pending',
        );
        final newRequest = await repo.createRequest(
          userId: currentUserId,
          packageId: widget.request!.packageId,
          packageName: widget.request!.packageName,
          price: widget.request!.price ?? 0,
          bodyArea: widget.request!.bodyArea ?? {},
          symptomsChart: finalSymptomsChart,
          symptoms: widget.request!.symptoms ?? [],
          status: 'pending',
        );
        consultationId = newRequest.id;
      } else {
        throw Exception('ไม่พบข้อมูลคำปรึกษา กรุณาลองใหม่อีกครั้ง');
      }

      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ส่งคำปรึกษาสำเร็จ! กรุณารอผู้เชี่ยวชาญเข้าห้องแชทครับ',
            ),
            backgroundColor: Color(0xFF4A8B2C),
          ),
        );
        
        // Transition to Chat Mode
        setState(() {
          _activeConsultationId = consultationId;
          _isConsultationActive = true;
          _isHeaderExpanded = false;
          _hasSubmitted = true; // ป้องกันกลับไปหน้า analyze-body → back ไป profile/history
          // Update local _consultationData immediately so UI unlocks without
          // waiting for _initChat async re-fetch (avoids stale-data flicker).
          if (_consultationData != null) {
            _consultationData!['status'] = 'in_progress';
          } else {
            _consultationData = <String, dynamic>{
              'id': consultationId,
              'status': 'in_progress',
            };
          }
        });
        
        // Re-init chat to ensure room is fully synced
        _initChat();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _viewPrescriptionDetails(String? prescriptionId) {
    if (prescriptionId == null) return;
    final consultationId = widget.entry?.id ?? widget.request?.id ?? '';
    final patientId = widget.entry?.patientId ?? widget.request?.userId ?? '';
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => PrescriptionEditorPage(
          consultationId: consultationId,
          patientId: patientId,
        ),
      ),
    );
  }

  void _viewSummaryDetails(String? noteId) {
    if (noteId == null) return;
    final consultationId = widget.entry?.id ?? widget.request?.id ?? '';
    final patientId = widget.entry?.patientId ?? widget.request?.userId ?? '';
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => ConsultationNoteEditorPage(
          consultationId: consultationId,
          patientId: patientId,
        ),
      ),
    );
  }

  bool _hasAllRequiredExpertsJoined() {
    // Check if ALL required experts have joined (per improvement plan)
    final requiredExperts = _expertStatuses.where((e) => e['isRequired'] == true).toList();
    if (requiredExperts.isNotEmpty) {
      return requiredExperts.every((e) => e['status'] == 'joined' || e['joinedAt'] != null);
    }
    // Fallback: if no required experts defined, check if ANY expert joined
    final anyJoined = _expertStatuses.any(
      (e) => e['status'] == 'joined' || e['joinedAt'] != null,
    );
    return anyJoined;
  }

  Widget _buildTimerBadge() {
    return TimerBadgeWidget(
      remainingSeconds: _timerController.remainingSeconds,
      isTimerRunning: _timerController.isRunning,
      allRequiredJoined: _hasAllRequiredExpertsJoined(),
      formatTimer: formatTimer,
    );
  }

  Widget _buildActionButtons() {
    return ActionButtonsWidget(
      isProvider: _isProvider,
      readOnly: widget.readOnly,
      onFinishPressed: _showFinishDialog,
      onVideoCallPressed: _startVideoCall,
      onInfoPressed: _showConsultationDetails,
    );
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Wrap(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Text(
                  'เครื่องมือเพิ่มเติม',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  child: const Icon(Icons.image_outlined, color: AppColors.primary),
                ),
                title: const Text('ส่งรูปภาพ'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendImage();
                },
              ),
              if (_isProvider) ...[
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    child: const Icon(Icons.medication_outlined, color: AppColors.primary),
                  ),
                  title: const Text('ออกใบสั่งยา'),
                  onTap: () {
                    Navigator.pop(ctx);
                    final consultationId = widget.entry?.id ?? widget.request?.id ?? '';
                    final patientId = widget.entry?.patientId ?? widget.request?.userId ?? '';
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => PrescriptionEditorPage(
                          consultationId: consultationId,
                          patientId: patientId,
                        ),
                      ),
                    );
                  },
                ),
                    // Health Data Permission Request (added to attachment menu)
    ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withOpacity(0.1),
        child: const Icon(Icons.lock_open, color: AppColors.primary),
      ),
      title: const Text('ขอสิทธิ์ดูข้อมูลสุขภาพ'),
      onTap: () {
        Navigator.pop(ctx);
        requestPermission();
      },
    ),
    // Existing items continue below

              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }



  void _startVideoCall() {
    final roomId = widget.entry?.roomId ?? 'consult_${widget.request?.id}';
    Navigator.pushNamed(
      context,
      '/live-vdo',
      arguments: {
        'roomId': roomId,
        'isCaller': true,
        'otherParticipantName': widget.entry?.patientName ?? 'Patient',
      },
    );
  }

  void _showConsultationDetails() {
    // Show a bottom sheet with patient details and symptoms
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildDetailsSheet(),
    );
  }

  Widget _buildDetailsSheet() {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'รายละเอียดการปรึกษา',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildDetailRow('ผู้ป่วย', widget.entry?.patientName ?? 'ไม่ระบุ'),
          _buildDetailRow('แพ็คเกจ', widget.entry?.packageName ?? widget.request?.packageName ?? 'ไม่ระบุ'),
          _buildDetailRow(
            'อาการเบื้องต้น',
            resolveBodyAreaText(
              requestSymptoms: widget.request?.symptoms,
              requestBodyArea: widget.request?.bodyArea,
              requestSymptomsChart: widget.request?.symptomsChart,
              entryBodyArea: widget.entry?.bodyArea,
              entrySymptomsChart: widget.entry?.symptomsChart,
              consultDataSymptoms: _consultationData?['symptoms'],
              consultDataBodyArea: _consultationData?['body_area'],
              consultDataSymptomsChart: _consultationData?['symptoms_chart'],
            ),
          ),
          const Divider(height: 32),
          const Text(
            'จุดที่พบอาการ (Body Map)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _buildSymptomsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSymptomsList() {
    // In production, fetch this from the consultation entry/request
    return ListView.builder(
      itemCount: 1, // Mock
      itemBuilder: (ctx, i) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.location_on, color: Colors.orange),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                resolveBodyAreaText(
                  requestSymptoms: widget.request?.symptoms,
                  requestBodyArea: widget.request?.bodyArea,
                  requestSymptomsChart: widget.request?.symptomsChart,
                  entryBodyArea: widget.entry?.bodyArea,
                  entrySymptomsChart: widget.entry?.symptomsChart,
                  consultDataSymptoms: _consultationData?['symptoms'],
                  consultDataBodyArea: _consultationData?['body_area'],
                  consultDataSymptomsChart: _consultationData?['symptoms_chart'],
                ),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Merge joined experts with package expert groups to show waiting groups too
  List<Map<String, dynamic>> _mergeWithPackageGroups(
    List<Map<String, dynamic>> joinedExperts,
  ) {
    final package = _selectedPackage;
    debugPrint('[ChartBoard] _mergeWithPackageGroups: joined=${joinedExperts.length}, package=${package?.name}, expertGroups=${package?.expertGroups.length}');
    if (package == null || package.expertGroups.isEmpty) {
      debugPrint('[ChartBoard] _mergeWithPackageGroups: SKIP (no package or no groups)');
      return joinedExperts;
    }

    final merged = <Map<String, dynamic>>[...joinedExperts];

    for (final group in package.expertGroups) {
      // Find the corresponding profession for this group to get its legacy role mappings if any
      final prof = findProfessionByNameOrRole(_professions, group.name, group.role);
      
      final groupRoleLower = group.role.toLowerCase();
      final groupNameLower = group.name.toLowerCase();
      
      final targetRoles = <String>{
        groupRoleLower,
        if (prof != null) prof.id.toLowerCase(),
        if (prof != null) prof.name.toLowerCase(),
      };
      
      if (groupNameLower.contains('เภสัช')) {
        targetRoles.add('pharmacist');
      } else if (groupNameLower.contains('เฉพาะทาง')) {
        targetRoles.add('specialist');
      } else if (groupNameLower.contains('อาจารย์')) {
        targetRoles.add('professor');
      } else if (groupNameLower.contains('หมอ') || groupNameLower.contains('แพทย์')) {
        targetRoles.add('doctor');
      }
      
      bool alreadyJoined = false;
      for (var i = 0; i < merged.length; i++) {
        final expert = merged[i];
        if (expert['status'] == 'waiting') continue; // only check joined experts

        final expertRole = (expert['role'] as String? ?? '').toLowerCase();
        final expertName = (expert['name'] as String? ?? '').toLowerCase();
        
        if (targetRoles.contains(expertRole) || expertName == groupNameLower) {
          alreadyJoined = true;
          
          // Sync UI properties from the group to the joined expert
          expert['isRequired'] = expert['isRequired'] == true || group.isRequired;
          expert['expertGroupIcon'] ??= prof?.iconName ?? group.icon ?? iconNameFromRole(group.role);
          expert['professionColorHex'] ??= prof?.colorHex;
          expert['expertGroupName'] ??= group.name;
        }
      }

      if (!alreadyJoined) {
        final iconName = prof?.iconName ?? group.icon ?? iconNameFromRole(group.role);
        merged.add({
          'role': group.role,
          'name': group.name,
          'status': 'waiting',
          'providerId': null,
          'isRequired': group.isRequired,
          'joinedAt': null,
          'providerAvatarUrl': null,
          'expertGroupIcon': iconName,
          'professionColorHex': prof?.colorHex,
        });
      }
    }

    debugPrint('[ChartBoard] _mergeWithPackageGroups: merged=${merged.length} (added ${merged.length - joinedExperts.length} waiting groups)');
    return merged;
  }

  Widget _buildBodyMapSummary() {
    return BodyMapSummaryWidget(
      bodyAreaText: resolveBodyAreaText(
        requestSymptoms: widget.request?.symptoms,
        requestBodyArea: widget.request?.bodyArea,
        requestSymptomsChart: widget.request?.symptomsChart,
        entryBodyArea: widget.entry?.bodyArea,
        entrySymptomsChart: widget.entry?.symptomsChart,
        consultDataSymptoms: _consultationData?['symptoms'],
        consultDataBodyArea: _consultationData?['body_area'],
        consultDataSymptomsChart: _consultationData?['symptoms_chart'],
      ),
    );
  }

}
