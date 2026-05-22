import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
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
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import '../../data/models/consultation_request_model.dart';
import '../../data/models/consultation_entry.dart';
import '../../../../features/chat/data/models/chat_models.dart';
import '../../data/models/consultation_package.dart';
import '../widgets/package_wheel_selector.dart';
import 'prescription_editor_page.dart';
import 'consultation_note_editor_page.dart';

class ChartBoardPage extends StatefulWidget {
  final ConsultationRequestModel? request;
  final ConsultationEntry? entry; // For active consultations

  const ChartBoardPage({super.key, this.request, this.entry});

  @override
  State<ChartBoardPage> createState() => _ChartBoardPageState();
}

class _ChartBoardPageState extends State<ChartBoardPage>
    with TickerProviderStateMixin {
  final _chatRepository = ServiceLocator.instance.chatRepository;
  final _healthPermissionRepository =
      ServiceLocator.instance.healthDataPermissionRepository;
  final _currentUser = AuthService.instance.currentUser;
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final _audioRecorder = AudioRecorder();

  String? _consultationRoomId;
  String? _activeConsultationId;

  List<ChatMessage> _messages = [];
  bool _isChatLoading = true;
  bool _isRecording = false;
  bool _isSending = false;
  bool _isConsultationActive = false; // Locked until paid (for patient)
  bool _isHeaderExpanded = true;
  bool _isProvider = false;

  StreamSubscription? _messagesSub;
  Timer? _healthPermissionPollTimer;
  List<ConsultationPackage> _availablePackages = [];
  ConsultationPackage? _selectedPackage;
  bool _isLoadingPackages = false;

  // --- Session Timer Features ---
  Timer? _sessionTimer;
  int _remainingSeconds = 900; // Mock 15 mins
  bool _isTimerRunning = false;
  bool _hasReviewed = false;

  // --- Expert Status ---
  List<Map<String, dynamic>> _expertStatuses = [];
  StreamSubscription? _expertStatusSub;

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Pain level options
  final List<Map<String, dynamic>> painLevels = [
    {
      'label': 'ไม่มี',
      'color': const Color(0xFF4CAF50),
      'icon': Icons.sentiment_very_satisfied,
    },
    {
      'label': 'เล็กน้อย',
      'color': const Color(0xFF8BC34A),
      'icon': Icons.sentiment_satisfied,
    },
    {
      'label': 'ปานกลาง',
      'color': const Color(0xFFFFC107),
      'icon': Icons.sentiment_neutral,
    },
    {
      'label': 'มาก',
      'color': const Color(0xFFFF9800),
      'icon': Icons.sentiment_dissatisfied,
    },
    {
      'label': 'มากที่สุด',
      'color': const Color(0xFFF44336),
      'icon': Icons.sentiment_very_dissatisfied,
    },
  ];
  String? _selectedPain;

  @override
  void initState() {
    super.initState();
    // Robust provider check (matches Dashboard logic)
    final professionId = _currentUser?.professionId;
    _isProvider = professionId != null && 
                  professionId != '00000000-0000-0000-0000-000000000001';
    
    // Auto-detect initial state
    if (widget.entry != null) {
      _isConsultationActive = true;
      _isHeaderExpanded = false;
      _selectedPain = widget.entry!.symptomsChart['pain_level']?.toString();
    } else if (widget.request?.symptomsChart['pain_level'] != null) {
      _selectedPain = widget.request!.symptomsChart['pain_level']?.toString();
    }

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
    _subscribeHealthPermissionUpdates();
    _startHealthPermissionPolling();
  }

  void _startTimer() {
    if (_isTimerRunning) return;
    _isTimerRunning = true;
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        if (mounted) {
          setState(() {
            _remainingSeconds--;
          });
        }
      } else {
        _sessionTimer?.cancel();
        _isTimerRunning = false;
        _onSessionExpired();
      }
    });
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

  String _formatTimer(int totalSeconds) {
    int minutes = totalSeconds ~/ 60;
    int seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _loadPackages() async {
    if (_isProvider) return;
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
          
          // Set initial package from request
          if (widget.request?.packageId != null) {
            _selectedPackage = pks.firstWhere(
              (p) => p.id == widget.request!.packageId,
              orElse: () => pks.first,
            );
          } else if (pks.isNotEmpty) {
            _selectedPackage = pks.first;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading packages: $e');
      if (mounted) setState(() => _isLoadingPackages = false);
    }
  }

  Future<void> _initChat() async {
    setState(() => _isChatLoading = true);

    try {
      final currentUserId = _currentUser?.id;
      final supabase = Supabase.instance.client;

      if (currentUserId == null) {
        setState(() => _isChatLoading = false);
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
        setState(() {
          _isChatLoading = false;
          _isConsultationActive = false;
        });
        return;
      }

      final roomId = 'consult_$consultationId';
      setState(() {
        _consultationRoomId = roomId;
        _activeConsultationId = consultationId;
      });

      await _loadLatestHealthPermission();
      _subscribeHealthPermissionUpdates();

      // 2. Fetch Consultation & Room Details
      final results = await Future.wait([
        supabase.from('consultation_requests').select().eq('id', consultationId).maybeSingle(),
        supabase.from('chat_rooms').select().eq('id', roomId).maybeSingle(),
      ]);

      final consultData = results[0];
      final roomData = results[1];

      if (consultData != null) {
        final status = consultData['status'] as String?;
        final paymentStatus = consultData['payment_status'] as String? ?? 'pending';
        
        if (mounted) {
          setState(() {
            // Patient needs to pay first, Providers can always see if they are assigned
            _isConsultationActive = (paymentStatus == 'paid') || _isProvider;
            
            if (consultData['package_id'] != null && _selectedPackage == null) {
              // Try to find in loaded packages later
            }
          });
        }
      }

      if (roomData != null) {
        final startedAtStr = roomData['started_at'] as String?;
        final sessionMins = (roomData['session_minutes'] as int?) ?? 15;
        final isActive = roomData['is_active'] as bool? ?? true;

        if (startedAtStr != null && isActive) {
          final startedAt = DateTime.parse(startedAtStr);
          final now = DateTime.now();
          final elapsedSeconds = now.difference(startedAt).inSeconds;
          final totalSeconds = sessionMins * 60;
          
          if (mounted) {
            setState(() {
              _remainingSeconds = (totalSeconds - elapsedSeconds).clamp(0, totalSeconds);
              if (_remainingSeconds > 0) {
                _startTimer();
              }
            });
          }
        }
      }

      // 3. Subscribe to Expert Statuses (Priority 2)
      _fetchExpertStatuses(consultationId);
      _expertStatusSub = supabase
          .from('consultation_room_experts')
          .stream(primaryKey: ['id'])
          .eq('consultation_id', consultationId)
          .listen((data) {
            if (mounted) {
              setState(() {
                _expertStatuses = data.map((e) => {
                  'role': e['expert_group_role'],
                  'name': e['expert_group_name'],
                  'status': e['status'],
                  'providerId': e['provider_id'],
                  'isRequired': e['is_required'] as bool? ?? false,
                }).toList();
              });
            }
          });

      // 4. Load Messages
      final messages = await _chatRepository.getMessages(roomId);

      if (mounted) {
        setState(() {
          _messages = messages;
          _isChatLoading = false;
        });

        // Subscribe to messages
        _messagesSub = _chatRepository.streamMessages(roomId).listen((updatedMessages) {
          if (mounted) {
            setState(() => _messages = updatedMessages);
            _scrollToBottom();
          }
        });

        _fadeController.forward();
        _slideController.forward();
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('ChartBoardPage: Init error: $e');
      if (mounted) setState(() => _isChatLoading = false);
    }
  }

  Future<void> _fetchExpertStatuses(String consultationId) async {
    try {
      final data = await Supabase.instance.client
          .from('consultation_room_experts')
          .select()
          .eq('consultation_id', consultationId);
      
      if (mounted) {
        setState(() {
          _expertStatuses = (data as List).map((e) => {
            'role': e['expert_group_role'],
            'name': e['expert_group_name'],
            'status': e['status'],
            'providerId': e['provider_id'],
            'isRequired': e['is_required'] as bool? ?? false,
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('Error fetching expert statuses: $e');
    }
  }

  /// Ensure the consultation chat room exists in chat_rooms table
  Future<void> _ensureConsultationRoom(
    String roomId,
    String currentUserId,
  ) async {
    try {
      final supabase = Supabase.instance.client;
      // Check if room already exists
      final existing = await supabase
          .from('chat_rooms')
          .select('id')
          .eq('id', roomId)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));

      if (existing == null) {
        // Create room with the patient's ID as participant
        await supabase
            .from('chat_rooms')
            .insert({
              'id': roomId,
              'participant_ids': [currentUserId],
              'last_message': null,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .timeout(const Duration(seconds: 5));
        debugPrint('ChartBoardPage: Created consultation room: $roomId');
      } else {
        debugPrint('ChartBoardPage: Room already exists: $roomId');
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
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);

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
    setState(() {
      // Optimistic update — show immediately
      _messages = [..._messages, message];
    });
    _scrollToBottom();

    try {
      await _chatRepository.sendMessage(message);
    } catch (e) {
      debugPrint('Send error: $e');
      // Keep message shown even if send fails (offline mode)
    }

    if (mounted) setState(() => _isSending = false);
  }

  Future<void> _sendSpecialMessage(String type, String content) async {
    if (_isSending) return;
    setState(() => _isSending = true);

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
      if (mounted) setState(() => _messages = [..._messages, message]);
      _scrollToBottom();
    } catch (e) {
      debugPrint('Special send error: $e');
    }

    if (mounted) setState(() => _isSending = false);
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
        if (mounted) setState(() => _messages = [..._messages, message]);
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
        if (mounted) setState(() => _isRecording = true);
      }
    } catch (e) {
      debugPrint('Record start error: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      if (mounted) setState(() => _isRecording = false);

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
          if (mounted) setState(() => _messages = [..._messages, message]);
          _scrollToBottom();
        }
      }
    } catch (e) {
      debugPrint('Record stop error: $e');
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _msgController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    _messagesSub?.cancel();
    _expertStatusSub?.cancel();
    _healthPermissionPollTimer?.cancel();
    _healthPermissionChannel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
            onPressed: () => Navigator.pop(context),
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
                      _isProvider ? "ห้องปรึกษา (มุมมองแพทย์)" : "กลุ่มผู้เชี่ยวชาญที่เข้าร่วม",
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
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
            // Health Data Permission Status Banner — Doctor side only
            if (_isProvider && _healthPermissionRequest != null)
              _buildHealthPermissionStatusBanner(_healthPermissionRequest!),
            _buildExpertStatusBanner(),
            _buildBodyMapSummary(),
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
            _buildChatInput(),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildFinishButton() {
    return ElevatedButton.icon(
      onPressed: _showFinishDialog,
      icon: const Icon(Icons.check_circle_outline, size: 14),
      label: const Text('เสร็จงาน', style: TextStyle(fontSize: 11)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
    if (_isChatLoading) {
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

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          itemCount: _messages.length + 1, // +1 for payment card at bottom
          itemBuilder: (context, index) {
            if (index == _messages.length) {
              // Only show payment card if not a provider and consultation not active
              if (!_isProvider && !_isConsultationActive) {
                return _buildPaymentCard();
              }
              // Show Review Card if completed and is patient
              if (!_isProvider && (widget.entry?.status == 'completed')) {
                return _buildReviewCard();
              }
              return const SizedBox(height: 20);
            }
            if (_messages.isEmpty) return const SizedBox.shrink();
            final msg = _messages[index];
            final isMe = msg.senderId == (_currentUser?.id ?? 'demo_user');
            return _buildMessageBubble(msg, isMe);
          },
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, bool isMe) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisAlignment: isMe
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe) ...[
              CircleAvatar(
                radius: 14,
                backgroundColor: Colors.white,
                child: const Icon(
                  Icons.medical_services,
                  size: 12,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.62,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: isMe ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (message.type == 'image' && message.attachmentUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(
                        imageUrl: message.attachmentUrl!,
                        width: 160,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          width: 160,
                          height: 120,
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    )
                  else if (message.type == 'voice' &&
                      message.attachmentUrl != null)
                    _MiniVoicePlayer(url: message.attachmentUrl!, isMe: isMe)
                  else if (message.type == 'prescription')
                    _buildPrescriptionCard(message)
                  else if (message.type == 'summary')
                    _buildSummaryCard(message)
                  else
                    Text(
                      message.content,
                      style: TextStyle(
                        color: isMe ? Colors.white : Colors.black87,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  const SizedBox(height: 3),
                  Text(
                    '${message.createdAt.hour}:${message.createdAt.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 9,
                      color: isMe
                          ? Colors.white.withOpacity(0.7)
                          : Colors.grey.shade500,
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

  Widget _buildPaymentCard() {
    final bool isReady = _selectedPain != null;
    final color = isReady ? const Color(0xFF4A8B2C) : Colors.white;
    final textColor = isReady ? Colors.white : Colors.black;

    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 16),
      child: InkWell(
        onTap: isReady ? _submitConsultationRequest : null,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: isReady
                    ? const Color(0xFF4A8B2C).withOpacity(0.3)
                    : Colors.black.withOpacity(0.05),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(
              color: isReady
                  ? const Color(0xFF4A8B2C).withOpacity(0.5)
                  : Colors.grey.shade200,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isReady
                      ? Colors.white.withOpacity(0.2)
                      : Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isReady ? Icons.check_circle : Icons.check_circle_outline,
                  color: isReady ? Colors.white : Colors.grey.shade300,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${widget.request?.price.toInt() ?? 0} บาท',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    Text(
                      isReady
                          ? 'ยืนยันและส่งคำรักษา'
                          : 'กรุณาเลือกระดับความเจ็บปวดก่อน',
                      style: TextStyle(
                        fontSize: 13,
                        color: isReady
                            ? Colors.white.withOpacity(0.9)
                            : Colors.orange.shade800,
                        fontWeight: isReady
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: isReady
                    ? Colors.white.withOpacity(0.5)
                    : Colors.grey.shade300,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHealthPermissionStatusBanner(Map<String, dynamic> req) {
    final status = req['status']?.toString() ?? 'pending';
    Color bgColor;
    Color textColor;
    IconData icon;
    String label;

    switch (status) {
      case 'granted':
        bgColor = const Color(0xFFE8F5E9);
        textColor = const Color(0xFF2E7D32);
        icon = Icons.check_circle_outline;
        label = 'ผู้ป่วยอนุมัติการเข้าถึงข้อมูลสุขภาพแล้ว';
        break;
      case 'denied':
        bgColor = const Color(0xFFFFEBEE);
        textColor = Colors.redAccent;
        icon = Icons.cancel_outlined;
        label = 'ผู้ป่วยปฏิเสธคำขอดูข้อมูลสุขภาพ';
        break;
      default:
        bgColor = Colors.orange.shade50;
        textColor = Colors.orange.shade800;
        icon = Icons.hourglass_top_rounded;
        label = 'รอผู้ป่วยตอบรับคำขอดูข้อมูลสุขภาพ...';
    }

    return Container(
      width: double.infinity,
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
          if (status == 'granted')
            TextButton.icon(
              onPressed: _openGrantedHealthDataSheet,
              style: TextButton.styleFrom(foregroundColor: textColor),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('ดูข้อมูลที่อนุญาต'),
            ),
        ],
      ),
    );
  }

  // State variable to hold current health permission request
  Map<String, dynamic>? _healthPermissionRequest;

  String? _lastShownHealthPermissionRequestId;
  bool _isHealthPermissionDialogOpen = false;

  void _openGrantedHealthDataSheet() {
    if (!_isProvider) return;
    final consultationId = _activeConsultationId;
    final doctorId = _currentUser?.id;
    if (consultationId == null || doctorId == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return FutureBuilder<Map<String, dynamic>>(
          future: _healthPermissionRepository.fetchGrantedHealthData(
            consultationId: consultationId,
            doctorId: doctorId,
            existingRequest: _healthPermissionRequest,
          ),
          builder: (context, snapshot) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.85,
              minChildSize: 0.6,
              builder: (_, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        height: 4,
                        width: 60,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'ข้อมูลสุขภาพของผู้ป่วย',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: snapshot.connectionState != ConnectionState.done
                            ? const Center(child: CircularProgressIndicator())
                            : snapshot.hasError
                                ? _buildHealthDataError(
                                    snapshot.error.toString(),
                                    scrollController,
                                  )
                                : ListView(
                                    controller: scrollController,
                                    padding:
                                        const EdgeInsets.fromLTRB(20, 0, 20, 32),
                                    children: _buildGrantedHealthSections(
                                      snapshot.data ?? const {},
                                    ),
                                  ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildHealthDataError(String message, ScrollController controller) {
    return ListView(
      controller: controller,
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ไม่สามารถโหลดข้อมูลสุขภาพได้',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildGrantedHealthSections(Map<String, dynamic> data) {
    final sections = <Widget>[];
    final granted = data['grantedFields'] as Map<String, dynamic>? ?? {};

    final general = data['general'] as Map<String, dynamic>?;
    if (granted['general'] == true && general != null && general.isNotEmpty) {
      sections.add(
        _buildGrantedSectionCard(
          icon: Icons.favorite_outline,
          title: 'ข้อมูลสุขภาพทั่วไป',
          children: _buildGeneralSectionContent(general),
        ),
      );
    }

    final history = (data['history'] as List?)?.cast<Map<String, dynamic>>();
    if (granted['history'] == true && history != null && history.isNotEmpty) {
      sections.add(
        _buildGrantedSectionCard(
          icon: Icons.event_note,
          title: 'ประวัติการรักษาในคำปรึกษานี้',
          children: history.map(_buildHistoryTile).toList(),
        ),
      );
    }

    final labs = (data['labs'] as Map<String, dynamic>?)?['metrics']
        as Map<String, dynamic>?;
    if (granted['labs'] == true && labs != null && labs.isNotEmpty) {
      sections.add(
        _buildGrantedSectionCard(
          icon: Icons.analytics_outlined,
          title: 'ข้อมูลจากอุปกรณ์สุขภาพ',
          children:
              labs.entries.map((entry) => _buildMetricGroup(entry.key, entry.value)).toList(),
        ),
      );
    }

    final meds = (data['medications'] as List?)?.cast<Map<String, dynamic>>();
    if (granted['medications'] == true && meds != null && meds.isNotEmpty) {
      sections.add(
        _buildGrantedSectionCard(
          icon: Icons.medication_liquid,
          title: 'รายการยาที่สั่งในคำปรึกษานี้',
          children: meds.map(_buildMedicationTile).toList(),
        ),
      );
    }

    if (sections.isEmpty) {
      sections.add(
        Container(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Text(
            'ไม่มีข้อมูลสุขภาพที่สามารถแสดงได้',
            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return sections;
  }

  Widget _buildGrantedSectionCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  List<Widget> _buildGeneralSectionContent(Map<String, dynamic> general) {
    final profile = general['profile'] as Map<String, dynamic>?;
    final healthInfo = general['health_info'] as Map<String, dynamic>?;
    final chips = <Widget>[];

    void addChip(String label, dynamic value, {IconData icon = Icons.info}) {
      if (value == null) return;
      chips.add(_buildHealthDataChip(label, value.toString(), icon: icon));
    }

    addChip(
      'ส่วนสูง',
      healthInfo?['height'] != null ? '${healthInfo!['height']} ซม.' : null,
      icon: Icons.height,
    );
    addChip(
      'น้ำหนัก',
      healthInfo?['weight'] != null ? '${healthInfo!['weight']} กก.' : null,
      icon: Icons.monitor_weight,
    );
    addChip('BMI', healthInfo?['bmi'], icon: Icons.scale);
    addChip('คะแนนสุขภาพ', healthInfo?['health_score'], icon: Icons.favorite);

    final emergencyContact = general['emergency_contact'];
    final emergencyPhone = general['emergency_phone'];

    return [
      if (profile != null)
        Text(
          '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'.trim(),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      if (chips.isNotEmpty) ...[
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: chips,
        ),
      ],
      if (emergencyContact != null || emergencyPhone != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ผู้ติดต่อฉุกเฉิน',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
              ),
              if (emergencyContact != null) Text('ชื่อ: $emergencyContact'),
              if (emergencyPhone != null) Text('โทร: $emergencyPhone'),
            ],
          ),
        ),
      ],
    ];
  }

  Widget _buildHealthDataChip(String label, String value,
      {IconData icon = Icons.info_outline}) {
    return Chip(
      avatar: Icon(icon, size: 16, color: AppColors.primary),
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      backgroundColor: Colors.grey.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      side: BorderSide(color: Colors.grey.shade300),
    );
  }

  Widget _buildHistoryTile(Map<String, dynamic> note) {
    final createdAt = note['created_at'];
    final created = createdAt != null
        ? DateFormat('dd MMM yyyy HH:mm')
            .format(DateTime.parse(createdAt).toLocal())
        : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'บันทึกเมื่อ $created',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          if (note['chief_complaint'] != null) ...[
            const SizedBox(height: 6),
            Text('อาการสำคัญ: ${note['chief_complaint']}'),
          ],
          if (note['diagnosis'] != null) ...[
            const SizedBox(height: 4),
            Text('การวินิจฉัย: ${note['diagnosis']}'),
          ],
          if (note['treatment_plan'] != null) ...[
            const SizedBox(height: 4),
            Text('แผนการรักษา: ${note['treatment_plan']}'),
          ],
          if (note['recommendations'] != null) ...[
            const SizedBox(height: 4),
            Text('คำแนะนำ: ${note['recommendations']}'),
          ],
        ],
      ),
    );
  }

  static const _metricNameTh = <String, String>{
    'active_calories': 'แคลอรีที่เผาผลาญ',
    'heart_rate': 'อัตราการเต้นของหัวใจ',
    'hrv_sdnn': 'ความแปรปรวนอัตราหัวใจ (HRV)',
    'steps': 'จำนวนก้าว',
    'sleep_duration': 'ระยะเวลาการนอน',
    'blood_oxygen': 'ความอิ่มตัวออกซิเจนในเลือด (SpO₂)',
    'blood_pressure_systolic': 'ความดันโลหิตตัวบน',
    'blood_pressure_diastolic': 'ความดันโลหิตตัวล่าง',
    'body_temperature': 'อุณหภูมิร่างกาย',
    'weight': 'น้ำหนัก',
    'bmi': 'ดัชนีมวลกาย (BMI)',
    'respiratory_rate': 'อัตราการหายใจ',
    'distance': 'ระยะทาง',
    'floors_climbed': 'จำนวนชั้นที่ขึ้น',
    'exercise_minutes': 'นาทีออกกำลังกาย',
    'resting_heart_rate': 'อัตราหัวใจขณะพัก',
    'vo2_max': 'VO₂ Max',
    'glucose': 'ระดับน้ำตาลในเลือด',
  };

  String _formatMetricValue(dynamic raw) {
    if (raw == null) return '-';
    if (raw is num) {
      if (raw == raw.truncate()) return raw.truncate().toString();
      return raw.toStringAsFixed(2);
    }
    final parsed = double.tryParse(raw.toString());
    if (parsed == null) return raw.toString();
    if (parsed == parsed.truncate()) return parsed.truncate().toString();
    return parsed.toStringAsFixed(2);
  }

  Widget _buildMetricGroup(String metricType, dynamic entries) {
    final list = (entries as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (list.isEmpty) return const SizedBox.shrink();
    final displayName =
        _metricNameTh[metricType] ?? metricType.replaceAll('_', ' ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          ...list.take(3).map((item) {
            final measured = item['measured_at'] != null
                ? DateFormat('dd MMM HH:mm')
                    .format(DateTime.parse(item['measured_at']).toLocal())
                : '';
            final unit = item['unit'] ?? '';
            final value = _formatMetricValue(item['value']);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$value $unit',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    measured,
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMedicationTile(Map<String, dynamic> prescription) {
    final created = prescription['issued_at'] != null
        ? DateFormat('dd MMM yyyy HH:mm')
            .format(DateTime.parse(prescription['issued_at']).toLocal())
        : '';
    final meds = (prescription['medications'] as List?) ?? [];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ออกเมื่อ $created',
            style: TextStyle(color: Colors.green.shade900, fontSize: 12),
          ),
          const SizedBox(height: 6),
          ...meds.take(4).map((item) {
            final med = item as Map<String, dynamic>;
            final name = med['name'] ?? '-';
            final dose = med['dose'] ?? '';
            final freq = med['frequency'] ?? '';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('$name  $dose  $freq'),
            );
          }),
          if (prescription['notes'] != null) ...[
            const Divider(),
            Text('คำแนะนำ: ${prescription['notes']}'),
          ],
        ],
      ),
    );
  }

  void _startHealthPermissionPolling() {
    if (!_isProvider) return;
    _healthPermissionPollTimer?.cancel();
    _healthPermissionPollTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) async {
        if (!mounted || !_isProvider) return;
        final consultationId = _activeConsultationId;
        final doctorId = _currentUser?.id;
        if (consultationId == null || doctorId == null) return;

        final latest = await _healthPermissionRepository.getLatestRequest(
          consultationId: consultationId,
          doctorId: doctorId,
        );
        if (!mounted || latest == null) return;

        final prevStatus = _healthPermissionRequest?['status'];
        final newStatus = latest['status'];
        if (prevStatus == newStatus) return;

        setState(() => _healthPermissionRequest = latest);

        if (newStatus == 'granted' && prevStatus == 'pending') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ ผู้ป่วยอนุมัติการเข้าถึงข้อมูลสุขภาพแล้ว'),
              backgroundColor: Color(0xFF4A8B2C),
            ),
          );
        } else if (newStatus == 'denied' && prevStatus == 'pending') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ ผู้ป่วยปฏิเสธคำขอดูข้อมูลสุขภาพ'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      },
    );
  }

  // Real-time channel for health permission updates
  RealtimeChannel? _healthPermissionChannel;

  Future<void> _loadLatestHealthPermission() async {
    final consultationId = _activeConsultationId;
    if (consultationId == null) return;

    Map<String, dynamic>? existing;
    if (_isProvider) {
      final providerId = _currentUser?.id;
      if (providerId == null) return;
      existing = await _healthPermissionRepository.getLatestRequest(
        consultationId: consultationId,
        doctorId: providerId,
      );
    } else {
      final patientId = widget.entry?.patientId ?? widget.request?.userId;
      if (patientId == null) return;
      existing = await _healthPermissionRepository.getPendingForPatient(
        consultationId: consultationId,
        patientId: patientId,
      );
    }

    if (mounted) {
      setState(() => _healthPermissionRequest = existing);
    }

    if (!mounted || _isProvider || existing == null) return;

    final requestId = existing['id']?.toString();
    final status = existing['status']?.toString();
    if (status == 'pending' &&
        requestId != null &&
        requestId != _lastShownHealthPermissionRequestId) {
      _lastShownHealthPermissionRequestId = requestId;
      final pendingRequest = Map<String, dynamic>.from(existing);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isProvider) {
          _showHealthPermissionDialog(pendingRequest);
        }
      });
    }
  }

  // Request health data permission from patient (provider action)
  void _requestHealthDataPermission() async {
    final providerId = _currentUser?.id;
    final patientId = widget.entry?.patientId ?? widget.request?.userId;
    final consultationId = _activeConsultationId;
    if (providerId == null || patientId == null || consultationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่พบข้อมูลคำปรึกษาหรือผู้ใช้งาน'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      setState(() {
        _healthPermissionRequest = {
          'consultation_id': consultationId,
          'doctor_id': providerId,
          'doctor_name': _currentUser?.fullName ?? 'Doctor',
          'patient_id': patientId,
          'status': 'pending',
          'granted_fields': const {
            'general': true,
            'history': true,
            'labs': true,
            'medications': true,
          },
        };
      });

      final response = await _healthPermissionRepository.requestPermission(
        consultationId: consultationId,
        doctorId: providerId,
        patientId: patientId,
        doctorName: _currentUser?.fullName ?? 'Doctor',
        requestedFields: const {
          'general': true,
          'history': true,
          'labs': true,
          'medications': true,
        },
      );
      if (mounted) {
        setState(() {
          _healthPermissionRequest = response;
        });
        messenger.showSnackBar(
          const SnackBar(
            content: Text('ส่งคำขอสิทธิ์ดูข้อมูลสุขภาพแล้ว รอผู้ป่วยอนุมัติ'),
            backgroundColor: Color(0xFF4A8B2C),
          ),
        );
      }
    } catch (e) {
      debugPrint('[HealthPerm] Error creating request: $e');
      if (mounted) {
        await _loadLatestHealthPermission();
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('ส่งคำขอไม่สำเร็จ: กรุณาลองใหม่อีกครั้ง'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // Subscribe to real-time health permission updates (for patient side)
  void _subscribeHealthPermissionUpdates() {
    final currentUserId = _currentUser?.id;
    if (currentUserId == null) return;

    _healthPermissionChannel?.unsubscribe();
    _healthPermissionChannel = null;

    // Patient listens for incoming requests addressed to them
    _healthPermissionChannel = Supabase.instance.client
        .channel('health_perm_$currentUserId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'health_data_permission_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'patient_id',
            value: currentUserId,
          ),
          callback: (payload) {
            debugPrint('[HealthPerm] Realtime INSERT received: ${payload.newRecord}');
            final newRecord = payload.newRecord;
            if (mounted && newRecord != null) {
              setState(() {
                _healthPermissionRequest = newRecord;
              });
              _maybeShowHealthPermissionDialog(newRecord);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'health_data_permission_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'doctor_id',
            value: currentUserId,
          ),
          callback: (payload) {
            debugPrint('[HealthPerm] Realtime UPDATE received: ${payload.newRecord}');
            final updated = payload.newRecord;
            if (mounted && updated != null) {
              setState(() {
                _healthPermissionRequest = updated;
              });
              _maybeShowHealthPermissionDialog(updated);
              // Notify doctor that patient responded
              final status = updated['status'];
              if (_isProvider && status == 'granted') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ ผู้ป่วยอนุมัติการเข้าถึงข้อมูลสุขภาพแล้ว'),
                    backgroundColor: Color(0xFF4A8B2C),
                  ),
                );
              } else if (_isProvider && status == 'denied') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('❌ ผู้ป่วยปฏิเสธคำขอดูข้อมูลสุขภาพ'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            }
          },
        )
        .subscribe();
    debugPrint('[HealthPerm] Subscribed to realtime channel for user=$currentUserId');
  }

  void _maybeShowHealthPermissionDialog(Map<String, dynamic> request) {
    if (_isProvider) return;
    final requestId = request['id']?.toString();
    final status = request['status']?.toString();
    if (requestId == null || status != 'pending') return;
    if (_isHealthPermissionDialogOpen ||
        requestId == _lastShownHealthPermissionRequestId) {
      return;
    }

    _lastShownHealthPermissionRequestId = requestId;
    _isHealthPermissionDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _isProvider) {
        _isHealthPermissionDialogOpen = false;
        return;
      }
      try {
        await _showHealthPermissionDialog(request);
      } finally {
        _isHealthPermissionDialogOpen = false;
      }
    });
  }

  // Show permission dialog for patient to grant/deny fields
  Future<void> _showHealthPermissionDialog(Map<String, dynamic> request) async {
    final defaultFields = {
      'general': true,
      'history': true,
      'labs': true,
      'medications': true,
    };
    final grantedFromRequest = request['granted_fields'] as Map<String, dynamic>?;
    Map<String, bool> fields = grantedFromRequest != null
        ? grantedFromRequest.map((key, value) => MapEntry(key, value == true))
        : Map<String, bool>.from(defaultFields);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Wrap(
                children: [
                  const ListTile(
                    title: Text('อนุญาตดูข้อมูลสุขภาพ'),
                  ),
                  SwitchListTile(
                    title: const Text('ข้อมูลทั่วไป'),
                    value: fields['general']!,
                    onChanged: (v) => setState(() => fields['general'] = v),
                  ),
                  SwitchListTile(
                    title: const Text('ประวัติการรักษา'),
                    value: fields['history']!,
                    onChanged: (v) => setState(() => fields['history'] = v),
                  ),
                  SwitchListTile(
                    title: const Text('ผลแลบ'),
                    value: fields['labs']!,
                    onChanged: (v) => setState(() => fields['labs'] = v),
                  ),
                  SwitchListTile(
                    title: const Text('ยาที่กำหนด'),
                    value: fields['medications']!,
                    onChanged: (v) => setState(() => fields['medications'] = v),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () async {
                              final granted = fields.map((k, v) => MapEntry(k, v));
                              await _healthPermissionRepository.respondPermission(
                                requestId: request['id'] as String,
                                granted: true,
                                grantedFields: granted,
                              );
                              if (mounted) {
                                setState(() {
                                  _healthPermissionRequest = null;
                                });
                              }
                              Navigator.pop(context);
                            },
                            child: const Text('ยอมให้'),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            await _healthPermissionRepository.respondPermission(
                              requestId: request['id'] as String,
                              granted: false,
                              grantedFields: fields,
                            );
                            if (mounted) {
                              setState(() {
                                _healthPermissionRequest = null;
                              });
                            }
                            Navigator.pop(context);
                          },
                          child: const Text('ปฏิเสธ'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildChatInput() {
    final hasText = _msgController.text.trim().isNotEmpty;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Opacity(
            opacity: (_isConsultationActive || _isProvider) ? 1.0 : 0.3,
            child: AbsorbPointer(
              absorbing: !(_isConsultationActive || _isProvider),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (_isProvider) ...[
                    _buildInputIconButton(
                      icon: Icons.attach_file,
                      tooltip: 'เครื่องมือแพทย์',
                      onTap: _showAttachmentMenu,
                    ),
                    const SizedBox(width: 4),
                    // Removed lock_open button from chat input row for providers. The request button will be placed within the attachment menu.

                  ] else ...[
                    _buildInputIconButton(
                      icon: Icons.image_outlined,
                      tooltip: 'ส่งรูปภาพ',
                      onTap: _pickAndSendImage,
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Text input
                  Expanded(
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: const Color(0xFF4A8B2C).withOpacity(0.3),
                          width: 1.5,
                        ),
                      ),
                      child: TextField(
                        controller: _msgController,
                        style:
                            const TextStyle(color: Colors.black87, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'ถามผู้เชี่ยวชาญ...',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Send / Mic button
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, anim) =>
                        ScaleTransition(scale: anim, child: child),
                    child: hasText
                        ? _buildActionButton(
                            key: const ValueKey('send'),
                            icon: Icons.send_rounded,
                            color: Colors.white,
                            bgColor: const Color(0xFF4A8B2C),
                            onTap: _sendMessage,
                            isLoading: _isSending,
                          )
                        : GestureDetector(
                            key: const ValueKey('mic'),
                            onLongPressStart: (_) => _startRecording(),
                            onLongPressEnd: (_) => _stopRecording(),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              height: 44,
                              width: 44,
                              decoration: BoxDecoration(
                                color: _isRecording
                                    ? Colors.redAccent
                                    : const Color(0xFF4A8B2C),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: (_isRecording
                                            ? Colors.redAccent
                                            : const Color(0xFF4A8B2C))
                                        .withOpacity(0.3),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Icon(
                                _isRecording ? Icons.stop_rounded : Icons.mic,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),

          // Lock Overlay for patients before payment
          if (!_isConsultationActive && !_isProvider)
            Positioned.fill(
              child: Container(
                color: Colors.white.withOpacity(0.1),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline, size: 14, color: Colors.orange.shade800),
                        const SizedBox(width: 6),
                        Text(
                          'กดยืนยันเพื่อเริ่มต้นการแชท',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.bold,
                          ),
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

  Widget _buildInputIconButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip ?? '',
        child: Container(
          height: 38,
          width: 38,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Icon(icon, color: Colors.grey.shade700, size: 20),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required Key key,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        height: 44,
        width: 44,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: bgColor.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: isLoading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Icon(icon, color: color, size: 20),
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
        widget.request?.symptomsChart ?? {},
      );
      finalSymptomsChart['pain_level'] = _selectedPain;

      // 2. Save to Repository
      final repo = ServiceLocator.instance.consultationRepository;
      final newRequest = await repo.createRequest(
        userId: currentUserId,
        packageId: widget.request?.packageId ?? '',
        packageName: widget.request?.packageName ?? '',
        price: widget.request?.price ?? 0,
        bodyArea: widget.request?.bodyArea ?? {},
        symptomsChart: finalSymptomsChart,
        symptoms: widget.request?.symptoms ?? [],
      );

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
          _activeConsultationId = newRequest.id;
          _isConsultationActive = true;
          _isHeaderExpanded = false;
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

  Widget _buildPrescriptionCard(ChatMessage message) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.medication, color: Colors.blue, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ใบสั่งยา',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.blue,
                      ),
                    ),
                    Text(
                      'Prescription',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          Text(
            message.content,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _viewPrescriptionDetails(message.attachmentUrl),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              child: const Text(
                'ข้อมูลที่อนุญาต',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(ChatMessage message) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.assignment, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'สรุปผลการตรวจ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      'Consultation Note',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          Text(
            message.content,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _viewSummaryDetails(message.attachmentUrl),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              child: const Text(
                'ข้อมูลที่อนุญาต',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
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

  Widget _buildTimerBadge() {
    final bool isLowTime = _remainingSeconds < 300 && _isTimerRunning;
    final bool isWaiting = !_isTimerRunning && _remainingSeconds > 0;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isWaiting 
            ? Colors.orange.shade50 
            : (isLowTime ? Colors.red.shade50 : AppColors.primary.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isWaiting 
              ? Colors.orange.withOpacity(0.3)
              : (isLowTime ? Colors.red.withOpacity(0.3) : AppColors.primary.withOpacity(0.3)),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isWaiting)
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, valueColor: AlwaysStoppedAnimation<Color>(Colors.orange)),
            )
          else
            Icon(
              Icons.timer_outlined,
              size: 14,
              color: isLowTime ? Colors.red : AppColors.primary,
            ),
          const SizedBox(width: 6),
          Text(
            isWaiting ? 'รอเริ่ม...' : _formatTimer(_remainingSeconds),
            style: TextStyle(
              color: isWaiting ? Colors.orange.shade800 : (isLowTime ? Colors.red : AppColors.primary),
              fontSize: 13,
              fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isProvider)
          TextButton.icon(
            onPressed: _showFinishDialog,
            icon: const Icon(Icons.done_all, color: AppColors.primary, size: 18),
            label: const Text('จบงาน', style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        IconButton(
          icon: const Icon(Icons.videocam_outlined, color: AppColors.primary),
          onPressed: _startVideoCall,
        ),
        IconButton(
          icon: const Icon(Icons.info_outline, color: Colors.grey),
          onPressed: _showConsultationDetails,
        ),
        const SizedBox(width: 4),
      ],
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
        _requestHealthDataPermission();
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




  Future<void> _showQuickReplies() async {
    final providerId = _currentUser?.id;
    if (providerId == null) return;

    List<String> templates = [];

    // Show loading indicator if needed (optional)
    
    try {
      final data = await Supabase.instance.client
          .from('doctor_quick_replies')
          .select()
          .eq('provider_id', providerId)
          .order('sort_order');
          
      templates = (data as List).map((e) => e['content'] as String).toList();
    } catch (e) {
      debugPrint('Error fetching quick replies: $e');
      // Fallback if table doesn't exist or fails
    }

    if (templates.isEmpty) {
      templates = [
        'สวัสดีครับ หมอรับเคสแล้วครับ',
        'กรุณาส่งรูปภาพบริเวณที่มีอาการครับ',
        'พบอาการมานานเท่าไรแล้วครับ?',
        'มีประวัติแพ้ยาอะไรไหมครับ?',
        'ขอบคุณสำหรับข้อมูลครับ หมอกำลังพิจารณาการรักษา',
      ];
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.6,
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ข้อความตอบกลับด่วน', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: templates.map((txt) => ListTile(
                          leading: const Icon(Icons.flash_on, color: Colors.amber),
                          title: Text(txt),
                          onTap: () {
                            Navigator.pop(ctx);
                            _sendSpecialMessage('text', txt);
                          },
                        )).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
          _buildDetailRow('อาการเบื้องต้น', widget.entry?.bodyArea ?? widget.request?.bodyArea['label'] ?? 'ไม่ระบุ'),
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
                widget.entry?.bodyArea ?? "ระบุบริเวณร่างกาย",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpertStatusBanner() {
    final hasWaitingRequired = _expertStatuses.any((e) => (e['isRequired'] == true) && (e['status'] == 'waiting'));
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasWaitingRequired ? Icons.info_outline : Icons.groups_outlined, 
                size: 16, 
                color: hasWaitingRequired ? Colors.orange : Colors.grey
              ),
              const SizedBox(width: 8),
              Text(
                hasWaitingRequired 
                    ? 'รอผู้เชี่ยวชาญที่จำเป็นเข้าร่วมเพื่อเริ่มนับเวลา' 
                    : 'ทีมผู้เชี่ยวชาญในเซสชั่นนี้',
                style: TextStyle(
                  color: hasWaitingRequired ? Colors.orange.shade800 : Colors.grey.shade600, 
                  fontSize: 12, 
                  fontWeight: FontWeight.w500
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _expertStatuses.map((expert) {
                final isJoined = expert['status'] == 'joined';
                final isRequired = expert['isRequired'] == true;
                
                return Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isJoined 
                        ? AppColors.primary.withOpacity(0.08) 
                        : (isRequired ? Colors.orange.shade50 : Colors.grey.shade50),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isJoined 
                          ? AppColors.primary.withOpacity(0.2) 
                          : (isRequired ? Colors.orange.withOpacity(0.2) : Colors.grey.shade200),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isJoined ? Icons.check_circle : (isRequired ? Icons.priority_high : Icons.hourglass_empty),
                        size: 14,
                        color: isJoined ? AppColors.primary : (isRequired ? Colors.orange : Colors.grey),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        expert['name'] + (isRequired ? ' *' : ''),
                        style: TextStyle(
                          color: isJoined ? AppColors.primary : (isRequired ? Colors.orange.shade700 : Colors.grey.shade600),
                          fontSize: 12,
                          fontWeight: isJoined || isRequired ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBodyMapSummary() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade50, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.analytics_outlined, color: Colors.orange, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'สรุปอาการจาก Body Map',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.entry?.bodyArea ?? widget.request?.bodyArea['label'] ?? "กำลังประมวลผลข้อมูลอาการ...",
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.orange),
        ],
      ),
    );
  }

  Widget _buildReviewCard() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            '⭐ ให้คะแนนการปรึกษา',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'ความพึงพอใจของคุณช่วยพัฒนาบริการของเรา',
            style: TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              5,
              (i) => Icon(Icons.star_border_rounded,
                  color: Colors.amber.shade400, size: 32),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: const Text('ส่งคะแนน'),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────
// Mini Voice Player
// ────────────────────────────────────────────

class _MiniVoicePlayer extends StatefulWidget {
  final String url;
  final bool isMe;
  const _MiniVoicePlayer({required this.url, required this.isMe});

  @override
  State<_MiniVoicePlayer> createState() => _MiniVoicePlayerState();
}

class _MiniVoicePlayerState extends State<_MiniVoicePlayer> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
    _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _audioPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted)
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.isMe ? Colors.black87 : Colors.white;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () async {
            if (_isPlaying) {
              await _audioPlayer.pause();
            } else {
              await _audioPlayer.play(UrlSource(widget.url));
            }
          },
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: (widget.isMe ? Colors.black : Colors.white).withOpacity(
                0.15,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              color: iconColor,
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: LinearProgressIndicator(
                value: _duration.inMilliseconds > 0
                    ? _position.inMilliseconds / _duration.inMilliseconds
                    : 0.0,
                backgroundColor: iconColor.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                minHeight: 3,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              _fmt(_isPlaying ? _position : _duration),
              style: TextStyle(fontSize: 9, color: iconColor.withOpacity(0.7)),
            ),
          ],
        ),
      ],
    );
  }

}
