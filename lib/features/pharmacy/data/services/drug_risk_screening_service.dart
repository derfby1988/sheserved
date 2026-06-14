import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ผลลัพธ์การตรวจสอบความเสี่ยงของยาแต่ละรายการ
class DrugRiskScreeningResult {
  final String medicationName;
  final bool isBlocked;
  final bool isWarning;
  final String fdaRiskStatus;
  final String fdaStatusNameTh;
  final String? dangerousSubCategory;
  final String? dangerousSubCategoryName;
  final String? customRiskLevel;
  final String? customRiskLevelName;
  final String blockReason;
  final String blockCode;
  final String legalBasis;
  final String prescriptionCondition;
  final String pharmacistDispensingRule;
  final String? requiredLicense;
  final bool providerHasLicense;
  final List<String> additionalNotes;

  const DrugRiskScreeningResult({
    required this.medicationName,
    required this.isBlocked,
    this.isWarning = false,
    this.fdaRiskStatus = '',
    this.fdaStatusNameTh = '',
    this.dangerousSubCategory,
    this.dangerousSubCategoryName,
    this.customRiskLevel,
    this.customRiskLevelName,
    this.blockReason = '',
    this.blockCode = '',
    this.legalBasis = '',
    this.prescriptionCondition = '',
    this.pharmacistDispensingRule = '',
    this.requiredLicense,
    this.providerHasLicense = true,
    this.additionalNotes = const [],
  });

  /// สรุปข้อความแสดงผลลัพธ์
  String get summary {
    if (isBlocked) return 'ห้ามสั่งผ่าน Telemedicine';
    if (isWarning) return 'ต้องระวัง — ตรวจสอบเงื่อนไข';
    return 'อนุญาตสั่งผ่าน Telemedicine';
  }
}

/// บริการตรวจสอบความเสี่ยงยาก่อนสั่งจ่าย
class DrugRiskScreeningService {
  DrugRiskScreeningService(SupabaseClient client);

  /// ข้อมูล FDA Risk Status
  static const Map<String, Map<String, dynamic>> _fdaRiskInfo = {
    'ND': {
      'nameTh': 'ยาสามัญประจำบ้าน',
      'nameEn': 'Household Remedy',
      'telemedicineAllowed': true,
      'legalBasis': 'พ.ร.บ.ยา พ.ศ. 2510 มาตรา 12 — ยาที่ไม่อันตรายต่อสุขภาพเมื่อใช้ตามขวด',
      'prescriptionCondition': 'ไม่ต้องมีใบสั่งยา (OTC)',
      'pharmacistRule': 'เภสัชกรจ่ายได้ที่ร้านยาทั่วไป ไม่ต้องมีใบสั่งยา',
      'requiredLicense': null,
    },
    'D': {
      'nameTh': 'ยาอันตราย',
      'nameEn': 'Dangerous Drug',
      'telemedicineAllowed': false, // ต้องดู subcategory
      'legalBasis': 'พ.ร.บ.ยา พ.ศ. 2510 มาตรา 71 — ยาอันตรายต้องสั่งจ่ายโดยแพทย์เท่านั้น',
      'prescriptionCondition': 'ต้องมีใบสั่งยาจากแพทย์ (Prescription Required)',
      'pharmacistRule': 'เภสัชกรจ่ายได้เฉพาะที่ร้านยาที่มีเภสัชกรประจำ และต้องมีใบสั่งยา',
      'requiredLicense': null,
    },
    'S': {
      'nameTh': 'ยาควบคุมพิเศษ',
      'nameEn': 'Special Controlled Drug',
      'telemedicineAllowed': false,
      'legalBasis': 'พ.ร.บ.ยา พ.ศ. 2510 มาตรา 80 — ยาควบคุมพิเศษต้องบันทึกการสั่งจ่ายและการจ่าย',
      'prescriptionCondition': 'ต้องมีใบสั่งยา + บันทึกในระบบติดตามการสั่งจ่าย (Prescription Monitoring)',
      'pharmacistRule': 'เภสัชกรจ่ายได้เฉพาะร้านยาที่มีใบอนุญาตขายยาควบคุมพิเศษ และต้องบันทึกรับ-จ่าย',
      'requiredLicense': null,
    },
    'N': {
      'nameTh': 'ยาเสพติดให้โทษ',
      'nameEn': 'Narcotic Drug',
      'telemedicineAllowed': false,
      'legalBasis': 'พ.ร.บ.ยาเสพติดให้โทษ พ.ศ. 2522 — ห้ามสั่งจ่ายผ่านระบบอิเล็กทรอนิกส์ (ประกาศสมาคมแพทย์ 2565)',
      'prescriptionCondition': 'ใช้แบบฟอร์มพิเศษ (บัญชีสม.) จำกัดจำนวน บางชนิดต้องขออนุญาตก่อน',
      'pharmacistRule': 'เภสัชกรจ่ายได้เฉพาะร้านยาที่มีใบอนุญาตขายยาเสพติด ต้องบันทึกรับ-จ่ายเข้มงวด',
      'requiredLicense': 'narcotic_dispensing',
    },
    'P': {
      'nameTh': 'วัตถุออกฤทธิ์ต่อจิตและประสาท',
      'nameEn': 'Psychotropic Substance',
      'telemedicineAllowed': false,
      'legalBasis': 'พ.ร.บ.วัตถุออกฤทธิ์ต่อจิตและประสาท พ.ศ. 2519 — ต้องตรวจร่างกายโดยตรง ห้ามสั่งผ่าน Telemedicine',
      'prescriptionCondition': 'ใช้ใบสั่งยาปกติ แต่มีจำกัดจำนวน ต้องบันทึกลงทะเบียน และต้องตรวจร่างกายผู้ป่วย',
      'pharmacistRule': 'เภสัชกรจ่ายได้เฉพาะร้านยาที่มีใบอนุญาต ต้องบันทึกรับ-จ่าย',
      'requiredLicense': 'psychotropic_dispensing',
    },
  };

