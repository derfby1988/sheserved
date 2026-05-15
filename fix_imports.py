import re

file_path = '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/pages/health_program_request_dashboard.dart'

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

imports = """
import '../../data/models/consultation_entry.dart';
import 'expert_chat_room_page.dart';
import '../widgets/dashboard/availability_toggle_button.dart';
"""

# Add imports
content = re.sub(r'(import \'../../../../shared/widgets/widgets.dart\';\n)', r'\1' + imports, content)

# Rename _AvailabilityToggleButton to AvailabilityToggleButton
content = content.replace('_AvailabilityToggleButton', 'AvailabilityToggleButton')

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Fixed imports and references.")
