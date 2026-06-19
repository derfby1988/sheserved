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
import '../../../../features/auth/data/repositories/user_repository.dart';
import '../../data/models/consultation_request_model.dart';
import '../../data/models/consultation_entry.dart';
import '../../../../features/chat/data/models/chat_models.dart';
import '../../data/models/consultation_package.dart';
import '../widgets/package_wheel_selector.dart';
import '../../../../features/admin/models/profession.dart';
import 'prescription_editor_page.dart';
import 'prescription_choice_page.dart';
import 'consultation_note_editor_page.dart';
import 'manage_quick_replies_page.dart';
import '../widgets/timer_badge_widget.dart';
import '../widgets/body_map_summary_widget.dart';
import '../widgets/action_buttons_widget.dart';
import '../widgets/chat_input_bar_widget.dart';
import '../widgets/mini_voice_player.dart';
import '../controllers/session_timer_controller.dart';
import '../controllers/professions_refresh_controller.dart';
import '../controllers/body_map_chat_controller.dart';
import '../utils/timer_formatter.dart';
import '../utils/chart_metric_helpers.dart';
import '../utils/body_area_formatter.dart';
import '../utils/expert_status_helpers.dart';
import '../mixins/health_permission_mixin.dart';
import '../widgets/health_data/expert_status_banner.dart';
import '../widgets/health_data/health_permission_status_banner.dart';
import '../widgets/health_data/pain_level_selector.dart';
import '../widgets/health_data/payment_card.dart';
import '../widgets/health_data/body_map_chat_bar.dart';
import '../widgets/health_data/prescription_card.dart';
import '../widgets/health_data/summary_card.dart';
import '../widgets/health_data/message_bubble.dart';
import '../widgets/health_data/health_data_error_view.dart';
import '../widgets/health_data/granted_health_sections.dart';
import '../../data/models/expert_completion_status.dart';
import '../../data/models/profession_package_rule.dart';
import '../widgets/completion_checklist.dart';
import '../widgets/finish_job_warning_dialog.dart';

class ChartBoardPage extends StatefulWidget {
  final ConsultationRequestModel? request;
  final ConsultationEntry? entry; // For active consultations
  final bool readOnly; // true = ดูอย่างเดียว ไม่สามารถดำเนินการได้
  final bool hasFinished; // true = provider จบงานแล้ว แต่ consultation ยังไม่ปิด

