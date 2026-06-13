import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/dashboard_theme_provider.dart';

/// หน้า Settings — Theme Tab
/// เลือก Light/Dark mode + Preset colors (Light) / Fixed (Dark)
class ThemeSettingsPage extends ConsumerWidget {
  const ThemeSettingsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardThemeProvider);
    final notifier = ref.read(dashboardThemeProvider.notifier);
    final theme = state.theme;

    if (state.isInitialLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isDark = theme?.isDarkMode ?? false;
    final accentColor = theme?.accentColor ?? const Color(0xFFFFC107);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ธีมสี Dashboard'),
        backgroundColor: theme?.primaryColor ?? const Color(0xFF00695C),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Light / Dark Toggle
            _buildModeToggle(context, isDark, accentColor, notifier),
            const SizedBox(height: 24),

            // Light Mode: Preset Grid
            if (!isDark) ...[
              const Text(
                'เลือกโทนสี',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              _PresetGrid(
                presets: state.presets.where((p) => p.presetKey != 'sheserved_dark').toList(),
                selectedKey: theme?.themePreset,
                onSelect: (key) => notifier.selectPreset(key),
              ),
              const SizedBox(height: 24),
            ],

            // Dark Mode: Fixed display
            if (isDark) ...[
              const Text(
                'Dark Theme',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              _DarkThemePreview(accentColor: accentColor),
              const SizedBox(height: 24),
            ],

            // Custom Colors (เฉพาะ Light mode)
            if (!isDark) ...[
              const Text(
                'สีที่กำหนดเอง',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              _CustomColorSection(notifier: notifier),
              const SizedBox(height: 24),
            ],

            // Actions
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 220,
                  child: ElevatedButton.icon(
                    onPressed: state.isSaving ? null : () => notifier.selectPreset('sheserved_default'),
                    icon: const Icon(Icons.restore),
                    label: const Text('คืนค่าเริ่มต้น'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade200,
                      foregroundColor: Colors.black87,
                    ),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pushNamed('/erp/settings/modules'),
                    icon: const Icon(Icons.dashboard_customize),
                    label: const Text('จัดการกลุ่มการ์ด'),
                  ),
                ),
              ],
            ),

            if (state.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  state.errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeToggle(BuildContext context, bool isDark, Color accentColor, DashboardThemeNotifier notifier) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeButton(
              icon: Icons.wb_sunny,
              label: 'Light',
              isSelected: !isDark,
              onTap: () {
                if (isDark) notifier.toggleDarkMode();
              },
            ),
          ),
          Expanded(
            child: _ModeButton(
              icon: Icons.nightlight_round,
              label: 'Dark',
              isSelected: isDark,
              onTap: () {
                if (!isDark) notifier.toggleDarkMode();
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ========================
// Mode Button
// ========================

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      elevation: isSelected ? 2 : 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: isSelected ? const Color(0xFF00695C) : Colors.grey),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? const Color(0xFF00695C) : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ========================
// Preset Grid
// ========================

class _PresetGrid extends StatelessWidget {
  final List<dynamic> presets;
  final String? selectedKey;
  final ValueChanged<String> onSelect;

  const _PresetGrid({
    required this.presets,
    this.selectedKey,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: presets.map((preset) {
        final isSelected = preset.presetKey == selectedKey;
        return _PresetCircle(
          preset: preset,
          isSelected: isSelected,
          onTap: () => onSelect(preset.presetKey),
        );
      }).toList(),
    );
  }
}

class _PresetCircle extends StatelessWidget {
  final dynamic preset;
  final bool isSelected;
  final VoidCallback onTap;

  const _PresetCircle({
    required this.preset,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = _hexToColor(preset.primaryColor);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: primary,
          borderRadius: BorderRadius.circular(28),
          elevation: isSelected ? 4 : 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onTap,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: isSelected
                    ? Border.all(color: const Color(0xFF00695C), width: 3)
                    : Border.all(color: Colors.transparent, width: 3),
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 24)
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 70,
          child: Text(
            preset.presetNameTh,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  static Color _hexToColor(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) return Color(int.parse('FF$hex', radix: 16));
    if (hex.length == 8) return Color(int.parse(hex, radix: 16));
    return Colors.grey;
  }
}

// ========================
// Dark Theme Preview
// ========================

class _DarkThemePreview extends StatelessWidget {
  final Color accentColor;

  const _DarkThemePreview({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: Color(0xFF0F0F0F),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text('Primary: #0F0F0F', style: TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text('Accent: #${accentColor.value.toRadixString(16).substring(2).toUpperCase()}',
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Dark Theme เป็น preset คงที่ ไม่สามารถปรับแต่งสีได้',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ========================
// Custom Color Section
// ========================

class _CustomColorSection extends StatefulWidget {
  final DashboardThemeNotifier notifier;

  const _CustomColorSection({required this.notifier});

  @override
  State<_CustomColorSection> createState() => _CustomColorSectionState();
}

class _CustomColorSectionState extends State<_CustomColorSection> {
  final _primaryController = TextEditingController(text: '#00695C');
  final _accentController = TextEditingController(text: '#FFC107');
  final _surfaceController = TextEditingController(text: '#FFFFFF');
  final _textPrimaryController = TextEditingController(text: '#FFFFFF');
  final _textSecondaryController = TextEditingController(text: 'rgba(255,255,255,0.7)');
  final _errorController = TextEditingController(text: '#F85149');

  @override
  void dispose() {
    _primaryController.dispose();
    _accentController.dispose();
    _surfaceController.dispose();
    _textPrimaryController.dispose();
    _textSecondaryController.dispose();
    _errorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ColorInput(label: 'Primary (Sidebar BG)', controller: _primaryController),
        _ColorInput(label: 'Accent (Toggle/Badge)', controller: _accentController),
        _ColorInput(label: 'Surface (Card BG)', controller: _surfaceController),
        _ColorInput(label: 'Text Primary', controller: _textPrimaryController),
        _ColorInput(label: 'Text Secondary', controller: _textSecondaryController),
        _ColorInput(label: 'Error', controller: _errorController),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () => widget.notifier.saveCustomColors(
            primary: _primaryController.text,
            accent: _accentController.text,
            surface: _surfaceController.text,
            textPrimary: _textPrimaryController.text,
            textSecondary: _textSecondaryController.text,
            error: _errorController.text,
          ),
          icon: const Icon(Icons.save),
          label: const Text('บันทึกสีที่กำหนดเอง'),
        ),
      ],
    );
  }
}

class _ColorInput extends StatelessWidget {
  final String label;
  final TextEditingController controller;

  const _ColorInput({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}
