import 'package:flutter/material.dart';

class RelationshipViewWidget extends StatelessWidget {
  const RelationshipViewWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_alt_outlined, size: 80, color: Colors.purple[200]),
          const SizedBox(height: 16),
          Text(
            'ความสัมพันธ์ในพื้นที่',
            style: TextStyle(
              fontFamily: 'SukhumvitSet',
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.purple[900],
            ),
          ),
          const SizedBox(height: 8),
          const Text('ข้อมูลอาสาสมัครและเครือข่ายความช่วยเหลือ'),
        ],
      ),
    );
  }
}
