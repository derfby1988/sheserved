import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../features/erp/presentation/providers/organization_settings_provider.dart';
import '../features/admin/models/organization_settings.dart';
import 'erp_first_time_setup_page.dart';

/// Main ERP Dashboard Page – entry point after tapping HomeErpCard.
/// Shows Organization Header (real data), branch selector, and module tiles.
class ErpDashboardPage extends ConsumerStatefulWidget {
  const ErpDashboardPage({Key? key}) : super(key: key);

  @override
  ConsumerState<ErpDashboardPage> createState() => _ErpDashboardPageState();
}

class _ErpDashboardPageState extends ConsumerState<ErpDashboardPage> {
  @override
  void initState() {
    super.initState();
    // Load organization from current user on first build
    Future.microtask(() {
      ref.read(organizationSettingsProvider.notifier).loadFromCurrentUser();
    });
  }

  @override
  Widget build(BuildContext context) {
    final orgState = ref.watch(organizationSettingsProvider);

    // First-time setup: no org data yet (but user has profession_id)
    if (!orgState.isLoading && orgState.settings == null) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE0F7FA), Color(0xFFB2EBF2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const ErpFirstTimeSetupPage(),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE0F7FA), Color(0xFFB2EBF2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          // Organization Header
          _OrganizationHeader(
            isLoading: orgState.isLoading,
            settings: orgState.settings,
            selectedBranchId: orgState.selectedBranchId,
            onBranchChanged: (branchId) {
              ref.read(organizationSettingsProvider.notifier).selectBranch(branchId);
            },
          ),

            if (orgState.errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    orgState.errorMessage!,
                    style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                  ),
                ),
              ),

            // Module Grid
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  children: const [
                    _ModuleTile(label: 'POS Management', routeName: '/posManagement', icon: Icons.point_of_sale),
                    _ModuleTile(label: 'Inventory Management', routeName: '/inventoryManagement', icon: Icons.inventory_2),
                    _ModuleTile(label: 'Procurement Management', routeName: '/procurementManagement', icon: Icons.shopping_bag),
                    _ModuleTile(label: 'Accounting Management', routeName: '/accountingManagement', icon: Icons.account_balance),
                    _ModuleTile(label: 'HR Management', routeName: '/hrManagement', icon: Icons.people_alt),
                    _ModuleTile(label: 'CRM Management', routeName: '/crmManagement', icon: Icons.contact_support),
                    _ModuleTile(label: 'KPI / Analytics', routeName: '/kpi/dashboard', icon: Icons.analytics, color: Color(0xFF0066FF)),
                    _ModuleTile(label: 'Organization Settings', routeName: '/erp/settings', icon: Icons.business),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
  }
}

/// Organization Header widget — แสดงชื่อองค์กร, โลโก้, สาขา
class _OrganizationHeader extends StatelessWidget {
  final bool isLoading;
  final OrganizationSettings? settings;
  final String? selectedBranchId;
  final ValueChanged<String> onBranchChanged;

  const _OrganizationHeader({
    required this.isLoading,
    required this.settings,
    required this.selectedBranchId,
    required this.onBranchChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (settings == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.business, color: Colors.grey),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'กำลังโหลดข้อมูลองค์กร...',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey),
              ),
            ),
          ],
        ),
      );
    }

    final org = settings!;
    final selectedBranch = selectedBranchId != null
        ? org.branches.firstWhere(
            (b) => b.id == selectedBranchId,
            orElse: () => org.selectedBranch ?? const OrganizationBranch(id: '', branchCode: '', branchName: ''),
          )
        : org.selectedBranch;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          // Logo
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(8),
              image: org.hasLogo
                  ? DecorationImage(
                      image: NetworkImage(org.logoUrl!),
                      fit: BoxFit.contain,
                    )
                  : null,
            ),
            child: org.hasLogo ? null : const Icon(Icons.business, size: 32, color: Color(0xFF0066FF)),
          ),
          const SizedBox(width: 12),

          // Org name + Branch selector
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  org.professionName,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A2E),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                if (org.branches.length > 1)
                  _BranchDropdown(
                    branches: org.branches,
                    selectedBranchId: selectedBranchId,
                    onChanged: onBranchChanged,
                  )
                else if (selectedBranch != null)
                  Text(
                    selectedBranch.branchName,
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),

          // Notification bell (placeholder)
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Color(0xFF0066FF)),
            onPressed: () {
              // TODO: navigate to notifications
            },
          ),
        ],
      ),
    );
  }
}

/// Dropdown เลือกสาขา
class _BranchDropdown extends StatelessWidget {
  final List<OrganizationBranch> branches;
  final String? selectedBranchId;
  final ValueChanged<String> onChanged;

  const _BranchDropdown({
    required this.branches,
    required this.selectedBranchId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFD0E3FF)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isDense: true,
          value: selectedBranchId ?? (branches.isNotEmpty ? branches.first.id : null),
          icon: const Icon(Icons.expand_more, size: 18, color: Color(0xFF0066FF)),
          items: branches.map((branch) {
            return DropdownMenuItem<String>(
              value: branch.id,
              child: Text(
                branch.branchName,
                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF0066FF)),
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  final String label;
  final String routeName;
  final IconData icon;
  final Color? color;

  const _ModuleTile({
    required this.label,
    required this.routeName,
    required this.icon,
    this.color,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tileColor = color ?? const Color(0xFF0066FF);
    return InkWell(
      onTap: () => Navigator.of(context).pushNamed(routeName),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tileColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: tileColor),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF1A1A2E)),
            ),
          ],
        ),
      ),
    );
  }
}
