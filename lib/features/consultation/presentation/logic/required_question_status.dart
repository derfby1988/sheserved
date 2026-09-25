import '../../../chat/data/models/chat_models.dart';

/// Required-question status rules shared by the patient chat UI.
///
/// Status → colour on the floating question buttons:
/// - `unread`   → แดง  (ยังไม่ได้เปิดตอบ)
/// - `reading`  → ทอง  (กำลังตอบ + แอนิเมชันจุด)
/// - `answered` → เขียว (ตอบแล้ว)
///
/// Only one question may be `reading` at a time. Without this rule the
/// previously opened question stays amber after the patient switches to
/// another one, so the expert sees several "answering" indicators and
/// assumes the patient is answering multiple questions at once.
class RequiredQuestionStatus {
  RequiredQuestionStatus._();

  /// Questions that must return to `unread` because the patient moved on to
  /// [keepId] (or closed the answer UI when [keepId] is null).
  static List<ChatMessage> staleReadingQuestions(
    List<ChatMessage> questions, {
    String? keepId,
  }) {
    return questions
        .where(
          (q) =>
              q.isRequired &&
              q.requiredStatus == RequiredStatus.reading &&
              q.id != keepId,
        )
        .toList();
  }
}
