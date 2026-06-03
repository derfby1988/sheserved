import 'package:flutter/material.dart';

/// HomeErpCard
///
/// Replaces `HomePharmacyCard` when a logged‑in user belongs to an organization
/// with `uses_pos_system = true`. Provides a single entry point to the ERP
/// Dashboard (module management, settings, permissions, etc.).
class HomeErpCard extends StatelessWidget {
  const HomeErpCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          // Navigate to the main ERP Dashboard page
          Navigator.of(context).pushNamed('/erpDashboard');
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: const [
              Icon(Icons.dashboard, size: 48, color: Colors.blueAccent),
              SizedBox(width: 16),
              Expanded(
                child: Text(
                  'ERP Dashboard',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
