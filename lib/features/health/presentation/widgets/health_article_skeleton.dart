import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class HealthArticleSkeleton extends StatelessWidget {
  const HealthArticleSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Area 3: Article Content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Container(height: 24, width: double.infinity, color: Colors.white),
                  const SizedBox(height: 8),
                  Container(height: 24, width: 200, color: Colors.white),
                  const SizedBox(height: 20),
                  
                  // Author
                  Row(
                    children: [
                      const CircleAvatar(radius: 24, backgroundColor: Colors.white),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(height: 14, width: 120, color: Colors.white),
                          const SizedBox(height: 4),
                          Container(height: 12, width: 180, color: Colors.white),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Content
                  Container(height: 16, width: double.infinity, color: Colors.white),
                  const SizedBox(height: 8),
                  Container(height: 16, width: double.infinity, color: Colors.white),
                  const SizedBox(height: 8),
                  Container(height: 16, width: 300, color: Colors.white),
                  const SizedBox(height: 16),
                  
                  // Image
                  Container(
                    height: 200,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ],
              ),
            ),

            // Area 4: Products
            Container(
              height: 120,
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: List.generate(3, (index) => 
                  Container(
                    width: 160,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),

            // Area 5: Comments
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: List.generate(3, (index) => 
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const CircleAvatar(radius: 16, backgroundColor: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(height: 14, width: 100, color: Colors.white),
                              const SizedBox(height: 8),
                              Container(height: 12, width: double.infinity, color: Colors.white),
                              const SizedBox(height: 4),
                              Container(height: 12, width: 200, color: Colors.white),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
