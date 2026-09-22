import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../../core/constants/app_colors.dart';

/// Icon options for position markers with localized Thai names.
const Map<String, ({IconData icon, String label})> kPositionIconChoices = {
  // 1. ผู้เล่น / บุคคล / บทบาทหลัก (Original + People roles)
  'player': (icon: Icons.person_rounded, label: 'ผู้เล่นทั่วไป'),
  'forward': (icon: Icons.sports_soccer_rounded, label: 'ฟุตบอล / สไตรเกอร์'),
  'midfielder': (
    icon: Icons.all_inclusive_rounded,
    label: 'กองกลาง / บ็อกซ์ทูบ็อกซ์',
  ),
  'defender': (icon: Icons.shield_rounded, label: 'กองหลัง / ป้องกัน'),
  'goalkeeper': (
    icon: Icons.front_hand_rounded,
    label: 'ผู้รักษาประตู / บล็อกเกอร์',
  ),
  'shooter': (
    icon: Icons.sports_basketball_rounded,
    label: 'บาสเกตบอล / ชู๊ตเตอร์',
  ),
  'captain': (icon: Icons.stars_rounded, label: 'กัปตันทีม'),
  'marker': (icon: Icons.location_on_rounded, label: 'ตำแหน่งสนาม'),

  // 2. กีฬาบอล / ไม้แร็กเกต / กีฬายอดนิยม
  'volleyball': (icon: Icons.sports_volleyball_rounded, label: 'วอลเลย์บอล'),
  'tennis': (icon: Icons.sports_tennis_rounded, label: 'เทนนิส / แร็กเกต'),
  'baseball': (icon: Icons.sports_baseball_rounded, label: 'เบสบอล / ซอฟต์บอล'),
  'football_us': (
    icon: Icons.sports_football_rounded,
    label: 'อเมริกันฟุตบอล / รักบี้',
  ),
  'golf': (icon: Icons.sports_golf_rounded, label: 'กอล์ฟ'),
  'cricket': (icon: Icons.sports_cricket_rounded, label: 'คริกเก็ต'),
  'hockey': (icon: Icons.sports_hockey_rounded, label: 'ฮอกกี้'),
  'handball': (icon: Icons.sports_handball_rounded, label: 'แฮนด์บอล'),
  'sports_ball': (icon: Icons.sports_rounded, label: 'ลูกบอล / นกหวีด'),
  'sports_score': (
    icon: Icons.sports_score_rounded,
    label: 'สกอร์ / ธงตาหมากรุก',
  ),

  // 3. ยิม / กรีฑา / แอ็กชัน / กีฬาทางน้ำ / ล้อเลื่อน
  'fitness': (icon: Icons.fitness_center_rounded, label: 'ฟิตเนส / ยกน้ำหนัก'),
  'running': (icon: Icons.directions_run_rounded, label: 'วิ่ง / สปรินเตอร์'),
  'walking': (icon: Icons.directions_walk_rounded, label: 'เดิน / เพเซอร์'),
  'cycling': (icon: Icons.pedal_bike_rounded, label: 'จักรยาน'),
  'swimming': (icon: Icons.pool_rounded, label: 'ว่ายน้ำ / กีฬาทางน้ำ'),
  'surfing': (icon: Icons.surfing_rounded, label: 'เซิร์ฟบอร์ด'),
  'skateboarding': (icon: Icons.skateboarding_rounded, label: 'สเก็ตบอร์ด'),
  'roller_skate': (icon: Icons.roller_skating_rounded, label: 'โรลเลอร์สเก็ต'),
  'kayaking': (icon: Icons.kayaking_rounded, label: 'พายเรือคายัค'),
  'rowing': (icon: Icons.rowing_rounded, label: 'กรรเชียงเรือ'),
  'hiking': (icon: Icons.hiking_rounded, label: 'เดินป่า / ไฮกิ้ง'),
  'skiing': (icon: Icons.downhill_skiing_rounded, label: 'สกี'),
  'snowboarding': (icon: Icons.snowboarding_rounded, label: 'สโนว์บอร์ด'),
  'yoga': (icon: Icons.self_improvement_rounded, label: 'โยคะ / สมาธิ'),
  'combat': (
    icon: Icons.sports_mma_rounded,
    label: 'ต่อสู้ / มวย / ศิลปะป้องกันตัว',
  ),
  'gymnastics': (icon: Icons.sports_gymnastics_rounded, label: 'ยิมนาสติก'),
  'motorsports': (
    icon: Icons.sports_motorsports_rounded,
    label: 'มอเตอร์สปอร์ต',
  ),
  'kabaddi': (icon: Icons.sports_kabaddi_rounded, label: 'แท็กเกิล / มวยปล้ำ'),

  // 4. บทบาททีม / สภาพจิตวิทยา / หน้าที่
  'pair': (icon: Icons.people_rounded, label: 'คู่ / แท็กทีม'),
  'group_work': (
    icon: Icons.group_work_rounded,
    label: 'ทีมเวิร์ก / ประสานงาน',
  ),
  'athlete': (
    icon: Icons.accessibility_new_rounded,
    label: 'นักกีฬา / ความคล่องตัว',
  ),
  'back_hand': (icon: Icons.back_hand_rounded, label: 'ตัวเซ็ต / แฮนด์'),
  'sweeper': (
    icon: Icons.security_rounded,
    label: 'สวีปเปอร์ / กองหลังตัวกวาด',
  ),
  'mvp': (icon: Icons.workspace_premium_rounded, label: 'MVP / ยอดเยี่ยม'),
  'medal': (icon: Icons.military_tech_rounded, label: 'เหรียญรางวัล'),
  'trophy': (icon: Icons.emoji_events_rounded, label: 'ถ้วยรางวัล / แชมป์'),
  'coach': (icon: Icons.campaign_rounded, label: 'โค้ช / บัญชาการเกม'),
  'flag': (icon: Icons.flag_rounded, label: 'ธง / เสาประตู'),
  'line_flag': (icon: Icons.outlined_flag_rounded, label: 'ริมเส้น / ไลน์แมน'),
  'speed': (icon: Icons.speed_rounded, label: 'สปีด / ปีกความเร็ว'),
  'timer': (icon: Icons.timer_rounded, label: 'คุมจังหวะเวลา'),
  'bolt': (icon: Icons.bolt_rounded, label: 'สายฟ้า / จู่โจมฉับพลัน'),
  'flash': (icon: Icons.flash_on_rounded, label: 'พลังทำลาย / หมัดหนัก'),
  'fire': (icon: Icons.local_fire_department_rounded, label: 'ไฟแรง / มือขึ้น'),
  'rocket': (icon: Icons.rocket_launch_rounded, label: 'ตัวทะลวง / จรวด'),
  'heart': (icon: Icons.favorite_rounded, label: 'หัวใจ / ซัพพอร์ต'),
  'playmaker': (
    icon: Icons.psychology_rounded,
    label: 'เพลย์เมกเกอร์ / บัญชาการ',
  ),
  'radar': (icon: Icons.radar_rounded, label: 'เรดาร์ / คุมพื้นที่กว้าง'),
  'navigator': (icon: Icons.navigation_rounded, label: 'นำทิศทาง / ไกด์'),
  'target': (icon: Icons.my_location_rounded, label: 'เป้าหมาย / เซ็นเตอร์'),
  'bullseye': (icon: Icons.adjust_rounded, label: 'ตรงเป้า / แม่นยำ'),
  'sniper': (
    icon: Icons.center_focus_strong_rounded,
    label: 'สไนเปอร์ / ยิงไกล',
  ),
  'pivot': (icon: Icons.transform_rounded, label: 'จุดหมุน / พิวอต'),
  'switch': (icon: Icons.swap_horiz_rounded, label: 'สลับตำแหน่ง / โอนย้าย'),
  'transition': (icon: Icons.sync_alt_rounded, label: 'สวนกลับ / สลับรับรุก'),
  'substitute': (
    icon: Icons.change_circle_rounded,
    label: 'ตัวสำรอง / สับเปลี่ยน',
  ),
  'bench': (
    icon: Icons.hourglass_top_rounded,
    label: 'ม้านั่งสำรอง / สแตนด์บาย',
  ),
  'free_role': (
    icon: Icons.control_camera_rounded,
    label: 'ฟรีโรล / วิ่งอิสระ',
  ),
  'medic': (
    icon: Icons.medical_services_rounded,
    label: 'หน่วยพยาบาล / กายภาพ',
  ),
  'recovery': (icon: Icons.healing_rounded, label: 'ฟื้นฟูสภาพร่างกาย'),
  'stamina': (
    icon: Icons.battery_charging_full_rounded,
    label: 'พละกำลัง / ความอึด',
  ),
  'anchor': (icon: Icons.anchor_rounded, label: 'สมอเรือ / ตัวยึดแนวรับ'),
  'diamond': (icon: Icons.diamond_rounded, label: 'ไดมอนด์ / รูปเพชร'),
  'hub': (icon: Icons.hub_rounded, label: 'ศูนย์กลางการกระจายบอล'),
  'lightbulb': (icon: Icons.lightbulb_rounded, label: 'ไอเดียสร้างสรรค์เกม'),
  'vision': (icon: Icons.visibility_rounded, label: 'วิสัยทัศน์กว้างไกล'),

  // 5. ทิศทาง / พื้นที่สนาม
  'dir_up': (icon: Icons.north_rounded, label: 'บุกขึ้นหน้า'),
  'dir_down': (icon: Icons.south_rounded, label: 'ถอยลงรับ'),
  'dir_right': (icon: Icons.east_rounded, label: 'กราบขวา'),
  'dir_left': (icon: Icons.west_rounded, label: 'กราบซ้าย'),
  'dir_up_right': (icon: Icons.north_east_rounded, label: 'หน้าขวา'),
  'dir_up_left': (icon: Icons.north_west_rounded, label: 'หน้าซ้าย'),
  'dir_down_right': (icon: Icons.south_east_rounded, label: 'หลังขวา'),
  'dir_down_left': (icon: Icons.south_west_rounded, label: 'หลังซ้าย'),
  'zone_grid': (icon: Icons.grid_view_rounded, label: 'คุมโซน'),
  'penalty_box': (icon: Icons.crop_free_rounded, label: 'ในกรอบเขตโทษ'),
  'key_space': (icon: Icons.lens_blur_rounded, label: 'ฮาล์ฟสเปซ / ช่องว่าง'),
  'center_circle': (icon: Icons.circle_outlined, label: 'วงกลมจุดกึ่งกลาง'),
};

/// Color choices available for position markers (#RRGGBB).
const List<String> kPositionColorChoices = [
  '#2196F3', // ฟ้า / Blue
  '#4CAF50', // เขียว / Green
  '#FF9800', // ส้ม / Orange
  '#E91E63', // ชมพู / Pink
  '#9C27B0', // ม่วง / Purple
  '#00BCD4', // ฟ้าคราม / Cyan
  '#F44336', // แดง / Red
  '#607D8B', // เทาน้ำเงิน / Blue Grey
];

Color parseHexColor(
  String? hexString, {
  Color fallback = const Color(0xFF2196F3),
}) {
  if (hexString == null || hexString.isEmpty) return fallback;
  final buffer = StringBuffer();
  if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
  buffer.write(hexString.replaceFirst('#', ''));
  try {
    return Color(int.parse(buffer.toString(), radix: 16));
  } catch (_) {
    return fallback;
  }
}

