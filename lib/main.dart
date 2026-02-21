import 'package:flutter/gestures.dart';
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
import 'features/health/presentation/pages/health_article_page.dart';
import 'features/health/data/models/health_article_models.dart';
import 'features/articles/presentation/pages/articles_page.dart';
import 'features/admin/presentation/pages/profession_admin_page.dart';
import 'features/admin/presentation/pages/registration_field_admin_page.dart';
import 'features/admin/presentation/pages/application_review_page.dart';
import 'features/admin/models/profession.dart';
import 'features/settings/presentation/pages/sync_settings_page.dart';
import 'services/test_websocket.dart';
import 'features/chat/presentation/pages/chat_list_page.dart';
import 'features/chat/presentation/pages/chat_room_page.dart';
import 'features/chat/presentation/pages/contact_list_page.dart';
import 'features/chat/presentation/pages/live_vdo_page.dart';
import 'services/service_locator.dart';
import 'config/app_config.dart';
import 'services/supabase_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'features/chat/data/models/chat_models.dart';

// เพิ่ม ScrollBehavior เพื่อรองรับ Mouse Dragging ในหน้า Web
class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

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

  // Initialize Supabase Service
  await SupabaseService.initialize();

  // Initialize Hive
  await Hive.initFlutter();
  Hive.registerAdapter(ChatRoomAdapter());
  Hive.registerAdapter(MessageStatusAdapter());
  Hive.registerAdapter(ChatMessageAdapter());
  Hive.registerAdapter(ChatParticipantAdapter());
  
  // Open Boxes
  await Hive.openBox<ChatRoom>('chat_rooms');
  await Hive.openBox<ChatMessage>('chat_messages');
  await Hive.openBox<ChatParticipant>('chat_participants');

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
      scrollBehavior: AppScrollBehavior(),
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
        '/test': (context) => const TestWebSocketWidget(),

        '/admin/professions': (context) => const ProfessionAdminPage(),
        '/admin/applications': (context) => const ApplicationReviewPage(),
        '/settings/sync': (context) => const SyncSettingsPage(),
        '/chat-list': (context) => const ChatListPage(),
        '/chat-contacts': (context) => const ContactListPage(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/chat-room') {
          final roomId = settings.arguments as String;
          return MaterialPageRoute(
            builder: (context) => ChatRoomPage(roomId: roomId),
          );
        }

        if (settings.name == '/live-vdo') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (context) => LiveVdoPage(
              roomId: args['roomId'],
              isCaller: args['isCaller'],
              otherParticipantName: args['otherParticipantName'],
            ),
          );
        }

        // Handle routes with arguments
        if (settings.name == '/health/article') {
          final args = settings.arguments;
          if (args is HealthArticle) {
            return MaterialPageRoute(
              builder: (context) => HealthArticlePage(article: args),
            );
          } else if (args is Map<String, dynamic>) {
            return MaterialPageRoute(
              builder: (context) => HealthArticlePage(
                article: args['article'] as HealthArticle?,
                targetPage: args['targetPage'] as int?,
                targetCommentId: args['targetCommentId'] as String?,
                pendingAction: args['pendingAction'] as String?,
                pendingCommentId: args['pendingCommentId'] as String?,
                openBookmarks: args['openBookmarks'] as bool? ?? false,
              ),
            );
          }
          return MaterialPageRoute(
            builder: (context) => const HealthArticlePage(),
          );
        }
        
        if (settings.name == '/admin/registration-fields') {
          final profession = settings.arguments as Profession?;
          return MaterialPageRoute(
            builder: (context) => RegistrationFieldAdminPage(profession: profession),
          );
        }

        if (settings.name == '/articles') {
          final initialFilter = settings.arguments as String?;
          return MaterialPageRoute(
            builder: (context) => ArticlesPage(initialFilter: initialFilter),
          );
        }

        return null;
      },
    );
  }
}
