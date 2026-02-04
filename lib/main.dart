import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/iphone_16_pro_wrapper.dart';
import 'features/home/presentation/pages/home_page.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/auth/presentation/pages/register_page.dart';
import 'features/auth/presentation/pages/register_wizard_page.dart';
import 'features/health/presentation/pages/health_page.dart';
import 'features/articles/presentation/pages/articles_page.dart';
import 'features/admin/presentation/pages/registration_field_admin_page.dart';
import 'services/test_websocket.dart';
// import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // TODO: Uncomment when Supabase is configured
  // Initialize Supabase
  // await SupabaseService.initialize();

  runApp(const SheservedApp());
}

class SheservedApp extends StatelessWidget {
  const SheservedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sheserved',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const HomePage(),
      routes: {
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterWizardPage(),
        '/register-simple': (context) => const RegisterPage(),
        '/health': (context) => const HealthPage(),
        '/articles': (context) => const ArticlesPage(),
        '/test': (context) => const TestWebSocketWidget(),
        '/admin/registration-fields': (context) => const RegistrationFieldAdminPage(),
      },
    );
  }
}
