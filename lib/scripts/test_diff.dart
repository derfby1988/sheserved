import 'package:diff_match_patch/diff_match_patch.dart';
void main() {
  final diffs = diff('ฉันกินข้าวที่บ้าน', 'ฉันเรียนหนังสือที่โรงเรียน');
  cleanupSemantic(diffs);
  for (var diff in diffs) {
    print('${diff.operation}: ${diff.text}');
  }
}
