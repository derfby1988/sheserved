import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:thai_buddhist_date/thai_buddhist_date.dart';
import 'package:thai_buddhist_date_pickers/thai_buddhist_date_pickers.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/iphone_16_pro_wrapper.dart';
import 'features/home/presentation/pages/home_page.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/auth/presentation/pages/register_page.dart';
import 'features/auth/presentation/pages/register_wizard_page.dart';
import 'features/health/presentation/pages/health_page.dart';
import 'features/health/presentation/pages/health_data_entry_page.dart';
import 'features/articles/presentation/pages/articles_page.dart';
import 'features/admin/presentation/pages/profession_admin_page.dart';
import 'features/admin/presentation/pages/registration_field_admin_page.dart';
import 'features/admin/presentation/pages/application_review_page.dart';
import 'features/admin/models/profession.dart';
import 'features/settings/presentation/pages/sync_settings_page.dart';
import 'services/test_websocket.dart';
import 'services/service_locator.dart';
import 'config/app_config.dart';

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

  // Initialize Supabase first (if configured)
  if (AppConfig.isSupabaseConfigured) {
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );
      debugPrint('Main: Supabase initialized successfully');
    } catch (e) {
      debugPrint('Main: Failed to initialize Supabase - $e');
    }
  } else {
    debugPrint('Main: Supabase not configured (using Local only)');
  }

  // Initialize Services (Local Database + Sync)
  await ServiceLocator.instance.initialize();

  // Initialize Thai Date Service
  await ThaiDateService().initializeLocale('th_TH');

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
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('th', 'TH'),
        Locale('en', 'US'),
      ],
      home: const HomePage(),
      routes: {
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterWizardPage(),
        '/register-simple': (context) => const RegisterPage(),
        '/health': (context) => const HealthPage(),
        '/health-data-entry': (context) => const HealthDataEntryPage(),
        '/articles': (context) => const ArticlesPage(),
        '/test': (context) => const TestWebSocketWidget(),
        '/admin/professions': (context) => const ProfessionAdminPage(),
        '/admin/applications': (context) => const ApplicationReviewPage(),
        '/settings/sync': (context) => const SyncSettingsPage(),
      },
      onGenerateRoute: (settings) {
        // Handle routes with arguments
        if (settings.name == '/admin/registration-fields') {
          final profession = settings.arguments as Profession?;
          return MaterialPageRoute(
            builder: (context) => RegistrationFieldAdminPage(profession: profession),
          );
        }
        return null;
      },
    );
  }
}
