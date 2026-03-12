import 'package:flutter/material.dart';

class ControlBackButtonWidget extends StatelessWidget {
  const ControlBackButtonWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            padding: const EdgeInsets.all(4),
            child: const Icon(Icons.subdirectory_arrow_left_rounded, 
              color: Color(0xFF84CC16), // Lime green from mockup
              size: 30
            ),
          ),
        ),
      ),
    );
  }
}
