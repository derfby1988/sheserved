import re

old_path = '/tmp/dashboard_old.dart'
current_path = '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/pages/health_program_request_dashboard.dart'

with open(old_path, 'r', encoding='utf-8') as f:
    old_content = f.read()

# Pattern to capture _acceptJob
accept_job_pattern = re.compile(r'(  Future<void> _acceptJob\(ConsultationEntry entry\) async \{.*?\n  \}\n)', re.DOTALL)
accept_job_match = accept_job_pattern.search(old_content)
accept_job_code = accept_job_match.group(1) if accept_job_match else ''

# Pattern to capture _openChat
open_chat_pattern = re.compile(r'(  void _openChat\(ConsultationEntry entry\) \{.*?\n  \}\n)', re.DOTALL)
open_chat_match = open_chat_pattern.search(old_content)
open_chat_code = open_chat_match.group(1) if open_chat_match else ''

# Pattern to capture _showStatusSheet
show_status_pattern = re.compile(r'(  void _showStatusSheet\(ConsultationEntry e\) \{.*?\n  \}\n)', re.DOTALL)
show_status_match = show_status_pattern.search(old_content)
show_status_code = show_status_match.group(1) if show_status_match else ''

# Pattern to capture _actionBtn
action_btn_pattern = re.compile(r'(  Widget _actionBtn\(\n    String text,\n    Color bgColor,\n    Color textColor,\n    IconData icon,\n    VoidCallback onTap,\n  \) \{.*?\n  \}\n)', re.DOTALL)
action_btn_match = action_btn_pattern.search(old_content)
action_btn_code = action_btn_match.group(1) if action_btn_match else ''

with open(current_path, 'r', encoding='utf-8') as f:
    current_content = f.read()

# Remove trailing }
current_content = current_content.rstrip()
if current_content.endswith('}'):
    current_content = current_content[:-1]

methods_to_add = "\n" + accept_job_code + "\n" + open_chat_code + "\n" + show_status_code + "\n" + action_btn_code + "\n}\n"

with open(current_path, 'w', encoding='utf-8') as f:
    f.write(current_content + methods_to_add)

print("Restored missing methods.")
