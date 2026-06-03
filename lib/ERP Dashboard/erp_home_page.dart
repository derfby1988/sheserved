import 'package:flutter/material.dart';

/// New ERP Home Page (renamed to avoid conflict with existing HomePage).
class ErpHomePage extends StatelessWidget {
  const ErpHomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Reuse HomeErpCard widget defined elsewhere.
    return const HomeErpCard();
  }
}
