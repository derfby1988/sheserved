import 'package:flutter/material.dart';

class ViewerCountWidget extends StatelessWidget {
  final String formattedViewerCount;

  const ViewerCountWidget({
    super.key,
    required this.formattedViewerCount,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'กำลังรับชม',
          style: TextStyle(
            fontFamily: 'SukhumvitSet',
            fontSize: 22, // Adjusted to fit in one line
            fontWeight: FontWeight.w800,
            color: Color(0xFFFF6B35), // Orange from mockup
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B35),
            borderRadius: BorderRadius.circular(25),
          ),
          child: Text(
            '$formattedViewerCount ราย',
            style: const TextStyle(
              fontFamily: 'SukhumvitSet',
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
