import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/video/models/incident_map_models.dart';
import 'package:sheserved/features/video/presentation/pages/widgets/incident_map/incident_map_surface.dart';
import 'package:sheserved/shared/widgets/gradient_progress_bar.dart';

Widget _harness(IncidentMapPhoto photo, {VoidCallback? onTap}) => MaterialApp(
  home: Scaffold(
    backgroundColor: Colors.black,
    body: Center(
      child: SizedBox(
        width: 64,
        height: 64,
        child: IncidentPhotoCard(photo: photo, onTap: onTap ?? () {}),
      ),
    ),
  ),
);

void main() {
  group('IncidentPhotoCard (§22.19 pending photo slot)', () {
    testWidgets('ภาพที่ยัง blur อยู่ → gradient bar และไม่ยิง network image', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          const IncidentMapPhoto(id: 'p1', url: '', blurStatus: 'blurring'),
        ),
      );

      expect(find.byType(IncidentPhotoLoadingPlaceholder), findsOneWidget);
      expect(find.byType(GradientProgressBar), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('แตะภาพที่ยัง blur อยู่ไม่เปิด gallery', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        _harness(
          const IncidentMapPhoto(id: 'p1', url: '', blurStatus: 'blurring'),
          onTap: () => tapped++,
        ),
      );

      await tester.tap(find.byType(IncidentPhotoCard));
      await tester.pump();
      expect(tapped, 0);
    });

    testWidgets('ภาพที่ blur เสร็จแล้วใช้ CachedNetworkImage และแตะได้', (
      tester,
    ) async {
      var tapped = 0;
      await tester.pumpWidget(
        _harness(
          const IncidentMapPhoto(id: 'p2', url: 'https://example.test/p2.jpg'),
          onTap: () => tapped++,
        ),
      );

      // ใช้ network image (placeholder ระหว่างโหลดเป็น gradient bar ของ §22.16)
      expect(find.byType(CachedNetworkImage), findsOneWidget);

      await tester.tap(find.byType(IncidentPhotoCard));
      await tester.pump();
      expect(tapped, 1);
    });
  });
}
