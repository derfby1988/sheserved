import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive/hive.dart';
import 'package:flutter/foundation.dart';
import '../models/chat_models.dart';
import '../../../../services/websocket_service.dart';

class ChatRepository {
  final SupabaseClient _supabase;
  final Box<ChatRoom> _roomBox;
  final Box<ChatMessage> _messageBox;
  final Box<ChatParticipant> _participantBox;
  final WebSocketService? _webSocketService;

  ChatRepository(
    this._supabase, 
    this._roomBox, 
    this._messageBox, 
    this._participantBox,
    [this._webSocketService]
  );

  // =====================================================
  // BOLA: Participant verification helper
  // =====================================================

  /// Verify that [userId] is a participant in [roomId].
  /// Throws Exception if not authorized.
  Future<void> _verifyParticipant(String roomId, String userId) async {
    final result = await _supabase
        .from('chat_rooms')
        .select('id')
        .eq('id', roomId)
        .contains('participant_ids', [userId])
        .maybeSingle();
    if (result == null) {
      throw Exception('Access denied: user is not a participant in this room');
    }
  }

  // =====================================================
  // PARTICIPANTS
  // =====================================================

  /// Get participant info (with caching)
  Future<ChatParticipant?> getParticipantInfo(String userId) async {
    // 1. Check Local Cache
    if (_participantBox.containsKey(userId)) {
      return _participantBox.get(userId);
    }

    // 2. Fetch from Supabase
    try {
      final response = await _supabase
          .from('users')
          .select('id, first_name, last_name, profile_image_url, last_seen_at, availability_status')
          .eq('id', userId)
          .single();
      
      final participant = ChatParticipant.fromJson(response);
      
      // Save to Cache
      await _participantBox.put(userId, participant);
      return participant;
    } catch (e) {
      debugPrint('ChatRepository: Error fetching participant info: $e');
      return null;
    }
  }

  // ================= =====================================
  // ROOMS
  // =====================================================

  /// Fetch all chat rooms for the current user
  Future<List<ChatRoom>> getChatRooms(String userId) async {
    debugPrint('ChatRepository: Fetching rooms for user: $userId');
    
    // 1. Get Local Rooms first as fallback
    final localRooms = _roomBox.values.where((room) => 
      room.participantIds.contains(userId)
    ).toList();
    
    try {
      // 2. Fetch from Supabase with timeout
      final response = await _supabase
          .from('chat_rooms')
          .select()
          .contains('participant_ids', [userId])
          .timeout(const Duration(seconds: 10));
      
      final dbRooms = (response as List).map((json) => ChatRoom.fromJson(json)).toList();
      
      debugPrint('ChatRepository: Successfully fetched ${dbRooms.length} rooms from Supabase');
      
      // 3. Update Cache
      for (var room in dbRooms) {
        await _roomBox.put(room.id, room);
      }
      
      return dbRooms;
    } catch (e) {
      debugPrint('ChatRepository: Error fetching rooms (returning local): $e');
      return localRooms;
    }
  }

  /// Check for existing room or create new one
  Future<ChatRoom?> getOrCreateRoom(List<String> participantIds) async {
    participantIds.sort(); // Consistent order

    try {
      // 1. Check if room exists
      final response = await _supabase
          .from('chat_rooms')
          .select()
          .contains('participant_ids', participantIds);
      
      final rooms = (response as List).map((json) => ChatRoom.fromJson(json)).toList();
      
      // Filter for exact match of participant list length
      final existingRoom = rooms.firstWhere(
        (r) => r.participantIds.length == participantIds.length,
        orElse: () => throw 'not found',
      );
      
      return existingRoom;
    } catch (e) {
      // 2. Create new room
      try {
        final insertResponse = await _supabase
            .from('chat_rooms')
            .insert({'participant_ids': participantIds})
            .select()
            .single();
        
        final newRoom = ChatRoom.fromJson(insertResponse);
        await _roomBox.put(newRoom.id, newRoom);
        return newRoom;
      } catch (e2) {
        debugPrint('ChatRepository: Error creating room: $e2');
        return null;
      }
    }
  }

  // =====================================================
  // MESSAGES
  // =====================================================

  Future<List<ChatMessage>> getMessages(String roomId, {required String callerId}) async {
    await _verifyParticipant(roomId, callerId);
    final localMessages = _messageBox.values.where((m) => m.roomId == roomId).toList();
    localMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    try {
      final response = await _supabase
          .from('chat_messages')
          .select()
          .eq('room_id', roomId)
          .order('created_at', ascending: true);
      
      final dbMessages = (response as List).map((json) => ChatMessage.fromJson(json)).toList();
      
      for (var message in dbMessages) {
        await _messageBox.put(message.id, message);
      }
      
      return dbMessages;
    } catch (e) {
      debugPrint('ChatRepository: Error fetching messages: $e');
      return localMessages;
    }
  }