  /// ข้อมูล Dangerous Subcategory ที่ห้าม Telemedicine
  static const Map<String, Map<String, String>> _prohibitedSubcategories = {
    'hormone_injection': {
      'nameTh': 'ฮอร์โมนฉีด',
      'reason': 'ยาฉีดทุกชนิดห้ามสั่งผ่าน Telemedicine — ต้องฉีดที่คลินิก',
      'legalBasis': 'ประกาศกระทรวงสาธารณสุข เรื่องหลักเกณฑ์การให้บริการ Telemedicine',
    },
    'chemotherapy': {
      'nameTh': 'ยาเคมีบำบัด',
      'reason': 'ยาเคมีบำบัดอันตรายสูง ต้องตรวจเลือดก่อนฉีด ห้ามสั่งผ่าน Telemedicine',
      'legalBasis': 'มาตรฐานการรักษาโรคมะเร็ง — ต้องตรวจร่างกายและเลือดก่อนสั่งยา',
    },
    'abortifacient': {
      'nameTh': 'ยาขับเลือด/ยาทำแท้ง',
      'reason': 'ยาขับเลือด/ยาทำแท้งเป็นยาอันตรายประเภทพิเศษ ห้ามสั่งผ่าน Telemedicine',
      'legalBasis': 'พ.ร.บ.คุ้มครองเด็กที่เกิดจากการตั้งครรภ์แทน พ.ศ. 2558 และ พ.ร.บ.ยา',
    },
  };

  /// ตรวจสอบสิทธิ์แพทย์ (ใบอนุญาต Telemedicine)
  Future<bool> _checkProviderTelemedicineLicense(String providerId) async {
    try {
      final response = await Supabase.instance.client
          .from('provider_profiles')
          .select('license_type, is_telemedicine_licensed')
          .eq('user_id', providerId)
          .maybeSingle();

      if (response == null) return false;
      return response['is_telemedicine_licensed'] == true;
    } catch (e) {
      debugPrint('Error checking provider license: $e');
      return false;
    }
  }

