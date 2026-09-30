import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/consultation/presentation/widgets/chat_input_bar_widget.dart';

void main() {
  testWidgets('editing mode allows changing the selected question', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'คำถามเดิม');
    final isSending = ValueNotifier(false);
    final isRecording = ValueNotifier(false);
    addTearDown(controller.dispose);
    addTearDown(isSending.dispose);
    addTearDown(isRecording.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              child: ChatInputBarWidget(
                controller: controller,
                isProvider: true,
                isChatActive: true,
                isSending: isSending,
                isRecording: isRecording,
                readOnly: false,
                onSend: () {},
                onStartRecording: () {},
                onStopRecording: () {},
                onPickImage: () {},
                onShowAttachmentMenu: () {},
                isEditingMode: true,
              ),
            ),
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled ?? true, isTrue);

    await tester.enterText(find.byType(TextField), 'คำถามที่แก้แล้ว');

    expect(controller.text, 'คำถามที่แก้แล้ว');
  });
}