/// Line-marking presets available for simulated fields.
const Map<String, String> kFieldStylePresets = {
  'generic': 'ทั่วไป (เส้นขอบ)',
  'football': 'ฟุตบอล',
  'futsal': 'ฟุตซอล / แฮนด์บอล',
  'basketball': 'บาสเกตบอล',
  'volleyball': 'วอลเลย์บอล',
  'beach_volleyball': 'วอลเลย์บอลชายหาด',
  'takraw': 'เซปักตะกร้อ',
  'rugby': 'รักบี้',
  'american_football': 'อเมริกันฟุตบอล',
  'baseball': 'เบสบอล / ซอฟต์บอล',
  'cricket': 'คริกเก็ต',
  'field_hockey': 'ฮอกกี้สนาม',
  'ice_hockey': 'ฮอกกี้น้ำแข็ง',
  'badminton': 'แบดมินตัน',
  'tennis': 'เทนนิส',
  'table_tennis': 'ปิงปอง',
  'pickleball': 'พิคเคิลบอล',
  'squash': 'สควอช',
  'boxing': 'เวทีมวย / มวยไทย',
  'taekwondo': 'เทควันโด (แปดเหลี่ยม)',
  'martial_arts': 'ยูโด / คาราเต้ / BJJ',
  'wrestling': 'มวยปล้ำ',
  'fencing': 'ฟันดาบ',
  'running_track': 'ลู่วิ่ง / กรีฑา',
  'swimming': 'สระว่ายน้ำ / โปโลน้ำ',
  'snooker': 'สนุกเกอร์ / บิลเลียด',
  'bowling': 'เลนโบว์ลิ่ง',
  'archery': 'ยิงธนู / เป้าคะแนน',
  'golf': 'กอล์ฟ (ฟาร์เวย์)',
  'gymnastics': 'ยิมนาสติก (พื้น/ลาน)',
  'cycling_track': 'เวโลโดรม / ลู่จักรยาน',
  'shooting_range': 'ลานยิงปืน',
};

/// Category mapping for field style presets.
const Map<String, String> kFieldPresetCategories = {
  'football': 'ball',
  'futsal': 'ball',
  'basketball': 'ball',
  'volleyball': 'ball',
  'beach_volleyball': 'ball',
  'takraw': 'ball',
  'rugby': 'ball',
  'american_football': 'ball',
  'baseball': 'ball',
  'cricket': 'ball',
  'field_hockey': 'ball',
  'ice_hockey': 'ball',
  'badminton': 'racquet',
  'tennis': 'racquet',
  'table_tennis': 'racquet',
  'pickleball': 'racquet',
  'squash': 'racquet',
  'boxing': 'combat',
  'taekwondo': 'combat',
  'martial_arts': 'combat',
  'wrestling': 'combat',
  'fencing': 'combat',
  'running_track': 'track_target',
  'swimming': 'track_target',
  'snooker': 'track_target',
  'bowling': 'track_target',
  'archery': 'track_target',
  'golf': 'track_target',
  'gymnastics': 'combat',
  'cycling_track': 'track_target',
  'shooting_range': 'track_target',
  'generic': 'generic',
};

class FieldCategoryItem {
  final String key;
  final String label;
  final IconData icon;

  const FieldCategoryItem({
    required this.key,
    required this.label,
    required this.icon,
  });
}

const List<FieldCategoryItem> kFieldCategories = [
  FieldCategoryItem(
    key: 'all',
    label: 'ทั้งหมด',
    icon: Icons.grid_view_rounded,
  ),
  FieldCategoryItem(
    key: 'ball',
    label: 'บอล / ทีม',
    icon: Icons.sports_soccer_rounded,
  ),
  FieldCategoryItem(
    key: 'racquet',
    label: 'แร็กเก็ต / โต๊ะ',
    icon: Icons.sports_tennis_rounded,
  ),
  FieldCategoryItem(
    key: 'combat',
    label: 'ต่อสู้ / เวที',
    icon: Icons.sports_kabaddi_rounded,
  ),
  FieldCategoryItem(
    key: 'track_target',
    label: 'ลู่ / สระ / เป้า',
    icon: Icons.timer_outlined,
  ),
  FieldCategoryItem(
    key: 'generic',
    label: 'ทั่วไป',
    icon: Icons.crop_square_rounded,
  ),
];

/// Helper to map sport name to field category
String getCategoryForSport(String? sportName) {
  if (sportName == null || sportName.trim().isEmpty) return 'all';
  final s = sportName.toLowerCase();
  if (s.contains('ฟุตบอล') ||
      s.contains('ฟุตซอล') ||
      s.contains('บาส') ||
      s.contains('วอลเลย์') ||
      s.contains('ตะกร้อ') ||
      s.contains('รักบี้') ||
      s.contains('อเมริกันฟุตบอล') ||
      s.contains('เบสบอล') ||
      s.contains('ซอฟต์บอล') ||
      s.contains('คริกเก็ต') ||
      s.contains('ฮอกกี้') ||
      s.contains('แฮนด์บอล') ||
      s.contains('football') ||
      s.contains('soccer') ||
      s.contains('basketball') ||
      s.contains('volleyball') ||
      s.contains('rugby') ||
      s.contains('baseball') ||
      s.contains('cricket') ||
      s.contains('hockey') ||
      s.contains('handball')) {
    return 'ball';
  }
  if (s.contains('แบด') ||
      s.contains('เทนนิส') ||
      s.contains('ปิงปอง') ||
      s.contains('สควอช') ||
      s.contains('พิคเคิล') ||
      s.contains('badminton') ||
      s.contains('tennis') ||
      s.contains('table tennis') ||
      s.contains('squash') ||
      s.contains('pickleball')) {
    return 'racquet';
  }
  if (s.contains('มวย') ||
      s.contains('เทควันโด') ||
      s.contains('ยูโด') ||
      s.contains('คาราเต้') ||
      s.contains('ยิวยิตสู') ||
      s.contains('ปล้ำ') ||
      s.contains('ดาบ') ||
      s.contains('boxing') ||
      s.contains('taekwondo') ||
      s.contains('judo') ||
      s.contains('karate') ||
      s.contains('bjj') ||
      s.contains('wrestling') ||
      s.contains('fencing')) {
    return 'combat';
  }
  if (s.contains('วิ่ง') ||
      s.contains('กรีฑา') ||
      s.contains('มาราธอน') ||
      s.contains('ว่าย') ||
      s.contains('โปโลน้ำ') ||
      s.contains('สนุ๊ก') ||
      s.contains('สนุกเกอร์') ||
      s.contains('บิลเลียด') ||
      s.contains('โบว์ลิ่ง') ||
      s.contains('ธนู') ||
      s.contains('ปืน') ||
      s.contains('ดาร์ท') ||
      s.contains('กอล์ฟ') ||
      s.contains('จักรยาน') ||
      s.contains('เวโลโดรม') ||
      s.contains('running') ||
      s.contains('swimming') ||
      s.contains('snooker') ||
      s.contains('billiards') ||
      s.contains('bowling') ||
      s.contains('archery') ||
      s.contains('shooting') ||
      s.contains('darts') ||
      s.contains('golf') ||
      s.contains('cycling') ||
      s.contains('velodrome')) {
    return 'track_target';
  }
  if (s.contains('ยิมนาสติก') || s.contains('gymnastics')) {
    return 'combat';
  }
  return 'all';
}

/// Helper to get smart default FieldStyle for a given sport name
FieldStyle getDefaultFieldStyleForSport(String? sportName) {
  if (sportName == null || sportName.trim().isEmpty) {
    return FieldStyle.fallback;
  }
  final s = sportName.toLowerCase();
  if (s.contains('ฟุตซอล') ||
      s.contains('แฮนด์บอล') ||
      s.contains('futsal') ||
      s.contains('handball')) {
    return const FieldStyle(
      preset: 'futsal',
      surface: '#1565C0',
      line: '#FFFFFF',
    );
  }
  if (s.contains('ฟุตบอล') || s.contains('football') || s.contains('soccer')) {
    return const FieldStyle(
      preset: 'football',
      surface: '#2E7D32',
      line: '#FFFFFF',
    );
  }
  if (s.contains('บาส') || s.contains('basketball')) {
    return const FieldStyle(
      preset: 'basketball',
      surface: '#EF6C00',
      line: '#FFFFFF',
    );
  }
  if (s.contains('วอลเลย์บอลชายหาด') || s.contains('beach volleyball')) {
    return const FieldStyle(
      preset: 'beach_volleyball',
      surface: '#EF6C00',
      line: '#212121',
    );
  }
  if (s.contains('วอลเลย์') || s.contains('volleyball')) {
    return const FieldStyle(
      preset: 'volleyball',
      surface: '#00838F',
      line: '#FFF176',
    );
  }
  if (s.contains('ตะกร้อ') || s.contains('takraw')) {
    return const FieldStyle(
      preset: 'takraw',
      surface: '#2E7D32',
      line: '#FFFFFF',
    );
  }
  if (s.contains('รักบี้') || s.contains('rugby')) {
    return const FieldStyle(
      preset: 'rugby',
      surface: '#2E7D32',
      line: '#FFFFFF',
    );
  }
  if (s.contains('อเมริกันฟุตบอล') || s.contains('american football')) {
    return const FieldStyle(
      preset: 'american_football',
      surface: '#2E7D32',
      line: '#FFFFFF',
    );
  }
  if (s.contains('เบสบอล') ||
      s.contains('ซอฟต์บอล') ||
      s.contains('baseball') ||
      s.contains('softball')) {
    return const FieldStyle(
      preset: 'baseball',
      surface: '#2E7D32',
      line: '#FFFFFF',
    );
  }
  if (s.contains('คริกเก็ต') || s.contains('cricket')) {
    return const FieldStyle(
      preset: 'cricket',
      surface: '#2E7D32',
      line: '#FFFFFF',
    );
  }
  if (s.contains('ฮอกกี้น้ำแข็ง') || s.contains('ice hockey')) {
    return const FieldStyle(
      preset: 'ice_hockey',
      surface: '#546E7A',
      line: '#FFFFFF',
    );
  }
  if (s.contains('ฮอกกี้') || s.contains('hockey')) {
    return const FieldStyle(
      preset: 'field_hockey',
      surface: '#1565C0',
      line: '#FFFFFF',
    );
  }
  if (s.contains('แบดมินตัน') || s.contains('badminton')) {
    return const FieldStyle(
      preset: 'badminton',
      surface: '#2E7D32',
      line: '#FFFFFF',
    );
  }
  if (s.contains('เทนนิส') || s.contains('tennis')) {
    return const FieldStyle(
      preset: 'tennis',
      surface: '#1565C0',
      line: '#FFFFFF',
    );
  }
  if (s.contains('ปิงปอง') || s.contains('table tennis')) {
    return const FieldStyle(
      preset: 'table_tennis',
      surface: '#1565C0',
      line: '#FFFFFF',
    );
  }
  if (s.contains('พิคเคิลบอล') || s.contains('pickleball')) {
    return const FieldStyle(
      preset: 'pickleball',
      surface: '#00838F',
      line: '#FFFFFF',
    );
  }
  if (s.contains('สควอช') || s.contains('squash')) {
    return const FieldStyle(
      preset: 'squash',
      surface: '#6D4C41',
      line: '#B71C1C',
    );
  }
  if (s.contains('มวย') || s.contains('boxing') || s.contains('muay thai')) {
    return const FieldStyle(
      preset: 'boxing',
      surface: '#1565C0',
      line: '#FFFFFF',
    );
  }
  if (s.contains('เทควันโด') || s.contains('taekwondo')) {
    return const FieldStyle(
      preset: 'taekwondo',
      surface: '#1565C0',
      line: '#FFFFFF',
    );
  }
  if (s.contains('ยูโด') ||
      s.contains('คาราเต้') ||
      s.contains('ยิวยิตสู') ||
      s.contains('judo') ||
      s.contains('karate') ||
      s.contains('bjj')) {
    return const FieldStyle(
      preset: 'martial_arts',
      surface: '#2E7D32',
      line: '#FFFFFF',
    );
  }
  if (s.contains('มวยปล้ำ') || s.contains('wrestling')) {
    return const FieldStyle(
      preset: 'wrestling',
      surface: '#1565C0',
      line: '#FFF176',
    );
  }
  if (s.contains('ฟันดาบ') || s.contains('fencing')) {
    return const FieldStyle(
      preset: 'fencing',
      surface: '#546E7A',
      line: '#FFFFFF',
    );
  }
  if (s.contains('วิ่ง') ||
      s.contains('มาราธอน') ||
      s.contains('กรีฑา') ||
      s.contains('running')) {
    return const FieldStyle(
      preset: 'running_track',
      surface: '#B71C1C',
      line: '#FFFFFF',
    );
  }
  if (s.contains('ว่าย') || s.contains('โปโลน้ำ') || s.contains('swimming')) {
    return const FieldStyle(
      preset: 'swimming',
      surface: '#1565C0',
      line: '#FFFFFF',
    );
  }
  if (s.contains('สนุ๊ก') ||
      s.contains('สนุกเกอร์') ||
      s.contains('บิลเลียด') ||
      s.contains('snooker') ||
      s.contains('billiards')) {
    return const FieldStyle(
      preset: 'snooker',
      surface: '#2E7D32',
      line: '#FFFFFF',
    );
  }
  if (s.contains('โบว์ลิ่ง') || s.contains('bowling')) {
    return const FieldStyle(
      preset: 'bowling',
      surface: '#6D4C41',
      line: '#FFFFFF',
    );
  }
  if (s.contains('ธนู') || s.contains('archery')) {
    return const FieldStyle(
      preset: 'archery',
      surface: '#546E7A',
      line: '#FFFFFF',
    );
  }
  if (s.contains('ยิงปืน') ||
      s.contains('ดาร์ท') ||
      s.contains('shooting') ||
      s.contains('darts')) {
    return const FieldStyle(
      preset: 'shooting_range',
      surface: '#37474F',
      line: '#FFFFFF',
    );
  }
  if (s.contains('กอล์ฟ') || s.contains('golf')) {
    return const FieldStyle(
      preset: 'golf',
      surface: '#2E7D32',
      line: '#FFFFFF',
    );
  }
  if (s.contains('ยิมนาสติก') || s.contains('gymnastics')) {
    return const FieldStyle(
      preset: 'gymnastics',
      surface: '#1565C0',
      line: '#FFF176',
    );
  }
  if (s.contains('จักรยาน') ||
      s.contains('เวโลโดรม') ||
      s.contains('cycling') ||
      s.contains('velodrome')) {
    return const FieldStyle(
      preset: 'cycling_track',
      surface: '#C62828',
      line: '#FFFFFF',
    );
  }
  return FieldStyle.fallback;
}

