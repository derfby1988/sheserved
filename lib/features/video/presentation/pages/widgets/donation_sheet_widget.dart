import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sheserved/features/donation/data/repositories/donation_repository.dart';
import 'package:sheserved/features/donation/models/donation_models.dart';

/// DonationSheetWidget — รองรับหลายคำร้องบริจาคต่อวิดีโอเดียว
/// ผู้บริจาคต้องเลือกก่อนว่าจะสนับสนุนคำร้องใบไหน แล้วจึงเลือกจำนวนเงิน
class DonationSheetWidget extends StatefulWidget {
  final String videoId;
  /// Callback เมื่อบริจาค: (amount, requestId)
  final Function(int amount, String? requestId) onDonate;

  const DonationSheetWidget({
    super.key,
    required this.videoId,
    required this.onDonate,
  });

  @override
  State<DonationSheetWidget> createState() => _DonationSheetWidgetState();
}

class _DonationSheetWidgetState extends State<DonationSheetWidget> {
  late DonationRepository _repo;
  List<DonationRequest> _requests = [];
  bool _isLoading = true;
  DonationRequest? _selectedRequest;

  @override
  void initState() {
    super.initState();
    _repo = DonationRepository(Supabase.instance.client);
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    try {
      final results = await _repo.getRequestsByVideoId(
        widget.videoId,
        activeOnly: true,
      );
      if (mounted) {
        setState(() {
          _requests = results;
          // เลือกคำร้องแรก (ของผู้แจ้ง Reporter) เป็น default
          _selectedRequest = results.isNotEmpty ? results.first : null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.only(top: 12, bottom: 32, left: 20, right: 20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              // Header
              const Text(
                'ร่วมสนับสนุนการช่วยเหลือ',
                style: TextStyle(
                  fontFamily: 'SukhumvitSet',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'เลือกรายการที่ต้องการสนับสนุน',
                style: TextStyle(
                  fontFamily: 'SukhumvitSet',
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 16),

              // ===== รายการคำร้อง =====
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(),
                )
              else if (_requests.isEmpty)
                _buildNoRequestsView()
              else
                _buildRequestListAndAmounts(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoRequestsView() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.grey[400], size: 48),
          const SizedBox(height: 12),
          Text(
            'ยังไม่มีคำร้องรับบริจาคที่เปิดใช้งาน\nสำหรับเหตุการณ์นี้',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'SukhumvitSet',
              fontSize: 14,
              color: Colors.grey[500],
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestListAndAmounts() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // รายการคำร้องทั้งหมด
        if (_requests.length == 1)
          _buildSingleRequestCard(_requests.first)
        else
          _buildMultiRequestSelector(),

        const SizedBox(height: 20),

        // ปุ่มเลือกจำนวนเงิน
        const Text(
          'เลือกจำนวนเงิน',
          style: TextStyle(
            fontFamily: 'SukhumvitSet',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [10, 50, 100, 500, 1000].map((amount) {
            return GestureDetector(
              onTap: () {
                Navigator.pop(context);
                widget.onDonate(amount, _selectedRequest?.id);
              },
              child: Container(
                width: 88,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6B35), Color(0xFFFF8F65)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF6B35).withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '฿${NumberFormat('#,##0').format(amount)}',
                    style: const TextStyle(
                      fontFamily: 'SukhumvitSet',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// แสดงการ์ดคำร้องเดียว
  Widget _buildSingleRequestCard(DonationRequest req) {
    return _buildRequestCard(req, isSelected: true, onTap: null);
  }

  /// แสดง Selector สำหรับหลายคำร้อง
  Widget _buildMultiRequestSelector() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: _requests.map((req) {
        final isSelected = _selectedRequest?.id == req.id;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildRequestCard(
            req,
            isSelected: isSelected,
            onTap: () => setState(() => _selectedRequest = req),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRequestCard(
    DonationRequest req, {
    required bool isSelected,
    VoidCallback? onTap,
  }) {
    final progress = (req.targetAmount ?? 0) > 0
        ? ((req.currentAmount ?? 0) / req.targetAmount!).clamp(0.0, 1.0)
        : 0.0;
    final fmt = NumberFormat('#,##0');

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFF6B35).withValues(alpha: 0.06)
              : Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF6B35) : Colors.grey.shade200,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // ป้ายหมวดหมู่
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    req.categoryId != null ? 'คำร้องบริจาค' : 'ทั่วไป',
                    style: const TextStyle(
                      fontFamily: 'SukhumvitSet',
                      fontSize: 11,
                      color: Color(0xFFFF6B35),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                if (isSelected && onTap != null)
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFFFF6B35), size: 20),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              req.title ?? 'คำร้องขอรับบริจาค',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'SukhumvitSet',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            if (req.targetAmount != null && req.targetAmount! > 0) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    '฿${fmt.format(req.currentAmount ?? 0)}',
                    style: const TextStyle(
                      fontFamily: 'SukhumvitSet',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFF6B35),
                    ),
                  ),
                  Text(
                    ' / ฿${fmt.format(req.targetAmount!)}',
                    style: TextStyle(
                      fontFamily: 'SukhumvitSet',
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontFamily: 'SukhumvitSet',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFF6B35),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  backgroundColor: Colors.grey[200],
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFFFF6B35),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
