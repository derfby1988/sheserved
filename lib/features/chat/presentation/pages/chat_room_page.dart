import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/service_locator.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/models/chat_models.dart';
import 'package:uuid/uuid.dart';
import '../../../../services/auth_service.dart';
import '../../../../features/consultation/presentation/pages/consultation_note_editor_page.dart';
import '../../../../features/consultation/presentation/pages/prescription_editor_page.dart';
import '../../../../features/consultation/presentation/pages/prescription_choice_page.dart';
import '../widgets/expert_group_status_banner.dart';
import '../widgets/session_timer_widget.dart';

class ChatRoomPage extends StatefulWidget {
  final String roomId;
  const ChatRoomPage({super.key, required this.roomId});

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final _chatRepository = ServiceLocator.instance.chatRepository;
  final _healthPermissionRepository =
      ServiceLocator.instance.healthDataPermissionRepository;
  final _currentUser = ServiceLocator.instance.currentUser;
  final _webSocketService = ServiceLocator.instance.websocketService;
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  StreamSubscription? _callInviteSub;
  StreamSubscription? _callAcceptSub;
  RealtimeChannel? _healthPermissionChannel;

  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  List<ChatParticipant> _otherParticipants = [];
  bool _isOtherTyping = false;
  Timer? _typingTimer;
  Timer? _healthPermissionPollTimer;

  final _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordingPath;

  StreamSubscription<ChatRoom?>? _roomSub;
  ChatRoom? _currentRoom;
  bool get _isProvider => AuthService.instance.currentUser?.isProvider ?? false;

  Map<String, dynamic>? _healthPermissionRequest;
  String? _lastShownHealthPermissionRequestId;
  bool _isHealthPermissionDialogOpen = false;

  String? get _consultationId {
    final roomId = widget.roomId;
    if (roomId.startsWith('consult_')) {
      return roomId.substring('consult_'.length);
    }
    return roomId.isEmpty ? null : roomId;
  }

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _loadLatestHealthPermission();
    _subscribeHealthPermissionUpdates();
    _startHealthPermissionPolling();
    _listenForCalls();

