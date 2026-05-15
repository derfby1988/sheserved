import re

file_path = '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/pages/health_program_request_dashboard.dart'
card_path = '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/widgets/dashboard/request_item_card.dart'

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Pattern for _buildCard (we'll capture up to the end of the class _HealthProgramRequestDashboardState)
# Since it's the last method in the state class, we can find it and replace it.
method_pattern = re.compile(r'(  Widget _buildCard\(ConsultationEntry e, int index\) \{.*?\n  \}\n)', re.DOTALL)
match = method_pattern.search(content)

if match:
    method_content = match.group(1)
    
    widget_code = """import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../data/models/consultation_entry.dart';
import '../../../../../shared/widgets/widgets.dart';

class RequestItemCardWidget extends StatelessWidget {
  final ConsultationEntry e;
  final int index;
  final bool isProvider;
  final String availabilityStatus;
  final Future<void> Function(ConsultationEntry) onAcceptJob;
  final void Function(ConsultationEntry) onOpenChat;

  const RequestItemCardWidget({
    super.key,
    required this.e,
    required this.index,
    required this.isProvider,
    required this.availabilityStatus,
    required this.onAcceptJob,
    required this.onOpenChat,
  });

  @override
""" + method_content.replace('Widget _buildCard(ConsultationEntry e, int index) {', 'Widget build(BuildContext context) {') \
    .replace('_isProvider', 'isProvider') \
    .replace('_availabilityStatus', 'availabilityStatus') \
    .replace('_acceptJob(e)', 'onAcceptJob(e)') \
    .replace('_openChat(e)', 'onOpenChat(e)')

    with open(card_path, 'w', encoding='utf-8') as f:
        f.write(widget_code)

    # Update main file
    content = content.replace("import '../widgets/dashboard/dashboard_search_filter.dart';", "import '../widgets/dashboard/dashboard_search_filter.dart';\nimport '../widgets/dashboard/request_item_card.dart';")
    content = content.replace("_buildCard(_filtered[i], i)", """RequestItemCardWidget(
                        e: _filtered[i],
                        index: i,
                        isProvider: _isProvider,
                        availabilityStatus: _availabilityStatus,
                        onAcceptJob: _acceptJob,
                        onOpenChat: _openChat,
                      )""")
    content = content.replace(method_content, "")

    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print("Extracted RequestItemCardWidget successfully.")
else:
    print("Could not find _buildCard.")
