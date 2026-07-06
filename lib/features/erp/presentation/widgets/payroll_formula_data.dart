class PayrollFormulaItem {
  final String title;
  final String formula;
  final String? example;
  final String? condition;
  final List<String>? details;
  final bool isEarning;

  const PayrollFormulaItem({
    required this.title,
    required this.formula,
    this.example,
    this.condition,
    this.details,
    this.isEarning = true,
  });
}

class PayrollFormulaData {
  static const _thb = 'THB';

  static List<PayrollFormulaItem> get earnings => [
        const PayrollFormulaItem(
          title: 'เงินเดือนพื้นฐาน (Base Salary)',
          formula: 'employees.base_salary',
          example: '30,000.00 × 1 = 30,000.00',
        ),
        const PayrollFormulaItem(
          title: 'ค่าล่วงเวลา (Overtime)',
          formula: 'OT_count × hourly_rate × multiplier',
          example: '5 × 125.00 × 1.5 = 937.50',
          details: [
            'hourly_rate = base_salary / (work_hours × 30)',
            'วันธรรมดา × 1.5',
            'วันหยุด (เสาร์-อาทิตย์) × 2.0',
            'วันหยุดนักขัตฤกษ์ × 3.0',
          ],
        ),
        const PayrollFormulaItem(
          title: 'คอมมิชชั่น (Commission)',
          formula: 'SUM(approved commissions)',
          example: '2,500.00 + 1,800.00 = 4,300.00',
        ),
        const PayrollFormulaItem(
          title: 'เบี้ยขยัน (Diligence Allowance)',
          formula: 'hr_settings.diligence_allowance_amount',
          condition: 'late_count = 0 AND absent_count = 0',
          example: '1,000.00',
        ),
      ];

  static List<PayrollFormulaItem> get deductions => [
        const PayrollFormulaItem(
          title: 'ประกันสังคม (Social Security)',
          formula: 'MIN(base_salary × rate, 750.00)',
          example: 'MIN(30,000 × 0.05, 750) = 750',
          isEarning: false,
        ),
        const PayrollFormulaItem(
          title: 'กองทุนสำรองเลี้ยงชีพ (Provident Fund)',
          formula: 'LEAST(base_salary, 100,000) × rate',
          example: '30,000 × 0.03 = 900.00',
          details: [
            'ฐานสูงสุด 100,000 THB/เดือน',
            'อัตราพนักงาน (default 3%)',
          ],
          isEarning: false,
        ),
        const PayrollFormulaItem(
          title: 'ภาษีเงินได้หัก ณ ที่จ่าย (Tax)',
          formula: 'Progressive PIT / 12',
          example: 'ดูรายละเอียดภาษี',
          details: [
            'annual_income = (base+OT+comm+bonus) × 12',
            'หัก personal_allowance (60,000)',
            'หัก tax_allowances (spouse, child, ...)',
            'หัก SS×12, PF×12',
            'Progressive Rate:',
            '  0-150K: 0% (ยกเว้น)',
            '  150-300K: 5%',
            '  300-500K: 10%',
            '  500-750K: 15%',
            '  750K-1M: 20%',
            '  1M-2M: 25%',
            '  2M-5M: 30%',
            '  5M+: 35%',
          ],
          isEarning: false,
        ),
        const PayrollFormulaItem(
          title: 'หักสาย (Late Penalty)',
          formula: 'late_minutes × rate_per_minute',
          example: '30 นาที × 5.00 = 150.00',
          isEarning: false,
        ),
        const PayrollFormulaItem(
          title: 'หักขาด (Absent Penalty)',
          formula: 'absent_days × rate_per_day',
          example: '1 วัน × 500.00 = 500.00',
          isEarning: false,
        ),
      ];

  static List<PayrollFormulaItem> get employerCosts => [
        const PayrollFormulaItem(
          title: 'ประกันสังคม (นายจ้าง)',
          formula: 'MIN(base_salary × rate, 750.00)',
          example: '750.00 (จ่ายเท่ากับพนักงาน)',
          isEarning: false,
        ),
        const PayrollFormulaItem(
          title: 'กองทุนสำรองเลี้ยงชีพ (นายจ้าง)',
          formula: 'LEAST(base_salary, 100,000) × employer_rate',
          example: '30,000 × 0.03 = 900.00',
          isEarning: false,
        ),
      ];

  static String get summaryExample => '''
Gross = 30,000 + 937.50 + 4,300 + 1,000 = 36,237.50
Deductions = 750 + 900 + 1,200 + 150 = 3,000.00
Net Pay = 36,237.50 - 3,000 = 33,237.50
─────────────────
Employer Cost = 36,237.50 + 750 + 900 = 37,887.50''';

  static String get currency => _thb;
}
