import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/auth_service.dart';
import '../../../services/service_locator.dart';
import '../data/repositories/chat_repository.dart';

final chatUnreadProvider = StateNotifierProvider<ChatUnreadNotifier, int>((ref) {
  return ChatUnreadNotifier(services.chatRepository);
});

class ChatUnreadNotifier extends StateNotifier<int> {
  final ChatRepository _repository;
  bool _isRefreshing = false;

  ChatUnreadNotifier(this._repository) : super(0);

  Future<void> refresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      final userId = AuthService.instance.userId;
      state = userId == null ? 0 : await _repository.getUnreadCount(userId);
    } finally {
      _isRefreshing = false;
    }
  }
}
