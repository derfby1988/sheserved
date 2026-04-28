import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../utils/promptpay_utils.dart';
import 'image_upload_field.dart';

/// วิดเจ็ตสำหรับแสดง QR Code พร้อมเพย์ และช่องอัปโหลดสลิป
/// ใช้เป็นฟีเจอร์กลางเพื่อรอให้แอดมินหรือระบบ API (เช่น SlipOk) ตรวจสอบต่อไป
class PromptPaySlipUploader extends StatelessWidget {
  /// เบอร์โทรศัพท์ หรือ เลชบัตรประชาชน พร้อมเพย์
  final String promptPayId;
  
  /// (Optional) ยอดเงินที่ต้องการให้โอน ถ้ามีจะฝังลงใน QR
  final double? targetAmount;
  
  /// ชื่อเจ้าของบัญชี หรือข้อความอธิบาย (จะแสดงใต้ QR Code)
  final String accountName;
  
  /// ฟังก์ชัน callback เมื่อผู้ใช้อัปโหลดสลิปเสร็จสิ้น (คืนค่า URL รูปภาพ)
  final ValueChanged<String> onSlipUploaded;
  
  /// ฟังก์ชัน callback เมื่อผู้ใช้ลบ/ยกเลิกรูปที่อัปโหลด
  final VoidCallback? onSlipRemoved;
  
  /// (Optional) รูปสลิปเดิมหากเคยอัปโหลดไว้แล้ว 
  final String? initialSlipUrl;

  const PromptPaySlipUploader({
    super.key,
    required this.promptPayId,
    required this.accountName,
    required this.onSlipUploaded,
    this.targetAmount,
    this.onSlipRemoved,
    this.initialSlipUrl,
  });

  @override
  Widget build(BuildContext context) {
    // สร้าง Payload สำหรับ PromptPay QR
    final qrPayload = PromptPayUtils.generateQrCode(
      promptPayId: promptPayId,
      amount: targetAmount,
    );

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Section 1: QR Code พร้อมเพย์ ──
            const Text(
              'รับเงินผ่านพร้อมเพย์ (PromptPay)', 
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            
            // ใช้ qr_flutter แสดงภาพ QR
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: QrImageView(
                  data: qrPayload,
                  version: QrVersions.auto,
                  size: 200.0,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF113566), // สีน้ำเงินพร้อมเพย์
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF113566),
                  ),
                  // สามารถใส่โลโก้พร้อมเพย์ตรงกลางได้หากมี assets
                  // embeddedImage: AssetImage('assets/images/promptpay_logo.png'),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // ข้อมูลบัญชีและปุ่มคัดลอก
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(accountName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('พร้อมเพย์: $promptPayId', style: TextStyle(color: Colors.grey.shade700)),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: promptPayId));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('คัดลอกหมายเลขพร้อมเพย์แล้ว')),
                          );
                        },
                        child: const Icon(Icons.copy_rounded, size: 16, color: Colors.blue),
                      )
                    ],
                  ),
                  if (targetAmount != null && targetAmount! > 0) ...[
                    const SizedBox(height: 4),
                    Text('ยอดเงิน: $targetAmount บาท', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  ]
                ],
              ),
            ),
            
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Divider(height: 1),
            ),

            // ── Section 2: อัปโหลดสลิป ──
            const Text(
              'แนบหลักฐานการโอนเงิน (สลิป)', 
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'กรุณาอัปโหลดรูปภาพสลิปที่สำเร็จ เพื่อส่งให้แอดมินหรือระบบตรวจสอบ', 
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            
            // นำ ImageUploadField ที่พัฒนาไว้มาครอบให้ทำงานได้เลย
            ImageUploadField(
              label: '',
              bucket: 'donations',
              pathPrefix: 'slips/', // จัดเก็บแยก folder ชัดเจน
              initialUrl: initialSlipUrl,
              quality: 85, // สำหรับสลิปอาจจะขอคุณภาพสูงขึ้นเล็กน้อยเพื่อเผื่อเปิดอ่าน QR
              maxDimension: 1280,
              onUploaded: onSlipUploaded,
              onRemoved: onSlipRemoved,
            ),
          ],
        ),
      ),
    );
  }
}
