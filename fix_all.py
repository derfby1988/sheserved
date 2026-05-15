import re, subprocess

old_path = '/tmp/dashboard_old.dart'
dash_path = '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/pages/health_program_request_dashboard.dart'
card_path = '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/widgets/dashboard/request_item_card.dart'

with open(old_path, 'r', encoding='utf-8') as f:
    old = f.read()

with open(dash_path, 'r', encoding='utf-8') as f:
    dash = f.read()

# ── recover missing methods from old file ──────────────────────────────────────
patterns = {
    '_buildEmpty': r'(  Widget _buildEmpty\(\) \{.*?\n  \}\n)',
    '_acceptJob':  r'(  Future<void> _acceptJob\(ConsultationEntry entry\) async \{.*?\n  \}\n)',
    '_joinRequest': r'(  Future<void> _joinRequest\(ConsultationEntry entry\) async \{.*?\n  \}\n)',
    '_showStatusSheet': r'(  void _showStatusSheet\(ConsultationEntry e\) \{.*?\n  \}\n)',
    '_actionBtn':  r'(  Widget _actionBtn\(\{.*?\}\) \{.*?\n  \}\n)',
    '_searchController_field': r'(  final TextEditingController _searchController = TextEditingController\(\);)',
}

# Check what's missing in dash
missing_methods = {}
for name, pat in patterns.items():
    if name == '_searchController_field':
        if '_searchController' not in dash:
            m = re.search(pat, old, re.DOTALL)
            if m:
                missing_methods[name] = m.group(1)
    else:
        if f'  {"_" if name.startswith("_") else ""}{name}' not in dash or f'def {name}' not in dash:
            # Check directly
            if name not in dash:
                m = re.search(pat, old, re.DOTALL)
                if m:
                    missing_methods[name] = m.group(1)

# Also always check for missing body methods
for name, pat in patterns.items():
    if name == '_searchController_field':
        continue
    m = re.search(pat, old, re.DOTALL)
    if m and name not in dash:
        missing_methods[name] = m.group(1)

print("Missing:", list(missing_methods.keys()))

# Insert missing field _searchController after state class opening
if '_searchController_field' in missing_methods and '_searchController' not in dash:
    field = missing_methods['_searchController_field']
    dash = dash.replace('  String _filterStatus = \'all\';', f'  String _filterStatus = \'all\';\n  {field}')

# Insert missing methods before the last }
methods_str = '\n'.join(v for k, v in missing_methods.items() if k != '_searchController_field')
# Insert before final closing }
dash = dash.rstrip()
if dash.endswith('}'):
    dash = dash[:-1] + '\n' + methods_str + '\n}\n'

with open(dash_path, 'w', encoding='utf-8') as f:
    f.write(dash)

print('Dashboard fixed.')
