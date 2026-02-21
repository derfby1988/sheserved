import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive/hive.dart';
import 'package:sheserved/features/chat/data/models/chat_models.dart';
import 'package:sheserved/features/chat/data/repositories/chat_repository.dart';
import 'package:sheserved/services/websocket_service.dart';

@GenerateMocks([SupabaseClient, Box, WebSocketService, PostgrestQueryBuilder, PostgrestFilterBuilder])
import 'chat_repository_test.mocks.dart';

void main() {
  late ChatRepository repository;
  late MockSupabaseClient mockSupabase;
  late MockBox<ChatRoom> mockRoomBox;
  late MockBox<ChatMessage> mockMessageBox;
  late MockBox<ChatParticipant> mockParticipantBox;
  late MockWebSocketService mockWebSocket;

  setUp(() {
    mockSupabase = MockSupabaseClient();
    mockRoomBox = MockBox<ChatRoom>();
    mockMessageBox = MockBox<ChatMessage>();
    mockParticipantBox = MockBox<ChatParticipant>();
    mockWebSocket = MockWebSocketService();

    repository = ChatRepository(
      mockSupabase,
      mockRoomBox,
      mockMessageBox,
      mockParticipantBox,
      mockWebSocket,
    );
  });

  group('ChatRepository', () {
    test('getParticipantInfo returns cached data if available', () async {
      final participant = ChatParticipant(id: '1', firstName: 'Test', lastName: 'User');
      when(mockParticipantBox.containsKey('1')).thenReturn(true);
      when(mockParticipantBox.get('1')).thenReturn(participant);

      final result = await repository.getParticipantInfo('1');

      expect(result, equals(participant));
      verify(mockParticipantBox.get('1')).called(1);
    });

    // More tests could be added here for Supabase interactions
    // Note: Mocking Supabase's fluent API requires multiple steps
  });
}
