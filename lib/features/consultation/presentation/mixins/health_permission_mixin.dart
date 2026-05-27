import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import '../pages/chart_board_page.dart';
import '../widgets/health_data/granted_health_sections.dart';

mixin HealthPermissionMixin on State<ChartBoardPage> {
  // ─── Dependencies ───
  final _repository = ServiceLocator.instance.healthDataPermissionRepository;

  // ─── State ───
  Timer? _pollTimer;
  RealtimeChannel? _channel;
  Map<String, dynamic>? _permissionRequest;
  String? _lastShownRequestId;
  bool _isDialogOpen = false;

  // ─── Abstract getters (supplied by the State class) ───
  bool get isProvider;
  String? get activeConsultationId;

  // ─── Public API ───
  Map<String, dynamic>? get permissionRequest => _permissionRequest;

  void initHealthPermission() {
    _subscribeUpdates();
    _startPolling();
  }

  void disposeHealthPermission() {
    _pollTimer?.cancel();
    _channel?.unsubscribe();
  }

  Future<void> loadLatestPermission() async {
    final consultationId = activeConsultationId;
    if (consultationId == null) return;

    Map<String, dynamic>? existing;
    if (isProvider) {
      final providerId = AuthService.instance.currentUser?.id;
      if (providerId == null) return;
      existing = await _repository.getLatestRequest(
        consultationId: consultationId,
        doctorId: providerId,
      );
    } else {
      final patientId = widget.entry?.patientId ?? widget.request?.userId;
      if (patientId == null) return;
      existing = await _repository.getPendingForPatient(
        consultationId: consultationId,
        patientId: patientId,
      );
    }

    if (mounted) {
      setState(() => _permissionRequest = existing);
    }

    if (!mounted || isProvider || existing == null) return;

    final requestId = existing['id']?.toString();
    final status = existing['status']?.toString();
    if (status == 'pending' &&
        requestId != null &&
        requestId != _lastShownRequestId) {
      _lastShownRequestId = requestId;
      final pendingRequest = Map<String, dynamic>.from(existing);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !isProvider) {
          _showDialog(pendingRequest);
        }
      });
    }
  }

  void openGrantedDataSheet() {
    if (!isProvider) return;
    final consultationId = activeConsultationId;
    final doctorId = AuthService.instance.currentUser?.id;
    if (consultationId == null || doctorId == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return FutureBuilder<Map<String, dynamic>>(
          future: _repository.fetchGrantedHealthData(
            consultationId: consultationId,
            doctorId: doctorId,
            existingRequest: _permissionRequest,
          ),
          builder: (context, snapshot) {
            return DraggableScrollableSheet(
              initialChildSize: 0.9,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              builder: (_, scrollController) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}'),
                  );
                }
                final data = snapshot.data ?? {};
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.health_and_safety,
                                color: Color(0xFF4A8B2C)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'ข้อมูลสุขภาพที่ได้รับอนุญาต',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            GrantedHealthSections(data: data),
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
      },
    );
  }

  Future<void> requestPermission() async {
    final providerId = AuthService.instance.currentUser?.id;
    final patientId = widget.entry?.patientId ?? widget.request?.userId;
    final consultationId = activeConsultationId;
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
        _permissionRequest = {
          'consultation_id': consultationId,
          'doctor_id': providerId,
          'doctor_name': AuthService.instance.currentUser?.fullName ?? 'Doctor',
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

      final response = await _repository.requestPermission(
        consultationId: consultationId,
        doctorId: providerId,
        patientId: patientId,
        doctorName: AuthService.instance.currentUser?.fullName ?? 'Doctor',
        requestedFields: const {
          'general': true,
          'history': true,
          'labs': true,
          'medications': true,
        },
      );
      if (mounted) {
        setState(() => _permissionRequest = response);
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
        await loadLatestPermission();
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('ส่งคำขอไม่สำเร็จ: กรุณาลองใหม่อีกครั้ง'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // ─── Private ───

  void _startPolling() {
    if (!isProvider) return;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) async {
        if (!mounted || !isProvider) return;
        final consultationId = activeConsultationId;
        final doctorId = AuthService.instance.currentUser?.id;
        if (consultationId == null || doctorId == null) return;

        final latest = await _repository.getLatestRequest(
          consultationId: consultationId,
          doctorId: doctorId,
        );
        if (!mounted || latest == null) return;

        final prevStatus = _permissionRequest?['status'];
        final newStatus = latest['status'];
        if (prevStatus == newStatus) return;

        setState(() => _permissionRequest = latest);

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

  void _subscribeUpdates() {
    final currentUserId = AuthService.instance.currentUser?.id;
    if (currentUserId == null) return;

    _channel?.unsubscribe();
    _channel = null;

    _channel = Supabase.instance.client
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
              setState(() => _permissionRequest = newRecord);
              _maybeShowDialog(newRecord);
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
              setState(() => _permissionRequest = updated);
              _maybeShowDialog(updated);
              final status = updated['status'];
              if (isProvider && status == 'granted') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ ผู้ป่วยอนุมัติการเข้าถึงข้อมูลสุขภาพแล้ว'),
                    backgroundColor: Color(0xFF4A8B2C),
                  ),
                );
              } else if (isProvider && status == 'denied') {
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

  void _maybeShowDialog(Map<String, dynamic> request) {
    if (isProvider) return;
    final requestId = request['id']?.toString();
    final status = request['status']?.toString();
    if (requestId == null || status != 'pending') return;
    if (_isDialogOpen || requestId == _lastShownRequestId) return;

    _lastShownRequestId = requestId;
    _isDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || isProvider) {
        _isDialogOpen = false;
        return;
      }
      try {
        await _showDialog(request);
      } finally {
        _isDialogOpen = false;
      }
    });
  }

  Future<void> _showDialog(Map<String, dynamic> request) async {
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
                              await _repository.respondPermission(
                                requestId: request['id'] as String,
                                granted: true,
                                grantedFields: granted,
                              );
                              if (mounted) {
                                setState(() => _permissionRequest = null);
                              }
                              Navigator.pop(context);
                            },
                            child: const Text('ยอมให้'),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            await _repository.respondPermission(
                              requestId: request['id'] as String,
                              granted: false,
                              grantedFields: fields,
                            );
                            if (mounted) {
                              setState(() => _permissionRequest = null);
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

}
