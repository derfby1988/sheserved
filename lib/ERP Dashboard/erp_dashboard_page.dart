import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Main ERP Dashboard Page – entry point after tapping HomeErpCard.
/// Shows navigation tiles for each ERP module and quick access to settings.
class ErpDashboardPage extends StatelessWidget {
  const ErpDashboardPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ERP Dashboard', style: GoogleFonts.inter()),
        backgroundColor: const Color(0xFF0066FF),
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE0F7FA), Color(0xFFB2EBF2)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: const [
            _ModuleTile(label: 'POS Management', routeName: '/posManagement'),
            _ModuleTile(label: 'Inventory Management', routeName: '/inventoryManagement'),
            _ModuleTile(label: 'Procurement Management', routeName: '/procurementManagement'),
            _ModuleTile(label: 'Accounting Management', routeName: '/accountingManagement'),
            _ModuleTile(label: 'HR Management', routeName: '/hrManagement'),
            _ModuleTile(label: 'CRM Management', routeName: '/crmManagement'),
            _ModuleTile(label: 'Organization Settings', routeName: '/organizationSettings'),
            _ModuleTile(label: 'Permission Management', routeName: '/permissionManagement'),
          ],
        ),
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  final String label;
  final String routeName;
  const _ModuleTile({required this.label, required this.routeName, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).pushNamed(routeName),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.8),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
          ],
        ),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
