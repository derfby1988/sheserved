import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/chat/data/models/chat_models.dart';
import 'package:sheserved/features/consultation/presentation/logic/required_question_status.dart';

ChatMessage _question(
  String id,
  RequiredStatus status, {
  String type = 'required_question',
}) => ChatMessage(
  id: id,
  roomId: 'room-1',
  senderId: 'expert-1',
  content: 'คำถาม $id',
  createdAt: DateTime.utc(2026, 9, 25, 8, 30),
  type: type,
  isRequired: true,
  requiredStatus: status,
);

void main() {
  group('RequiredQuestionStatus', () {
    test('switching questions reverts every other reading question', () {
      final questions = [
        _question('q1', RequiredStatus.reading),
        _question('q2', RequiredStatus.unread, type: 'closed_ended_question'),
        _question('q3', RequiredStatus.answered),
      ];

      final stale = RequiredQuestionStatus.staleReadingQuestions(
        questions,
        keepId: 'q2',
      );

      expect(stale.map((q) => q.id), ['q1']);
    });

    test('reopening the same question reverts nothing', () {
      final questions = [_question('q1', RequiredStatus.reading)];

      expect(
        RequiredQuestionStatus.staleReadingQuestions(questions, keepId: 'q1'),
        isEmpty,
      );
    });

    test('closing the answer UI reverts every reading question', () {
      final questions = [
        _question('q1', RequiredStatus.reading, type: 'closed_ended_question'),
        _question('q2', RequiredStatus.reading),
        _question('q3', RequiredStatus.unread),
        _question('q4', RequiredStatus.answered),
      ];

      final stale = RequiredQuestionStatus.staleReadingQuestions(questions);

      expect(stale.map((q) => q.id), ['q1', 'q2']);
    });

    test('ignores ordinary chat messages', () {
      final questions = [
        ChatMessage(
          id: 'chat-1',
          roomId: 'room-1',
          senderId: 'patient-1',
          content: 'สวัสดี',
          createdAt: DateTime.utc(2026, 9, 25, 8, 30),
          requiredStatus: RequiredStatus.reading,
        ),
      ];

      expect(RequiredQuestionStatus.staleReadingQuestions(questions), isEmpty);
    });
  });
}