    _roomSub = _chatRepository.streamRoom(widget.roomId).listen((room) {
      if (mounted && room != null) {
        setState(() => _currentRoom = room);
      }
    });
  }

  Future<void> _loadInitialData() async {
    // 1. Load messages
    final msgs = await _chatRepository.getMessages(widget.roomId);

    // 2. Fetch other participants info
    final rooms = await _chatRepository.getChatRooms(_currentUser?.id ?? '');
    final room = rooms.firstWhere((r) => r.id == widget.roomId);
    final otherIds = room.participantIds
        .where((id) => id != _currentUser?.id)
        .toList();

    final infos = <ChatParticipant>[];
    for (var id in otherIds) {
      final info = await _chatRepository.getParticipantInfo(id);
      if (info != null) infos.add(info);
    }

    if (mounted) setState(() => _otherParticipants = infos);

    if (mounted) {
      setState(() {
        _messages = msgs;
        _isLoading = false;
      });
      _scrollToBottom();
      _markMessagesAsRead(msgs);
    }
  }

  Future<void> _loadLatestHealthPermission() async {
    if (_isProvider) return;
    final consultationId = _consultationId;
    final patientId = _currentUser?.id;
    if (consultationId == null || patientId == null) return;

    final existing = await _healthPermissionRepository.getPendingForPatient(
      consultationId: consultationId,
      patientId: patientId,
    );

    if (!mounted) return;
    setState(() => _healthPermissionRequest = existing);
    if (existing != null) {
      debugPrint('[HealthPerm][ChatRoom] Loaded pending request: $existing');
      _maybeShowHealthPermissionDialog(existing);
    }
  }

  void _startHealthPermissionPolling() {
    if (_isProvider) return;
    _healthPermissionPollTimer?.cancel();
    _healthPermissionPollTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) {
        if (!mounted || _isProvider) return;
        _loadLatestHealthPermission();
      },
    );
  }

  void _subscribeHealthPermissionUpdates() {
    if (_isProvider) return;
    final currentUserId = _currentUser?.id;
    if (currentUserId == null) return;

    _healthPermissionChannel?.unsubscribe();
    _healthPermissionChannel = Supabase.instance.client
        .channel('health_perm_chat_$currentUserId')
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
            final newRecord = payload.newRecord;
            debugPrint('[HealthPerm][ChatRoom] INSERT: $newRecord');
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
            column: 'patient_id',
            value: currentUserId,
          ),
          callback: (payload) {
            final updated = payload.newRecord;
            debugPrint('[HealthPerm][ChatRoom] UPDATE: $updated');
            if (mounted && updated != null) {
              setState(() {
                _healthPermissionRequest = updated;
              });
              _maybeShowHealthPermissionDialog(updated);
            }
          },
        )
        .subscribe();

    debugPrint('[HealthPerm][ChatRoom] Subscribed for patient=$currentUserId');
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
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
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

  void _markMessagesAsRead(List<ChatMessage> messages) {
    final user = _currentUser;
    if (user == null) return;
    for (var msg in messages) {
      if (msg.senderId != user.id && !msg.readBy.containsKey(user.id)) {
        _chatRepository.markMessageAsRead(msg.id, user.id);
      }
    }
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
    // บังคับถ่ายรูปจากกล้องตามข้อกำหนด PDPA (Camera Only)
    final image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );

    final user = _currentUser;
    if (image != null && user != null) {
      File file = File(image.path);

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

      try {
        file = await _processImagePDPA(file);
      } catch (e) {
        debugPrint('PDPA process error: $e');
      }

      final url = await _chatRepository.uploadFile(
        file,
        'chat/${widget.roomId}',
      );

      if (!mounted) return;
      Navigator.pop(context); // Close dialog

      if (url != null) {
        final newMessage = ChatMessage(
          id: const Uuid().v4(),
          roomId: widget.roomId,
          senderId: user.id,
          content: '[รูปภาพ]',
          createdAt: DateTime.now(),
          type: 'image',
          attachmentUrl: url,
          attachmentType: 'image/jpeg',
          status: MessageStatus.sent,
        );

        final success = await _chatRepository.sendMessage(newMessage);
        if (!success && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('ส่งรูปภาพไม่สำเร็จ')));
        }
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('อัปโหลดรูปภาพไม่สำเร็จ')));
      }
    }
  }

  void _listenForCalls() {
    _callInviteSub = _webSocketService.callInviteStream.listen((data) {
      if (data['roomId'] == widget.roomId &&
          data['callerId'] != _currentUser?.id) {
        _showIncomingCallDialog(data);
      }
    });

    _callAcceptSub = _webSocketService.callAcceptStream.listen((data) {
      final otherParticipant = _otherParticipants.isNotEmpty
          ? _otherParticipants.first
          : null;
      if (data['roomId'] == widget.roomId &&
          data['calleeId'] == otherParticipant?.id) {
        // Navigate to LiveVdoPage as caller
        if (!mounted) return;
        Navigator.pushNamed(
          context,
          '/live-vdo',
          arguments: {
            'roomId': widget.roomId,
            'isCaller': true,
            'otherParticipantName': otherParticipant?.firstName ?? 'Expert',
          },
        );
      }
    });
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        _recordingPath =
            '${directory.path}/record_${DateTime.now().millisecondsSinceEpoch}.m4a';

        const config = RecordConfig();
        await _audioRecorder.start(config, path: _recordingPath!);

        setState(() => _isRecording = true);
      }
    } catch (e) {
      debugPrint('Error starting record: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      setState(() => _isRecording = false);

      final user = _currentUser;
      if (path != null && user != null) {
        final file = File(path);

        // Upload to Supabase
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('กำลังส่งข้อความเสียง...')),
        );

        final url = await _chatRepository.uploadFile(
          file,
          'chat/${widget.roomId}',
        );

        if (url != null) {
          final newMessage = ChatMessage(
            id: const Uuid().v4(),
            roomId: widget.roomId,
            senderId: user.id,
            content: '[ข้อความเสียง]',
            createdAt: DateTime.now(),
            type: 'voice',
            attachmentUrl: url,
            attachmentType: 'audio/m4a',
            status: MessageStatus.sent,
          );

          await _chatRepository.sendMessage(newMessage);
        }
      }
    } catch (e) {
      debugPrint('Error stopping record: $e');
    }
  }

  void _showMedicalToolsBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'เครื่องมือแพทย์',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_document, color: Colors.blue),
                title: const Text('บันทึกการตรวจ (Consultation Note)'),
                subtitle: const Text('สรุปอาการ แผนการรักษา และนัดหมาย'),
                onTap: () {
                  Navigator.pop(context);
                  _openConsultationNoteEditor();
                },
              ),
              ListTile(
                leading: const Icon(Icons.medication, color: Colors.green),
                title: const Text('ออกใบสั่งยา (Prescription)'),
                subtitle: const Text('สั่งจ่ายยาให้คนไข้'),
                onTap: () {
                  Navigator.pop(context);
                  _openPrescriptionEditor();
                },
              ),
              ListTile(
                leading: const Icon(Icons.quickreply, color: Colors.orange),
                title: const Text('ข้อความตอบกลับด่วน (Quick Reply)'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Show quick replies
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _openConsultationNoteEditor() {
    final patientId =
        _currentRoom?.participantIds.firstWhere(
          (id) => id != _currentUser?.id,
          orElse: () => '',
        ) ??
        '';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConsultationNoteEditorPage(
          consultationId: widget
              .roomId, // Assuming roomId represents consultation request context for now
          patientId: patientId,
        ),
      ),
    );
  }

  void _openPrescriptionEditor() {
    final patientId =
        _currentRoom?.participantIds.firstWhere(
          (id) => id != _currentUser?.id,
          orElse: () => '',
        ) ??
        '';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PrescriptionEditorPage(
          consultationId: widget
              .roomId, // Assuming roomId represents consultation request context for now
          patientId: patientId,
        ),
      ),
    );
  }

  void _showIncomingCallDialog(Map<String, dynamic> data) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('สายเรียกเข้า'),
        content: Text('${data['callerName']} กำลังเรียกวิดีโอ...'),
        actions: [
          TextButton(
            onPressed: () {
              _webSocketService.rejectCall(widget.roomId, _currentUser!.id);
              Navigator.pop(context);
            },
            child: const Text('ปฏิเสธ', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              _webSocketService.acceptCall(widget.roomId, _currentUser!.id);
              Navigator.pop(context);
              Navigator.pushNamed(
                context,
                '/live-vdo',
                arguments: {
                  'roomId': widget.roomId,
                  'isCaller': false,
                  'otherParticipantName': data['callerName'],
                },
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('รับสาย'),
          ),
        ],
      ),
    );
  }

  void _startVideoCall() {
    final otherParticipant = _otherParticipants.isNotEmpty
        ? _otherParticipants.first
        : null;
    final user = _currentUser;
    if (user == null || otherParticipant == null) return;

    // We get profile details from AuthService directly
    final currentProfile = AuthService.instance.currentUser;
    final fullName = currentProfile != null
        ? '${currentProfile.firstName} ${currentProfile.lastName}'
        : 'User';
    final profileImageUrl = currentProfile?.profileImageUrl ?? '';

    _webSocketService.sendCallInvite(
      widget.roomId,
      user.id,
      fullName,
      profileImageUrl,
    );

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('กำลังเรียกสาย...')));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final user = _currentUser;
    if (_msgController.text.trim().isEmpty || user == null) return;

    final content = _msgController.text.trim();
    _msgController.clear();

    final newMessage = ChatMessage(
      id: const Uuid().v4(),
      roomId: widget.roomId,
      senderId: user.id,
      content: content,
      createdAt: DateTime.now(),
      status: MessageStatus.sent,
    );

    final success = await _chatRepository.sendMessage(newMessage);
    if (!success && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ส่งข้อความไม่สำเร็จ')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white24,
                  backgroundImage:
                      (_otherParticipants.isNotEmpty &&
                          _otherParticipants.first.profileImageUrl != null)
                      ? NetworkImage(_otherParticipants.first.profileImageUrl!)
                      : null,
                  child:
                      (_otherParticipants.isEmpty ||
                          _otherParticipants.first.profileImageUrl == null)
                      ? const Icon(Icons.group, color: Colors.white, size: 20)
                      : null,
                ),
                if (_otherParticipants.length == 1 &&
                    (_otherParticipants.first.isOnline ||
                        _otherParticipants.first.isBusy))
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _otherParticipants.first.isBusy
                            ? Colors.orange
                            : Colors.greenAccent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _otherParticipants.length > 1
                        ? 'แชทกลุ่ม (${_otherParticipants.length + 1})'
                        : _otherParticipants.isNotEmpty
                        ? _otherParticipants.first.fullName
                        : 'Expert Chat',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _isOtherTyping
                        ? 'ใครบางคนกำลังพิมพ์...'
                        : _otherParticipants.length > 1
                        ? _otherParticipants.map((p) => p.firstName).join(', ')
                        : _otherParticipants.isNotEmpty
                        ? (_otherParticipants.first.isOnline
                              ? 'พร้อมให้บริการ'
                              : (_otherParticipants.first.isBusy
                                    ? 'ไม่ว่าง'
                                    : 'ออฟไลน์'))
                        : 'กำลังโหลด...',
                    style: TextStyle(
                      fontSize: 11,
                      color: _isOtherTyping
                          ? Colors.white
                          : (_otherParticipants.isNotEmpty &&
                                    _otherParticipants.first.isOnline
                                ? Colors.greenAccent
                                : Colors.white70),
                      fontStyle: _isOtherTyping
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_currentRoom?.roomType == 'consultation' &&
              _currentRoom?.startedAt != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: SessionTimerWidget(
                  startedAt: _currentRoom!.startedAt!,
                  sessionMinutes: _currentRoom!.sessionMinutes ?? 15,
                  onExpire: () {
                    // Lock room if expired
                    if (_currentRoom!.isActive) {
                      // Call RPC to end session or just setState if we have a local flag
                      // (The server cron will actually do it, but we lock UI immediately)
                    }
                  },
                ),
              ),
            ),
          IconButton(
            onPressed: _startVideoCall,
            icon: const Icon(Icons.videocam),
            tooltip: 'วิดีโอคอล',
          ),
          IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert)),
        ],
        backgroundColor: AppColors.primary,
        elevation: 0,
      ),
      body: Column(
        children: [
          if (_currentRoom != null)
            ExpertGroupStatusBanner(
              room: _currentRoom!,
              isProvider: _isProvider,
              onAbandon: () async {
                if (_currentRoom?.consultationId == null ||
                    _currentUser == null)
                  return;
                try {
                  await ServiceLocator.instance.consultationRepository
                      .abandonProviderFromGroup(
                        consultationId: _currentRoom!.consultationId!,
                        providerId: _currentUser!.id,
                      );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('สละสิทธิ์สำเร็จ โควต้าถูกคืนแล้ว'),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
            ),
          if (_healthPermissionRequest != null &&
              _healthPermissionRequest!['status'] == 'pending' &&
              !_isProvider)
            Container(
              width: double.infinity,
              color: Colors.orange.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'แพทย์ ${_healthPermissionRequest!['doctor_name'] ?? 'Doctor'} ขอสิทธิ์ดูข้อมูลสุขภาพ',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        _showHealthPermissionDialog(_healthPermissionRequest!),
                    child: const Text('ข้อมูลที่อนุญาต'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                StreamBuilder<List<ChatMessage>>(
                  stream: _chatRepository.streamMessages(widget.roomId),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      _messages = snapshot.data!;
                      _scrollToBottom();
                      _markMessagesAsRead(_messages);
                    }

                    if (_isLoading && _messages.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 20,
                      ),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final user = _currentUser;
                        final isMe = msg.senderId == user?.id;
                        return _MessageBubble(
                          message: msg,
                          isMe: isMe,
                          otherParticipants: _otherParticipants,
                          consultationId: _consultationId ?? '',
                          isProvider: _isProvider,
                          currentUserId: _currentUser?.id ?? '',
                        );
                      },
                    );
                  },
                ),
                // Typing Indicator Stream
                if (_currentUser != null)
                  StreamBuilder<bool>(
                    stream: _chatRepository.streamAnyTyping(
                      widget.roomId,
                      _currentUser.id,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data != _isOtherTyping) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted)
                            setState(() => _isOtherTyping = snapshot.data!);
                        });
                      }
                      return const SizedBox.shrink();
                    },
                  ),
              ],
            ),
          ),
          if (_currentRoom?.isActive == false)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey.shade200,
              alignment: Alignment.center,
              child: const Text(
                'การให้คำปรึกษาสิ้นสุดลงแล้ว',
                style: TextStyle(color: Colors.black54),
              ),
            )
          else
            _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(0, -2),
            blurRadius: 10,
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              onPressed: _pickAndSendImage,
              icon: Icon(Icons.add_circle_outline, color: AppColors.primary),
            ),
            if (_isProvider)
              IconButton(
                onPressed: _showMedicalToolsBottomSheet,
                icon: Icon(Icons.medical_information, color: AppColors.primary),
              ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F0F0),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _msgController,
                  decoration: const InputDecoration(
                    hintText: 'พิมพ์ข้อความ...',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    fillColor: Colors.transparent,
                  ),
                  onChanged: (text) {
                    final user = _currentUser;
                    if (user == null) return;
                    _chatRepository.sendTypingStatus(
                      widget.roomId,
                      user.id,
                      true,
                    );
                    _typingTimer?.cancel();
                    _typingTimer = Timer(const Duration(seconds: 2), () {
                      _chatRepository.sendTypingStatus(
                        widget.roomId,
                        user.id,
                        false,
                      );
                    });
                  },
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (_msgController.text.isEmpty)
              GestureDetector(
                onLongPressStart: (_) => _startRecording(),
                onLongPressEnd: (_) => _stopRecording(),
                child: Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: _isRecording ? Colors.red : AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.mic,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: () {
                    _sendMessage();
                    final user = _currentUser;
                    if (user != null) {
                      _chatRepository.sendTypingStatus(
                        widget.roomId,
                        user.id,
                        false,
                      );
                    }
                  },
                  icon: const Icon(Icons.send, color: Colors.white, size: 20),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    _typingTimer?.cancel();
    _healthPermissionPollTimer?.cancel();
    _callInviteSub?.cancel();
    _callAcceptSub?.cancel();
    _healthPermissionChannel?.unsubscribe();
    if (_currentUser != null) {
      _chatRepository.sendTypingStatus(widget.roomId, _currentUser.id, false);
    }
    _msgController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final List<ChatParticipant> otherParticipants;
  final String consultationId;
  final bool isProvider;
  final String currentUserId;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.otherParticipants,
    required this.consultationId,
    required this.isProvider,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          gradient: isMe ? AppColors.primaryGradient : null,
          color: isMe ? null : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isMe ? 20 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 20),
          ),
          boxShadow: [
            BoxShadow(
              color: isMe
                  ? AppColors.primary.withOpacity(0.25)
                  : Colors.black.withOpacity(0.05),
              offset: const Offset(0, 4),
              blurRadius: 10,
            ),
          ],
          border: isMe
              ? null
              : Border.all(color: Colors.grey.shade100, width: 1),
        ),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (message.type == 'image' && message.attachmentUrl != null)
              _buildImageContent(context),
            if (message.type == 'voice' && message.attachmentUrl != null)
              _VoiceMessageBubble(url: message.attachmentUrl!, isMe: isMe),
            if (message.type == 'note')
              _buildMedicalCard(
                context,
                icon: Icons.edit_document,
                title: 'บันทึกการตรวจ',
                color: Colors.blue,
                isMe: isMe,
              ),
            if (message.type == 'prescription')
              _buildMedicalCard(
                context,
                icon: Icons.medication,
                title: 'ใบสั่งยา',
                color: Colors.green,
                isMe: isMe,
                onTap: () {
                  final prescriptionId = message.attachmentUrl;
                  if (prescriptionId == null || prescriptionId.isEmpty) return;
                  if (isProvider) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => PrescriptionEditorPage(
                          consultationId: consultationId,
                          patientId: currentUserId,
                        ),
                      ),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => PrescriptionChoicePage(
                          consultationId: consultationId,
                          patientId: currentUserId,
                          prescriptionId: prescriptionId,
                        ),
                      ),
                    );
                  }
                },
              ),
            if (message.type == 'text' ||
                (message.type != 'note' &&
                    message.type != 'prescription' &&
                    message.content.isNotEmpty &&
                    message.content != '[รูปภาพ]' &&
                    message.content != '[ข้อความเสียง]'))
              Text(
                message.content,
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black87,
                  fontSize: 15,
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${message.createdAt.hour}:${message.createdAt.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: (isMe ? Colors.white : Colors.black54).withOpacity(
                      0.6,
                    ),
                    fontSize: 10,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.readBy.isNotEmpty ? Icons.done_all : Icons.done,
                    size: 12,
                    color: message.readBy.isNotEmpty
                        ? Colors.blueAccent
                        : Colors.white70,
                  ),
                ],
              ],
            ),
            if (isMe && message.readBy.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  'อ่านโดย: ${_getReaderNames()}',
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.blueAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getReaderNames() {
    if (message.readBy.isEmpty) return '';
    final names = <String>[];
    for (var userId in message.readBy.keys) {
      final p = otherParticipants.firstWhere(
        (p) => p.id == userId,
        orElse: () =>
            ChatParticipant(id: userId, firstName: 'User', lastName: ''),
      );
      names.add(p.firstName);
    }
    return names.join(', ');
  }

  Widget _buildMedicalCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Color color,
    required bool isMe,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap ?? () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เปิดดู $title (ระบบดูข้อมูลกำลังพัฒนา)')),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? Colors.white.withOpacity(0.2) : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isMe
                ? Colors.white.withOpacity(0.5)
                : color.withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isMe ? Colors.white : color,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isMe ? AppColors.primary : Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isMe ? Colors.white : color,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'แตะเพื่อดูรายละเอียด',
                  style: TextStyle(
                    color: isMe
                        ? Colors.white.withOpacity(0.8)
                        : Colors.black54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Icon(Icons.chevron_right, color: isMe ? Colors.white : color),
          ],
        ),
      ),
    );
  }

  Widget _buildImageContent(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // TODO: Open full screen image
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: message.attachmentUrl!,
            placeholder: (context, url) => Container(
              height: 200,
              width: 200,
              color: Colors.grey[200],
              child: const Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (context, url, error) => const Icon(Icons.error),
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

class _VoiceMessageBubble extends StatefulWidget {
  final String url;
  final bool isMe;

  const _VoiceMessageBubble({required this.url, required this.isMe});

  @override
  State<_VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<_VoiceMessageBubble> {
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
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play(UrlSource(widget.url));
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isMe ? Colors.white : AppColors.primary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: _togglePlayback,
          icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: color),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                value: _duration.inMilliseconds > 0
                    ? _position.inMilliseconds / _duration.inMilliseconds
                    : 0.0,
                backgroundColor: color.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatDuration(_isPlaying ? _position : _duration),
              style: TextStyle(color: color.withOpacity(0.7), fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
