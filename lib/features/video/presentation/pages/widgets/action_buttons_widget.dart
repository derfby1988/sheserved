import 'package:flutter/material.dart';

class ActionButtonsWidget extends StatelessWidget {
  final String likeCountFormatted;
  final String donationTotalFormatted;
  final VoidCallback onLike;
  final VoidCallback onYieldWay;
  final VoidCallback onDonate;

  const ActionButtonsWidget({
    super.key,
    required this.likeCountFormatted,
    required this.donationTotalFormatted,
    required this.onLike,
    required this.onYieldWay,
    required this.onDonate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInteractionButtonRow(
          value: likeCountFormatted,
          label: 'ส่งกำลังใจ',
          onTap: onLike,
        ),
        const SizedBox(height: 6),
        _buildInteractionButtonRow(
          value: '20%',
          label: 'ให้ทาง',
          onTap: onYieldWay,
        ),
        const SizedBox(height: 6),
        _buildInteractionButtonRow(
          value: donationTotalFormatted,
          label: 'บริจาค',
          onTap: onDonate,
        ),
      ],
    );
  }

  Widget _buildInteractionButtonRow({
    required String value,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              width: 70,
              padding: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF6B7280).withValues(alpha: 0.8), // Gray background
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: Center(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontFamily: 'SukhumvitSet',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          // Label Box (Orange - Pill shape on the right)
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B35),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'SukhumvitSet',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