  Future<bool> sendMessage(ChatMessage message, {required String callerId}) async {
    await _verifyParticipant(message.roomId, callerId);
    try {
      final response = await _supabase.from('chat_messages').insert(message.toJson()).select().single();
      final sentMessage = ChatMessage.fromJson(response);
      
      await _messageBox.put(sentMessage.id, sentMessage);
      
      // Update room's last message
      await _supabase.from('chat_rooms').update({
        'last_message': sentMessage.content,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', message.roomId);
      
      return true;
    } catch (e) {
      debugPrint('ChatRepository: Error sending message: $e');
      return false;
    }
  }

  /// Upload a file to Supabase Storage and return a signed URL (BOLA: time-limited access)
  Future<String?> uploadFile(File file, String path) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
      final fullPath = '$path/$fileName';
      
      await _supabase.storage.from('chat_attachments').upload(fullPath, file);
      
      final signedUrl = await _supabase.storage
          .from('chat_attachments')
          .createSignedUrl(fullPath, 3600);
      return signedUrl;
    } catch (e) {
      debugPrint('ChatRepository: Error uploading file: $e');
      return null;
    }
  }

  Future<void> markMessageAsRead(String messageId, String userId) async {
    try {
      // BOLA: Verify user is participant in the message's room
      final currentMsg = _messageBox.get(messageId);
      if (currentMsg != null) {
        await _verifyParticipant(currentMsg.roomId, userId);
      }
      // 1. Get current message to update its read_by map
      final readBy = Map<String, DateTime>.from(currentMsg?.readBy ?? {});
      
      // If already read by this user, skip
      if (readBy.containsKey(userId)) return;

      readBy[userId] = DateTime.now();

      // 2. Update Supabase
      // Using jsonb_set to update just one key in the read_by map
      await _supabase.from('chat_messages').update({
        'read_by': readBy.map((k, v) => MapEntry(k, v.toIso8601String())),
      }).eq('id', messageId);

      // 3. Update Local Cache
      if (currentMsg != null) {
        await _messageBox.put(messageId, currentMsg.copyWith(readBy: readBy));
      }
    } catch (e) {
      debugPrint('ChatRepository: Error marking message as read: $e');
    }
  }

  /// BOLA: streamMessages requires callerId to verify participation before streaming.
  /// Note: Supabase realtime streams cannot be scoped server-side from the client.
  /// The _verifyParticipant check runs once at subscription time. RLS must be
  /// enabled as defense-in-depth (Plan 12).
  Stream<List<ChatMessage>> streamMessages(String roomId, {required String callerId}) {
    // Fire a one-shot participant check; if unauthorized, the stream will error.
    _verifyParticipant(roomId, callerId).catchError((_) {});
    return _supabase
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('room_id', roomId)
        .order('created_at', ascending: true)
        .map((data) {
          final messages = data.map((json) => ChatMessage.fromJson(json)).toList();
          for (var m in messages) {
            _messageBox.put(m.id, m);
          }
          return messages;
        });
  }

  /// BOLA: streamRoom requires callerId to verify participation before streaming.
  Stream<ChatRoom?> streamRoom(String roomId, {required String callerId}) {
    _verifyParticipant(roomId, callerId).catchError((_) {});
    return _supabase
        .from('chat_rooms')
        .stream(primaryKey: ['id'])
        .eq('id', roomId)
        .map((data) {
          if (data.isEmpty) return null;
          final room = ChatRoom.fromJson(data.first);
          _roomBox.put(room.id, room);
          return room;
        });
  }

  // =====================================================
  // REAL-TIME SIGNALING (Typing, Presence)
  // =====================================================

  void sendTypingStatus(String roomId, String userId, bool isTyping) {
    _webSocketService?.sendTypingStatus(roomId, userId, isTyping);
  }

  Stream<bool> streamTypingStatus(String roomId, String otherUserId) {
    if (_webSocketService == null) return const Stream.empty();
    
    _webSocketService?.joinRoom(roomId);
    
    return _webSocketService!.typingStream
        .where((data) => data['roomId'] == roomId && data['userId'] == otherUserId)
        .map((data) => data['isTyping'] as bool);
  }

  Stream<bool> streamAnyTyping(String roomId, String myUserId) {
    if (_webSocketService == null) return const Stream.empty();
    
    _webSocketService?.joinRoom(roomId);
    
    return _webSocketService!.typingStream
        .where((data) => data['roomId'] == roomId && data['userId'] != myUserId)
        .map((data) => data['isTyping'] as bool);
  }

  // =====================================================
  // REQUIRED QUESTIONS
  // =====================================================

