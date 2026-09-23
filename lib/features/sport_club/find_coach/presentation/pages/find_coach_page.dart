import 'package:flutter/material.dart';
import 'package:sheserved/features/sport_club/shared/presentation/widgets/sports_hub_placeholder_page.dart';

class FindCoachPage extends StatelessWidget {
  const FindCoachPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SportsHubPlaceholderPage(
      icon: Icons.school_rounded,
      title: 'หาโค้ช/เทรนเนอร์',
    );
  }
}
