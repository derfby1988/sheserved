import re

file_path = '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/pages/health_program_request_dashboard.dart'
filter_path = '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/widgets/dashboard/dashboard_search_filter.dart'

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Pattern for _buildSearchFilter
method_pattern = re.compile(r'(  Widget _buildSearchFilter\(\) \{.*?\n  \}\n)', re.DOTALL)
match = method_pattern.search(content)

if match:
    method_content = match.group(1)
    
    widget_code = """import 'package:flutter/material.dart';
import '../../../../../core/constants/app_colors.dart';

class DashboardSearchFilterWidget extends StatelessWidget {
  final TextEditingController searchController;
  final String selectedStatusTab;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onTabSelected;

  const DashboardSearchFilterWidget({
    super.key,
    required this.searchController,
    required this.selectedStatusTab,
    required this.onSearchChanged,
    required this.onTabSelected,
  });

  @override
""" + method_content.replace('Widget _buildSearchFilter() {', 'Widget build(BuildContext context) {') \
    .replace('_searchController', 'searchController') \
    .replace('_onSearchChanged', 'onSearchChanged') \
    .replace('setState(() => _selectedStatusTab = status)', 'onTabSelected(status)') \
    .replace('_selectedStatusTab', 'selectedStatusTab')

    with open(filter_path, 'w', encoding='utf-8') as f:
        f.write(widget_code)

    # Update main file
    content = content.replace("import '../widgets/dashboard/dashboard_stat_chip.dart';", "import '../widgets/dashboard/dashboard_stat_chip.dart';\nimport '../widgets/dashboard/dashboard_search_filter.dart';")
    content = content.replace("_buildSearchFilter(),", """DashboardSearchFilterWidget(
          searchController: _searchController,
          selectedStatusTab: _selectedStatusTab,
          onSearchChanged: _onSearchChanged,
          onTabSelected: (status) {
            setState(() => _selectedStatusTab = status);
          },
        ),""")
    content = content.replace(method_content, "")

    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print("Extracted DashboardSearchFilterWidget successfully.")
else:
    print("Could not find _buildSearchFilter.")
