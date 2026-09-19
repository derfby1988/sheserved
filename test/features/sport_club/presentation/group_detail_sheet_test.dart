import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sheets/group_detail_sheet.dart';

void main() {
  group('group member swipe chat access', () {
    test('allows a group member to chat with every active member', () {
      expect(
        canOpenGroupChatFromMemberSwipe(canChat: true, isActiveMember: true),
        isTrue,
      );
    });

    test('rejects inactive targets and users without group chat access', () {
      expect(
        canOpenGroupChatFromMemberSwipe(canChat: true, isActiveMember: false),
        isFalse,
      );
      expect(
        canOpenGroupChatFromMemberSwipe(canChat: false, isActiveMember: true),
        isFalse,
      );
    });
  });
}
