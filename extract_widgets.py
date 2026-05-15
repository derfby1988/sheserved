import os
import re

file_path = '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/pages/health_program_request_dashboard.dart'
dashboard_widgets_dir = '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/widgets/dashboard/'

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# AvailabilityBanner
banner_pattern = re.compile(r'class _AvailabilityBanner extends StatelessWidget \{.*?\n\}\n', re.DOTALL)
banner_match = banner_pattern.search(content)
if banner_match:
    banner_content = banner_match.group(0).replace('_AvailabilityBanner', 'AvailabilityBanner')
    with open(os.path.join(dashboard_widgets_dir, 'availability_banner.dart'), 'w', encoding='utf-8') as f:
        f.write("import 'package:flutter/material.dart';\nimport '../../../../../core/constants/app_colors.dart';\n\n" + banner_content)
    print("Extracted AvailabilityBanner")

# AvailabilityToggleButton
toggle_pattern = re.compile(r'class _AvailabilityToggleButton extends StatelessWidget \{.*?\n\}\n', re.DOTALL)
toggle_match = toggle_pattern.search(content)
if toggle_match:
    toggle_content = toggle_match.group(0).replace('_AvailabilityToggleButton', 'AvailabilityToggleButton')
    with open(os.path.join(dashboard_widgets_dir, 'availability_toggle_button.dart'), 'w', encoding='utf-8') as f:
        f.write("import 'package:flutter/material.dart';\nimport '../../../../../core/constants/app_colors.dart';\n\n" + toggle_content)
    print("Extracted AvailabilityToggleButton")

# Remove extracted parts from original file
new_content = content
new_content = re.sub(r'// ─── Model: Rich consultation entry with patient info ─────────────────────────\nclass ConsultationEntry \{.*?\n\}\n', '', new_content, flags=re.DOTALL)
new_content = re.sub(r'class _AvailabilityBanner extends StatelessWidget \{.*?\n\}\n', '', new_content, flags=re.DOTALL)
new_content = re.sub(r'// ─── Availability Toggle Button ───────────────────────────────────────────────\nclass _AvailabilityToggleButton extends StatelessWidget \{.*?\n\}\n', '', new_content, flags=re.DOTALL)
new_content = re.sub(r'// ─── Expert Chat Room Page ───────────────────────────────────────────────────\nclass ExpertChatRoomPage extends StatefulWidget \{.*?\n\nclass _ExpertChatRoomPageState extends State<ExpertChatRoomPage> \{.*?\n\}\n', '', new_content, flags=re.DOTALL)
new_content = re.sub(r'// ─── Local message model ──────────────────────────────────────────────────────\nclass _LocalMsg \{.*?\n\}\n', '', new_content, flags=re.DOTALL)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(new_content)

print("Removed extracted parts from main file.")
