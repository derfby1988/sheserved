import re

dashboard_path = '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/pages/health_program_request_dashboard.dart'
card_path = '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/widgets/dashboard/request_item_card.dart'

with open(dashboard_path, 'r', encoding='utf-8') as f:
    dashboard_content = f.read()

# Pattern for _avatar, _statusBadge, _infoRow, _buildActionRow
# These are the last methods in the _HealthProgramRequestDashboardState class.
# We will match from "Widget _avatar" to the end of the file.
pattern = re.compile(r'(  Widget _avatar\(ConsultationEntry e\).*)$', re.DOTALL)
match = pattern.search(dashboard_content)

if match:
    methods_content = match.group(1)
    
    # Remove from dashboard
    new_dashboard_content = dashboard_content.replace(methods_content, "}\n")
    with open(dashboard_path, 'w', encoding='utf-8') as f:
        f.write(new_dashboard_content)

    # Clean up methods content
    methods_content = methods_content.replace('Widget _avatar(ConsultationEntry e)', 'Widget _avatar(ConsultationEntry e, BuildContext context)')
    methods_content = methods_content.replace('_isProvider', 'isProvider')
    methods_content = methods_content.replace('_acceptJob(e)', 'onAcceptJob(e)')
    methods_content = methods_content.replace('_openChat(e)', 'onOpenChat(e)')
    methods_content = methods_content.replace('_availabilityStatus', 'availabilityStatus')
    # Remove the extra '}' at the end of methods_content which belonged to the dashboard class
    methods_content = methods_content.rstrip()
    if methods_content.endswith('}'):
        methods_content = methods_content[:-1]

    # Read card file
    with open(card_path, 'r', encoding='utf-8') as f:
        card_content = f.read()
    
    # Remove the last '}' from card_content
    card_content = card_content.rstrip()
    if card_content.endswith('}'):
        card_content = card_content[:-1]
    
    # Add methods to card
    with open(card_path, 'w', encoding='utf-8') as f:
        f.write(card_content + '\n' + methods_content + '}\n')

print("Moved methods to RequestItemCardWidget.")