/// Surface color palette for simulated fields (#RRGGBB).
const List<String> kFieldSurfaceColors = [
  '#2E7D32', // หญ้าเขียว / Grass green
  '#1565C0', // น้ำเงิน / Blue court
  '#EF6C00', // ดิน/ส้ม / Clay orange
  '#6D4C41', // ไม้ / Wood brown
  '#00838F', // เทอร์ควอยซ์ / Teal
  '#546E7A', // เทา / Grey
  '#B71C1C', // แดง / Red
  '#7B1FA2', // ม่วง / Purple
];

/// Line color palette for field markings (#RRGGBB).
const List<String> kFieldLineColors = [
  '#FFFFFF', // ขาว
  '#FFF176', // เหลืองอ่อน
  '#212121', // ดำ
];

/// Field appearance config stored in sports.field_style (JSONB).
class FieldStyle {
  final String preset; // key in kFieldStylePresets
  final String surface; // '#RRGGBB'
  final String line; // '#RRGGBB'

  const FieldStyle({
    this.preset = 'generic',
    this.surface = '#2E7D32',
    this.line = '#FFFFFF',
  });

  static const FieldStyle fallback = FieldStyle();

  factory FieldStyle.fromJson(dynamic json) {
    if (json is! Map) return fallback;
    final preset = json['preset']?.toString() ?? 'generic';
    return FieldStyle(
      preset: kFieldStylePresets.containsKey(preset) ? preset : 'generic',
      surface: json['surface']?.toString() ?? '#2E7D32',
      line: json['line']?.toString() ?? '#FFFFFF',
    );
  }

  Map<String, dynamic> toJson() => {
    'preset': preset,
    'surface': surface,
    'line': line,
  };

  FieldStyle copyWith({String? preset, String? surface, String? line}) {
    return FieldStyle(
      preset: preset ?? this.preset,
      surface: surface ?? this.surface,
      line: line ?? this.line,
    );
  }
}

Color _darkenColor(Color c, double factor) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness * factor).clamp(0.0, 1.0)).toColor();
}

/// Custom painter for grass field (single or double side) with subtle markings.
class FieldCanvasPainter extends CustomPainter {
  final String layout; // 'single' or 'double'
  final bool isDark;
  final FieldStyle style;

  FieldCanvasPainter({
    required this.layout,
    this.isDark = false,
    this.style = FieldStyle.fallback,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Pitch base gradient
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(16));

    final surface = parseHexColor(
      style.surface,
      fallback: const Color(0xFF2E7D32),
    );
    final surfaceDark = _darkenColor(surface, 0.66);
    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [_darkenColor(surface, 0.45), _darkenColor(surface, 0.32)]
            : [surface, surfaceDark],
      ).createShader(rect);
    canvas.drawRRect(rrect, basePaint);

    // Subtle pitch stripes (alternating grass texture)
    final stripePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;
    final stripeCount = 6;
    final stripeWidth = size.width / stripeCount;
    for (int i = 0; i < stripeCount; i += 2) {
      final stripeRect = Rect.fromLTWH(
        i * stripeWidth,
        0,
        stripeWidth,
        size.height,
      );
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(stripeRect, stripePaint);
      canvas.restore();
    }

