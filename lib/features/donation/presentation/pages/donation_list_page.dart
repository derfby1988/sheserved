import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/repositories/donation_repository.dart';
import '../../models/donation_models.dart';
import '../widgets/trending_donation_card.dart';
import 'donation_detail_page.dart';

class DonationListPage extends StatefulWidget {
  final String categoryId;
  final String categoryName;

  const DonationListPage({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  State<DonationListPage> createState() => _DonationListPageState();
}

class _DonationListPageState extends State<DonationListPage> {
  late DonationRepository _repository;

  @override
  void initState() {
    super.initState();
    _repository = DonationRepository(Supabase.instance.client);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.categoryName),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<DonationRequest>>(
        stream: _repository.watchRequests(categoryId: widget.categoryId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('เกิดข้อผิดพลาดในการโหลดข้อมูล'));
          }

          final requests = snapshot.data ?? [];
          if (requests.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text('ยังไม่มีคำร้องขอในหมวดหมู่นี้', style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              final request = requests[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: SizedBox(
                   height: 220,
                   child: TrendingDonationCard(
                    request: request,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DonationDetailPage(request: request),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
