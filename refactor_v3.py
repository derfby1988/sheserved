"""
Safe refactor v3 - wait for opening brace before counting nesting depth.
"""
import os, re

src  = '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/pages/health_program_request_dashboard.dart'
base = '/Users/dave_macmini/sheserved/lib/features/consultation'

with open(src, 'r', encoding='utf-8') as f:
    lines = f.readlines()

def find_class_end(lines, class_start_idx):
    """
    Find the closing } of a class. 
    Wait for the first { after the class keyword before tracking nesting.
    """
    found_open = False
    depth = 0
    for i, line in enumerate(lines[class_start_idx:], class_start_idx):
        for ch in line:
            if not found_open:
                if ch == '{':
                    found_open = True
                    depth = 1
            else:
                if ch == '{':
                    depth += 1
                elif ch == '}':
                    depth -= 1
                    if depth == 0:
                        return i
    return len(lines) - 1

# ── Find class starts by keyword ───────────────────────────────────────────
target_classes = {
    'ConsultationEntry':             'class ConsultationEntry {',
    'HealthProgramRequestDashboard': 'class HealthProgramRequestDashboard extends',
    '_HealthProgramRequestDashboardState': 'class _HealthProgramRequestDashboardState',
    '_AvailabilityBanner':           'class _AvailabilityBanner extends',
    '_AvailabilityToggleButton':     'class _AvailabilityToggleButton extends',
    'ExpertChatRoomPage':            'class ExpertChatRoomPage extends',
    '_ExpertChatRoomPageState':      'class _ExpertChatRoomPageState extends',
    '_LocalMsg':                     'class _LocalMsg {',
}

starts = {}
for name, keyword in target_classes.items():
    for i, line in enumerate(lines):
        if keyword in line:
            starts[name] = i
            break

# compute ends
ends = {}
for name, s in starts.items():
    ends[name] = find_class_end(lines, s)

for name in starts:
    print(f"  {name}: lines {starts[name]+1}–{ends[name]+1}")

# ── Helper ──────────────────────────────────────────────────────────────────
def block(s, e):
    return ''.join(lines[s:e+1])

# ── 1. consultation_entry.dart ──────────────────────────────────────────────
with open(f'{base}/data/models/consultation_entry.dart', 'w') as f:
    f.write(block(starts['ConsultationEntry'], ends['ConsultationEntry']) + '\n')
print("✓ consultation_entry.dart")

# ── 2. local_chat_message.dart ──────────────────────────────────────────────
local_msg = block(starts['_LocalMsg'], ends['_LocalMsg'])
local_msg = local_msg.replace('class _LocalMsg', 'class LocalChatMessage')
with open(f'{base}/data/models/local_chat_message.dart', 'w') as f:
    f.write(local_msg + '\n')
print("✓ local_chat_message.dart")

# ── 3. availability_banner.dart ─────────────────────────────────────────────
banner = block(starts['_AvailabilityBanner'], ends['_AvailabilityBanner'])
banner = banner.replace('_AvailabilityBanner', 'AvailabilityBanner')
with open(f'{base}/presentation/widgets/dashboard/availability_banner.dart', 'w') as f:
    f.write("import 'package:flutter/material.dart';\nimport '../../../../core/constants/app_colors.dart';\n\n")
    f.write(banner + '\n')
print("✓ availability_banner.dart")

# ── 4. availability_toggle_button.dart ──────────────────────────────────────
toggle = block(starts['_AvailabilityToggleButton'], ends['_AvailabilityToggleButton'])
toggle = toggle.replace('_AvailabilityToggleButton', 'AvailabilityToggleButton')
with open(f'{base}/presentation/widgets/dashboard/availability_toggle_button.dart', 'w') as f:
    f.write("import 'package:flutter/material.dart';\nimport '../../../../core/constants/app_colors.dart';\n\n")
    f.write(toggle + '\n')
print("✓ availability_toggle_button.dart")

# ── 5. expert_chat_room_page.dart ────────────────────────────────────────────
# Include both ExpertChatRoomPage + _ExpertChatRoomPageState
chat_start = starts['ExpertChatRoomPage']
chat_end   = ends['_ExpertChatRoomPageState']
chat = block(chat_start, chat_end)
chat = chat.replace('_LocalMsg', 'LocalChatMessage')

orig_imports = block(0, starts['ConsultationEntry'] - 1)  # lines before ConsultationEntry

extra = (
    "import '../../data/models/consultation_entry.dart';\n"
    "import '../../data/models/local_chat_message.dart';\n"
)
with open(f'{base}/presentation/pages/expert_chat_room_page.dart', 'w') as f:
    f.write(orig_imports)
    f.write(extra)
    f.write('\n')
    f.write(chat)
    f.write('\n')
print("✓ expert_chat_room_page.dart")

# ── 6. Rewrite dashboard ─────────────────────────────────────────────────────
# Keep: imports, HealthProgramRequestDashboard, _HealthProgramRequestDashboardState
dash_start = starts['HealthProgramRequestDashboard']
dash_end   = ends['_HealthProgramRequestDashboardState']
dashboard_body = block(dash_start, dash_end)

# Rename inline widget references
dashboard_body = dashboard_body.replace('_AvailabilityToggleButton(', 'AvailabilityToggleButton(')
dashboard_body = dashboard_body.replace('_AvailabilityBanner(', 'AvailabilityBanner(')

new_dash = (
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
) + dashboard_body + '\n'

with open(src, 'w') as f:
    f.write(new_dash)

print(f"✓ dashboard rewritten ({len(new_dash.splitlines())} lines)")
