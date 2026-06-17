// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_models.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ChatRoomAdapter extends TypeAdapter<ChatRoom> {
  @override
  final int typeId = 0;

  @override
  ChatRoom read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ChatRoom(
      id: fields[0] as String,
      participantIds: (fields[1] as List).cast<String>(),
      lastMessage: fields[2] as String?,
      updatedAt: fields[3] as DateTime,
      metadata: (fields[4] as Map?)?.cast<dynamic, dynamic>(),
      roomType: fields[5] as String?,
      consultationId: fields[6] as String?,
      packageId: fields[7] as String?,
      title: fields[8] as String?,
      isActive: fields[9] as bool,
      expiresAt: fields[10] as DateTime?,
      sessionMinutes: fields[11] as int?,
      startedAt: fields[12] as DateTime?,
      endedAt: fields[13] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, ChatRoom obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.participantIds)
      ..writeByte(2)
      ..write(obj.lastMessage)
      ..writeByte(3)
      ..write(obj.updatedAt)
      ..writeByte(4)
      ..write(obj.metadata)
      ..writeByte(5)
      ..write(obj.roomType)
      ..writeByte(6)
      ..write(obj.consultationId)
      ..writeByte(7)
      ..write(obj.packageId)
      ..writeByte(8)
      ..write(obj.title)
      ..writeByte(9)
      ..write(obj.isActive)
      ..writeByte(10)
      ..write(obj.expiresAt)
      ..writeByte(11)
      ..write(obj.sessionMinutes)
      ..writeByte(12)
      ..write(obj.startedAt)
      ..writeByte(13)
      ..write(obj.endedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatRoomAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ChatMessageAdapter extends TypeAdapter<ChatMessage> {
  @override
  final int typeId = 2;

  @override
  ChatMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ChatMessage(
      id: fields[0] as String,
      roomId: fields[1] as String,
      senderId: fields[2] as String,
      content: fields[3] as String,
      createdAt: fields[4] as DateTime,
      status: fields[5] as MessageStatus,
      type: fields[6] as String,
      attachmentUrl: fields[7] as String?,
      attachmentType: fields[8] as String?,
      readBy: (fields[9] as Map).cast<String, DateTime>(),
      bodyPart: fields[10] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ChatMessage obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.roomId)
      ..writeByte(2)
      ..write(obj.senderId)
      ..writeByte(3)
      ..write(obj.content)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write(obj.status)
      ..writeByte(6)
      ..write(obj.type)
      ..writeByte(7)
      ..write(obj.attachmentUrl)
      ..writeByte(8)
      ..write(obj.attachmentType)
      ..writeByte(9)
      ..write(obj.readBy)
      ..writeByte(10)
      ..write(obj.bodyPart);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ChatParticipantAdapter extends TypeAdapter<ChatParticipant> {
  @override
  final int typeId = 3;

  @override
  ChatParticipant read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ChatParticipant(
      id: fields[0] as String,
      firstName: fields[1] as String,
      lastName: fields[2] as String,
      profileImageUrl: fields[3] as String?,
      lastSeenAt: fields[4] as DateTime?,
      availabilityStatus: fields[5] as String,
    );
  }

  @override
  void write(BinaryWriter writer, ChatParticipant obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.firstName)
      ..writeByte(2)
      ..write(obj.lastName)
      ..writeByte(3)
      ..write(obj.profileImageUrl)
      ..writeByte(4)
      ..write(obj.lastSeenAt)
      ..writeByte(5)
      ..write(obj.availabilityStatus);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatParticipantAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class MessageStatusAdapter extends TypeAdapter<MessageStatus> {
  @override
  final int typeId = 1;

  @override
  MessageStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return MessageStatus.sent;
      case 1:
        return MessageStatus.delivered;
      case 2:
        return MessageStatus.read;
      default:
        return MessageStatus.sent;
    }
  }

  @override
  void write(BinaryWriter writer, MessageStatus obj) {
    switch (obj) {
      case MessageStatus.sent:
        writer.writeByte(0);
        break;
      case MessageStatus.delivered:
        writer.writeByte(1);
        break;
      case MessageStatus.read:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
