import re

file_path = '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/pages/health_program_request_dashboard.dart'

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace("selectedStatusTab: _selectedStatusTab,", "selectedStatusTab: _filterStatus,")
content = content.replace("setState(() => _selectedStatusTab = status);", "setState(() => _filterStatus = status);\n            _applyFilter();")
content = content.replace("onSearchChanged: _onSearchChanged,", "onSearchChanged: (v) {\n            setState(() => _searchQuery = v);\n            _applyFilter();\n          },")

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Fixed DashboardSearchFilterWidget usage in dashboard.")
