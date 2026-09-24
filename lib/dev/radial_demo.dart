import 'package:flutter/material.dart';

import '../features/consultation/presentation/widgets/radial_question_view.dart';

void main() {
  runApp(const RadialDemoApp());
}

class RadialDemoApp extends StatelessWidget {
  const RadialDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RadialDemoPage(),
    );
  }
}

class _DemoCase {
  final String title;
  final String question;
  final ClosedEndedConfig config;

  const _DemoCase(this.title, this.question, this.config);
}

class RadialDemoPage extends StatefulWidget {
  const RadialDemoPage({super.key});

  @override
  State<RadialDemoPage> createState() => _RadialDemoPageState();
}

class _RadialDemoPageState extends State<RadialDemoPage> {
  static final _cases = <_DemoCase>[
    _DemoCase(
      'ปวด 5 ระดับ',
      'ปวดแค่ไหน?',
      ClosedEndedConfig.quantitative(5),
    ),
    _DemoCase(
      'ปวด 3 ระดับ',
      'เจ็บไหม?',
      ClosedEndedConfig.quantitative(3),
    ),
    _DemoCase(
      'ปวด 10 ระดับ',
      'ระดับความปวด',
      ClosedEndedConfig.quantitative(10),
    ),
    _DemoCase(
      'อาการ 4 ตัวเลือก',
      'อาการหลัก',
      ClosedEndedConfig.qualitative([
        'ปวดหัว',
        'คลื่นไส้',
        'เวียนหัว',
        'ไม่ระบุปัญหา',
      ]),
    ),
  ];

  int _caseIndex = 0;

  @override
  Widget build(BuildContext context) {
    final demo = _cases[_caseIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: RadialQuestionView(
              key: ValueKey(_caseIndex),
              questionText: demo.question,
              config: demo.config,
              expertName: 'นพ. ตัวอย่าง ทดสอบ',
              showBackground: true,
            ),
          ),
          Positioned(
            left: 16,
            bottom: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _cases.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ElevatedButton(
                      key: ValueKey('demo-tab-$i'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: i == _caseIndex
                            ? Colors.white.withValues(alpha: 0.35)
                            : Colors.white.withValues(alpha: 0.12),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                      ),
                      onPressed: () => setState(() => _caseIndex = i),
                      child: Text(
                        _cases[i].title,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
