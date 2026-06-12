import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../../data/models/payment_channel.dart';
import '../providers/phase_two_provider.dart';
import '../widgets/glass_card.dart';

class PaymentChannelsPage extends ConsumerStatefulWidget {
  final String professionId;

  const PaymentChannelsPage({
    Key? key,
    required this.professionId,
  }) : super(key: key);

  @override
  ConsumerState<PaymentChannelsPage> createState() => _PaymentChannelsPageState();
}

class _PaymentChannelsPageState extends ConsumerState<PaymentChannelsPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseTwoProvider.notifier).loadPaymentChannels(widget.professionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseTwoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ช่องทางชำระเงิน / Payment Channels'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.errorMessage != null
              ? Center(child: Text('Error: ${state.errorMessage}'))
              : state.paymentChannels.isEmpty
                  ? const Center(
                      child: Text(
                        'ยังไม่มีช่องทางชำระเงิน',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: state.paymentChannels.length,
                      itemBuilder: (context, index) {
                        final channel = state.paymentChannels[index];
                        return _PaymentChannelCard(
                          channel: channel,
                          onToggle: (enabled) async {
                            final success = await ref
                                .read(phaseTwoProvider.notifier)
                                .togglePaymentChannel(channel.id, enabled);
                            if (!success && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('อัปเดตไม่สำเร็จ')),
                              );
                            }
                          },
                        );
                      },
                    ),
    );
  }
}

class _PaymentChannelCard extends StatelessWidget {
  final PaymentChannel channel;
  final ValueChanged<bool> onToggle;

  const _PaymentChannelCard({
    required this.channel,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 12,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            _buildIcon(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.channelName,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  Text(
                    'ประเภท: ${_typeLabel(channel.channelType)} · ค่าธรรมเนียม ${channel.feePercent.toStringAsFixed(2)}%',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            if (channel.isDefault)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'ค่าเริ่มต้น',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Switch(
              value: channel.isEnabled,
              onChanged: onToggle,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon() {
    final iconData = _resolveIcon(channel.iconName);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(iconData, color: Colors.blue, size: 24),
    );
  }

  IconData _resolveIcon(String? name) {
    switch (name) {
      case 'qr_code':
        return Icons.qr_code;
      case 'credit_card':
        return Icons.credit_card;
      case 'money':
        return Icons.money;
      case 'account_balance':
        return Icons.account_balance;
      case 'wallet':
        return Icons.account_balance_wallet;
      default:
        return Icons.payment;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'cash':
        return 'เงินสด';
      case 'bank_transfer':
        return 'โอนเงิน';
      case 'promptpay':
        return 'PromptPay';
      case 'credit_card':
        return 'บัตรเครดิต';
      case 'e_wallet':
        return 'e-Wallet';
      default:
        return 'อื่นๆ';
    }
  }
}