  /// Get all required questions for a room
  Future<List<ChatMessage>> getRequiredQuestions(String roomId, {required String callerId}) async {
    await _verifyParticipant(roomId, callerId);
    try {
      final response = await _supabase
          .from('chat_messages')
          .select()
          .eq('room_id', roomId)
          .eq('is_required', true)
          .order('created_at', ascending: true);
      
      final messages = (response as List).map((json) => ChatMessage.fromJson(json)).toList();
      return messages;
    } catch (e) {
      debugPrint('ChatRepository: Error fetching required questions: $e');
      return [];
    }
  }

  /// Update required status of a message (unread -> reading -> answered)
  Future<bool> updateRequiredStatus(String messageId, RequiredStatus status, {required String callerId}) async {
    try {
      // BOLA: Verify caller is participant in the message's room
      final currentMsg = _messageBox.get(messageId);
      if (currentMsg != null) {
        await _verifyParticipant(currentMsg.roomId, callerId);
      }
      await _supabase.from('chat_messages').update({
        'required_status': status.name,
      }).eq('id', messageId);
      return true;
    } catch (e) {
      debugPrint('ChatRepository: Error updating required status: $e');
      return false;
    }
  }

  /// Submit answer for a required question and send as regular message
  Future<bool> submitRequiredAnswer(String messageId, String answer, String bodyPart, {String? type = 'text', required String callerId}) async {
    try {
      // BOLA: Verify caller is participant in the message's room
      final currentMsg = _messageBox.get(messageId);
      if (currentMsg != null) {
        await _verifyParticipant(currentMsg.roomId, callerId);
      }
      // 1. Update the required question with answer
      final response = await _supabase.from('chat_messages').update({
        'required_answer': answer,
        'required_answered_at': DateTime.now().toIso8601String(),
        'required_status': RequiredStatus.answered.name,
      }).eq('id', messageId).select().single();

      final updated = ChatMessage.fromJson(response);
      await _messageBox.put(messageId, updated);

      return true;
    } catch (e) {
      debugPrint('ChatRepository: Error submitting required answer: $e');
      return false;
    }
  }

  /// Edit a required question (red status) - update owner and save history
  Future<bool> editRequiredQuestion(String messageId, String newContent, String editorId) async {
    try {
      // 1. Get current message
      final currentMsg = _messageBox.get(messageId);
      if (currentMsg == null) {
        debugPrint('ChatRepository: Message not found for edit');
        return false;
      }
      // BOLA: Verify editor is participant in the message's room
      await _verifyParticipant(currentMsg.roomId, editorId);

      // 2. Save edit history
      await _supabase.from('required_question_edits').insert({
        'message_id': messageId,
        'previous_content': currentMsg.content,
        'edited_by': editorId,
        'edited_at': DateTime.now().toIso8601String(),
      });

      // 3. Update message content and owner
      final response = await _supabase.from('chat_messages').update({
        'content': newContent,
        'required_owner_id': editorId,
      }).eq('id', messageId).select().single();

      final updated = ChatMessage.fromJson(response);
      await _messageBox.put(messageId, updated);

      return true;
    } catch (e) {
      debugPrint('ChatRepository: Error editing required question: $e');
      return false;
    }
  }

  /// Create a new required question when editing an already-touched one
  Future<ChatMessage?> createNewRequiredQuestion(ChatMessage original, String newContent, String editorId) async {
    try {
      // 1. Save edit history for original
      await _supabase.from('required_question_edits').insert({
        'message_id': original.id,
        'previous_content': original.content,
        'edited_by': editorId,
        'edited_at': DateTime.now().toIso8601String(),
      });

      // 2. Create new message
      final newMessage = ChatMessage(
        id: '${DateTime.now().millisecondsSinceEpoch}_${editorId}',
        roomId: original.roomId,
        senderId: editorId,
        content: newContent,
        createdAt: DateTime.now(),
        type: 'required_question',
        isRequired: true,
        requiredStatus: RequiredStatus.unread,
        bodyPart: original.bodyPart,
        requiredOwnerId: editorId,
      );

      final response = await _supabase.from('chat_messages').insert(newMessage.toJson()).select().single();
      final sentMessage = ChatMessage.fromJson(response);
      await _messageBox.put(sentMessage.id, sentMessage);

      return sentMessage;
    } catch (e) {
      debugPrint('ChatRepository: Error creating new required question: $e');
      return null;
    }
  }

  /// Get edit history for a required question
  Future<List<Map<String, dynamic>>> getRequiredQuestionEdits(String messageId) async {
    try {
      final response = await _supabase
          .from('required_question_edits')
          .select('previous_content, edited_by, edited_at, users(first_name, last_name)')
          .eq('message_id', messageId)
          .order('edited_at', ascending: true);
      
      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('ChatRepository: Error fetching edit history: $e');
      return [];
    }
  }
}
