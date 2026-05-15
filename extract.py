import os
import re

file_path = '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/pages/health_program_request_dashboard.dart'
chat_page_path = '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/pages/expert_chat_room_page.dart'
dashboard_widgets_dir = '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/widgets/dashboard/'

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Pattern for ExpertChatRoomPage and _ExpertChatRoomPageState
chat_pattern = re.compile(r'(class ExpertChatRoomPage extends StatefulWidget \{.*?\n\n)(class _ExpertChatRoomPageState extends State<ExpertChatRoomPage> \{.*?\n\n)(?=(?:class|// ─── Local message model))', re.DOTALL)
match = chat_pattern.search(content)

if match:
    expert_chat_content = match.group(0)
    imports = """import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../services/service_locator.dart';
import '../../../../features/auth/data/repositories/user_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../chat/data/models/chat_models.dart';
import '../../data/repositories/consultation_repository.dart';
import '../../data/models/consultation_entry.dart';
import '../../data/models/local_chat_message.dart';
import 'health_program_request_dashboard.dart';

"""
    
    # Replace _LocalMsg with LocalChatMessage
    expert_chat_content = expert_chat_content.replace('_LocalMsg', 'LocalChatMessage')

    with open(chat_page_path, 'w', encoding='utf-8') as f:
        f.write(imports + expert_chat_content)
    
    print("Extracted ExpertChatRoomPage successfully.")
else:
    print("Could not find ExpertChatRoomPage.")

