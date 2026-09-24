import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:sheserved/features/chat/data/models/chat_models.dart';
import 'package:sheserved/features/consultation/presentation/widgets/closed_ended_dialog.dart';
import 'package:sheserved/features/consultation/presentation/widgets/health_data/message_bubble.dart';

void main() {
  group('ClosedEndedConfig', () {
    test('quantitative accepts only 3, 5 or 10 scale levels', () {
      for (final n in [3, 5, 10]) {
        expect(ClosedEndedConfig.quantitative(n).isValid, isTrue);
      }
      for (final n in [1, 2, 4, 6, 9, 11]) {
        expect(ClosedEndedConfig.qualitative(const ['a', 'b']).isValid, isTrue);
        final cfg = ClosedEndedConfig.tryParse({
          'type': 'quantitative',
          'scale_levels': n,
        });
        expect(cfg, isNull, reason: 'scale $n must be rejected');
      }
    });

    test('qualitative accepts 2-10 options and rejects out of range', () {
      expect(
        ClosedEndedConfig.qualitative(const ['ใช่', 'ไม่ใช่']).isValid,
        isTrue,
      );
      expect(
        ClosedEndedConfig.qualitative(
          List.generate(10, (i) => 'ตัวเลือก $i'),
        ).isValid,
        isTrue,
      );
      expect(ClosedEndedConfig.qualitative(const ['เดียว']).isValid, isFalse);
      expect(
        ClosedEndedConfig.qualitative(
          List.generate(11, (i) => 'ตัวเลือก $i'),
        ).isValid,
        isFalse,
      );
    });

    test('rejects empty, duplicate and too-long labels', () {
      expect(
        ClosedEndedConfig.qualitative(const ['ใช่', '  ']).validate(),
        contains('empty'),
      );
      expect(
        ClosedEndedConfig.qualitative(const ['ใช่', 'ใช่ ']).validate(),
        contains('duplicate'),
      );
      expect(
        ClosedEndedConfig.qualitative(['ใช่', 'x' * 81]).validate(),
        contains('80'),
      );
    });

    test('answerCount derives from definition and never stores a field', () {
      final quant = ClosedEndedConfig.quantitative(5);
      expect(quant.answerCount, 5);
      expect(quant.effectiveOptions, ['1', '2', '3', '4', '5']);
      expect(quant.labelAt(4), '5');
      expect(quant.labelAt(5), isNull);
      expect(quant.toJson().containsKey('answer_count'), isFalse);
      expect(quant.toJson()['scale_levels'], 5);

      final qual = ClosedEndedConfig.qualitative(const ['a', 'b', 'c']);
      expect(qual.answerCount, 3);
      expect(qual.effectiveOptions, ['a', 'b', 'c']);
    });

    test('tryParse round-trips valid configs and rejects malformed ones', () {
      final quant = ClosedEndedConfig.quantitative(10);
      expect(ClosedEndedConfig.tryParse(quant.toJson()), quant);

      final qual = ClosedEndedConfig.qualitative(const ['a', 'b']);
      expect(ClosedEndedConfig.tryParse(qual.toJson()), qual);

      expect(ClosedEndedConfig.tryParse(null), isNull);
      expect(ClosedEndedConfig.tryParse('nope'), isNull);
      expect(ClosedEndedConfig.tryParse({'type': 'unknown'}), isNull);
      expect(
        ClosedEndedConfig.tryParse({'type': 'qualitative', 'options': 'x'}),
        isNull,
      );
      expect(ClosedEndedConfig.tryParse({'type': 'quantitative'}), isNull);
    });
  });

  group('ChatMessage closed_ended_config', () {
    ChatMessage makeMessage({Map<dynamic, dynamic>? config}) => ChatMessage(
      id: 'm1',
      roomId: 'room-1',
      senderId: 'expert-1',
      content: 'ปวดไหม',
      createdAt: DateTime.utc(2026, 9, 25, 8),
      type: 'closed_ended_question',
      isRequired: true,
      requiredStatus: RequiredStatus.unread,
      requiredOwnerId: 'expert-1',
      closedEndedConfigJson: config,
    );

    test('JSON round-trip preserves the config', () {
      final config = ClosedEndedConfig.qualitative(const ['ใช่', 'ไม่ใช่']);
      final msg = makeMessage(config: config.toJson());
      final restored = ChatMessage.fromJson(msg.toJson());

      expect(restored.isClosedEndedQuestion, isTrue);
      expect(restored.closedEndedConfig, config);
      expect(restored.isRequired, isTrue);
      expect(restored.requiredStatus, RequiredStatus.unread);
    });

    test('legacy messages without config parse safely', () {
      final json = makeMessage().toJson()..remove('closed_ended_config');
      final msg = ChatMessage.fromJson(json);
      expect(msg.closedEndedConfig, isNull);
      expect(msg.closedEndedConfigJson, isNull);
    });

    test('malformed config falls back to null instead of throwing', () {
      final msg = makeMessage(config: {'type': 'bogus'});
      expect(msg.closedEndedConfig, isNull);
    });

    test('copyWith keeps and replaces the config', () {
      final msg = makeMessage(
        config: ClosedEndedConfig.quantitative(3).toJson(),
      );
      expect(msg.copyWith().closedEndedConfigJson, msg.closedEndedConfigJson);
      final replaced = msg.copyWith(
        closedEndedConfigJson: ClosedEndedConfig.qualitative(const [
          'a',
          'b',
        ]).toJson(),
      );
      expect(replaced.closedEndedConfig!.type, ClosedEndedType.qualitative);
    });
  });

  group('ChatMessage Hive round-trip', () {
    late Directory dir;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('hive_closed_ended_test');
      Hive.init(dir.path);
      registerChatHiveAdapters();
    });

    tearDownAll(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('registers RequiredStatusAdapter for message persistence', () {
      expect(Hive.isAdapterRegistered(4), isTrue);
    });

    test('closed-ended config survives a Hive write/read', () async {
      final box = await Hive.openBox<ChatMessage>('ce_messages');
      final msg = ChatMessage(
        id: 'm1',
        roomId: 'room-1',
        senderId: 'expert-1',
        content: 'ปวดไหม',
        createdAt: DateTime.utc(2026, 9, 25, 8),
        type: 'closed_ended_question',
        isRequired: true,
        requiredStatus: RequiredStatus.reading,
        closedEndedConfigJson: ClosedEndedConfig.quantitative(5).toJson(),
      );
      await box.put('m1', msg);
      final restored = box.get('m1')!;
      expect(restored.closedEndedConfig, ClosedEndedConfig.quantitative(5));
      await box.close();
    });

    test('legacy cached message without field 19 reads as null', () async {
      final box = await Hive.openBox<ChatMessage>('ce_legacy');
      final legacy = ChatMessage(
        id: 'legacy-1',
        roomId: 'room-1',
        senderId: 'u1',
        content: 'สวัสดี',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      await box.put('legacy-1', legacy);
      expect(box.get('legacy-1')!.closedEndedConfig, isNull);
      await box.close();
    });
  });

  group('ClosedEndedConfigDialog', () {
    testWidgets('confirm returns a validated quantitative config', (
      tester,
    ) async {
      ClosedEndedConfig? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await ClosedEndedConfigDialog.show(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('คำถามปลายปิด'), findsOneWidget);
      await tester.tap(find.text('1–10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ยืนยัน'));
      await tester.pumpAndSettle();

      expect(result, ClosedEndedConfig.quantitative(10));
    });

    testWidgets('qualitative shows validation error for empty options', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ClosedEndedConfigDialog.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('เชิงคุณภาพ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ยืนยัน'));
      await tester.pumpAndSettle();

      expect(find.text('กรุณากรอกตัวเลือกให้ครบทุกข้อ'), findsOneWidget);
      // Dialog stays open — no pop happened.
      expect(find.text('คำถามปลายปิด'), findsOneWidget);
    });

    testWidgets('qualitative accepts typed options and returns config', (
      tester,
    ) async {
      ClosedEndedConfig? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await ClosedEndedConfigDialog.show(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('เชิงคุณภาพ'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'ตัวเลือกที่ 1'),
        'ใช่',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'ตัวเลือกที่ 2'),
        'ไม่ใช่',
      );
      await tester.tap(find.text('ยืนยัน'));
      await tester.pumpAndSettle();

      expect(result, ClosedEndedConfig.qualitative(const ['ใช่', 'ไม่ใช่']));
    });

    testWidgets('cancel returns null', (tester) async {
      ClosedEndedConfig? result = ClosedEndedConfig.quantitative(3);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await ClosedEndedConfigDialog.show(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });
  });

  group('MessageBubble closed_ended_question', () {
    ChatMessage closedEnded({String? answer}) => ChatMessage(
      id: 'm1',
      roomId: 'room-1',
      senderId: 'expert-1',
      content: 'ระดับความปวดเป็นอย่างไร',
      createdAt: DateTime.utc(2026, 9, 25, 8, 30),
      type: 'closed_ended_question',
      isRequired: true,
      requiredStatus: answer == null
          ? RequiredStatus.unread
          : RequiredStatus.answered,
      requiredAnswer: answer,
      requiredAnsweredAt: answer == null
          ? null
          : DateTime.utc(2026, 9, 25, 8, 45),
      closedEndedConfigJson: ClosedEndedConfig.qualitative(const [
        'ใช่',
        'ไม่ใช่',
      ]).toJson(),
    );

    Widget wrap(ChatMessage msg, {bool isMe = false}) => MaterialApp(
      home: Scaffold(
        body: MessageBubble(message: msg, isMe: isMe),
      ),
    );

    testWidgets('shows the purple closed-ended badge before answering', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(closedEnded()));
      expect(find.text('ปลายปิด · บังคับ'), findsOneWidget);
      expect(
        find.textContaining('ระดับความปวดเป็นอย่างไร', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('คำตอบ:'), findsNothing);
    });

    testWidgets('projects the selected answer with option index', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(closedEnded(answer: 'ใช่')));
      expect(find.textContaining('คำตอบ: ใช่'), findsOneWidget);
      expect(find.textContaining('ตัวเลือกที่ 1'), findsOneWidget);
    });

    testWidgets('open-ended required_question rendering stays unchanged', (
      tester,
    ) async {
      final msg = ChatMessage(
        id: 'm2',
        roomId: 'room-1',
        senderId: 'expert-1',
        content: 'อธิบายอาการ',
        createdAt: DateTime.utc(2026, 9, 25, 8, 30),
        type: 'required_question',
        isRequired: true,
        requiredStatus: RequiredStatus.answered,
        requiredAnswer: 'ปวดตามข้อ',
        requiredAnsweredAt: DateTime.utc(2026, 9, 25, 8, 45),
      );
      await tester.pumpWidget(wrap(msg));
      expect(find.text('ปลายปิด · บังคับ'), findsNothing);
      expect(find.text('ปวดตามข้อ'), findsOneWidget);
    });
  });
}