  /// ตรวจสอบยา 1 รายการ
  Future<DrugRiskScreeningResult> screenMedication({
    required String medicationName,
    String? fdaRiskStatus,
    String? dangerousSubCategory,
    String? customRiskLevel,
    required String providerId,
    bool isTelemedicine = true,
  }) async {
    // 1. ตรวจสอบใบอนุญาต Telemedicine ของแพทย์
    final hasTelemedicineLicense = await _checkProviderTelemedicineLicense(providerId);

    // 2. ถ้าไม่มีใบอนุญาต Telemedicine → บล็อกทุกยา
    if (isTelemedicine && !hasTelemedicineLicense) {
      return DrugRiskScreeningResult(
        medicationName: medicationName,
        isBlocked: true,
        blockReason: 'แพทย์ไม่มีใบอนุญาตให้บริการ Telemedicine',
        blockCode: 'NO_TELEMED_LICENSE',
        legalBasis: 'ประกาศกระทรวงสาธารณสุข เรื่องหลักเกณฑ์การให้บริการ Telemedicine พ.ศ. 2565',
        prescriptionCondition: 'ต้องขอใบอนุญาต Telemedicine จากสภาวิชาชีพก่อนจึงสามารถสั่งยาผ่านระบบออนไลน์ได้',
        pharmacistDispensingRule: 'เภสัชกรมีสิทธิ์ปฏิเสธจ่ายยาหากพบว่าใบสั่งยามาจากแพทย์ที่ไม่มีใบอนุญาต Telemedicine',
        requiredLicense: 'telemedicine',
        providerHasLicense: false,
        additionalNotes: [
          'กรุณาติดต่อสภาวิชาชีพเพื่อขอใบอนุญาต Telemedicine',
          'หรือให้ผู้ป่วยมาตรวจที่คลินิกแบบ Face-to-Face',
        ],
      );
    }

    // 3. ถ้าไม่มี FDA status → ตรวจสอบ custom risk level
    if (fdaRiskStatus == null || fdaRiskStatus.isEmpty) {
      if (customRiskLevel != null && customRiskLevel.isNotEmpty) {
        return _screenByCustomRiskLevel(
          medicationName: medicationName,
          customRiskLevel: customRiskLevel,
          hasTelemedicineLicense: hasTelemedicineLicense,
        );
      }
      // ไม่มีข้อมูล risk → warning
      return DrugRiskScreeningResult(
        medicationName: medicationName,
        isBlocked: false,
        isWarning: true,
        blockReason: 'ไม่พบข้อมูล FDA Risk Status หรือ Custom Risk Level',
        blockCode: 'UNKNOWN_RISK',
        legalBasis: 'ระบบไม่สามารถตรวจสอบความปลอดภัยของยาได้ กรุณาตรวจสอบด้วยตนเอง',
        prescriptionCondition: 'แพทย์ต้องยืนยันว่ายานี้ปลอดภัยสำหรับการสั่งผ่าน Telemedicine',
        pharmacistDispensingRule: 'เภสัชกรควรตรวจสอบรายละเอียดยาก่อนจ่าย หากไม่แน่ใจให้ปฏิเสธและให้ผู้ป่วยติดต่อแพทย์',
        providerHasLicense: hasTelemedicineLicense,
        additionalNotes: [
          'ยานี้อาจไม่มีในระบบฐานข้อมูล FDA หรือยังไม่ได้กำหนดระดับความเสี่ยง',
          'แนะนำให้ระบุ Custom Risk Level สำหรับยานี้ในระบบ',
        ],
      );
    }

    // 4. ตรวจสอบตาม FDA Risk Status
    final fdaInfo = _fdaRiskInfo[fdaRiskStatus];
    if (fdaInfo == null) {
      return DrugRiskScreeningResult(
        medicationName: medicationName,
        isBlocked: false,
        isWarning: true,
        fdaRiskStatus: fdaRiskStatus,
        blockReason: 'ไม่รู้จักรหัส FDA Risk Status: $fdaRiskStatus',
        blockCode: 'UNKNOWN_FDA_CODE',
        legalBasis: 'ระบบไม่สามารถตรวจสอบความปลอดภัยได้ กรุณาตรวจสอบด้วยตนเอง',
        prescriptionCondition: 'ต้องตรวจสอบรหัส FDA ด้วยตนเอง',
        pharmacistDispensingRule: 'ตรวจสอบรายละเอียดยาด้วยตนเอง',
        providerHasLicense: hasTelemedicineLicense,
      );
    }

    // 5. ตรวจสอบ N (Narcotic) และ P (Psychotropic) → ห้ามเด็ดขาด
    if (fdaRiskStatus == 'N' || fdaRiskStatus == 'P') {
      return DrugRiskScreeningResult(
        medicationName: medicationName,
        isBlocked: true,
        fdaRiskStatus: fdaRiskStatus,
        fdaStatusNameTh: fdaInfo['nameTh'] as String,
        blockReason: 'ยา${fdaInfo['nameTh']} ห้ามสั่งผ่าน Telemedicine โดยเด็ดขาด',
        blockCode: 'PROHIBITED_FDA_STATUS_$fdaRiskStatus',
        legalBasis: fdaInfo['legalBasis'] as String,
        prescriptionCondition: fdaInfo['prescriptionCondition'] as String,
        pharmacistDispensingRule: fdaInfo['pharmacistRule'] as String,
        requiredLicense: fdaInfo['requiredLicense'] as String?,
        providerHasLicense: hasTelemedicineLicense,
        additionalNotes: [
          'หากต้องการสั่งยานี้ ผู้ป่วยต้องมาตรวจที่คลินิกแบบ Face-to-Face',
          'แพทย์ต้องตรวจร่างกายผู้ป่วยโดยตรงก่อนสั่งยา${fdaInfo['nameTh']}',
          'เภสัชกรมีสิทธิ์ปฏิเสธจ่ายหากไม่พบใบสั่งยาที่ถูกต้องตามกฎหมาย',
        ],
      );
    }

    // 6. ตรวจสอบ S (Special Controlled)
    if (fdaRiskStatus == 'S') {
      return DrugRiskScreeningResult(
        medicationName: medicationName,
        isBlocked: true,
        fdaRiskStatus: fdaRiskStatus,
        fdaStatusNameTh: fdaInfo['nameTh'] as String,
        blockReason: 'ยาควบคุมพิเศษ ห้ามสั่งผ่าน Telemedicine',
        blockCode: 'PROHIBITED_FDA_STATUS_S',
        legalBasis: fdaInfo['legalBasis'] as String,
        prescriptionCondition: fdaInfo['prescriptionCondition'] as String,
        pharmacistDispensingRule: fdaInfo['pharmacistRule'] as String,
        providerHasLicense: hasTelemedicineLicense,
        additionalNotes: [
          'ยาควบคุมพิเศษต้องสั่งจ่ายด้วยตนเองที่คลินิก',
          'ต้องบันทึกการสั่งจ่ายในระบบติดตาม (Prescription Monitoring)',
        ],
      );
    }

    // 7. ตรวจสอบ D (Dangerous) + subcategory
    if (fdaRiskStatus == 'D') {
      if (dangerousSubCategory != null && _prohibitedSubcategories.containsKey(dangerousSubCategory)) {
        final subInfo = _prohibitedSubcategories[dangerousSubCategory]!;
        return DrugRiskScreeningResult(
          medicationName: medicationName,
          isBlocked: true,
          fdaRiskStatus: fdaRiskStatus,
          fdaStatusNameTh: fdaInfo['nameTh'] as String,
          dangerousSubCategory: dangerousSubCategory,
          dangerousSubCategoryName: subInfo['nameTh'],
          blockReason: subInfo['reason']!,
          blockCode: 'PROHIBITED_DANGEROUS_SUBCATEGORY',
          legalBasis: subInfo['legalBasis']!,
          prescriptionCondition: 'ต้องตรวจร่างกายผู้ป่วยโดยตรงที่คลินิก',
          pharmacistDispensingRule: 'เภสัชกรจ่ายได้เฉพาะที่ร้านยาที่มีเภสัชกร และต้องมีใบสั่งยาที่ถูกต้อง',
          providerHasLicense: hasTelemedicineLicense,
          additionalNotes: [
            'หมวดหมู่ ${subInfo['nameTh']} เป็นยาอันตรายประเภทที่ห้ามสั่งผ่าน Telemedicine',
            'ผู้ป่วยต้องมาตรวจที่คลินิกเพื่อรับการรักษา',
          ],
        );
      }
      // D ทั่วไปที่ไม่ใช่ prohibited subcategory → warning (ต้องระวัง)
      return DrugRiskScreeningResult(
        medicationName: medicationName,
        isBlocked: false,
        isWarning: true,
        fdaRiskStatus: fdaRiskStatus,
        fdaStatusNameTh: fdaInfo['nameTh'] as String,
        dangerousSubCategory: dangerousSubCategory,
        blockReason: 'ยาอันตราย — ต้องระวังในการสั่งจ่าย',
        blockCode: 'DANGEROUS_DRUG_WARNING',
        legalBasis: fdaInfo['legalBasis'] as String,
        prescriptionCondition: fdaInfo['prescriptionCondition'] as String,
        pharmacistDispensingRule: fdaInfo['pharmacistRule'] as String,
        providerHasLicense: hasTelemedicineLicense,
        additionalNotes: [
          'ยาอันตรายต้องมีใบสั่งยาจากแพทย์เท่านั้น',
          'แนะนำให้ตรวจสอบประวัติแพ้ยาของผู้ป่วยก่อนสั่งจ่าย',
        ],
      );
    }

    // 8. ND (Non-Dangerous / Household) → อนุญาต
    return DrugRiskScreeningResult(
      medicationName: medicationName,
      isBlocked: false,
      fdaRiskStatus: fdaRiskStatus,
      fdaStatusNameTh: fdaInfo['nameTh'] as String,
      blockReason: '',
      blockCode: 'APPROVED',
      legalBasis: fdaInfo['legalBasis'] as String,
      prescriptionCondition: fdaInfo['prescriptionCondition'] as String,
      pharmacistDispensingRule: fdaInfo['pharmacistRule'] as String,
      providerHasLicense: hasTelemedicineLicense,
    );
  }

