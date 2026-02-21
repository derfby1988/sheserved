import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive/hive.dart';
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
          .select('id, first_name, last_name, profile_image_url')
          .eq('id', userId)
          .single();
      
      final participant = ChatParticipant.fromJson(response);
      
      // Save to Cache
      await _participantBox.put(userId, participant);
      return participant;
    } catch (e) {
      print('ChatRepository: Error fetching participant info: $e');
      return null;
    }
  }

  // ================= =====================================
  // ROOMS
  // =====================================================

  /// Fetch all chat rooms for the current user
  Future<List<ChatRoom>> getChatRooms(String userId) async {
    final localRooms = _roomBox.values.where((room) => 
      room.participantIds.contains(userId)
    ).toList();
    
    try {
      final response = await _supabase
          .from('chat_rooms')
          .select()
          .contains('participant_ids', [userId]);
      
      final dbRooms = (response as List).map((json) => ChatRoom.fromJson(json)).toList();
      
      for (var room in dbRooms) {
        await _roomBox.put(room.id, room);
      }
      
      return dbRooms;
    } catch (e) {
      print('ChatRepository: Error fetching rooms: $e');
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
        print('ChatRepository: Error creating room: $e2');
        return null;
      }
    }
  }

  // =====================================================
  // MESSAGES
  // =====================================================

  Future<List<ChatMessage>> getMessages(String roomId) async {
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
      print('ChatRepository: Error fetching messages: $e');
      return localMessages;
    }
  }

  Future<bool> sendMessage(ChatMessage message) async {
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
      print('ChatRepository: Error sending message: $e');
      return false;
    }
  }

  /// Upload a file to Supabase Storage and return the public URL
  Future<String?> uploadFile(File file, String path) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
      final fullPath = '$path/$fileName';
      
      await _supabase.storage.from('chat_attachments').upload(fullPath, file);
      
      final url = _supabase.storage.from('chat_attachments').getPublicUrl(fullPath);
      return url;
    } catch (e) {
      print('ChatRepository: Error uploading file: $e');
      return null;
    }
  }

  Future<void> markMessageAsRead(String messageId, String userId) async {
    try {
      // 1. Get current message to update its read_by map
      final currentMsg = _messageBox.get(messageId);
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
      print('ChatRepository: Error marking message as read: $e');
    }
  }

  Stream<List<ChatMessage>> streamMessages(String roomId) {
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
}
