import re

# ── 1. Fix import path in availability_toggle_button.dart ───────────────────
for fname in [
    '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/widgets/dashboard/availability_toggle_button.dart',
    '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/widgets/dashboard/availability_banner.dart',
]:
    with open(fname, 'r') as f: c = f.read()
    # 4 levels up → 5 levels up
    c = c.replace(
        "import '../../../../core/constants/app_colors.dart';",
        "import '../../../../../core/constants/app_colors.dart';"
    )
    with open(fname, 'w') as f: f.write(c)
    print(f"Fixed import in {fname.split('/')[-1]}")

# ── 2. Add AvailabilityBanner import to dashboard ───────────────────────────
dash = '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/pages/health_program_request_dashboard.dart'
with open(dash, 'r') as f: c = f.read()
if 'availability_banner.dart' not in c:
    c = c.replace(
        "import '../widgets/dashboard/availability_toggle_button.dart';",
        "import '../widgets/dashboard/availability_toggle_button.dart';\nimport '../widgets/dashboard/availability_banner.dart';"
    )
    with open(dash, 'w') as f: f.write(c)
    print("Added AvailabilityBanner import to dashboard")
else:
    print("AvailabilityBanner import already present")

# ── 3. Check home_page.dart for initialFocusId usage ────────────────────────
home = '/Users/dave_macmini/sheserved/lib/features/home/presentation/pages/home_page.dart'
with open(home, 'r') as f: hc = f.read()
# Check what's around line 546
lines = hc.splitlines()
for i, l in enumerate(lines):
    if 'initialFocusId' in l:
        print(f"home_page.dart line {i+1}: {l.strip()}")
        print(f"  context: {lines[max(0,i-2):i+3]}")