    // Boundary lines
    final lineColor = parseHexColor(style.line, fallback: Colors.white);
    final linePaint = Paint()
      ..color = lineColor.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final innerInset = 10.0;
    final pitchRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        innerInset,
        innerInset,
        size.width - innerInset,
        size.height - innerInset,
      ),
      const Radius.circular(8),
    );
    canvas.drawRRect(pitchRect, linePaint);

    final isDouble = layout == 'double';
    final midX = size.width / 2;
    final netPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6;
    final dotPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    switch (style.preset) {
      case 'football':
        _paintFootball(
          canvas,
          size,
          linePaint,
          dotPaint,
          innerInset,
          isDouble,
          midX,
        );
        break;
      case 'futsal':
        _paintFutsalHandball(
          canvas,
          size,
          linePaint,
          dotPaint,
          innerInset,
          isDouble,
          midX,
        );
        break;
      case 'badminton':
        _paintBadminton(
          canvas,
          size,
          linePaint,
          netPaint,
          innerInset,
          isDouble,
          midX,
        );
        break;
      case 'volleyball':
        _paintVolleyball(
          canvas,
          size,
          linePaint,
          netPaint,
          innerInset,
          isDouble,
          midX,
        );
        break;
      case 'beach_volleyball':
        _paintBeachVolleyball(
          canvas,
          size,
          linePaint,
          netPaint,
          innerInset,
          isDouble,
          midX,
        );
        break;
      case 'takraw':
        _paintTakraw(
          canvas,
          size,
          linePaint,
          netPaint,
          innerInset,
          isDouble,
          midX,
        );
        break;
      case 'tennis':
        _paintTennis(
          canvas,
          size,
          linePaint,
          netPaint,
          innerInset,
          isDouble,
          midX,
        );
        break;
      case 'basketball':
        _paintBasketball(
          canvas,
          size,
          linePaint,
          dotPaint,
          innerInset,
          isDouble,
          midX,
        );
        break;
      case 'rugby':
        _paintRugby(canvas, size, linePaint, innerInset, isDouble, midX);
        break;
      case 'american_football':
        _paintAmericanFootball(
          canvas,
          size,
          linePaint,
          innerInset,
          isDouble,
          midX,
        );
        break;
      case 'baseball':
        _paintBaseball(canvas, size, linePaint, dotPaint, innerInset);
        break;
      case 'cricket':
        _paintCricket(canvas, size, linePaint, innerInset);
        break;
      case 'field_hockey':
        _paintFieldHockey(
          canvas,
          size,
          linePaint,
          dotPaint,
          innerInset,
          isDouble,
          midX,
        );
        break;
      case 'ice_hockey':
        _paintIceHockey(
          canvas,
          size,
          linePaint,
          dotPaint,
          innerInset,
          isDouble,
          midX,
        );
        break;
      case 'table_tennis':
        _paintTableTennis(
          canvas,
          size,
          linePaint,
          netPaint,
          innerInset,
          isDouble,
          midX,
        );
        break;
      case 'pickleball':
        _paintPickleball(
          canvas,
          size,
          linePaint,
          netPaint,
          innerInset,
          isDouble,
          midX,
        );
        break;
      case 'squash':
        _paintSquash(canvas, size, linePaint, innerInset);
        break;
      case 'boxing':
        _paintBoxing(canvas, size, linePaint, innerInset);
        break;
      case 'taekwondo':
        _paintTaekwondo(canvas, size, linePaint, dotPaint, innerInset);
        break;
      case 'martial_arts':
        _paintMartialArts(canvas, size, linePaint, dotPaint, innerInset);
        break;
      case 'wrestling':
        _paintWrestling(canvas, size, linePaint, dotPaint, innerInset);
        break;
      case 'fencing':
        _paintFencing(canvas, size, linePaint, netPaint, innerInset);
        break;
      case 'running_track':
        _paintRunningTrack(canvas, size, linePaint, innerInset);
        break;
      case 'swimming':
        _paintSwimming(canvas, size, linePaint, innerInset);
        break;
      case 'snooker':
        _paintSnooker(canvas, size, linePaint, dotPaint, innerInset);
        break;
      case 'bowling':
        _paintBowling(canvas, size, linePaint, dotPaint, innerInset);
        break;
      case 'archery':
        _paintArchery(canvas, size, linePaint, dotPaint, innerInset);
        break;
      case 'golf':
        _paintGolf(canvas, size, linePaint, dotPaint, innerInset);
        break;
      case 'gymnastics':
        _paintGymnastics(canvas, size, linePaint, dotPaint, innerInset);
        break;
      case 'cycling_track':
        _paintCyclingTrack(canvas, size, linePaint, innerInset);
        break;
      case 'shooting_range':
        _paintShootingRange(canvas, size, linePaint, dotPaint, innerInset);
        break;
      default: // generic — boundary only + center line when double
        if (isDouble) {
          canvas.drawLine(
            Offset(midX, innerInset),
            Offset(midX, size.height - innerInset),
            linePaint,
          );
        }
    }
  }

  void _paintFootball(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint dotPaint,
    double innerInset,
    bool isDouble,
    double midX,
  ) {
    if (isDouble) {
      canvas.drawLine(
        Offset(midX, innerInset),
        Offset(midX, size.height - innerInset),
        linePaint,
      );
      final centerCircleRadius = (size.height - innerInset * 2) * 0.22;
      canvas.drawCircle(
        Offset(midX, size.height / 2),
        centerCircleRadius,
        linePaint,
      );
      canvas.drawCircle(Offset(midX, size.height / 2), 3.5, dotPaint);

      final boxWidth = size.width * 0.16;
      final boxHeight = size.height * 0.45;
      final boxTop = (size.height - boxHeight) / 2;
      canvas.drawRect(
        Rect.fromLTWH(innerInset, boxTop, boxWidth, boxHeight),
        linePaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          size.width - innerInset - boxWidth,
          boxTop,
          boxWidth,
          boxHeight,
        ),
        linePaint,
      );
    } else {
      final boxWidth = size.width * 0.44;
      final boxHeight = size.height * 0.26;
      final boxLeft = (size.width - boxWidth) / 2;
      canvas.drawRect(
        Rect.fromLTWH(
          boxLeft,
          size.height - innerInset - boxHeight,
          boxWidth,
          boxHeight,
        ),
        linePaint,
      );
      final arcRadius = size.width * 0.22;
      canvas.drawCircle(
        Offset(size.width / 2, innerInset),
        arcRadius,
        linePaint,
      );
    }
  }

  void _paintFutsalHandball(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint dotPaint,
    double innerInset,
    bool isDouble,
    double midX,
  ) {
    if (isDouble) {
      canvas.drawLine(
        Offset(midX, innerInset),
        Offset(midX, size.height - innerInset),
        linePaint,
      );
      canvas.drawCircle(
        Offset(midX, size.height / 2),
        (size.height - innerInset * 2) * 0.18,
        linePaint,
      );
      canvas.drawCircle(Offset(midX, size.height / 2), 3.0, dotPaint);

      final dRadius = (size.height - innerInset * 2) * 0.35;
      final midY = size.height / 2;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(innerInset, midY), radius: dRadius),
        -1.5708,
        3.1416,
        false,
        linePaint,
      );
      canvas.drawArc(
        Rect.fromCircle(
          center: Offset(size.width - innerInset, midY),
          radius: dRadius,
        ),
        1.5708,
        3.1416,
        false,
        linePaint,
      );
      canvas.drawCircle(
        Offset(innerInset + dRadius * 0.6, midY),
        2.5,
        dotPaint,
      );
      canvas.drawCircle(
        Offset(size.width - innerInset - dRadius * 0.6, midY),
        2.5,
        dotPaint,
      );
    } else {
      final dRadius = size.width * 0.35;
      final midX2 = size.width / 2;
      canvas.drawArc(
        Rect.fromCircle(
          center: Offset(midX2, size.height - innerInset),
          radius: dRadius,
        ),
        3.1416,
        3.1416,
        false,
        linePaint,
      );
      canvas.drawCircle(
        Offset(midX2, size.height - innerInset - dRadius * 0.6),
        2.5,
        dotPaint,
      );
    }
  }

  void _paintBeachVolleyball(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint netPaint,
    double innerInset,
    bool isDouble,
    double midX,
  ) {
    if (isDouble) {
      // Net in the middle
      canvas.drawLine(
        Offset(midX, innerInset),
        Offset(midX, size.height - innerInset),
        netPaint,
      );
    } else {
      // Single side view: net line + attack zone suggestion
      canvas.drawLine(
        Offset(midX, innerInset),
        Offset(midX, size.height - innerInset),
        netPaint,
      );
      // Mark mid-court (no attack line in beach volleyball, just net + free zone)
    }
  }

  void _paintTakraw(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint netPaint,
    double innerInset,
    bool isDouble,
    double midX,
  ) {
    if (isDouble) {
      canvas.drawLine(
        Offset(midX, innerInset),
        Offset(midX, size.height - innerInset),
        netPaint,
      );
      final qcRadius = (size.height - innerInset * 2) * 0.16;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(midX, innerInset), radius: qcRadius),
        0,
        3.1416,
        false,
        linePaint,
      );
      canvas.drawArc(
        Rect.fromCircle(
          center: Offset(midX, size.height - innerInset),
          radius: qcRadius,
        ),
        3.1416,
        3.1416,
        false,
        linePaint,
      );
      final serveRadius = (size.height - innerInset * 2) * 0.12;
      final halfW = midX - innerInset;
      canvas.drawCircle(
        Offset(innerInset + halfW * 0.5, size.height / 2),
        serveRadius,
        linePaint,
      );
      canvas.drawCircle(
        Offset(size.width - innerInset - halfW * 0.5, size.height / 2),
        serveRadius,
        linePaint,
      );
    } else {
      final serveRadius = size.height * 0.16;
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        serveRadius,
        linePaint,
      );
    }
  }

  void _paintRugby(
    Canvas canvas,
    Size size,
    Paint linePaint,
    double innerInset,
    bool isDouble,
    double midX,
  ) {
    final courtW = size.width - innerInset * 2;
    if (isDouble) {
      canvas.drawLine(
        Offset(midX, innerInset),
        Offset(midX, size.height - innerInset),
        linePaint,
      );
      final tryLineOffset = courtW * 0.10;
      canvas.drawLine(
        Offset(innerInset + tryLineOffset, innerInset),
        Offset(innerInset + tryLineOffset, size.height - innerInset),
        linePaint,
      );
      canvas.drawLine(
        Offset(size.width - innerInset - tryLineOffset, innerInset),
        Offset(
          size.width - innerInset - tryLineOffset,
          size.height - innerInset,
        ),
        linePaint,
      );
      final line22Offset = courtW * 0.28;
      canvas.drawLine(
        Offset(innerInset + line22Offset, innerInset),
        Offset(innerInset + line22Offset, size.height - innerInset),
        linePaint,
      );
      canvas.drawLine(
        Offset(size.width - innerInset - line22Offset, innerInset),
        Offset(
          size.width - innerInset - line22Offset,
          size.height - innerInset,
        ),
        linePaint,
      );
      final line10Offset = courtW * 0.40;
      canvas.drawLine(
        Offset(innerInset + line10Offset, innerInset),
        Offset(innerInset + line10Offset, size.height - innerInset),
        linePaint,
      );
      canvas.drawLine(
        Offset(size.width - innerInset - line10Offset, innerInset),
        Offset(
          size.width - innerInset - line10Offset,
          size.height - innerInset,
        ),
        linePaint,
      );
    } else {
      final tryLineOffset = size.height * 0.18;
      canvas.drawLine(
        Offset(innerInset, size.height - innerInset - tryLineOffset),
        Offset(
          size.width - innerInset,
          size.height - innerInset - tryLineOffset,
        ),
        linePaint,
      );
      canvas.drawLine(
        Offset(innerInset, size.height - innerInset - tryLineOffset * 2),
        Offset(
          size.width - innerInset,
          size.height - innerInset - tryLineOffset * 2,
        ),
        linePaint,
      );
    }
  }

  void _paintAmericanFootball(
    Canvas canvas,
    Size size,
    Paint linePaint,
    double innerInset,
    bool isDouble,
    double midX,
  ) {
    final courtW = size.width - innerInset * 2;
    if (isDouble) {
      // Top-view landscape: end zones + yard lines
      final endZoneW = courtW * 0.11;
      canvas.drawLine(
        Offset(innerInset + endZoneW, innerInset),
        Offset(innerInset + endZoneW, size.height - innerInset),
        linePaint,
      );
      canvas.drawLine(
        Offset(size.width - innerInset - endZoneW, innerInset),
        Offset(size.width - innerInset - endZoneW, size.height - innerInset),
        linePaint,
      );
      // Center line
      canvas.drawLine(
        Offset(midX, innerInset),
        Offset(midX, size.height - innerInset),
        linePaint,
      );
      final playableW = courtW - endZoneW * 2;
      final yardInterval = playableW / 10;
      for (int i = 1; i < 10; i++) {
        if (i == 5) continue; // skip center — already drawn
        final x = innerInset + endZoneW + i * yardInterval;
        canvas.drawLine(
          Offset(x, innerInset),
          Offset(x, size.height - innerInset),
          linePaint,
        );
      }
    } else {
      // Single side: end zone at bottom + hash marks
      final courtH = size.height - innerInset * 2;
      final endZoneH = courtH * 0.18;
      canvas.drawLine(
        Offset(innerInset, size.height - innerInset - endZoneH),
        Offset(size.width - innerInset, size.height - innerInset - endZoneH),
        linePaint,
      );
      final yardInterval = (courtH - endZoneH) / 5;
      for (int i = 1; i < 5; i++) {
        final y = size.height - innerInset - endZoneH - i * yardInterval;
        canvas.drawLine(
          Offset(innerInset, y),
          Offset(size.width - innerInset, y),
          linePaint,
        );
      }
    }
  }

  void _paintBaseball(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint dotPaint,
    double innerInset,
  ) {
    final midX = size.width / 2;
    final homeY = size.height - innerInset - 4;
    final diamondSize = (size.height - innerInset * 2) * 0.55;

    final path = Path()
      ..moveTo(midX, homeY)
      ..lineTo(midX + diamondSize * 0.6, homeY - diamondSize * 0.5)
      ..lineTo(midX, homeY - diamondSize)
      ..lineTo(midX - diamondSize * 0.6, homeY - diamondSize * 0.5)
      ..close();
    canvas.drawPath(path, linePaint);

    canvas.drawLine(
      Offset(midX, homeY),
      Offset(innerInset, innerInset + 10),
      linePaint,
    );
    canvas.drawLine(
      Offset(midX, homeY),
      Offset(size.width - innerInset, innerInset + 10),
      linePaint,
    );

    final outfieldRect = Rect.fromCircle(
      center: Offset(midX, homeY),
      radius: diamondSize * 1.35,
    );
    canvas.drawArc(outfieldRect, -2.5, 1.86, false, linePaint);

    canvas.drawCircle(Offset(midX, homeY), 3.0, dotPaint);
    canvas.drawCircle(
      Offset(midX + diamondSize * 0.6, homeY - diamondSize * 0.5),
      3.0,
      dotPaint,
    );
    canvas.drawCircle(Offset(midX, homeY - diamondSize), 3.0, dotPaint);
    canvas.drawCircle(
      Offset(midX - diamondSize * 0.6, homeY - diamondSize * 0.5),
      3.0,
      dotPaint,
    );
    canvas.drawCircle(Offset(midX, homeY - diamondSize * 0.5), 3.0, dotPaint);
  }

  void _paintCricket(
    Canvas canvas,
    Size size,
    Paint linePaint,
    double innerInset,
  ) {
    final midX = size.width / 2;
    final midY = size.height / 2;
    final ovalRect = Rect.fromLTRB(
      innerInset + 8,
      innerInset + 4,
      size.width - innerInset - 8,
      size.height - innerInset - 4,
    );
    canvas.drawOval(ovalRect, linePaint);

    final innerOval = Rect.fromLTRB(
      midX - size.width * 0.28,
      midY - size.height * 0.36,
      midX + size.width * 0.28,
      midY + size.height * 0.36,
    );
    canvas.drawOval(innerOval, linePaint);

    final pitchW = size.width * 0.24;
    final pitchH = size.height * 0.16;
    final pitchRect = Rect.fromCenter(
      center: Offset(midX, midY),
      width: pitchW,
      height: pitchH,
    );
    canvas.drawRect(pitchRect, linePaint);

    canvas.drawLine(
      Offset(pitchRect.left + pitchW * 0.15, pitchRect.top),
      Offset(pitchRect.left + pitchW * 0.15, pitchRect.bottom),
      linePaint,
    );
    canvas.drawLine(
      Offset(pitchRect.right - pitchW * 0.15, pitchRect.top),
      Offset(pitchRect.right - pitchW * 0.15, pitchRect.bottom),
      linePaint,
    );
  }

  void _paintFieldHockey(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint dotPaint,
    double innerInset,
    bool isDouble,
    double midX,
  ) {
    final courtW = size.width - innerInset * 2;
    if (isDouble) {
      canvas.drawLine(
        Offset(midX, innerInset),
        Offset(midX, size.height - innerInset),
        linePaint,
      );
      final line23 = courtW * 0.25;
      canvas.drawLine(
        Offset(innerInset + line23, innerInset),
        Offset(innerInset + line23, size.height - innerInset),
        linePaint,
      );
      canvas.drawLine(
        Offset(size.width - innerInset - line23, innerInset),
        Offset(size.width - innerInset - line23, size.height - innerInset),
        linePaint,
      );

      final dRadius = (size.height - innerInset * 2) * 0.40;
      final midY = size.height / 2;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(innerInset, midY), radius: dRadius),
        -1.5708,
        3.1416,
        false,
        linePaint,
      );
      canvas.drawArc(
        Rect.fromCircle(
          center: Offset(size.width - innerInset, midY),
          radius: dRadius,
        ),
        1.5708,
        3.1416,
        false,
        linePaint,
      );
    } else {
      final dRadius = size.width * 0.38;
      canvas.drawArc(
        Rect.fromCircle(
          center: Offset(size.width / 2, size.height - innerInset),
          radius: dRadius,
        ),
        3.1416,
        3.1416,
        false,
        linePaint,
      );
    }
  }

  void _paintIceHockey(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint dotPaint,
    double innerInset,
    bool isDouble,
    double midX,
  ) {
    final midY = size.height / 2;
    final courtW = size.width - innerInset * 2;

    // Red center line
    final redPaint = Paint()
      ..color = Colors.red.shade600.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawLine(
      Offset(midX, innerInset),
      Offset(midX, size.height - innerInset),
      redPaint,
    );
    canvas.drawCircle(
      Offset(midX, midY),
      (size.height - innerInset * 2) * 0.22,
      redPaint,
    );
    canvas.drawCircle(Offset(midX, midY), 3.0, dotPaint);

    // Blue lines
    final bluePaint = Paint()
      ..color = Colors.blue.shade700.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    final blue1X = innerInset + courtW * 0.33;
    final blue2X = size.width - innerInset - courtW * 0.33;
    canvas.drawLine(
      Offset(blue1X, innerInset),
      Offset(blue1X, size.height - innerInset),
      bluePaint,
    );
    canvas.drawLine(
      Offset(blue2X, innerInset),
      Offset(blue2X, size.height - innerInset),
      bluePaint,
    );

    // Face-off spots
    final spotRadius = (size.height - innerInset * 2) * 0.16;
    final leftSpotX = innerInset + courtW * 0.16;
    final rightSpotX = size.width - innerInset - courtW * 0.16;
    final topSpotY = innerInset + (size.height - innerInset * 2) * 0.25;
    final botSpotY =
        size.height - innerInset - (size.height - innerInset * 2) * 0.25;

    canvas.drawCircle(Offset(leftSpotX, topSpotY), spotRadius, linePaint);
    canvas.drawCircle(Offset(leftSpotX, botSpotY), spotRadius, linePaint);
    canvas.drawCircle(Offset(rightSpotX, topSpotY), spotRadius, linePaint);
    canvas.drawCircle(Offset(rightSpotX, botSpotY), spotRadius, linePaint);

    // Goal crease arcs at each end
    canvas.drawArc(
      Rect.fromCircle(center: Offset(innerInset + 8, midY), radius: 14),
      -1.5708,
      3.1416,
      false,
      linePaint,
    );
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width - innerInset - 8, midY),
        radius: 14,
      ),
      1.5708,
      3.1416,
      false,
      linePaint,
    );
  }

  void _paintTableTennis(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint netPaint,
    double innerInset,
    bool isDouble,
    double midX,
  ) {
    final midY = size.height / 2;
    canvas.drawLine(
      Offset(innerInset, midY),
      Offset(size.width - innerInset, midY),
      linePaint,
    );
    canvas.drawLine(
      Offset(midX, innerInset - 4),
      Offset(midX, size.height - innerInset + 4),
      netPaint,
    );
  }

  void _paintPickleball(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint netPaint,
    double innerInset,
    bool isDouble,
    double midX,
  ) {
    final midY = size.height / 2;
    if (isDouble) {
      canvas.drawLine(
        Offset(midX, innerInset),
        Offset(midX, size.height - innerInset),
        netPaint,
      );
      final halfW = midX - innerInset;
      final kitchen1X = midX - halfW * 0.35;
      final kitchen2X = midX + halfW * 0.35;
      canvas.drawLine(
        Offset(kitchen1X, innerInset),
        Offset(kitchen1X, size.height - innerInset),
        linePaint,
      );
      canvas.drawLine(
        Offset(kitchen2X, innerInset),
        Offset(kitchen2X, size.height - innerInset),
        linePaint,
      );
      canvas.drawLine(
        Offset(innerInset, midY),
        Offset(kitchen1X, midY),
        linePaint,
      );
      canvas.drawLine(
        Offset(kitchen2X, midY),
        Offset(size.width - innerInset, midY),
        linePaint,
      );
    } else {
      canvas.drawLine(
        Offset(midX, innerInset),
        Offset(midX, size.height - innerInset),
        netPaint,
      );
      canvas.drawLine(
        Offset(innerInset, midY),
        Offset(size.width - innerInset, midY),
        linePaint,
      );
    }
  }

  void _paintSquash(
    Canvas canvas,
    Size size,
    Paint linePaint,
    double innerInset,
  ) {
    final midY = size.height / 2;
    final courtW = size.width - innerInset * 2;
    // Short service line divides the court ~55% from the back wall (left/front)
    final shortLineX = innerInset + courtW * 0.55;
    canvas.drawLine(
      Offset(shortLineX, innerInset),
      Offset(shortLineX, size.height - innerInset),
      linePaint,
    );
    // Half-court line extends from short line to the FRONT wall (right side = front)
    canvas.drawLine(
      Offset(shortLineX, midY),
      Offset(size.width - innerInset, midY),
      linePaint,
    );

    // Service boxes are on the FRONT side (right of short line)
    final boxSize = (size.height - innerInset * 2) * 0.28;
    canvas.drawRect(
      Rect.fromLTWH(shortLineX, innerInset, boxSize, boxSize),
      linePaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        shortLineX,
        size.height - innerInset - boxSize,
        boxSize,
        boxSize,
      ),
      linePaint,
    );
  }

  void _paintBoxing(
    Canvas canvas,
    Size size,
    Paint linePaint,
    double innerInset,
  ) {
    final side = (size.height - innerInset * 2);
    final left = (size.width - side) / 2;
    final ringRect = Rect.fromLTWH(left, innerInset, side, side);

    // Boxing ring: 4 rope lines — use full opacity for ropes
    final ropePaint = Paint()
      ..color = linePaint.color.withValues(alpha: 1.0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = linePaint.strokeWidth;
    for (int i = 0; i < 4; i++) {
      final inset = i * 5.5;
      canvas.drawRect(ringRect.deflate(inset), ropePaint);
    }

    // Corner indicators: red / blue (opposite) / white (neutral x2)
    final padPaintRed = Paint()
      ..color = Colors.red.shade700
      ..style = PaintingStyle.fill;
    final padPaintBlue = Paint()
      ..color = Colors.blue.shade700
      ..style = PaintingStyle.fill;
    final padPaintNeutral = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(left + 5, innerInset + 5), 5.0, padPaintRed);
    canvas.drawCircle(
      Offset(left + side - 5, innerInset + side - 5),
      5.0,
      padPaintBlue,
    );
    canvas.drawCircle(
      Offset(left + side - 5, innerInset + 5),
      5.0,
      padPaintNeutral,
    );
    canvas.drawCircle(
      Offset(left + 5, innerInset + side - 5),
      5.0,
      padPaintNeutral,
    );
  }

  void _paintTaekwondo(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint dotPaint,
    double innerInset,
  ) {
    final midX = size.width / 2;
    final midY = size.height / 2;
    final r = (size.height - innerInset * 2) * 0.44;

    final path = Path();
    for (int i = 0; i < 8; i++) {
      final angle = (i * 45 - 22.5) * 3.14159265 / 180.0;
      final x = midX + r * 1.3 * math.cos(angle);
      final y = midY + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, linePaint);

    canvas.drawLine(
      Offset(midX - 10, midY),
      Offset(midX + 10, midY),
      linePaint,
    );
    canvas.drawLine(
      Offset(midX, midY - 10),
      Offset(midX, midY + 10),
      linePaint,
    );
    canvas.drawCircle(Offset(midX, midY), 3.0, dotPaint);
  }

  void _paintMartialArts(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint dotPaint,
    double innerInset,
  ) {
    final midX = size.width / 2;
    final midY = size.height / 2;
    final innerW = size.width * 0.55;
    final innerH = size.height * 0.58;
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(midX, midY),
        width: innerW,
        height: innerH,
      ),
      linePaint,
    );

    canvas.drawLine(
      Offset(midX - 14, midY - 12),
      Offset(midX - 14, midY + 12),
      linePaint,
    );
    canvas.drawLine(
      Offset(midX + 14, midY - 12),
      Offset(midX + 14, midY + 12),
      linePaint,
    );
  }

  void _paintWrestling(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint dotPaint,
    double innerInset,
  ) {
    final midX = size.width / 2;
    final midY = size.height / 2;
    final radius = (size.height - innerInset * 2) * 0.44;

    canvas.drawCircle(Offset(midX, midY), radius, linePaint);

    final passivityPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0;
    canvas.drawCircle(Offset(midX, midY), radius * 0.88, passivityPaint);

    canvas.drawCircle(Offset(midX, midY), radius * 0.28, linePaint);
    canvas.drawCircle(Offset(midX, midY), 3.0, dotPaint);
  }

  void _paintFencing(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint netPaint,
    double innerInset,
  ) {
    final midX = size.width / 2;
    final midY = size.height / 2;
    final pisteH = size.height * 0.40;
    final pisteRect = Rect.fromLTWH(
      innerInset,
      midY - pisteH / 2,
      size.width - innerInset * 2,
      pisteH,
    );
    canvas.drawRect(pisteRect, linePaint);

    canvas.drawLine(
      Offset(midX, pisteRect.top),
      Offset(midX, pisteRect.bottom),
      netPaint,
    );

    final guardOffset = (size.width - innerInset * 2) * 0.15;
    canvas.drawLine(
      Offset(midX - guardOffset, pisteRect.top),
      Offset(midX - guardOffset, pisteRect.bottom),
      linePaint,
    );
    canvas.drawLine(
      Offset(midX + guardOffset, pisteRect.top),
      Offset(midX + guardOffset, pisteRect.bottom),
      linePaint,
    );

    final warnOffset = (size.width - innerInset * 2) * 0.12;
    canvas.drawLine(
      Offset(innerInset + warnOffset, pisteRect.top),
      Offset(innerInset + warnOffset, pisteRect.bottom),
      linePaint,
    );
    canvas.drawLine(
      Offset(size.width - innerInset - warnOffset, pisteRect.top),
      Offset(size.width - innerInset - warnOffset, pisteRect.bottom),
      linePaint,
    );
  }

  void _paintRunningTrack(
    Canvas canvas,
    Size size,
    Paint linePaint,
    double innerInset,
  ) {
    final laneCount = 4;
    for (int i = 0; i < laneCount; i++) {
      final inset = innerInset + i * 7.0;
      final laneRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(inset, inset, size.width - inset, size.height - inset),
        Radius.circular((size.height - inset * 2) / 2),
      );
      canvas.drawRRect(laneRect, linePaint);
    }
    // Start/Finish line: horizontal line across the straight on the right side
    final finishX = size.width * 0.72;
    canvas.drawLine(
      Offset(finishX, innerInset),
      Offset(finishX, size.height - innerInset),
      linePaint,
    );
  }

  void _paintSwimming(
    Canvas canvas,
    Size size,
    Paint linePaint,
    double innerInset,
  ) {
    final laneCount = 5;
    final courtH = size.height - innerInset * 2;
    final laneH = courtH / laneCount;
    // Lane dividers
    for (int i = 1; i < laneCount; i++) {
      final y = innerInset + i * laneH;
      canvas.drawLine(
        Offset(innerInset, y),
        Offset(size.width - innerInset, y),
        linePaint,
      );
    }
    // T-markers at both ends of each lane (top & bottom)
    for (int i = 0; i < laneCount; i++) {
      final laneTopY = innerInset + i * laneH;
      final laneMidY = laneTopY + laneH / 2;
      // Top wall T-mark
      canvas.drawLine(
        Offset(innerInset + 8, laneTopY),
        Offset(innerInset + 8, laneTopY + laneH * 0.3),
        linePaint,
      );
      canvas.drawLine(
        Offset(innerInset + 4, laneTopY + laneH * 0.3),
        Offset(innerInset + 12, laneTopY + laneH * 0.3),
        linePaint,
      );
      // Bottom wall T-mark (mirrored)
      canvas.drawLine(
        Offset(size.width - innerInset - 8, laneTopY + laneH),
        Offset(size.width - innerInset - 8, laneTopY + laneH * 0.7),
        linePaint,
      );
      canvas.drawLine(
        Offset(size.width - innerInset - 12, laneTopY + laneH * 0.7),
        Offset(size.width - innerInset - 4, laneTopY + laneH * 0.7),
        linePaint,
      );
      // Center guide line
      canvas.drawLine(
        Offset(innerInset + laneH * 0.15, laneMidY),
        Offset(size.width - innerInset - laneH * 0.15, laneMidY),
        linePaint,
      );
    }
  }

  void _paintSnooker(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint dotPaint,
    double innerInset,
  ) {
    final midY = size.height / 2;
    final courtW = size.width - innerInset * 2;

    final baulkX = innerInset + courtW * 0.22;
    canvas.drawLine(
      Offset(baulkX, innerInset),
      Offset(baulkX, size.height - innerInset),
      linePaint,
    );

    final dRadius = (size.height - innerInset * 2) * 0.25;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(baulkX, midY), radius: dRadius),
      1.5708,
      3.1416,
      false,
      linePaint,
    );

    final pocketPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.fill;
    final pR = 5.0;
    canvas.drawCircle(Offset(innerInset + 2, innerInset + 2), pR, pocketPaint);
    canvas.drawCircle(
      Offset(size.width - innerInset - 2, innerInset + 2),
      pR,
      pocketPaint,
    );
    canvas.drawCircle(
      Offset(innerInset + 2, size.height - innerInset - 2),
      pR,
      pocketPaint,
    );
    canvas.drawCircle(
      Offset(size.width - innerInset - 2, size.height - innerInset - 2),
      pR,
      pocketPaint,
    );
    canvas.drawCircle(Offset(size.width / 2, innerInset), pR, pocketPaint);
    canvas.drawCircle(
      Offset(size.width / 2, size.height - innerInset),
      pR,
      pocketPaint,
    );
  }

  void _paintBowling(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint dotPaint,
    double innerInset,
  ) {
    final midY = size.height / 2;
    final laneH = size.height * 0.45;
    final laneRect = Rect.fromLTWH(
      innerInset,
      midY - laneH / 2,
      size.width - innerInset * 2,
      laneH,
    );
    canvas.drawRect(laneRect, linePaint);

    final foulX = innerInset + (size.width - innerInset * 2) * 0.15;
    canvas.drawLine(
      Offset(foulX, laneRect.top),
      Offset(foulX, laneRect.bottom),
      linePaint,
    );

    final arrowX = innerInset + (size.width - innerInset * 2) * 0.45;
    for (final dy in [-8.0, 0.0, 8.0]) {
      canvas.drawLine(
        Offset(arrowX, midY + dy),
        Offset(arrowX + 8, midY + dy - 3),
        linePaint,
      );
      canvas.drawLine(
        Offset(arrowX, midY + dy),
        Offset(arrowX + 8, midY + dy + 3),
        linePaint,
      );
    }

    final pinDeckX =
        size.width - innerInset - (size.width - innerInset * 2) * 0.15;
    canvas.drawCircle(Offset(pinDeckX, midY), 2.5, dotPaint);
    canvas.drawCircle(Offset(pinDeckX + 8, midY - 6), 2.5, dotPaint);
    canvas.drawCircle(Offset(pinDeckX + 8, midY + 6), 2.5, dotPaint);
    canvas.drawCircle(Offset(pinDeckX + 16, midY - 12), 2.5, dotPaint);
    canvas.drawCircle(Offset(pinDeckX + 16, midY), 2.5, dotPaint);
    canvas.drawCircle(Offset(pinDeckX + 16, midY + 12), 2.5, dotPaint);
  }

  void _paintArchery(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint dotPaint,
    double innerInset,
  ) {
    final midX = size.width / 2;
    final midY = size.height / 2;
    final maxR = (size.height - innerInset * 2) * 0.44;

    for (int i = 1; i <= 5; i++) {
      canvas.drawCircle(Offset(midX, midY), maxR * (i / 5.0), linePaint);
    }
    canvas.drawCircle(Offset(midX, midY), 3.0, dotPaint);
  }

  // ---------------------------------------------------------------------------
  // Golf: Tee box, fairway contour, putting green & flag pole
  // ---------------------------------------------------------------------------
  void _paintGolf(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint dotPaint,
    double innerInset,
  ) {
    final midY = size.height / 2;
    final teeX = innerInset + size.width * 0.15;
    final greenX = size.width - innerInset - size.width * 0.22;

    // Tee Box marker
    canvas.drawCircle(Offset(teeX, midY - 10), 3.0, linePaint);
    canvas.drawCircle(Offset(teeX, midY + 10), 3.0, linePaint);

    // Putting Green Contour (Oval)
    final greenRect = Rect.fromCenter(
      center: Offset(greenX, midY),
      width: size.width * 0.28,
      height: size.height * 0.55,
    );
    canvas.drawOval(greenRect, linePaint);

    // Hole & Flag stick
    canvas.drawCircle(Offset(greenX, midY), 3.5, dotPaint);
    canvas.drawLine(Offset(greenX, midY), Offset(greenX, midY - 20), linePaint);
    final flagPath = Path()
      ..moveTo(greenX, midY - 20)
      ..lineTo(greenX + 10, midY - 15)
      ..lineTo(greenX, midY - 10);
    canvas.drawPath(flagPath, linePaint);
  }

  // ---------------------------------------------------------------------------
  // Gymnastics: Floor exercise mat + Vault runway & apparatus
  // ---------------------------------------------------------------------------
  void _paintGymnastics(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint dotPaint,
    double innerInset,
  ) {
    final midX = size.width / 2;
    final midY = size.height / 2;

    // Floor Exercise Mat (Square / Outer border inset)
    final matSize = size.height * 0.65;
    final floorMat = Rect.fromCenter(
      center: Offset(midX * 0.7, midY),
      width: matSize,
      height: matSize,
    );
    canvas.drawRect(floorMat, linePaint);
    canvas.drawRect(floorMat.deflate(6), linePaint);

    // Vault Runway on the right side
    final vaultX = size.width - innerInset - 40;
    canvas.drawLine(Offset(vaultX - 60, midY), Offset(vaultX, midY), linePaint);
    // Vault table
    canvas.drawRect(
      Rect.fromCenter(center: Offset(vaultX, midY), width: 14, height: 24),
      linePaint,
    );
  }

  // ---------------------------------------------------------------------------
  // Cycling Track: Velodrome Oval & Finish line
  // ---------------------------------------------------------------------------
  void _paintCyclingTrack(
    Canvas canvas,
    Size size,
    Paint linePaint,
    double innerInset,
  ) {
    final trackRect = Rect.fromLTWH(
      innerInset + 10,
      innerInset + 10,
      size.width - (innerInset + 10) * 2,
      size.height - (innerInset + 10) * 2,
    );

    // Velodrome concentric ovals
    final outerRRect = RRect.fromRectAndRadius(
      trackRect,
      Radius.circular(size.height * 0.45),
    );
    final innerRRect = RRect.fromRectAndRadius(
      trackRect.deflate(22),
      Radius.circular(size.height * 0.35),
    );
    final blueLineRRect = RRect.fromRectAndRadius(
      trackRect.deflate(11),
      Radius.circular(size.height * 0.40),
    );

    canvas.drawRRect(outerRRect, linePaint);
    canvas.drawRRect(innerRRect, linePaint);
    canvas.drawRRect(blueLineRRect, linePaint);

    // Finish line perpendicular to straightaway
    final midX = size.width / 2;
    final botY1 = trackRect.bottom - 22;
    final botY2 = trackRect.bottom;
    canvas.drawLine(Offset(midX, botY1), Offset(midX, botY2), linePaint);
  }

  // ---------------------------------------------------------------------------
  // Shooting Range: Firing line, lane markers & concentric targets
  // ---------------------------------------------------------------------------
  void _paintShootingRange(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint dotPaint,
    double innerInset,
  ) {
    final firingLineX = innerInset + size.width * 0.18;
    final targetLineX = size.width - innerInset - size.width * 0.15;

    // Firing line
    canvas.drawLine(
      Offset(firingLineX, innerInset),
      Offset(firingLineX, size.height - innerInset),
      linePaint,
    );

    // 3 Shooting Lanes
    final h = size.height - innerInset * 2;
    final laneY1 = innerInset + h * 0.25;
    final laneY2 = innerInset + h * 0.50;
    final laneY3 = innerInset + h * 0.75;

    for (final y in [laneY1, laneY2, laneY3]) {
      // Lane dividers
      canvas.drawLine(
        Offset(firingLineX, y),
        Offset(targetLineX, y),
        linePaint,
      );

      // Target bulls-eye
      canvas.drawCircle(Offset(targetLineX, y), 14, linePaint);
      canvas.drawCircle(Offset(targetLineX, y), 8, linePaint);
      canvas.drawCircle(Offset(targetLineX, y), 2.5, dotPaint);
    }
  }

  void _paintBadminton(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint netPaint,
    double innerInset,
    bool isDouble,
    double midX,
  ) {
    // Singles sidelines inset from top/bottom edges.
    final sideInset = size.height * 0.12;
    final topY = innerInset + sideInset;
    final botY = size.height - innerInset - sideInset;

    if (isDouble) {
      // Net at center.
      canvas.drawLine(
        Offset(midX, innerInset),
        Offset(midX, size.height - innerInset),
        netPaint,
      );
      // Per half: short service line ~22% from net + singles sidelines.
      final halfW = midX - innerInset;
      for (final dir in [-1.0, 1.0]) {
        final shortServiceX = midX + dir * halfW * 0.22;
        canvas.drawLine(
          Offset(shortServiceX, innerInset),
          Offset(shortServiceX, size.height - innerInset),
          linePaint,
        );
        // Long service (doubles) line near back boundary.
        final backX = midX + dir * halfW * 0.88;
        canvas.drawLine(Offset(backX, topY), Offset(backX, botY), linePaint);
      }
    } else {
      // Full court without net: doubles boundary + singles sidelines + service lines.
      canvas.drawLine(
        Offset(innerInset, topY),
        Offset(size.width - innerInset, topY),
        linePaint,
      );
      canvas.drawLine(
        Offset(innerInset, botY),
        Offset(size.width - innerInset, botY),
        linePaint,
      );
      final courtW = size.width - innerInset * 2;
      canvas.drawLine(
        Offset(innerInset + courtW * 0.28, topY),
        Offset(innerInset + courtW * 0.28, botY),
        linePaint,
      );
      canvas.drawLine(
        Offset(innerInset + courtW * 0.72, topY),
        Offset(innerInset + courtW * 0.72, botY),
        linePaint,
      );
      canvas.drawLine(Offset(midX, topY), Offset(midX, botY), linePaint);
    }
  }

  void _paintVolleyball(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint netPaint,
    double innerInset,
    bool isDouble,
    double midX,
  ) {
    if (isDouble) {
      canvas.drawLine(
        Offset(midX, innerInset),
        Offset(midX, size.height - innerInset),
        netPaint,
      );
      // Attack (3m) line ~25% from net on each half.
      final halfW = midX - innerInset;
      for (final dir in [-1.0, 1.0]) {
        final attackX = midX + dir * halfW * 0.30;
        canvas.drawLine(
          Offset(attackX, innerInset),
          Offset(attackX, size.height - innerInset),
          linePaint,
        );
      }
    } else {
      // Center + attack lines.
      canvas.drawLine(
        Offset(midX, innerInset),
        Offset(midX, size.height - innerInset),
        netPaint,
      );
      final courtW = size.width - innerInset * 2;
      canvas.drawLine(
        Offset(innerInset + courtW * 0.25, innerInset),
        Offset(innerInset + courtW * 0.25, size.height - innerInset),
        linePaint,
      );
      canvas.drawLine(
        Offset(innerInset + courtW * 0.75, innerInset),
        Offset(innerInset + courtW * 0.75, size.height - innerInset),
        linePaint,
      );
    }
  }

  void _paintTennis(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint netPaint,
    double innerInset,
    bool isDouble,
    double midX,
  ) {
    // Singles sidelines inset from top/bottom edges.
    final sideInset = size.height * 0.10;
    final topY = innerInset + sideInset;
    final botY = size.height - innerInset - sideInset;
    final midY = size.height / 2;

    if (isDouble) {
      canvas.drawLine(
        Offset(midX, innerInset),
        Offset(midX, size.height - innerInset),
        netPaint,
      );
      final halfW = midX - innerInset;
      for (final dir in [-1.0, 1.0]) {
        // Service line ~32% from net.
        final serviceX = midX + dir * halfW * 0.34;
        canvas.drawLine(
          Offset(serviceX, topY),
          Offset(serviceX, botY),
          linePaint,
        );
        // Center service line from net to service line.
        canvas.drawLine(Offset(midX, midY), Offset(serviceX, midY), linePaint);
      }
      // Singles sidelines.
      canvas.drawLine(Offset(innerInset, topY), Offset(midX, topY), linePaint);
      canvas.drawLine(Offset(innerInset, botY), Offset(midX, botY), linePaint);
      canvas.drawLine(
        Offset(midX, topY),
        Offset(size.width - innerInset, topY),
        linePaint,
      );
      canvas.drawLine(
        Offset(midX, botY),
        Offset(size.width - innerInset, botY),
        linePaint,
      );
    } else {
      canvas.drawLine(
        Offset(innerInset, topY),
        Offset(size.width - innerInset, topY),
        linePaint,
      );
      canvas.drawLine(
        Offset(innerInset, botY),
        Offset(size.width - innerInset, botY),
        linePaint,
      );
      canvas.drawLine(
        Offset(midX, innerInset),
        Offset(midX, size.height - innerInset),
        netPaint,
      );
      final halfW = midX - innerInset;
      for (final dir in [-1.0, 1.0]) {
        final serviceX = midX + dir * halfW * 0.38;
        canvas.drawLine(
          Offset(serviceX, topY),
          Offset(serviceX, botY),
          linePaint,
        );
        canvas.drawLine(Offset(midX, midY), Offset(serviceX, midY), linePaint);
      }
    }
  }

  void _paintBasketball(
    Canvas canvas,
    Size size,
    Paint linePaint,
    Paint dotPaint,
    double innerInset,
    bool isDouble,
    double midX,
  ) {
    if (isDouble) {
      canvas.drawLine(
        Offset(midX, innerInset),
        Offset(midX, size.height - innerInset),
        linePaint,
      );
      final centerCircleRadius = (size.height - innerInset * 2) * 0.20;
      canvas.drawCircle(
        Offset(midX, size.height / 2),
        centerCircleRadius,
        linePaint,
      );
      canvas.drawCircle(Offset(midX, size.height / 2), 3.5, dotPaint);
      // Key + free-throw arc near each end.
      final keyW = size.width * 0.13;
      final keyH = size.height * 0.34;
      final keyTop = (size.height - keyH) / 2;
      canvas.drawRect(Rect.fromLTWH(innerInset, keyTop, keyW, keyH), linePaint);
      canvas.drawRect(
        Rect.fromLTWH(size.width - innerInset - keyW, keyTop, keyW, keyH),
        linePaint,
      );
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(innerInset + keyW, size.height / 2),
          width: keyH,
          height: keyH,
        ),
        -1.5708,
        3.1416,
        false,
        linePaint,
      );
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(size.width - innerInset - keyW, size.height / 2),
          width: keyH,
          height: keyH,
        ),
        1.5708,
        3.1416,
        false,
        linePaint,
      );
    } else {
      final keyW = size.width * 0.36;
      final keyH = size.height * 0.26;
      final keyLeft = (size.width - keyW) / 2;
      canvas.drawRect(
        Rect.fromLTWH(keyLeft, size.height - innerInset - keyH, keyW, keyH),
        linePaint,
      );
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height - innerInset - keyH),
          width: keyW,
          height: keyW * 0.7,
        ),
        3.1416,
        3.1416,
        false,
        linePaint,
      );
      canvas.drawCircle(
        Offset(size.width / 2, innerInset),
        size.width * 0.20,
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant FieldCanvasPainter oldDelegate) {
    return oldDelegate.layout != layout ||
        oldDelegate.isDark != isDark ||
        oldDelegate.style.preset != style.preset ||
        oldDelegate.style.surface != style.surface ||
        oldDelegate.style.line != style.line;
  }
}

