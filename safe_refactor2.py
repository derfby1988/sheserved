"""
Safe refactor: extract classes into new files, then strip from dashboard and add imports.
All operations are line-based using the confirmed line ranges.
"""

src = '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/pages/health_program_request_dashboard.dart'
base = '/Users/dave_macmini/sheserved/lib/features/consultation'

with open(src, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# 0-indexed inclusive ranges confirmed from previous step
# class ConsultationEntry: lines 15-86  →  idx 14-85
# class _AvailabilityBanner: lines 1171-1216  →  idx 1170-1215
# class _AvailabilityToggleButton: lines 1219-1267  →  idx 1218-1266
# class ExpertChatRoomPage: lines 1270-1276  →  idx 1269-1275
# class _ExpertChatRoomPageState: lines 1278-1957  →  idx 1277-1956
# class _LocalMsg: lines 1960-1972  →  idx 1959-1971

# Helper
def get_block(lines, s, e):
    """0-indexed inclusive"""
    return ''.join(lines[s:e+1])

# ── 1. consultation_entry.dart ───────────────────────────────────────────────
entry_code = get_block(lines, 14, 85)
with open(f'{base}/data/models/consultation_entry.dart', 'w', encoding='utf-8') as f:
    f.write(entry_code)
print("Written: consultation_entry.dart")

# ── 2. local_chat_message.dart ───────────────────────────────────────────────
local_msg_code = get_block(lines, 1959, 1971)
local_msg_code = local_msg_code.replace('class _LocalMsg', 'class LocalChatMessage')
with open(f'{base}/data/models/local_chat_message.dart', 'w', encoding='utf-8') as f:
    f.write(local_msg_code)
print("Written: local_chat_message.dart")

# ── 3. availability_banner.dart ──────────────────────────────────────────────
banner_code = get_block(lines, 1170, 1215)
banner_code = banner_code.replace('class _AvailabilityBanner', 'class AvailabilityBanner')
banner_imports = (
    "import 'package:flutter/material.dart';\n"
    "import '../../../../core/constants/app_colors.dart';\n\n"
)
with open(f'{base}/presentation/widgets/dashboard/availability_banner.dart', 'w', encoding='utf-8') as f:
    f.write(banner_imports + banner_code)
print("Written: availability_banner.dart")

# ── 4. availability_toggle_button.dart ──────────────────────────────────────
toggle_code = get_block(lines, 1218, 1266)
toggle_code = toggle_code.replace('class _AvailabilityToggleButton', 'class AvailabilityToggleButton')
toggle_imports = (
    "import 'package:flutter/material.dart';\n"
    "import '../../../../core/constants/app_colors.dart';\n\n"
)
with open(f'{base}/presentation/widgets/dashboard/availability_toggle_button.dart', 'w', encoding='utf-8') as f:
    f.write(toggle_imports + toggle_code)
print("Written: availability_toggle_button.dart")

# ── 5. expert_chat_room_page.dart ────────────────────────────────────────────
# ExpertChatRoomPage: 1269-1275, _ExpertChatRoomPageState: 1277-1956
chat_code = get_block(lines, 1269, 1956)
chat_code = chat_code.replace('_LocalMsg', 'LocalChatMessage')

# Get original imports (lines 0-13)
orig_imports = get_block(lines, 0, 13)
# Add extra imports needed
extra_imports = (
    "import '../../data/models/consultation_entry.dart';\n"
    "import '../../data/models/local_chat_message.dart';\n"
)
chat_imports = orig_imports + extra_imports

with open(f'{base}/presentation/pages/expert_chat_room_page.dart', 'w', encoding='utf-8') as f:
    f.write(chat_imports + "\n" + chat_code)
print("Written: expert_chat_room_page.dart")

# ── 6. Rewrite dashboard: keep imports + _HealthProgramRequestDashboard classes only ──
# Lines to keep in dashboard:
# 0-13: imports
# 88-1169: HealthProgramRequestDashboard + _HealthProgramRequestDashboardState
# (skip ConsultationEntry 14-85, skip banner 1170-1266, skip chat 1269-1956, skip LocalMsg 1959-1971)

# Get comment line before AvailabilityBanner if any (line 1169 = idx 1168)
# State class ends at line 1168 based on what's between state and banner

# Actually let's find exact end of _HealthProgramRequestDashboardState
# We know it's between line 97-??? and _AvailabilityBanner starts at 1171
# The state class must end before 1170. Let's find it via brace counting.

def find_class_end(lines, start):
    depth = 0
    for i, line in enumerate(lines[start:], start):
        depth += line.count('{') - line.count('}')
        if depth == 0 and i > start:
            return i
    return len(lines) - 1

state_end = find_class_end(lines, 96)  # _HealthProgramRequestDashboardState starts at idx 96
print(f"State class ends at line {state_end+1}")

# New dashboard imports
new_imports = (
    "import 'dart:async';\n"
    "import 'package:flutter/material.dart';\n"
    "import 'package:intl/intl.dart';\n"
    "import '../../../../core/constants/app_colors.dart';\n"
    "import '../../../../services/service_locator.dart';\n"
    "import '../../../../services/auth_service.dart';\n"
    "import '../../../../features/auth/data/repositories/user_repository.dart';\n"
    "import 'package:supabase_flutter/supabase_flutter.dart';\n"
    "import '../../../chat/data/models/chat_models.dart';\n"
    "import '../../data/repositories/consultation_repository.dart';\n"
    "import '../../data/models/consultation_entry.dart';\n"
    "import '../../../../shared/widgets/widgets.dart';\n"
    "import 'expert_chat_room_page.dart';\n"
    "import '../widgets/dashboard/availability_toggle_button.dart';\n"
    "\n"
)

# Dashboard body: StatefulWidget (88-95) + State (96-state_end)
dashboard_body = get_block(lines, 88, state_end)

# Rename _AvailabilityToggleButton and _AvailabilityBanner references
dashboard_body = dashboard_body.replace('_AvailabilityToggleButton', 'AvailabilityToggleButton')
dashboard_body = dashboard_body.replace('_AvailabilityBanner', 'AvailabilityBanner')

new_dashboard = new_imports + dashboard_body + "\n"

with open(src, 'w', encoding='utf-8') as f:
    f.write(new_dashboard)

print(f"Rewrote dashboard: {len(new_dashboard.splitlines())} lines")
