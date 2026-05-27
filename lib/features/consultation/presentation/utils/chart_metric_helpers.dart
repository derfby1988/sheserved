import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';

const metricNameTh = <String, String>{
  'active_calories': 'แคลอรีที่เผาผลาญ',
  'heart_rate': 'อัตราการเต้นของหัวใจ',
  'hrv_sdnn': 'ความแปรปรวนอัตราหัวใจ (HRV)',
  'steps': 'จำนวนก้าว',
  'sleep_duration': 'ระยะเวลาการนอน',
  'blood_oxygen': 'ความอิ่มตัวออกซิเจนในเลือด (SpO₂)',
  'blood_pressure_systolic': 'ความดันโลหิตตัวบน',
  'blood_pressure_diastolic': 'ความดันโลหิตตัวล่าง',
  'body_temperature': 'อุณหภูมิร่างกาย',
  'weight': 'น้ำหนัก',
  'bmi': 'ดัชนีมวลกาย (BMI)',
  'respiratory_rate': 'อัตราการหายใจ',
  'distance': 'ระยะทาง',
  'floors_climbed': 'จำนวนชั้นที่ขึ้น',
  'exercise_minutes': 'นาทีออกกำลังกาย',
  'resting_heart_rate': 'อัตราหัวใจขณะพัก',
  'vo2_max': 'VO₂ Max',
  'glucose': 'ระดับน้ำตาลในเลือด',
};

/// Formats a raw metric value into a clean display string.
/// Truncates whole numbers and limits decimals to 2 places.
String formatMetricValue(dynamic raw) {
  if (raw == null) return '-';
  if (raw is num) {
    if (raw == raw.truncate()) return raw.truncate().toString();
    return raw.toStringAsFixed(2);
  }
  final parsed = double.tryParse(raw.toString());
  if (parsed == null) return raw.toString();
  if (parsed == parsed.truncate()) return parsed.truncate().toString();
  return parsed.toStringAsFixed(2);
}

/// Formats a raw datetime into "dd MMM HH:mm" display string.
String formatMetricDate(dynamic raw) {
  if (raw == null) return '-';
  final parsed = raw is DateTime
      ? raw
      : DateTime.tryParse(raw.toString())?.toLocal();
  if (parsed == null) return raw.toString();
  return DateFormat('dd MMM HH:mm').format(parsed);
}

/// Returns a chart color for a given metric type.
Color metricChartColor(String metricType) {
  switch (metricType) {
    case 'heart_rate':
      return const Color(0xFFE57373);
    case 'hrv_sdnn':
    case 'hrv':
      return const Color(0xFF8E6CFF);
    case 'steps':
      return const Color(0xFF4DB6AC);
    case 'active_calories':
    case 'calories':
      return const Color(0xFFFF8A65);
    case 'sleep_asleep':
    case 'sleep':
      return const Color(0xFF5C6BC0);
    case 'blood_oxygen':
    case 'spo2':
      return const Color(0xFF42A5F5);
    default:
      return AppColors.primary;
  }
}

/// Builds a list of FlSpot points from raw double values.
/// Duplicates the single value when only one data point exists
/// so the chart still renders a visible line.
List<FlSpot> buildSpots(List<double> values) {
  if (values.isEmpty) return const [];
  if (values.length == 1) {
    return [FlSpot(0, values.first), FlSpot(1, values.first)];
  }
  return [
    for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i]),
  ];
}