/// Interactive Editor for sport group positions on a pitch canvas.
class PositionLineupEditor extends StatefulWidget {
  final String layout; // 'single' or 'double'
  final List<Map<String, dynamic>> positions;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;
  final bool enabled;
  final FieldStyle fieldStyle;

  const PositionLineupEditor({
    super.key,
    required this.layout,
    required this.positions,
    required this.onChanged,
    this.enabled = true,
    this.fieldStyle = FieldStyle.fallback,
  });

  @override
  State<PositionLineupEditor> createState() => _PositionLineupEditorState();
}

class _PositionLineupEditorState extends State<PositionLineupEditor> {
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _items = List<Map<String, dynamic>>.from(
      widget.positions.map((p) => Map<String, dynamic>.from(p)),
    );
  }

  @override
  void didUpdateWidget(covariant PositionLineupEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.positions != oldWidget.positions) {
      _items = List<Map<String, dynamic>>.from(
        widget.positions.map((p) => Map<String, dynamic>.from(p)),
      );
    }
  }

  void _notify() {
    widget.onChanged(List<Map<String, dynamic>>.from(_items));
  }

  Future<void> _openMarkerModal({
    Map<String, dynamic>? existing,
    int? index,
  }) async {
    if (!widget.enabled) return;
    final res = await showPositionMarkerEditor(
      context,
      existing: existing,
      layout: widget.layout,
    );
    if (res == null) return;

    setState(() {
      if (index != null && index >= 0 && index < _items.length) {
        _items[index] = {..._items[index], ...res};
      } else {
        // Default placement near center or tapped position
        final nextX = 0.5;
        final nextY = 0.5;
        _items.add({
          ...res,
          'x': nextX,
          'y': nextY,
          'side': widget.layout == 'double' ? (nextX >= 0.5 ? 1 : 0) : 0,
          'is_active': true,
        });
      }
    });
    _notify();
  }

  void _deleteMarker(int index) {
    if (!widget.enabled) return;
    setState(() {
      _items.removeAt(index);
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final isDouble = widget.layout == 'double';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Canvas Header Bar
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    isDouble
                        ? Icons.compare_arrows_rounded
                        : Icons.crop_portrait_rounded,
                    size: 16,
                    color: AppColors.primaryDark,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isDouble ? 'สนาม 2 ฝั่ง' : 'สนาม 1 ฝั่ง',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (widget.enabled)
              TextButton.icon(
                onPressed: () => _openMarkerModal(),
                icon: const Icon(Icons.add_location_alt_rounded, size: 18),
                label: const Text('เพิ่มตำแหน่ง'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryDark,
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // Interactive Pitch Box
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final w = constraints.maxWidth;
              final h = w * (isDouble ? 0.60 : 0.82);

              return GestureDetector(
                onTapUp: widget.enabled
                    ? (details) {
                        final nx = (details.localPosition.dx / w).clamp(
                          0.05,
                          0.95,
                        );
                        final ny = (details.localPosition.dy / h).clamp(
                          0.05,
                          0.95,
                        );
                        final side = isDouble ? (nx >= 0.5 ? 1 : 0) : 0;
                        showPositionMarkerEditor(
                          context,
                          layout: widget.layout,
                        ).then((res) {
                          if (res != null) {
                            setState(() {
                              _items.add({
                                ...res,
                                'x': nx,
                                'y': ny,
                                'side': side,
                                'is_active': true,
                              });
                            });
                            _notify();
                          }
                        });
                      }
                    : null,
                child: SizedBox(
                  width: w,
                  height: h,
                  child: Stack(
                    children: [
                      // Pitch background
                      Positioned.fill(
                        child: CustomPaint(
                          painter: FieldCanvasPainter(
                            layout: widget.layout,
                            style: widget.fieldStyle,
                          ),
                        ),
                      ),

                      // Hint text if empty
                      if (_items.isEmpty)
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.touch_app_rounded,
                                    color: Colors.white70,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'แตะที่สนามเพื่อวางตำแหน่งผู้เล่น',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // Markers
                      for (int i = 0; i < _items.length; i++) ...[
                        _buildDraggableMarker(
                          index: i,
                          item: _items[i],
                          canvasWidth: w,
                          canvasHeight: h,
                          isDouble: isDouble,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),

        // Marker summary chips below pitch
        if (_items.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < _items.length; i++)
                _buildPositionPill(index: i, item: _items[i]),
            ],
          ),
      ],
    );
  }

  Widget _buildDraggableMarker({
    required int index,
    required Map<String, dynamic> item,
    required double canvasWidth,
    required double canvasHeight,
    required bool isDouble,
  }) {
    final x = ((item['x'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
    final y = ((item['y'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
    final iconKey = item['icon']?.toString() ?? 'player';
    final iconMeta =
        kPositionIconChoices[iconKey] ?? kPositionIconChoices['player']!;
    final color = parseHexColor(item['color']?.toString());
    final label = item['label']?.toString() ?? 'ตำแหน่ง';
    final slots = (item['slots'] as num?)?.toInt() ?? 1;

    final markerSize = 44.0;
    final left = (x * canvasWidth - markerSize / 2).clamp(
      0.0,
      canvasWidth - markerSize,
    );
    final top = (y * canvasHeight - markerSize / 2).clamp(
      0.0,
      canvasHeight - markerSize,
    );

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onPanUpdate: widget.enabled
            ? (details) {
                setState(() {
                  final newLeft = left + details.delta.dx;
                  final newTop = top + details.delta.dy;
                  final nx = ((newLeft + markerSize / 2) / canvasWidth).clamp(
                    0.05,
                    0.95,
                  );
                  final ny = ((newTop + markerSize / 2) / canvasHeight).clamp(
                    0.05,
                    0.95,
                  );
                  item['x'] = nx;
                  item['y'] = ny;
                  if (isDouble) {
                    item['side'] = nx >= 0.5 ? 1 : 0;
                  }
                });
                _notify();
              }
            : null,
        onTap: () => _openMarkerModal(existing: item, index: index),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: markerSize,
              height: markerSize,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: Icon(iconMeta.icon, color: Colors.white, size: 22),
              ),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$label ($slots)',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPositionPill({
    required int index,
    required Map<String, dynamic> item,
  }) {
    final iconKey = item['icon']?.toString() ?? 'player';
    final iconMeta =
        kPositionIconChoices[iconKey] ?? kPositionIconChoices['player']!;
    final color = parseHexColor(item['color']?.toString());
    final label = item['label']?.toString() ?? '';
    final slots = (item['slots'] as num?)?.toInt() ?? 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(iconMeta.icon, color: Colors.white, size: 14),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$slots คน',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryDark,
              ),
            ),
          ),
          if (widget.enabled) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: () => _openMarkerModal(existing: item, index: index),
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.edit_outlined, size: 16, color: Colors.grey),
              ),
            ),
            InkWell(
              onTap: () => _deleteMarker(index),
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Colors.redAccent,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Read-only pitch viewer displaying lineup and slot availability.
class PositionLineupView extends StatelessWidget {
  final String layout; // 'single' or 'double'
  final List<Map<String, dynamic>> positions;
  final Map<String, int>? takenCounts; // position_id -> taken count
  final String? selectedPositionId;
  final ValueChanged<String>? onPositionSelected;
  final FieldStyle fieldStyle;

  const PositionLineupView({
    super.key,
    required this.layout,
    required this.positions,
    this.takenCounts,
    this.selectedPositionId,
    this.onPositionSelected,
    this.fieldStyle = FieldStyle.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final isDouble = layout == 'double';
    final activePositions = positions
        .where((p) => p['is_active'] != false)
        .toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final w = constraints.maxWidth;
          final h = w * (isDouble ? 0.60 : 0.82);

          return SizedBox(
            width: w,
            height: h,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: FieldCanvasPainter(
                      layout: layout,
                      style: fieldStyle,
                    ),
                  ),
                ),
                for (final pos in activePositions) ...[_buildMarker(pos, w, h)],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMarker(
    Map<String, dynamic> pos,
    double canvasWidth,
    double canvasHeight,
  ) {
    final posId = pos['id']?.toString() ?? '';
    final x = ((pos['x'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
    final y = ((pos['y'] as num?)?.toDouble() ?? 0.5).clamp(0.0, 1.0);
    final iconKey = pos['icon']?.toString() ?? 'player';
    final iconMeta =
        kPositionIconChoices[iconKey] ?? kPositionIconChoices['player']!;
    final color = parseHexColor(pos['color']?.toString());
    final label = pos['label']?.toString() ?? '';
    final slots = (pos['slots'] as num?)?.toInt() ?? 1;

    final taken = takenCounts != null && posId.isNotEmpty
        ? (takenCounts![posId] ?? 0)
        : 0;
    final remaining = (slots - taken).clamp(0, slots);
    final isFull = takenCounts != null && remaining <= 0;
    final isSelected =
        selectedPositionId != null && selectedPositionId == posId;

    final markerSize = 42.0;
    final left = (x * canvasWidth - markerSize / 2).clamp(
      0.0,
      canvasWidth - markerSize,
    );
    final top = (y * canvasHeight - markerSize / 2).clamp(
      0.0,
      canvasHeight - markerSize,
    );

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onTap: (onPositionSelected != null && !isFull && posId.isNotEmpty)
            ? () => onPositionSelected!(posId)
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: markerSize,
              height: markerSize,
              decoration: BoxDecoration(
                color: isFull ? Colors.grey.shade500 : color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.amberAccent : Colors.white,
                  width: isSelected ? 3.5 : 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isSelected
                        ? Colors.amber.withValues(alpha: 0.6)
                        : Colors.black.withValues(alpha: 0.35),
                    blurRadius: isSelected ? 10 : 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Icon(iconMeta.icon, color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primaryDark
                    : Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                takenCounts != null
                    ? '$label (${isFull ? 'เต็ม' : 'เหลือ $remaining'})'
                    : '$label ($slots)',
                style: TextStyle(
                  color: isFull ? Colors.red.shade200 : Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet dialog to create or edit a position marker.
Future<Map<String, dynamic>?> showPositionMarkerEditor(
  BuildContext context, {
  Map<String, dynamic>? existing,
  String layout = 'single',
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final labelCtrl = TextEditingController(
        text: existing?['label']?.toString() ?? '',
      );
      final iconScrollCtrl = ScrollController();
      String selectedIcon = existing?['icon']?.toString() ?? 'player';
      String selectedColor =
          existing?['color']?.toString() ?? kPositionColorChoices.first;
      int slots = (existing?['slots'] as num?)?.toInt() ?? 1;
      int side = (existing?['side'] as num?)?.toInt() ?? 0;
      String? errorText;

      return StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 14,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: parseHexColor(
                            selectedColor,
                          ).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          (kPositionIconChoices[selectedIcon] ??
                                  kPositionIconChoices['player']!)
                              .icon,
                          color: parseHexColor(selectedColor),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        existing != null
                            ? 'แก้ไขตำแหน่งผู้เล่น'
                            : 'เพิ่มตำแหน่งผู้เล่น',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Label Input
                  TextField(
                    controller: labelCtrl,
                    maxLength: 60,
                    decoration: InputDecoration(
                      labelText: 'ชื่อตำแหน่ง (เช่น กองหน้า, ผู้รักษาประตู)',
                      hintText: 'ระบุชื่อตำแหน่งผู้เล่น',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      errorText: errorText,
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Icon Picker
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'เลือกไอคอนตำแหน่ง',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${kPositionIconChoices.length} แบบ',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 180),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Scrollbar(
                      controller: iconScrollCtrl,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: iconScrollCtrl,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: kPositionIconChoices.entries.map((entry) {
                            final isSelected = selectedIcon == entry.key;
                            return Tooltip(
                              message: entry.value.label,
                              child: InkWell(
                                onTap: () => setModalState(
                                  () => selectedIcon = entry.key,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primary
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppColors.primaryDark
                                          : Colors.grey.shade300,
                                      width: isSelected ? 2 : 1,
                                    ),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.35),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Icon(
                                    entry.value.icon,
                                    size: 22,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.grey.shade800,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Color Palette Picker
                  const Text(
                    'เลือกสีหมุดตำแหน่ง',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    children: kPositionColorChoices.map((hex) {
                      final c = parseHexColor(hex);
                      final isSelected =
                          selectedColor.toUpperCase() == hex.toUpperCase();
                      return GestureDetector(
                        onTap: () => setModalState(() => selectedColor = hex),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.black87 : Colors.white,
                              width: isSelected ? 3 : 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 18,
                                )
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // Slots Stepper
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'จำนวนที่รับในตำแหน่งนี้',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '1 – 50 คน',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: slots > 1
                                ? () => setModalState(() => slots--)
                                : null,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$slots',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: slots < 50
                                ? () => setModalState(() => slots++)
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Side selector if double
                  if (layout == 'double') ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Text(
                          'ฝั่งสนาม:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(
                              value: 0,
                              label: Text('ฝั่งซ้าย / เจ้าบ้าน'),
                            ),
                            ButtonSegment(
                              value: 1,
                              label: Text('ฝั่งขวา / ทีมเยือน'),
                            ),
                          ],
                          selected: {side},
                          onSelectionChanged: (set) =>
                              setModalState(() => side = set.first),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        final trimmed = labelCtrl.text.trim();
                        if (trimmed.isEmpty) {
                          setModalState(
                            () => errorText = 'กรุณาระบุชื่อตำแหน่ง',
                          );
                          return;
                        }
                        Navigator.pop(ctx, {
                          if (existing?['id'] != null) 'id': existing!['id'],
                          'label': trimmed,
                          'icon': selectedIcon,
                          'color': selectedColor,
                          'slots': slots,
                          'side': side,
                          if (existing?['x'] != null) 'x': existing!['x'],
                          if (existing?['y'] != null) 'y': existing!['y'],
                        });
                      },
                      child: const Text(
                        'ตกลง',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Shared picker for field appearance (line preset + surface/line colors).
/// Controlled widget — parent keeps the [value] and rebuilds on [onChanged].
class FieldStylePicker extends StatefulWidget {
  final FieldStyle value;
  final ValueChanged<FieldStyle> onChanged;
  final String? sportName;

  const FieldStylePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.sportName,
  });

  @override
  State<FieldStylePicker> createState() => _FieldStylePickerState();
}

class _FieldStylePickerState extends State<FieldStylePicker> {
  late String _selectedCategory;

  @override
  void initState() {
    super.initState();
    _initCategory();
  }

  @override
  void didUpdateWidget(covariant FieldStylePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sportName != oldWidget.sportName) {
      // Only re-init category when sport name actually changes (e.g. dialog reopened for a different sport)
      setState(_initCategory);
    }
  }

  void _initCategory() {
    final sportCat = getCategoryForSport(widget.sportName);
    if (sportCat != 'all') {
      _selectedCategory = sportCat;
    } else {
      // Fall back to the category of the currently selected preset
      _selectedCategory = kFieldPresetCategories[widget.value.preset] ?? 'all';
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredEntries = kFieldStylePresets.entries.where((e) {
      if (_selectedCategory == 'all') return true;
      return kFieldPresetCategories[e.key] == _selectedCategory;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ลักษณะเส้นสนาม',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        // Category Filter (Single-row horizontal scrollable)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: kFieldCategories.map((cat) {
              final isCatSelected = _selectedCategory == cat.key;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  avatar: Icon(
                    cat.icon,
                    size: 14,
                    color: isCatSelected ? Colors.white : AppColors.primary,
                  ),
                  label: Text(
                    cat.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isCatSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isCatSelected ? Colors.white : Colors.black87,
                    ),
                  ),
                  selected: isCatSelected,
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                  checkmarkColor: Colors.white,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  onSelected: (_) {
                    setState(() {
                      _selectedCategory = cat.key;
                    });
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: filteredEntries.map((e) {
            final selected = widget.value.preset == e.key;
            return ChoiceChip(
              label: Text(e.value, style: const TextStyle(fontSize: 12)),
              selected: selected,
              onSelected: (_) =>
                  widget.onChanged(widget.value.copyWith(preset: e.key)),
              selectedColor: AppColors.primary.withValues(alpha: 0.2),
              labelStyle: TextStyle(
                color: selected ? AppColors.primaryDark : Colors.black87,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        const Text(
          'สีพื้นสนาม',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kFieldSurfaceColors.map((hex) {
            final c = parseHexColor(hex);
            final selected =
                widget.value.surface.toUpperCase() == hex.toUpperCase();
            return Semantics(
              label: 'สีพื้นสนาม $hex',
              selected: selected,
              button: true,
              child: GestureDetector(
                onTap: () =>
                    widget.onChanged(widget.value.copyWith(surface: hex)),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? AppColors.primaryDark : Colors.white,
                      width: selected ? 3 : 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        const Text(
          'สีเส้นสนาม',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: kFieldLineColors.map((hex) {
            final c = parseHexColor(hex);
            final selected =
                widget.value.line.toUpperCase() == hex.toUpperCase();
            return Semantics(
              label: 'สีเส้นสนาม $hex',
              selected: selected,
              button: true,
              child: GestureDetector(
                onTap: () => widget.onChanged(widget.value.copyWith(line: hex)),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? AppColors.primaryDark
                          : Colors.grey.shade400,
                      width: selected ? 3 : 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: selected
                      ? Icon(
                          Icons.check,
                          color: hex == '#212121'
                              ? Colors.white
                              : Colors.black87,
                          size: 16,
                        )
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// Bottom Sheet helper for selecting a player position (for Join Session or Owner Position choice).
Future<String?> showPositionPickerSheet(
  BuildContext context, {
  required String layout,
  required List<Map<String, dynamic>> positions,
  Map<String, int>? takenCounts,
  String? selectedPositionId,
  String title = 'เลือกตำแหน่งผู้เล่น',
  String? subtitle,
  FieldStyle fieldStyle = FieldStyle.fallback,
}) async {
  String? currentSelectedId = selectedPositionId;

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setState) {
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (subtitle != null && subtitle.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Pitch View
                        PositionLineupView(
                          layout: layout,
                          positions: positions,
                          takenCounts: takenCounts,
                          selectedPositionId: currentSelectedId,
                          fieldStyle: fieldStyle,
                          onPositionSelected: (posId) {
                            setState(() {
                              currentSelectedId = posId;
                            });
                          },
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'ตำแหน่งที่เปิดรับ',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        // List of positions
                        ...positions.map((pos) {
                          final id = pos['id']?.toString() ?? '';
                          final label = pos['label']?.toString() ?? '';
                          final slots = (pos['slots'] as num?)?.toInt() ?? 1;
                          final taken = takenCounts?[id] ?? 0;
                          final remaining = (slots - taken).clamp(0, slots);
                          final isFull = remaining <= 0;
                          final isSelected = currentSelectedId == id;
                          final color = parseHexColor(pos['color']?.toString());
                          final iconKey = pos['icon']?.toString() ?? 'player';
                          final iconMeta =
                              kPositionIconChoices[iconKey] ??
                              kPositionIconChoices['player']!;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary.withValues(alpha: 0.08)
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primaryDark
                                    : (isFull
                                          ? Colors.grey.shade300
                                          : Colors.grey.shade200),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: ListTile(
                              onTap: isFull
                                  ? null
                                  : () {
                                      setState(() {
                                        currentSelectedId = id;
                                      });
                                    },
                              leading: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: isFull ? Colors.grey : color,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  iconMeta.icon,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                label,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isFull
                                      ? Colors.grey
                                      : AppColors.textPrimary,
                                ),
                              ),
                              subtitle: Text(
                                isFull
                                    ? 'เต็มแล้ว ($taken/$slots)'
                                    : 'เหลือ $remaining จาก $slots คน',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isFull
                                      ? Colors.redAccent
                                      : AppColors.primaryDark,
                                  fontWeight: isFull
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                ),
                              ),
                              trailing: Radio<String>(
                                value: id,
                                groupValue: currentSelectedId,
                                onChanged: isFull
                                    ? null
                                    : (val) {
                                        setState(() {
                                          currentSelectedId = val;
                                        });
                                      },
                                activeColor: AppColors.primaryDark,
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: currentSelectedId == null
                            ? null
                            : () => Navigator.pop(context, currentSelectedId),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryDark,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'ยืนยันการเลือกตำแหน่ง',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
