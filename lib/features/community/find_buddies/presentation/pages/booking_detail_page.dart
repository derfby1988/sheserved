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
                      Text('สถานะ: ${_booking!['status']}'),
                      const SizedBox(height: 8),
                      if (_booking!['session'] != null)
                        Text('เวลา: ${DateTime.parse(_booking!['session']['starts_at'].toString()).toLocal()} - ${DateTime.parse(_booking!['session']['ends_at'].toString()).toLocal()}'),
                      if (_booking!['session']?['group'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('ก๊วน: ${_booking!['session']['group']['name']}'),
                        ),
                      const Spacer(),
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
