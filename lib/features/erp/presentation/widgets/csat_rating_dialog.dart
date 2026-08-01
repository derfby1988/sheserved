import 'package:flutter/material.dart';
import '../../data/repositories/crm_repository.dart';

/// Dialog ให้คะแนนประเมินความพึงพอใจ CSAT & Feedback (Group G - Phase 26-27)
class CsatRatingDialog extends StatefulWidget {
  final CrmRepository crmRepo;
  final String professionId;
  final String? customerId;
  final String? appointmentId;

  const CsatRatingDialog({
    super.key,
    required this.crmRepo,
    required this.professionId,
    this.customerId,
    this.appointmentId,
  });

  @override
  State<CsatRatingDialog> createState() => _CsatRatingDialogState();
}

class _CsatRatingDialogState extends State<CsatRatingDialog> {
  int _rating = 5;
  final _commentController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    setState(() => _isSubmitting = true);

    final success = await widget.crmRepo.submitCustomerFeedback({
      'profession_id': widget.professionId,
      'customer_id': widget.customerId,
      'appointment_id': widget.appointmentId,
      'rating': _rating,
      'comment': _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
    });

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (success) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ขอบคุณสำหรับข้อเสนอแนะและความคิดเห็นของคุณ!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เกิดข้อผิดพลาดในการส่งแบบประเมิน')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Column(
        children: [
          Icon(Icons.sentiment_very_satisfied, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 8),
          const Text('ประเมินความพึงพอใจการบริการ'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('กรุณาให้คะแนนความพึงพอใจการรับบริการ'),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final starValue = index + 1;
                return IconButton(
                  icon: Icon(
                    starValue <= _rating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 36,
                  ),
                  onPressed: () {
                    setState(() {
                      _rating = starValue;
                    });
                  },
                );
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _commentController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'ข้อเสนอแนะเพิ่มเติม (ตัวเลือก)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('ข้าม'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _handleSubmit,
          child: _isSubmitting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('ส่งแบบประเมิน'),
        ),
      ],
    );
  }
}
