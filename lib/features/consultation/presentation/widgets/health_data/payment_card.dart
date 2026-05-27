import 'package:flutter/material.dart';

class PaymentCard extends StatelessWidget {
  final bool isReady;
  final int price;
  final VoidCallback? onSubmit;

  const PaymentCard({
    super.key,
    required this.isReady,
    required this.price,
    this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final color = isReady ? const Color(0xFF4A8B2C) : Colors.white;
    final textColor = isReady ? Colors.white : Colors.black;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: InkWell(
        onTap: isReady ? onSubmit : null,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: isReady
                    ? const Color(0xFF4A8B2C).withOpacity(0.3)
                    : Colors.black.withOpacity(0.05),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(
              color: isReady
                  ? const Color(0xFF4A8B2C).withOpacity(0.5)
                  : Colors.grey.shade200,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isReady
                      ? Colors.white.withOpacity(0.2)
                      : Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isReady ? Icons.check_circle : Icons.check_circle_outline,
                  color: isReady ? Colors.white : Colors.grey.shade300,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$price บาท',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    Text(
                      isReady
                          ? 'ยืนยันและส่งคำรักษา'
                          : 'กรุณาเลือกระดับความเจ็บปวดก่อน',
                      style: TextStyle(
                        fontSize: 13,
                        color: isReady
                            ? Colors.white.withOpacity(0.9)
                            : Colors.orange.shade800,
                        fontWeight: isReady
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: isReady
                    ? Colors.white.withOpacity(0.5)
                    : Colors.grey.shade300,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
