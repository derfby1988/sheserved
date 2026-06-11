import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/phase_two_provider.dart';
import '../widgets/glass_card.dart';

class CheckoutPage extends ConsumerStatefulWidget {
  final String professionId;

  const CheckoutPage({
    Key? key,
    required this.professionId,
  }) : super(key: key);

  @override
  ConsumerState<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends ConsumerState<CheckoutPage> {
  String _selectedMethod = 'promptpay';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseTwoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ชำระเงิน / Checkout'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildPaymentMethods(),
                const SizedBox(height: 20),
                _buildSummary(),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: state.isSaving ? null : () => _confirmPayment(),
            child: state.isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('ยืนยันการชำระเงิน'),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentMethods() {
    final methods = [
      _PaymentMethod('promptpay', 'PromptPay QR', Icons.qr_code),
      _PaymentMethod('cash', 'เงินสด', Icons.money),
      _PaymentMethod('credit_card', 'บัตรเครดิต', Icons.credit_card),
    ];

    return GlassCard(
      section: GlassSection.card,
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'วิธีชำระเงิน',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...methods.map((m) => RadioListTile<String>(
                title: Row(
                  children: [
                    Icon(m.icon),
                    const SizedBox(width: 12),
                    Text(m.label),
                  ],
                ),
                value: m.value,
                groupValue: _selectedMethod,
                onChanged: (v) => setState(() => _selectedMethod = v!),
              )),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    return GlassCard(
      section: GlassSection.card,
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'สรุปรายการ',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildSummaryRow('ยอดรวม', '฿0.00'),
          _buildSummaryRow('ส่วนลด', '-฿0.00'),
          _buildSummaryRow('VAT', '฿0.00'),
          const Divider(),
          _buildSummaryRow('ยอดสุทธิ', '฿0.00', isTotal: true),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: isTotal ? 16 : 14)),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmPayment() async {
    // TODO: Implement actual payment flow
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('ชำระเงินด้วย $_selectedMethod - WIP')),
    );
  }
}

class _PaymentMethod {
  final String value;
  final String label;
  final IconData icon;

  _PaymentMethod(this.value, this.label, this.icon);
}
