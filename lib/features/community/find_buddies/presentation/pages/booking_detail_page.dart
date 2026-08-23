import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../../../services/auth_service.dart';
import '../../../find_buddies/data/fitness_buddies_repository.dart';

class BookingDetailPage extends StatefulWidget {
  final String bookingId;
  const BookingDetailPage({super.key, required this.bookingId});

  @override
  State<BookingDetailPage> createState() => _BookingDetailPageState();
}

class _BookingDetailPageState extends State<BookingDetailPage> {
  late final FitnessBuddiesRepository _repo;
  Map<String, dynamic>? _booking;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _repo = FitnessBuddiesRepository(Supabase.instance.client);
    _load();
  }

  Future<void> _load() async {
    final user = AuthService.instance.currentUser;
    final userId = user?.id ?? '';
    final data = await _repo.getBookingDetail(widget.bookingId, userId: userId);
    if (!mounted) return;
    setState(() {
      _booking = data;
      _loading = false;
    });
  }

  Widget _buildStatus() {
    final status = _booking!['status']?.toString() ?? '';
    final cancelledBy = _booking!['cancelled_by']?.toString() ?? '';
    final cancelReason = _booking!['cancel_reason']?.toString() ?? '';

    String label;
    Color color;

    if (status == 'rejected' && cancelledBy == 'system' && cancelReason == 'AUTO_TIMEOUT') {
      label = 'ถูกยกเลิกอัตโนมัติ (ครบกำหนดอนุมัติ)';
      color = Colors.orange;
    } else {
      switch (status) {
        case 'pending':
          label = 'รออนุมัติ';
          color = Colors.amber;
          break;
        case 'confirmed':
          label = 'ยืนยันแล้ว';
          color = Colors.green;
          break;
        case 'rejected':
          label = 'ถูกปฏิเสธ';
          color = Colors.red;
          break;
        case 'cancelled':
          label = 'ยกเลิกแล้ว';
          color = Colors.grey;
          break;
        default:
          label = status;
          color = Colors.black87;
      }
    }

    return Row(
      children: [
        const Text('สถานะ: '),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Future<void> _cancel() async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    try {
      await _repo.cancelBooking(widget.bookingId, user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ยกเลิกการจองแล้ว')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ยกเลิกไม่สำเร็จ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('รายละเอียดการจอง')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _booking == null
              ? const Center(child: Text('ไม่พบข้อมูลการจอง'))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatus(),
                      const SizedBox(height: 8),
                      if (_booking!['session'] != null)
                        Text('เวลา: ${DateTime.parse(_booking!['session']['starts_at'].toString()).toLocal()} - ${DateTime.parse(_booking!['session']['ends_at'].toString()).toLocal()}'),
                      if (_booking!['session']?['group'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('ก๊วน: ${_booking!['session']['group']['name']}'),
                        ),
                      if (_booking!['cancel_reason'] != null && (_booking!['cancel_reason'] as String).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('เหตุผล: ${_booking!['cancel_reason']}', style: const TextStyle(color: Colors.grey)),
                        ),
                      const Spacer(),
                      if (_booking!['cancelled_by'] != 'system')
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _cancel,
                                child: const Text('ยกเลิกการจอง'),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
    );
  }
}
