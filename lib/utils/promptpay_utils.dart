// PromptPay Generation Utility
class PromptPayUtils {
  static String generateQrCode({required String promptPayId, double? amount}) {
    // 000201 = Payload Format Indicator (01)
    // 010211 = Point of Initiation Method (11 = Static, 12 = Dynamic)
    String payload = "000201010211";

    // 29 = Merchant Account Info
    String target = promptPayId.replaceAll(RegExp(r'[^0-9]'), '');
    String pPId = "";
    
    // Check PromptPay type
    if (target.length >= 15) {
      // e-Wallet ID (15 digits)
      pPId = "0315$target";
    } else if (target.length == 13) {
      // Citizen ID (13 digits)
      pPId = "0213$target";
    } else {
      // Mobile Number (Phone number typically 10 digits)
      if (target.startsWith("0")) {
        target = "66${target.substring(1)}";
      }
      pPId = "0113$target";
    }

    // 0016A000000677010111 = Application ID for PromptPay
    String merchantInfo = "0016A000000677010111$pPId";
    String merchantInfoLen = merchantInfo.length.toString().padLeft(2, '0');
    payload += "29$merchantInfoLen$merchantInfo";
    
    // 5802TH = Country Code (TH)
    // 5303764 = Transaction Currency (THB = 764)
    payload += "5802TH5303764";

    // Amount (optional)
    if (amount != null && amount > 0) {
      String amtStr = amount.toStringAsFixed(2);
      String amtLen = amtStr.length.toString().padLeft(2, '0');
      payload += "54$amtLen$amtStr";
    }

    // 5802TH (Country Code) sometimes needed after if not provided correctly, but order matters.
    // The spec requires 6304 at the end for CRC
    payload += "6304";
    
    // Calculate CRC16
    String crc = _crc16(payload).toRadixString(16).padLeft(4, '0').toUpperCase();
    return payload + crc;
  }

  // CRC16-CCITT (0xFFFF) implementation
  static int _crc16(String payload) {
    int crc = 0xFFFF;
    for (int i = 0; i < payload.length; i++) {
      crc ^= (payload.codeUnitAt(i) << 8);
      for (int j = 0; j < 8; j++) {
        if ((crc & 0x8000) != 0) {
          crc = (crc << 1) ^ 0x1021;
        } else {
          crc = crc << 1;
        }
      }
      crc &= 0xFFFF;
    }
    return crc;
  }
}