  const ChartBoardPage({
    super.key,
    this.request,
    this.entry,
    this.readOnly = false,
    this.hasFinished = false,
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
  bool _hasFinished = false; // true = provider จบงานแล้ว (multi-expert tracking)

  StreamSubscription? _messagesSub;
  List<ConsultationPackage> _availablePackages = [];
  ConsultationPackage? _selectedPackage;
  bool _isLoadingPackages = false;

  // --- Session Timer Features ---
  late final SessionTimerController _timerController;
  bool _hasReviewed = false;

  // --- Expert Status ---
  List<Map<String, dynamic>> _expertStatuses = [];
  int _expertStatusesFetchToken = 0;
  StreamSubscription? _expertStatusSub;
  StreamSubscription? _expertAvailabilitySub;
  Map<String, dynamic> _completionStatus = {};
  bool _isCheckingCompletion = false;

  // --- Professions (for accurate icons/colors from admin settings) ---
  List<Profession> _professions = [];
  late final ProfessionsRefreshController _professionsRefreshController;
  Map<String, dynamic>? _consultationData;

  // Phase 6.8: Expert completion rules status
  ExpertCompletionStatus? _expertCompletionStatus;
  ProfessionPackageRule? _professionPackageRule;
  bool _isCheckingExpertCompletion = false;

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

  // --- BodyMap Chat Selector (Phase 6.6) ---
  late final BodyMapChatController _bodyMapChatController;

  // --- Required Questions (Phase 6.7) ---
  List<ChatMessage> _requiredQuestions = [];
  ChatMessage? _activeRequiredQuestion;
  bool _showRequiredOverlay = false;
  final TextEditingController _requiredAnswerController = TextEditingController();
  final FocusNode _requiredAnswerFocus = FocusNode();
  Timer? _typingTimer;
  DateTime? _lastTypingTime;
  DateTime? _lastManualCloseTime;
  bool _isBlocked = false;
  ScrollController? _floatingButtonsScrollController;

  // Expert-side required question state
  bool _isRequiredToggle = false;
  String? _editingQuestionId;

  // Keyboard visibility for hiding banners
  bool _isKeyboardVisible = false;

  @override
  void initState() {
    super.initState();
    _bodyMapChatController = BodyMapChatController(msgController: _msgController);
    // Robust provider check (matches Dashboard logic)
    final professionId = _currentUser?.professionId;
    _isProvider = professionId != null && 
                  professionId != '00000000-0000-0000-0000-000000000001';

    // Auto-detect initial state
    // NOTE: Don't set _isConsultationActive here — let _initChat determine
    // from real payment_status to avoid hiding the pain selector prematurely.
    _hasFinished = widget.hasFinished;
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

    // Scroll controller for floating buttons (horizontal scroll + scrollbar)
    _floatingButtonsScrollController = ScrollController();

    // Listen for messages to detect required questions
    _messagesNotifier.addListener(_onMessagesChanged);

    // Track typing to delay block UI
    _msgController.addListener(_onPatientTyping);

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
    _loadCompletionStatus();
    if (_isProvider) _loadExpertCompletionStatus();
    _loadPackages();
    _loadProfessions();
    _professionsRefreshController = ProfessionsRefreshController(onRefresh: _loadProfessions);
    _professionsRefreshController.start();
    WidgetsBinding.instance.addObserver(this);
    // Detect initial keyboard state
    _isKeyboardVisible = WidgetsBinding.instance.window.viewInsets.bottom > 0;
    initHealthPermission();
  }

  void _startTimer() {
    debugPrint('[ChartBoard] _startTimer called, _isTimerRunning=${_timerController.isRunning.value}, remaining=${_timerController.remainingSeconds.value}');
    _timerController.start();
  }

  /// โหลดสถานะการเสร็จงานของ experts ทั้งหมดใน consultation นี้
  Future<void> _loadCompletionStatus() async {
    final consultationId = widget.entry?.id ?? widget.request?.id ?? _activeConsultationId;
    if (consultationId == null || consultationId.isEmpty) return;

    setState(() => _isCheckingCompletion = true);
    try {
      final repo = ServiceLocator.instance.consultationRepository;
      final status = await repo.getExpertCompletionStatus(consultationId);
      final currentUserId = _currentUser?.id;
      final experts = (status['experts'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final hasCurrentUserFinished = currentUserId != null && experts.any((expert) {
        return expert['provider_id']?.toString() == currentUserId &&
            expert['is_finished'] == true;
      });

      if (mounted) {
        setState(() {
          _completionStatus = status;
          _hasFinished = widget.hasFinished || _hasFinished || hasCurrentUserFinished;
          _isCheckingCompletion = false;
        });
      }
    } catch (e) {
      debugPrint('ChartBoard: _loadCompletionStatus error: $e');
      if (mounted) setState(() => _isCheckingCompletion = false);
    }
  }

  /// Phase 6.8: โหลดสถานะการทำงานของ expert (completion rules)
  Future<void> _loadExpertCompletionStatus() async {
    final consultationId = widget.entry?.id ?? widget.request?.id;
    if (consultationId == null || consultationId.isEmpty) return;
    final authUser = _currentUser;
    if (authUser == null) return;

    final packageId = _canonicalPackageId();
    final professionId = authUser.professionId;

    setState(() => _isCheckingExpertCompletion = true);
    try {
      final repo = ServiceLocator.instance.consultationRepository;
      final result = await repo.getMyCompletionStatus(consultationId, authUser.id);

      // Load profession package rules to know which conditions are actually required
      ProfessionPackageRule? rule;
      if (packageId != null && packageId.isNotEmpty && professionId != null && professionId.isNotEmpty) {
        try {
          rule = await repo.getProfessionPackageRules(packageId, professionId);
        } catch (e) {
          // Silently ignore - checklist will show all items as fallback
        }
      }

      if (mounted) {
        setState(() {
          _expertCompletionStatus = ExpertCompletionStatus.fromJson(result);
          _professionPackageRule = rule;
          _isCheckingExpertCompletion = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isCheckingExpertCompletion = false);
    }
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
          _applyExpertStatuses(merged, source: 'loadPackages');
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

      if (mounted && _selectedPackage != null && _expertStatuses.isNotEmpty) {
        final joinedExperts = _expertStatuses.where((e) => e['status'] == 'joined').toList();
        final merged = _mergeWithPackageGroups(joinedExperts);
        _applyExpertStatuses(merged, source: 'loadProfessions');
      }
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

  Future<void> _ensureSelectedPackageForMerge() async {
    if (_selectedPackage != null && _selectedPackage!.expertGroups.isNotEmpty) {
      return;
    }

    final packageId = _canonicalPackageId();
    if (packageId == null || packageId.isEmpty) {
      return;
    }

    try {
      final packageResponse = await Supabase.instance.client
          .from('consultation_packages')
          .select()
          .eq('id', packageId)
          .maybeSingle();

      if (packageResponse == null) {
        debugPrint('[ChartBoard] _ensureSelectedPackageForMerge: packageId=$packageId not found');
        return;
      }

      final fallbackPackage = ConsultationPackage.fromJson(Map<String, dynamic>.from(packageResponse));
      if (mounted) {
        setState(() {
          _selectedPackage = fallbackPackage;
        });
      } else {
        _selectedPackage = fallbackPackage;
      }
      debugPrint('[ChartBoard] _ensureSelectedPackageForMerge: loaded package fallback => ${fallbackPackage.name} ($packageId)');
    } catch (e) {
      debugPrint('[ChartBoard] _ensureSelectedPackageForMerge error: $e');
    }
  }

  bool _hasProviderId(Map<String, dynamic> expert) {
    final providerId = expert['providerId']?.toString().trim();
    return providerId != null && providerId.isNotEmpty;
  }

  bool _canApplyExpertStatuses(List<Map<String, dynamic>> nextStatuses) {
    if (_expertStatuses.isEmpty) return true;

    final currentProviderIds = _expertStatuses
        .where(_hasProviderId)
        .map((e) => e['providerId'].toString())
        .toSet();
    if (currentProviderIds.isEmpty) return true;

    final nextProviderIds = nextStatuses
        .where(_hasProviderId)
        .map((e) => e['providerId'].toString())
        .toSet();

    if (nextProviderIds.isEmpty) {
      debugPrint('[ChartBoard] _canApplyExpertStatuses: skip empty/providerless payload because current providers exist=$currentProviderIds');
      return false;
    }

    final missingCurrentProviders = currentProviderIds.difference(nextProviderIds);
    if (missingCurrentProviders.isNotEmpty) {
      final nextHasJoined = nextStatuses.any((e) => e['status'] == 'joined');
      if (!nextHasJoined) {
        debugPrint('[ChartBoard] _canApplyExpertStatuses: skip payload missing current providers=$missingCurrentProviders');
        return false;
      }
    }

    return true;
  }

  void _applyExpertStatuses(List<Map<String, dynamic>> nextStatuses, {required String source, int? token}) {
    if (token != null && token != _expertStatusesFetchToken) {
      debugPrint('[ChartBoard] _applyExpertStatuses($source): skip stale token=$token current=$_expertStatusesFetchToken');
      return;
    }
    if (!mounted) return;
    if (!_canApplyExpertStatuses(nextStatuses)) return;

    setState(() {
      _expertStatuses = nextStatuses;
    });
    debugPrint('[ChartBoard] _applyExpertStatuses($source): applied ${nextStatuses.length} rows');
  }

  String _normalizeConsultationRole(String? raw) {
    final value = (raw ?? '').toLowerCase().trim();
    if (value.isEmpty) return '';
    if (value.contains('professor') || value.contains('อาจารย์')) return 'professor';
    if (value.contains('specialist') || value.contains('เฉพาะทาง')) return 'specialist';
    if (value.contains('pharmacist') || value.contains('เภสัช')) return 'pharmacist';
    if (value.contains('nurse') || value.contains('พยาบาล')) return 'nurse';
    if (value == Profession.doctorGpProfessionId ||
        value == Profession.doctorFamilyProfessionId ||
        value == 'doctor_gp' ||
        value == 'doctor_family') {
      return 'doctor';
    }
    if (value == Profession.doctorSpecialistProfessionId || value == 'doctor_specialist') {
      return 'specialist';
    }
    if (value == Profession.pharmacistProfessionId || value == 'pharmacist') {
      return 'pharmacist';
    }
    if (value.contains('doctor') || value.contains('แพทย์') || value == 'หมอ') return 'doctor';
    return value;
  }

  String _consultationMatchKey(String? name, String? role) {
    final prof = findProfessionByNameOrRole(_professions, name, role);
    if (prof != null) {
      return 'profession:${prof.id.toLowerCase().trim()}';
    }

    final normalizedRole = _normalizeConsultationRole(role);
    if (normalizedRole.isNotEmpty) {
      return 'role:$normalizedRole';
    }

    final normalizedName = (name ?? '').toLowerCase().trim();
    if (normalizedName.isNotEmpty) {
      return 'name:$normalizedName';
    }

    return '';
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
              final oldStatus = _consultationData?['status'] as String? ?? 'pending';
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
          .listen((data) async {
            if (!mounted) return;

            final joined = data.map((e) {
              final user = e['users'] as Map<String, dynamic>? ?? {};
              return {
                'role': e['expert_group_role'],
                'name': e['expert_group_name'],
                'status': e['status'],
                'providerId': e['provider_id'],
                'isRequired': e['is_required'] as bool? ?? false,
                'joinedAt': e['joined_at'],
                'leftAt': e['left_at'],
                'finishedAt': e['finished_at'],
                'providerAvatarUrl': e['provider_avatar_url'] ?? e['provider_image_url'] ?? e['avatar_url'] ?? e['profile_image_url'] ?? user['profile_image_url'],
                'expertGroupIcon': e['expert_group_icon'] ?? e['category_icon'] ?? e['group_icon'] ?? e['icon'],
                'availabilityStatus': user['availability_status'] as String? ?? 'offline',
              };
            }).toList();

            await _ensureSelectedPackageForMerge();
            if (!mounted) return;

            // Merge with package groups to show waiting groups too
            final merged = _mergeWithPackageGroups(joined);
            _applyExpertStatuses(merged, source: 'realtime_stream');

            // Sync _hasFinished if current user's finished_at changed in the stream
            final currentUserId = _currentUser?.id;
            if (currentUserId != null) {
              bool isFinishedInStream = false;
              for (final e in joined) {
                if (e['providerId']?.toString() == currentUserId && e['finishedAt'] != null) {
                  isFinishedInStream = true;
                  break;
                }
              }
              if (isFinishedInStream != _hasFinished) {
                await _loadCompletionStatus();
              }
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

      // 3.5 Subscribe to Users availability_status changes for joined experts
      _expertAvailabilitySub = supabase
          .from('users')
          .stream(primaryKey: ['id'])
          .listen((userChanges) {
            debugPrint('[ChartBoard] users stream triggered: ${userChanges.length} changes');
            final joinedProviderIds = _expertStatuses
                .where((e) => e['status'] == 'joined' && e['providerId'] != null)
                .map((e) => e['providerId'] as String)
                .toSet();
            if (joinedProviderIds.isEmpty) return;
            
            bool shouldRefresh = false;
            for (final change in userChanges) {
              final changedUserId = change['id'] as String?;
              if (changedUserId != null && joinedProviderIds.contains(changedUserId)) {
                shouldRefresh = true;
                break;
              }
            }
            if (shouldRefresh && consultationId != null) {
              debugPrint('[ChartBoard] Provider availability changed → re-fetching expert statuses');
              _fetchExpertStatuses(consultationId);
            }
          });

      // 4. Load Messages
      final messages = await _chatRepository.getMessages(roomId);

      if (mounted) {
        _messagesNotifier.value = messages;
        _isChatLoadingNotifier.value = false;

        // Load body part message counts (Phase 6.6)
        await _bodyMapChatController.loadMessageCounts(
          roomId: roomId,
          currentUserId: currentUserId,
        );

        // Subscribe to messages
        _messagesSub = _chatRepository.streamMessages(roomId).listen((updatedMessages) {
          if (mounted) {
            _messagesNotifier.value = updatedMessages;
            _scrollToBottom();
            // Refresh body part counts on new messages (Phase 6.6)
            _bodyMapChatController.loadMessageCounts(
              roomId: roomId,
              currentUserId: currentUserId,
            );
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
    final fetchToken = ++_expertStatusesFetchToken;
    try {
      debugPrint('[ChartBoard] _fetchExpertStatuses START for consultationId=$consultationId');
      final data = await Supabase.instance.client
          .from('consultation_room_experts')
          .select('*, users!inner(availability_status, first_name, last_name, profile_image_url)')
          .eq('consultation_id', consultationId);

      debugPrint('[ChartBoard] _fetchExpertStatuses rows=${(data as List).length}');
      for (final row in data) {
        debugPrint('[ChartBoard] expert raw row: $row');
      }

      final userData = (data as List).map((e) {
        final user = e['users'] as Map<String, dynamic>? ?? {};
        return {
          'role': e['expert_group_role'],
          'name': e['expert_group_name'],
          'status': e['status'],
          'providerId': e['provider_id'],
          'isRequired': e['is_required'] as bool? ?? false,
          'joinedAt': e['joined_at'],
          'leftAt': e['left_at'],
          'finishedAt': e['finished_at'],
          'providerAvatarUrl': e['provider_avatar_url'] ?? e['provider_image_url'] ?? e['avatar_url'] ?? e['profile_image_url'] ?? user['profile_image_url'],
          'expertGroupIcon': e['expert_group_icon'] ?? e['category_icon'] ?? e['group_icon'] ?? e['icon'],
          'availabilityStatus': user['availability_status'] as String? ?? 'offline',
        };
      }).toList();

      List<Map<String, dynamic>> mapped = List.from(userData);

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
          mapped = (refreshed as List).map((e) {
            final user = e['users'] as Map<String, dynamic>? ?? {};
            return {
              'role': e['expert_group_role'],
              'name': e['expert_group_name'],
              'status': e['status'],
              'providerId': e['provider_id'],
              'isRequired': e['is_required'] as bool? ?? false,
              'joinedAt': e['joined_at'],
              'leftAt': e['left_at'],
              'finishedAt': e['finished_at'],
              'providerAvatarUrl': e['provider_avatar_url'] ?? e['provider_image_url'] ?? e['avatar_url'] ?? e['profile_image_url'] ?? user['profile_image_url'],
              'expertGroupIcon': e['expert_group_icon'] ?? e['category_icon'] ?? e['group_icon'] ?? e['icon'],
              'availabilityStatus': user['availability_status'] as String? ?? 'offline',
            };
          }).toList();
        }

        // If still empty, provider may be assigned in consultation_data but not synced to room_experts (legacy consultation)
        if (mapped.isEmpty && _consultationData?['provider_id'] != null) {
          final providerId = _consultationData!['provider_id'] as String;
          debugPrint('[ChartBoard] consultation_room_experts still empty after ensure — calling syncProviderToRoomExperts for provider=$providerId');
          await repo.syncProviderToRoomExperts(
            consultationId: consultationId,
            providerId: providerId,
          );
          // Re-query after sync
          final synced = await Supabase.instance.client
              .from('consultation_room_experts')
              .select()
              .eq('consultation_id', consultationId);
          if ((synced as List).isNotEmpty) {
            debugPrint('[ChartBoard] syncProviderToRoomExperts succeeded, re-query got ${synced.length} rows');
            mapped = (synced as List).map((e) {
              final user = e['users'] as Map<String, dynamic>? ?? {};
              return {
                'role': e['expert_group_role'],
                'name': e['expert_group_name'],
                'status': e['status'],
                'providerId': e['provider_id'],
                'isRequired': e['is_required'] as bool? ?? false,
                'joinedAt': e['joined_at'],
                'leftAt': e['left_at'],
                'finishedAt': e['finished_at'],
                'providerAvatarUrl': e['provider_avatar_url'] ?? e['provider_image_url'] ?? e['avatar_url'] ?? e['profile_image_url'] ?? user['profile_image_url'],
                'expertGroupIcon': e['expert_group_icon'] ?? e['category_icon'] ?? e['group_icon'] ?? e['icon'],
                'availabilityStatus': user['availability_status'] as String? ?? 'offline',
              };
            }).toList();
          }
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
            'availabilityStatus': user['availability_status'] as String? ?? 'offline',
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
            .select('first_name, last_name, profile_image_url, profession_id, availability_status')
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
            'availabilityStatus': user['availability_status'] as String? ?? 'offline',
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

      // Query prescriptions for each joined expert
      final joinedProviderIds = mapped
          .where((e) => e['providerId'] != null)
          .map((e) => e['providerId'] as String)
          .toList();
      if (joinedProviderIds.isNotEmpty) {
        try {
          final prescriptions = await Supabase.instance.client
              .from('prescriptions')
              .select('provider_id')
              .eq('consultation_id', consultationId);
          final prescriberIds = (prescriptions as List)
              .map((p) => p['provider_id'] as String?)
              .where((id) => id != null)
              .toSet();
          for (final expert in mapped) {
            expert['hasPrescription'] = prescriberIds.contains(expert['providerId']);
          }
        } catch (e) {
          debugPrint('[ChartBoard] prescription query error: $e');
        }
      }

      await _ensureSelectedPackageForMerge();

      // Merge with package expert groups to show waiting groups with grey icons
      final merged = _mergeWithPackageGroups(mapped);
      debugPrint('[ChartBoard] _fetchExpertStatuses merged length=${merged.length} (joined=${mapped.where((e) => e['status'] == 'joined').length}, waiting=${merged.length - mapped.where((e) => e['status'] == 'joined').length})');

      _applyExpertStatuses(merged, source: 'fetch', token: fetchToken);

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

    // ─── Expert: Required Question ─────────────────────────────
    if (_isProvider && _isRequiredToggle) {
      await _sendRequiredQuestion(text, roomId);
      if (mounted) _isSendingNotifier.value = false;
      return;
    }

    // ─── Expert: Edit Required Question ──────────────────────────
    if (_isProvider && _editingQuestionId != null) {
      await _editRequiredQuestion(text);
      if (mounted) _isSendingNotifier.value = false;
      return;
    }

    // ─── Normal message ────────────────────────────────────────
    final message = ChatMessage(
      id: const Uuid().v4(),
      roomId: roomId,
      senderId: _currentUser?.id ?? 'demo_user',
      content: text,
      createdAt: DateTime.now(),
      type: 'text',
      status: MessageStatus.sent,
      bodyPart: _bodyMapChatController.activeBodyPart,
    );

    // Optimistic counter update
    final activePart = _bodyMapChatController.activeBodyPart;
    if (activePart != null) {
      setState(() {
        _bodyMapChatController.bodyPartMessageCount[activePart] =
            (_bodyMapChatController.bodyPartMessageCount[activePart] ?? 0) + 1;
      });
    }

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

    if (mounted) {
      _isSendingNotifier.value = false;
      if (_isProvider) _loadExpertCompletionStatus();
    }
  }

  /// Expert sends a new required question
  Future<void> _sendRequiredQuestion(String text, String roomId) async {
    final message = ChatMessage(
      id: const Uuid().v4(),
      roomId: roomId,
      senderId: _currentUser?.id ?? 'expert',
      content: text,
      createdAt: DateTime.now(),
      type: 'required_question',
      status: MessageStatus.sent,
      isRequired: true,
      requiredStatus: RequiredStatus.unread,
      requiredOwnerId: _currentUser?.id,
      bodyPart: _bodyMapChatController.activeBodyPart,
    );

    _msgController.clear();
    _messagesNotifier.value = [..._messagesNotifier.value, message];
    _scrollToBottom();

    try {
      await _chatRepository.sendMessage(message);
      if (mounted) {
        setState(() {
          _isRequiredToggle = false;
        });
        if (_isProvider) _loadExpertCompletionStatus();
      }
    } catch (e) {
      debugPrint('Send required question error: $e');
    }
  }

  /// Expert edits an existing required question
  Future<void> _editRequiredQuestion(String text) async {
    if (_editingQuestionId == null) return;

    final existing = _requiredQuestions.firstWhere(
      (q) => q.id == _editingQuestionId,
      orElse: () => ChatMessage(
        id: '',
        roomId: '',
        senderId: '',
        content: '',
        createdAt: DateTime.now(),
      ),
    );

    if (existing.id.isEmpty) {
      setState(() => _editingQuestionId = null);
      return;
    }

    // If patient has already seen it (status != unread), create new question
    if (existing.requiredStatus != RequiredStatus.unread) {
      await _sendRequiredQuestion(text, existing.roomId);
      setState(() => _editingQuestionId = null);
      return;
    }

    // Otherwise edit in-place
    try {
      await _chatRepository.editRequiredQuestion(_editingQuestionId!, text, _currentUser?.id ?? '');
      _msgController.clear();
      if (mounted) {
        setState(() => _editingQuestionId = null);
      }
    } catch (e) {
      debugPrint('Edit required question error: $e');
    }
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
        if (mounted) {
          _messagesNotifier.value = [..._messagesNotifier.value, message];
          if (_isProvider) _loadExpertCompletionStatus();
        }
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
  void didChangeMetrics() {
    super.didChangeMetrics();
    final bottomInset = WidgetsBinding.instance.window.viewInsets.bottom;
    final isVisible = bottomInset > 0;
    if (_isKeyboardVisible != isVisible && mounted) {
      setState(() => _isKeyboardVisible = isVisible);
      // Phase 6.7: When keyboard closes, re-evaluate if patient should be blocked
      if (!isVisible && !_isProvider) {
        _checkShouldBlock();
      }
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
    _msgController.removeListener(_onPatientTyping);
    _floatingButtonsScrollController?.dispose();
    _requiredAnswerController.dispose();
    _requiredAnswerFocus.dispose();
    _typingTimer?.cancel();
    _messagesSub?.cancel();
    _expertStatusSub?.cancel();
    _expertAvailabilitySub?.cancel();
    _roomSub?.cancel();
    _consultationSub?.cancel();
    disposeHealthPermission();
    _messagesNotifier.removeListener(_onMessagesChanged);
    _messagesNotifier.dispose();
    _isChatLoadingNotifier.dispose();
    _isRecordingNotifier.dispose();
    _isSendingNotifier.dispose();
    _timerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isProviderActive = _isProvider && (_consultationData?['status'] == 'in_progress');

    return PopScope(
      canPop: !_hasSubmitted && !isProviderActive,
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
        if (isProviderActive && !didPop) {
          // Provider กด system back → trigger ผ่าน leading button แทน
          // (leading button จัดการ dialog ยืนยันเอง)
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
              onPressed: () async {
                if (_hasSubmitted) {
                  // หลังส่งคำรักษาแล้ว → ไปหน้า profile/history แทน analyze-body
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/profile',
                    (route) => route.isFirst,
                    arguments: {'tabIndex': 2},
                  );
                  return;
                }

                // Provider ใน consultation ที่กำลังดำเนินอยู่ → ยืนยันก่อนออก
                final isActive = _isProvider && (_consultationData?['status'] == 'in_progress');
                if (isActive) {
                  final shouldLeave = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('ยืนยันการออกจากห้องแชท'),
                      content: const Text(
                        'การปรึกษายังดำเนินอยู่ หากออกไปตอนนี้ สามารถกลับเข้ามาห้องแชทนี้ได้ผ่านเมนู "ประวัติการปรึกษา"\n\n'
                        'คำแนะนำ: หากต้องการอัปโหลดเอกสารเพิ่มเติม กรุณาใช้ปุ่มใน dialog แจ้งเตือนแทนการออกจากหน้านี้',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('อยู่ต่อ'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('ออกจากห้องแชท'),
                        ),
                      ],
                    ),
                  );
                  if (shouldLeave != true) return;
                }

                if (mounted) Navigator.pop(context);
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
            // Health Data Permission Status Banner — Doctor side only (ซ่อนในโหมดดูอย่างเดียว + ซ่อนเมื่อเปิดแป้นพิมพ์)
            if (_isProvider && !widget.readOnly && permissionRequest != null)
              AnimatedOpacity(
                opacity: _isKeyboardVisible ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: _isKeyboardVisible ? const SizedBox.shrink() : HealthPermissionStatusBanner(
                  request: permissionRequest!,
                  onViewData: openGrantedDataSheet,
                ),
              ),
            AnimatedOpacity(
              opacity: _isKeyboardVisible ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: _isKeyboardVisible ? const SizedBox.shrink() : ExpertStatusBanner(
                expertStatuses: _expertStatuses,
                professions: _professions,
                onAvatarTap: (providerId) {
                  if (_isProvider && _currentUser?.id == providerId && _expertCompletionStatus != null) {
                    _showCompletionChecklistDialog();
                  }
                },
              ),
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
                child: Stack(
                  children: [
                    // 1. Messages list (always at bottom)
                    _buildMessagesList(),

                    // 2. Blur overlay on top of messages when blocked
                    if (_isBlocked && !_isProvider)
                      Positioned.fill(
                        child: ClipRect(
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                            child: Container(
                              color: Colors.white.withOpacity(0.25),
                            ),
                          ),
                        ),
                      ),

                    // 3. Floating required question buttons (above blur)
                    if (_requiredQuestions.isNotEmpty)
                      _buildRequiredQuestionFloatingButtons(),

                    // 4. Required question answer overlay (topmost)
                    if (!_isProvider)
                      _buildRequiredQuestionOverlay(),
                  ],
                ),
              ),
            ),
            // Pain level selector + Payment card for patients before payment/activation
            if (!_isProvider && !_hasSubmitted && (_consultationData?['status'] ?? 'pending') == 'pending')
              Column(
                children: [
                  PainLevelSelector(
                    selectedPain: _selectedPain,
                    onSelected: (pain) => setState(() => _selectedPain = pain),
                  ),
                  const SizedBox(height: 8),
                  PaymentCard(
                    isReady: _selectedPain != null,
                    price: (widget.entry?.price ?? widget.request?.price ?? 0).toInt(),
                    onSubmit: _submitConsultationRequest,
                  ),
                ],
              ),
            _buildBodyMapSummary(),
            if (_isBlocked && !_isProvider)
              _buildBlockedInput()
            else
              _buildChatInput(),
          ],
        ),
      ),
    ),
    ),
    );
  }

  void _showCompletionChecklistDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        backgroundColor: Colors.white,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: SingleChildScrollView(
                  child: CompletionChecklist(
                    status: _expertCompletionStatus!,
                    rule: _professionPackageRule,
                    onClose: () => Navigator.pop(ctx),
                  ),
                ),
              ),
            ),
            Positioned(
              top: -12,
              right: -12,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFinishDialog() async {
    // Phase 6.8: Check completion rules from profession_package_rules before finishing
    if (_isProvider) {
      await _loadExpertCompletionStatus();
    }

    if (_expertCompletionStatus != null && !_expertCompletionStatus!.canFinish) {
      final override = await showDialog<bool>(
        context: context,
        builder: (ctx) => FinishJobWarningDialog(
          missingRequirements: _expertCompletionStatus!.missingRequirements,
          onOverride: () {},
        ),
      );
      if (override != true) return;
    }

    if (!mounted) return;

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
              await _finishJobMultiExpert();
            },
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
  }

  /// จบงานแบบ multi-expert: mark ตัวเองเสร็จ รอคนอื่น
  Future<void> _finishJobMultiExpert() async {
    final authUser = _currentUser;
    if (authUser == null) return;

    final consultationId = widget.entry?.id ?? widget.request?.id;
    if (consultationId == null || consultationId.isEmpty) return;

    final consultRepo = ServiceLocator.instance.consultationRepository;
    final userRepo = UserRepository(Supabase.instance.client);

    try {
      var result = await consultRepo.markExpertFinished(
        consultationId,
        authUser.id,
      );
      // If no rows found, provider is not synced to consultation_room_experts yet (legacy consultation)
      // Sync provider first, then retry markExpertFinished
      var totalExperts = result['total_count'] as int? ?? 0;
      if (totalExperts == 0) {
        await consultRepo.syncProviderToRoomExperts(
          consultationId: consultationId,
          providerId: authUser.id,
        );
        // Retry markExpertFinished after sync
        result = await consultRepo.markExpertFinished(
          consultationId,
          authUser.id,
        );
        totalExperts = result['total_count'] as int? ?? 0;
      }

      final allFinished = result['all_finished'] as bool? ?? false;

      // คืนสถานะ provider → online
      await userRepo.setAvailabilityStatus(authUser.id, 'online');

      // Sync completion state from DB so the finish/revert buttons and read-only overlay stay correct
      await _loadCompletionStatus();
      debugPrint('[ChartBoard] _finishJobMultiExpert: after _loadCompletionStatus _hasFinished=$_hasFinished');

      // ดึงข้อมูล package เพื่อคำนวณจำนวน expert ที่ถูกต้อง
      final packageId = widget.entry?.packageId ?? widget.request?.packageId;
      bool usedPackageFallback = false;

      if (packageId != null && packageId.isNotEmpty && totalExperts == 0) {
        try {
          final packageResponse = await Supabase.instance.client
              .from('consultation_packages')
              .select('expert_groups')
              .eq('id', packageId)
              .single();
          final groups = packageResponse['expert_groups'] as List? ?? [];
          int packageTotal = 0;
          for (final group in groups) {
            if (group is Map) {
              final max = group['max_experts'] ?? group['maxExperts'] ?? -1;
              if (max is int && max > 0) {
                packageTotal += max;
              } else if (max == -1) {
                packageTotal += 1;
              }
            }
          }
          if (packageTotal > 0) {
            totalExperts = packageTotal;
            usedPackageFallback = true;
          }
        } catch (e) {
          debugPrint('ChartBoard: Failed to fetch package expert count: $e');
        }
      }

      if (mounted) {
        debugPrint('[ChartBoard] _finishJobMultiExpert: totalExperts=$totalExperts, usedPackageFallback=$usedPackageFallback, RPC finished_count=${result['finished_count']}');
        setState(() => _hasFinished = true);

        if (allFinished) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ เสร็จสิ้น! ทุกผู้เชี่ยวชาญจบงานแล้ว'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 3),
            ),
          );
          await Future.delayed(const Duration(seconds: 3));
          if (mounted) Navigator.pop(context);
        } else {
          // ถ้าใช้ข้อมูลจาก package (consultation_room_experts ว่าง) ให้นับเราเป็น 1 คนที่จบงานแล้ว
          // ถ้าใช้ข้อมูลจาก RPC ให้ใช้ค่าจาก RPC
          final finishedCount = usedPackageFallback ? 1 : (result['finished_count'] as int? ?? 1);
          final remainingCount = totalExperts - finishedCount;
          debugPrint('[ChartBoard] _finishJobMultiExpert: finishedCount=$finishedCount, remainingCount=$remainingCount');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'คุณจบงานแล้ว รอผู้เชี่ยวชาญอีก $remainingCount คน '
                '($finishedCount / $totalExperts)',
              ),
              backgroundColor: AppColors.info,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('ChartBoard: _finishJobMultiExpert error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// ยกเลิกสถานะจบงาน (revert)
  void _showRevertDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยกเลิกจบงาน?'),
        content: const Text('คุณต้องการกลับมาทำงานในห้องแชทนี้ต่อใช่หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _revertFinish();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF9800)),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
  }

  Future<void> _revertFinish() async {
    final authUser = _currentUser;
    if (authUser == null) return;

    final consultationId = widget.entry?.id ?? widget.request?.id;
    if (consultationId == null || consultationId.isEmpty) return;

    final consultRepo = ServiceLocator.instance.consultationRepository;

    try {
      await consultRepo.markExpertReverted(consultationId, authUser.id);
      await _loadCompletionStatus();
      if (mounted) {
        setState(() => _hasFinished = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ยกเลิกจบงานแล้ว คุณสามารถแชทต่อได้'),
            backgroundColor: AppColors.info,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('ChartBoard: _revertFinish error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
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

        final activePart = _bodyMapChatController.activeBodyPart;
        final allMessages = _messagesNotifier.value;
        // Sort: required questions with answers use answer time; others use creation time
        final sortedMessages = [...allMessages]..sort((a, b) {
          final aTime = a.type == 'required_question' && a.requiredAnsweredAt != null
              ? a.requiredAnsweredAt!
              : a.createdAt;
          final bTime = b.type == 'required_question' && b.requiredAnsweredAt != null
              ? b.requiredAnsweredAt!
              : b.createdAt;
          return aTime.compareTo(bTime);
        });
        final messages = activePart == null
            ? sortedMessages
            : sortedMessages.where((m) => m.bodyPart?.toLowerCase().trim() == activePart).toList();
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
                final senderAvatarUrl = _expertStatuses
                    .firstWhere(
                      (e) => e['providerId'] == msg.senderId,
                      orElse: () => {},
                    )['providerAvatarUrl']
                    ?.toString();
                return MessageBubble(
                  message: msg,
                  isMe: isMe,
                  hideBodyPart: activePart != null,
                  bodyPartIconName: _bodyMapChatController.resolveBodyPartIconName(msg.bodyPart),
                  senderAvatarUrl: senderAvatarUrl,
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

  Future<void> _showQuickRepliesBottomSheet() async {
    final user = _currentUser;
    if (user == null) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: Supabase.instance.client
            .from('doctor_quick_replies')
            .select()
            .eq('provider_id', user.id)
            .order('sort_order', ascending: true),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final replies = snapshot.data ?? [];
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'ข้อความด่วน',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => ManageQuickRepliesPage()),
                          );
                        },
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('จัดการ'),
                      ),
                    ],
                  ),
                ),
                if (replies.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'ยังไม่มีข้อความด่วน\nคุณสามารถกดปุ่ม "จัดการ" เพื่อเพิ่มข้อความได้',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: replies.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final reply = replies[index];
                        return ListTile(
                          title: Text(
                            reply['content']?.toString() ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _msgController.text = reply['content']?.toString() ?? '';
                            // Move cursor to the end
                            _msgController.selection = TextSelection.fromPosition(
                              TextPosition(offset: _msgController.text.length),
                            );
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildChatInput() {
    final status = _consultationData?['status'] as String? ?? 'pending';
    final isChatActive = _isProvider || _hasSubmitted || status == 'in_progress';
    final readOnly = widget.readOnly || _hasFinished;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Expert: Required question toggle
          if (_isProvider && _editingQuestionId == null) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 12, right: 12),
              child: Row(
                children: [
                  Switch(
                    value: _isRequiredToggle,
                    onChanged: (v) => setState(() => _isRequiredToggle = v),
                    activeColor: AppColors.primary,
                  ),
                  Text(
                    'คำถามบังคับ',
                    style: TextStyle(
                      fontSize: 12,
                      color: _isRequiredToggle ? AppColors.primary : Colors.grey,
                    ),
                  ),
                  if (_isRequiredToggle)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'จำเป็น',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          // Expert: Editing mode banner
          if (_isProvider && _editingQuestionId != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 6, left: 12, right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit, size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'แก้ไขคำถาม',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() {
                      _editingQuestionId = null;
                      _msgController.clear();
                    }),
                    child: Icon(Icons.close, size: 16, color: Colors.orange.shade700),
                  ),
                ],
              ),
            ),
          ],
          ChatInputBarWidget(
            key: ValueKey('chat-input-${widget.readOnly}-$readOnly-$_hasFinished'),
            controller: _msgController,
            isProvider: _isProvider,
            isChatActive: isChatActive,
            isSending: _isSendingNotifier,
            isRecording: _isRecordingNotifier,
            readOnly: readOnly,
            readOnlyLabel: _hasFinished ? 'คุณจบงานแล้ว — กดยกเลิกเพื่อแชทต่อ' : null,
            onSend: _sendMessage,
            onStartRecording: _startRecording,
            onStopRecording: _stopRecording,
            onPickImage: _pickAndSendImage,
            onShowAttachmentMenu: _showAttachmentMenu,
            onShowQuickReplies: _showQuickRepliesBottomSheet,
            onTextChanged: (_) => setState(() {}),
            activeBodyPartIconName: _bodyMapChatController.activeBodyPartIconName,
            onClearBodyPart: () {
              setState(() => _bodyMapChatController.clearBodyPart());
            },
            isRequiredMode: _isProvider && _isRequiredToggle,
            isEditingMode: _isProvider && _editingQuestionId != null,
          ),
        ],
      ),
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

  Future<void> _viewPrescriptionDetails(String? prescriptionId) async {
    if (prescriptionId == null) return;
    final consultationId = widget.entry?.id ?? widget.request?.id ?? '';
    final patientId = widget.entry?.patientId ?? widget.request?.userId ?? '';

    if (_isProvider) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => PrescriptionEditorPage(
            consultationId: consultationId,
            patientId: patientId,
          ),
        ),
      );
      if (mounted) _loadExpertCompletionStatus();
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => PrescriptionChoicePage(
          consultationId: consultationId,
          patientId: patientId,
          prescriptionId: prescriptionId,
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
    debugPrint('[ChartBoard] _buildActionButtons: _isProvider=$_isProvider, _hasFinished=$_hasFinished, readOnly=${widget.readOnly}');
    return ActionButtonsWidget(
      key: ValueKey('action-buttons-${widget.readOnly}-$_hasFinished'),
      isProvider: _isProvider,
      readOnly: widget.readOnly || _hasFinished,
      hasFinished: _hasFinished,
      onFinishPressed: _showFinishDialog,
      onRevertPressed: _showRevertDialog,
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



  Future<void> _startVideoCall() async {
    final roomId = widget.entry?.roomId ?? 'consult_${widget.request?.id}';
    await Navigator.pushNamed(
      context,
      '/live-vdo',
      arguments: {
        'roomId': roomId,
        'isCaller': true,
        'otherParticipantName': widget.entry?.patientName ?? 'Patient',
      },
    );
    if (mounted && _isProvider) _loadExpertCompletionStatus();
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
    final assignedExpertIndexes = <int>{};

    for (final group in package.expertGroups) {
      // Find the corresponding profession for this group to get its icon/color fallback.
      final prof = findProfessionByNameOrRole(_professions, group.name, group.role);

      final groupMatchKey = _consultationMatchKey(group.name, group.role);
      final groupNameLower = group.name.toLowerCase().trim();

      int? matchedIndex;
      for (var i = 0; i < merged.length; i++) {
        if (assignedExpertIndexes.contains(i)) continue;

        final expert = merged[i];
        if (expert['status'] == 'waiting') continue; // only check joined experts

        final expertNameLower = (expert['name'] as String? ?? '').toLowerCase().trim();
        final expertGroupNameLower = (expert['expertGroupName'] as String? ?? '').toLowerCase().trim();
        final expertMatchKey = _consultationMatchKey(
          expert['name'] as String?,
          expert['role']?.toString(),
        );

        final matchesByRole = groupMatchKey.isNotEmpty && expertMatchKey == groupMatchKey;
        final matchesByName = groupNameLower.isNotEmpty &&
            (expertNameLower == groupNameLower || expertGroupNameLower == groupNameLower);

        if (matchesByRole || matchesByName) {
          matchedIndex = i;
          break;
        }
      }

      if (matchedIndex != null) {
        assignedExpertIndexes.add(matchedIndex);
        final expert = merged[matchedIndex];
        // Sync UI properties from the group to the joined expert
        expert['isRequired'] = expert['isRequired'] == true || group.isRequired;
        expert['expertGroupIcon'] ??= prof?.iconName ?? group.icon ?? iconNameFromRole(group.role);
        expert['professionColorHex'] ??= prof?.colorHex;
        expert['expertGroupName'] ??= group.name;
      } else {
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

  // =====================================================
  // Required Questions (Phase 6.7)
  // =====================================================

  /// Called whenever messages change — detects required questions and updates block state
  void _onMessagesChanged() {
    final messages = _messagesNotifier.value;
    final required = messages.where((m) => m.isRequired).toList();
    if (!mounted) return;

    // Detect new question to auto-scroll to latest button
    final previousCount = _requiredQuestions.length;
    final currentCount = required.length;
    final hasNewQuestion = currentCount > previousCount;

    final hasUnreadNow = required.any((q) => q.requiredStatus == RequiredStatus.unread);
    final isNewUnread = hasNewQuestion && hasUnreadNow;

    setState(() {
      _requiredQuestions = required;
    });

    // Scroll to latest unread button after rebuild.
    if (isNewUnread && _floatingButtonsScrollController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _floatingButtonsScrollController?.hasClients != true) return;

        final target = _floatingButtonsScrollController!.position.minScrollExtent;
        if ((_floatingButtonsScrollController!.offset - target).abs() > 1.0) {
          debugPrint('[FloatingButtons] animateTo(minScrollExtent) called, currentOffset=${_floatingButtonsScrollController!.offset}, target=$target, itemCount=${_requiredQuestions.length}');
          _floatingButtonsScrollController!.animateTo(
            target,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
          debugPrint('[FloatingButtons] animateTo(minScrollExtent) scheduled');
        }
      });
    }

    // Patient side: check if should block
    if (!_isProvider) {
      _checkShouldBlock();
    }
  }

  /// Track patient typing to delay block UI
  void _onPatientTyping() {
    if (_isProvider) return;
    final pending = _requiredQuestions.where(
      (q) => q.requiredStatus == RequiredStatus.unread || q.requiredStatus == RequiredStatus.reading,
    ).toList();
    if (pending.isEmpty) return;

    // Patient is typing — temporarily unblock
    if (_isBlocked) {
      setState(() => _isBlocked = false);
    }

    // Set timer to re-block after 2 seconds of inactivity
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) _checkShouldBlock();
    });
  }

  /// Check if patient should be blocked (has pending required questions)
  void _checkShouldBlock() {
    final pending = _requiredQuestions.where(
      (q) => q.requiredStatus == RequiredStatus.unread || q.requiredStatus == RequiredStatus.reading,
    ).toList();

    if (pending.isEmpty) {
      if (mounted) setState(() => _isBlocked = false);
      return;
    }

    // Check if patient is currently typing
    final isTyping = _msgController.text.isNotEmpty;
    final hasFocus = _msgController.text.isNotEmpty; // Simplified check

    if (isTyping || _isKeyboardVisible) {
      // Phase 6.7: Do NOT force block/overlay while patient is typing
      // or keyboard is visible. Wait for patient to finish.
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && !_isKeyboardVisible) {
          setState(() => _isBlocked = true);
        }
      });
    } else {
      if (mounted) setState(() => _isBlocked = true);
    }

    // Auto-open overlay if only 1 pending question (patient side, not already open)
    // Phase 6.7: MUST NOT force overlay when patient is typing or keyboard is visible
    final justClosed = _lastManualCloseTime != null &&
        DateTime.now().difference(_lastManualCloseTime!).inSeconds < 2;
    if (!_isProvider &&
        pending.length == 1 &&
        !_showRequiredOverlay &&
        _activeRequiredQuestion == null &&
        !justClosed &&
        !isTyping &&
        !_isKeyboardVisible) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _onPatientTapRequiredQuestion(pending.first);
      });
    }
  }

  /// Patient taps a floating required question button
  void _onPatientTapRequiredQuestion(ChatMessage question) async {
    if (_isProvider) return; // Only patient side

    setState(() {
      _activeRequiredQuestion = question;
      _showRequiredOverlay = true;
    });

    // Update status to reading
    await _chatRepository.updateRequiredStatus(question.id, RequiredStatus.reading);

    // Open keyboard
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) FocusScope.of(context).requestFocus(_requiredAnswerFocus);
    });
  }

  /// Patient cancels answering
  void _onPatientCancelAnswer() async {
    if (_activeRequiredQuestion != null) {
      await _chatRepository.updateRequiredStatus(
        _activeRequiredQuestion!.id,
        RequiredStatus.unread,
      );
    }
    setState(() {
      _showRequiredOverlay = false;
      _activeRequiredQuestion = null;
      _requiredAnswerController.clear();
      _lastManualCloseTime = DateTime.now();
    });
  }

  /// Patient submits answer
  Future<void> _onPatientSubmitAnswer() async {
    if (_activeRequiredQuestion == null) return;
    final answer = _requiredAnswerController.text.trim();
    if (answer.isEmpty) return;

    final question = _activeRequiredQuestion!;

    // Submit required answer (answer is shown inline inside the required question bubble)
    await _chatRepository.submitRequiredAnswer(
      question.id,
      answer,
      question.bodyPart ?? '',
    );

    if (mounted) {
      setState(() {
        _showRequiredOverlay = false;
        _activeRequiredQuestion = null;
        _requiredAnswerController.clear();
        _lastManualCloseTime = DateTime.now();
      });
      if (_isProvider) _loadExpertCompletionStatus();
      // _checkShouldBlock() is NOT called here — realtime stream updates
      // _requiredQuestions via _onMessagesChanged, which then re-checks block state
      // Calling it here would race with local state still having old pending data
    }
  }

  /// Build floating required question buttons (above messages area)
  Widget _buildRequiredQuestionFloatingButtons() {
    return Positioned(
      top: 8,
      right: 8,
      left: 8,
      child: Scrollbar(
        controller: _floatingButtonsScrollController,
        thumbVisibility: false,
        child: SingleChildScrollView(
          controller: _floatingButtonsScrollController,
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: _requiredQuestions.reversed.map((q) {
          Color bgColor;
          switch (q.requiredStatus) {
            case RequiredStatus.unread:
              bgColor = Colors.red.shade600;
              break;
            case RequiredStatus.reading:
              bgColor = const Color(0xFFFFB300);
              break;
            case RequiredStatus.answered:
              bgColor = Colors.green.shade600;
              break;
            default:
              bgColor = Colors.grey.shade400;
          }
          final isUnread = q.requiredStatus == RequiredStatus.unread;
          Widget button = GestureDetector(
            onTap: () {
              // Green (answered) buttons: scroll to question+answer in messages
              if (q.requiredStatus == RequiredStatus.answered) {
                _scrollToQuestion(q);
                return;
              }
              if (_isProvider) {
                _onExpertTapQuestion(q);
              } else {
                _onPatientTapRequiredQuestion(q);
              }
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: isUnread
                    // Red: expert profile image (who asked the question)
                    ? _buildAvatar(
                        imageUrl: _expertStatuses
                            .firstWhere(
                              (e) => e['providerId'] == q.requiredOwnerId,
                              orElse: () => {},
                            )['providerAvatarUrl']
                            ?.toString(),
                        fallbackIcon: Icons.warning_amber,
                      )
                    : (q.requiredStatus == RequiredStatus.reading
                        // Amber: typing dots animation
                        ? _TypingDots(color: Colors.white)
                        // Green: patient profile image
                        : _buildAvatar(
                            imageUrl: widget.entry?.patientAvatar ?? _currentUser?.profileImageUrl,
                            fallbackIcon: Icons.check,
                          )),
              ),
            ),
          );

          // Ripple animation for unread (red) buttons
          if (isUnread) {
            button = _buildRippleWrapper(button);
          }

          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: button,
          );
        }).toList(),
      ),
    ),
  ),
);
  }

  /// Water ripple effect behind a floating button
  Widget _buildRippleWrapper(Widget child) {
    return SizedBox(
      width: 60,
      height: 60,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            _RippleRing(delay: 0.0, color: Colors.red.shade600),
            _RippleRing(delay: 0.6, color: Colors.red.shade600),
            _RippleRing(delay: 1.2, color: Colors.red.shade600),
            SizedBox(width: 36, height: 36, child: child),
          ],
        ),
      ),
    );
  }

  /// Small circular avatar for floating buttons (profile image or fallback icon)
  Widget _buildAvatar({String? imageUrl, required IconData fallbackIcon}) {
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 16,
        backgroundColor: Colors.transparent,
        backgroundImage: CachedNetworkImageProvider(imageUrl),
      );
    }
    return Icon(fallbackIcon, color: Colors.white, size: 18);
  }

  /// Blocked input message (shown when patient has pending required questions)
  Widget _buildBlockedInput() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border(
          top: BorderSide(color: Colors.red.shade100),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.warning_amber, color: Colors.red.shade400, size: 20),
          const SizedBox(width: 8),
          Text(
            'กรุณาตอบคำถามบังคับก่อน',
            style: TextStyle(
              color: Colors.red.shade600,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Build the required question answer overlay
  Widget _buildRequiredQuestionOverlay() {
    if (!_showRequiredOverlay || _activeRequiredQuestion == null) {
      return const SizedBox.shrink();
    }

    final question = _activeRequiredQuestion!;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with question and close button
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber, color: Colors.red, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'คำถามบังคับ',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          question.content,
                          style: const TextStyle(fontSize: 15, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _onPatientCancelAnswer,
                    child: const Icon(Icons.close, color: Colors.grey, size: 22),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Answer input with SOS prefix
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7F5),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _requiredAnswerController,
                        focusNode: _requiredAnswerFocus,
                        decoration: const InputDecoration(
                          hintText: 'พิมพ์คำตอบ...',
                          hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                        onSubmitted: (_) => _onPatientSubmitAnswer(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Submit button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _onPatientSubmitAnswer,
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('ส่งคำตอบ'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Expert taps a required question button to edit it
  void _onExpertTapQuestion(ChatMessage question) {
    if (!_isProvider) return;

    setState(() {
      _editingQuestionId = question.id;
      _msgController.text = question.content;
      _isRequiredToggle = false;
    });

    // Move cursor to end
    _msgController.selection = TextSelection.fromPosition(
      TextPosition(offset: _msgController.text.length),
    );
  }

  /// Scroll messages list to show the given required question
  void _scrollToQuestion(ChatMessage question) {
    // Clear body part filter so the question is visible in the list
    if (_bodyMapChatController.activeBodyPart != null) {
      setState(() => _bodyMapChatController.onChipSelected(null));
    }

    // Find the question's index in the full messages list
    final allMessages = _messagesNotifier.value;
    final index = allMessages.indexWhere((m) => m.id == question.id);
    if (index == -1) return;

    // Scroll to the message after rebuild
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final targetOffset = (index * 70.0).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  // Phase 6.6: BodyMapChatBar via controller
  Widget _buildBodyMapSummary() {
    _bodyMapChatController.resolveBodyPartChips(
      request: widget.request,
      entry: widget.entry,
      consultationData: _consultationData,
    );
    if (_bodyMapChatController.bodyPartChips.isEmpty) {
      return const SizedBox.shrink();
    }
    // Check if patient has pending required questions
    final hasPendingRequired = !_isProvider && _requiredQuestions.any(
      (q) => q.requiredStatus == RequiredStatus.unread || q.requiredStatus == RequiredStatus.reading,
    );

    // Hide pills if patient hasn't selected a floating button yet
    if (hasPendingRequired && _activeRequiredQuestion == null && !_showRequiredOverlay) {
      return const SizedBox.shrink();
    }

    // When patient is answering a required question, show only that question's body part pill
    final activeQuestion = _activeRequiredQuestion;
    if (hasPendingRequired && _showRequiredOverlay && activeQuestion != null) {
      final bodyPart = activeQuestion.bodyPart;
      // If question has a specific body part, show only that pill
      if (bodyPart != null && bodyPart.isNotEmpty) {
        final chip = _bodyMapChatController.bodyPartChips.firstWhere(
          (c) => c.key == bodyPart.toLowerCase().trim(),
          orElse: () => BodyPartChipData(key: bodyPart, label: bodyPart),
        );
        return Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Container(
                constraints: const BoxConstraints(minHeight: 22, maxHeight: 22),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.orange),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (iconNameToIconData(chip.iconName) != null) ...[
                      Icon(iconNameToIconData(chip.iconName), size: 10, color: Colors.white),
                      const SizedBox(width: 3),
                    ],
                    Text(
                      chip.label,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.0,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }
      // Question has no body part (general/overview) — show 'ภาพรวม' pill
      return Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 22, maxHeight: 22),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.orange),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.list_alt, size: 10, color: Colors.white),
                  SizedBox(width: 3),
                  Text(
                    'ภาพรวม',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.0,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return BodyMapChatBar(
      bodyParts: _bodyMapChatController.bodyPartChips,
      patientMessageCount: _bodyMapChatController.bodyPartMessageCount,
      activeBodyPart: _bodyMapChatController.activeBodyPart,
      disabled: hasPendingRequired,
      onBodyPartSelected: (key) {
        setState(() => _bodyMapChatController.onChipSelected(key));
        FocusScope.of(context).requestFocus(FocusNode());
      },
    );
  }

}

/// Animated ripple ring for floating button water ripple effect
class _RippleRing extends StatefulWidget {
  final double delay;
  final Color color;

  const _RippleRing({required this.delay, required this.color});

  @override
  State<_RippleRing> createState() => _RippleRingState();
}

class _RippleRingState extends State<_RippleRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = _controller.value;
        final cycle = 1.8; // seconds per ripple cycle
        // Phase 0→1: ring starts small/visible and expands/fades
        final phase = ((value * cycle + widget.delay) % cycle) / cycle;

        return Container(
          width: 36 + (phase * 24),
          height: 36 + (phase * 24),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withOpacity((1 - phase) * 0.35),
          ),
        );
      },
    );
  }
}

/// Animated typing dots (…) for "patient is typing" indicator
class _TypingDots extends StatefulWidget {
  final Color color;
  const _TypingDots({required this.color});

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(delay: 0.0, t: t, color: widget.color),
            const SizedBox(width: 2),
            _Dot(delay: 0.33, t: t, color: widget.color),
            const SizedBox(width: 2),
            _Dot(delay: 0.66, t: t, color: widget.color),
          ],
        );
      },
    );
  }
}

class _Dot extends StatelessWidget {
  final double delay;
  final double t;
  final Color color;

  const _Dot({required this.delay, required this.t, required this.color});

  @override
  Widget build(BuildContext context) {
    final phase = ((t + delay) % 1.0);
    final opacity = phase < 0.5 ? 0.3 + (phase * 2 * 0.7) : 1.0 - ((phase - 0.5) * 2 * 0.7);
    final scale = 0.6 + (opacity * 0.4);
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          color: color.withOpacity(opacity.clamp(0.3, 1.0)),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
