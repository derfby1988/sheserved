"""Fix request_item_card.dart: correct TlzButton API usage and imports."""

card_path = '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/widgets/dashboard/request_item_card.dart'

with open(card_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Fix TlzButton.primary(text:..., onPressed:...) -> TlzButton(text:..., onPressed:..., type: TlzButtonType.primary, isFullWidth: true)
import re

# Replace TlzButton.primary( with TlzButton(type: TlzButtonType.primary, isFullWidth: true, 
content = re.sub(r'TlzButton\.primary\(', 'TlzButton(type: TlzButtonType.primary, isFullWidth: true, ', content)
# Replace TlzButton.outline( with TlzButton(type: TlzButtonType.outline, isFullWidth: true,
content = re.sub(r'TlzButton\.outline\(', 'TlzButton(type: TlzButtonType.outline, isFullWidth: true, ', content)

# Fix textColor parameter (TlzButton.outline had textColor: as named param which is supported)
# Already handled since the constructor supports it.

# Make sure import of consultation_entry is present
if "import '../../data/models/consultation_entry.dart';" not in content:
    content = content.replace(
        "import 'package:flutter/material.dart';",
        "import 'package:flutter/material.dart';\nimport '../../data/models/consultation_entry.dart';"
    )

with open(card_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Fixed request_item_card.dart")