  /// ตรวจสอบตาม Custom Risk Level
  DrugRiskScreeningResult _screenByCustomRiskLevel({
    required String medicationName,
    required String customRiskLevel,
    required bool hasTelemedicineLicense,
  }) {
    final levelNames = {
      'low': 'ความเสี่ยงต่ำ',
      'medium': 'ความเสี่ยงปานกลาง',
      'high': 'ความเสี่ยงสูง',
      'very_high': 'ความเสี่ยงสูงมาก',
      'prohibited': 'ห้ามใช้',
    };

    if (customRiskLevel == 'prohibited') {
      return DrugRiskScreeningResult(
        medicationName: medicationName,
        isBlocked: true,
        customRiskLevel: customRiskLevel,
        customRiskLevelName: levelNames[customRiskLevel],
        blockReason: 'ยานี้ถูกระบุว่า "ห้ามใช้" ในระบบ Custom Risk Level',
        blockCode: 'PROHIBITED_CUSTOM_RISK',
        legalBasis: 'องค์กรกำหนดให้ยานี้ห้ามใช้ในระบบ Telemedicine',
        prescriptionCondition: 'ห้ามสั่งจ่ายยานี้ในทุกกรณี',
        pharmacistDispensingRule: 'เภสัชกรห้ามจ่ายยานี้',
        providerHasLicense: hasTelemedicineLicense,
        additionalNotes: [
          'ยานี้อาจมีผลข้างเคียงรุนแรงหรือข้อห้ามทางกฎหมาย',
          'หากต้องการใช้จริง ต้องตรวจร่างกายผู้ป่วยโดยตรงที่คลินิก',
        ],
      );
    }

    if (customRiskLevel == 'high' || customRiskLevel == 'very_high') {
      return DrugRiskScreeningResult(
        medicationName: medicationName,
        isBlocked: false,
        isWarning: true,
        customRiskLevel: customRiskLevel,
        customRiskLevelName: levelNames[customRiskLevel],
        blockReason: 'ยามีระดับความเสี่ยงสูง — ต้องระวังในการสั่งจ่าย',
        blockCode: 'HIGH_RISK_CUSTOM_LEVEL',
        legalBasis: 'องค์กรกำหนดให้ยานี้อยู่ในระดับความเสี่ยงสูง',
        prescriptionCondition: 'ต้องมีเหตุผลทางการแพทย์ที่ชัดเจน และแจ้งผู้ป่วยถึงความเสี่ยง',
        pharmacistDispensingRule: 'เภสัชกรควรตรวจสอบใบสั่งยาและแจ้งเตือนผู้ป่วยถึงความเสี่ยง',
        providerHasLicense: hasTelemedicineLicense,
        additionalNotes: [
          'แนะนำให้ติดตามอาการผู้ป่วยอย่างใกล้ชิด',
          'หากมีอาการผิดปกติ ให้ผู้ป่วยหยุดยาและปรึกษาแพทย์ทันที',
        ],
      );
    }

    // low / medium → อนุญาต
    return DrugRiskScreeningResult(
      medicationName: medicationName,
      isBlocked: false,
      customRiskLevel: customRiskLevel,
      customRiskLevelName: levelNames[customRiskLevel],
      blockCode: 'APPROVED',
      legalBasis: 'องค์กรกำหนดให้ยานี้อยู่ในระดับความเสี่ยงต่ำ-ปานกลาง',
      prescriptionCondition: 'สามารถสั่งจ่ายตามปกติ',
      pharmacistDispensingRule: 'เภสัชกรจ่ายได้ตามปกติ',
      providerHasLicense: hasTelemedicineLicense,
    );
  }

  /// ตรวจสอบรายการยาทั้งหมดในใบสั่งยา
  Future<List<DrugRiskScreeningResult>> screenPrescription({
    required List<Map<String, dynamic>> medications,
    required String providerId,
    bool isTelemedicine = true,
  }) async {
    final results = <DrugRiskScreeningResult>[];
    for (final med in medications) {
      final result = await screenMedication(
        medicationName: med['name'] ?? 'ไม่ระบุชื่อ',
        fdaRiskStatus: med['fda_risk_status'] as String?,
        dangerousSubCategory: med['dangerous_sub_category'] as String?,
        customRiskLevel: med['custom_risk_level'] as String?,
        providerId: providerId,
        isTelemedicine: isTelemedicine,
      );
      results.add(result);
    }
    return results;
  }
}
