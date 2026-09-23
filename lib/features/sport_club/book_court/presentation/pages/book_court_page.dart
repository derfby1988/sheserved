import 'package:flutter/material.dart';
import 'package:sheserved/features/sport_club/shared/presentation/widgets/sports_hub_placeholder_page.dart';

class BookCourtPage extends StatelessWidget {
  const BookCourtPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SportsHubPlaceholderPage(
      icon: Icons.sports_tennis_rounded,
      title: 'จองสนามกีฬา',
    );
  }
}
