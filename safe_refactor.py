import re

src = '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/pages/health_program_request_dashboard.dart'
with open(src, 'r', encoding='utf-8') as f:
    content = f.read()
lines = content.splitlines(keepends=True)

# ── 1. Find class boundaries precisely ──────────────────────────────────────
def find_class_end(lines, start_line_idx):
    """Find the closing } of a top-level class starting at start_line_idx (0-indexed)."""
    depth = 0
    for i, line in enumerate(lines[start_line_idx:], start_line_idx):
        depth += line.count('{') - line.count('}')
        if depth == 0 and i > start_line_idx:
            return i
    return len(lines) - 1

# Find each class start
class_starts = {}
for i, line in enumerate(lines):
    stripped = line.strip()
    for cls in ['class ConsultationEntry', 'class HealthProgramRequestDashboard extends',
                'class _HealthProgramRequestDashboardState',
                'class _AvailabilityBanner', 'class _AvailabilityToggleButton',
                'class ExpertChatRoomPage', 'class _ExpertChatRoomPageState',
                'class _LocalMsg']:
        if stripped.startswith(cls):
            class_starts[cls] = i
            break

print("Class starts:", {k: v for k, v in class_starts.items()})

# Find ends
def get_class_range(lines, start):
    end = find_class_end(lines, start)
    return start, end

ranges = {}
for cls, start in class_starts.items():
    s, e = get_class_range(lines, start)
    ranges[cls] = (s, e)
    print(f"  {cls}: lines {s+1}-{e+1}")

