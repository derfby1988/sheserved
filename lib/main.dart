import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:thai_buddhist_date/thai_buddhist_date.dart';
import 'package:thai_buddhist_date_pickers/thai_buddhist_date_pickers.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/guards/auth_guard_widget.dart';
import 'core/observers/route_logger_observer.dart';
import 'core/pages/not_found_page.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/iphone_16_pro_wrapper.dart';
import 'core/layout/main_app_layout.dart';
import 'package:sheserved/features/admin/presentation/pages/video_admin_page.dart';
import 'package:sheserved/features/admin/presentation/pages/watermark_management_page.dart';
import 'package:sheserved/features/auth/presentation/pages/login_page.dart';
import 'features/auth/presentation/pages/register_page.dart';
import 'features/auth/presentation/pages/register_wizard_page.dart';
import 'features/health/presentation/pages/health_page.dart';
import 'features/health/presentation/pages/health_data_entry_page.dart';
import 'features/consultation/presentation/pages/health_program_request_dashboard.dart'
    show dashboardRouteObserver;
import 'features/health/presentation/pages/health_article_page.dart';
import 'features/health/data/models/health_article_models.dart';
import 'features/articles/presentation/pages/articles_page.dart';
import 'features/admin/presentation/pages/profession_admin_page.dart';
import 'features/admin/presentation/pages/registration_field_admin_page.dart';
import 'features/admin/presentation/pages/body_region_admin_page.dart';
import 'features/admin/presentation/pages/package_admin_page.dart';
import 'features/admin/presentation/pages/application_review_page.dart';
import 'features/admin/presentation/pages/user_category_admin_page.dart';
import 'features/admin/presentation/pages/system_monitor_page.dart';
import 'features/pharmacy/presentation/pages/pharmacy_filters_admin_page.dart';
import 'features/admin/models/profession.dart';
import 'features/settings/presentation/pages/sync_settings_page.dart';
import 'services/test_websocket.dart';
import 'features/chat/presentation/pages/chat_list_page.dart';
import 'features/chat/presentation/pages/contact_list_page.dart';
import 'features/chat/presentation/pages/chat_room_page.dart';
import 'features/chat/presentation/pages/live_vdo_page.dart';
import 'features/consultation/presentation/pages/package_healthcare_page.dart';
import 'features/consultation/presentation/pages/analyze_body_area_page.dart';
import 'features/consultation/presentation/pages/chart_board_page.dart';
import 'features/consultation/presentation/pages/vega_ai_chat_page.dart';
import 'features/consultation/presentation/pages/health_program_request_dashboard.dart';
import 'features/consultation/data/models/consultation_request_model.dart';
import 'features/consultation/data/models/consultation_entry.dart';
import 'features/donation/presentation/pages/donation_dashboard_page.dart';
import 'features/donation/presentation/pages/donation_admin_page.dart';
import 'services/service_locator.dart';
import 'config/app_config.dart';
import 'config/sync_config.dart';
import 'services/supabase_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'features/chat/data/models/chat_models.dart';
import 'features/profile/presentation/pages/profile_page.dart';
import 'features/video/presentation/pages/emergency_live_page.dart';
import 'features/video/presentation/pages/rescue_page.dart';
import 'features/admin/presentation/pages/video_admin_page.dart';
import 'features/consultation/presentation/pages/my_consultations_page.dart';
import 'features/consultation/presentation/pages/provider_history_page.dart';
import 'features/consultation/presentation/pages/consultation_chat_history_page.dart';
import 'features/admin/presentation/pages/platform_settings_page.dart';
import 'features/kpi/presentation/pages/kpi_dashboard_page.dart';
import 'features/kpi/presentation/pages/kpi_target_form_page.dart';
import 'features/kpi/presentation/pages/kpi_refresh_history_page.dart';
import 'ERP Dashboard/erp_dashboard_shell.dart';
import 'ERP Dashboard/erp_dashboard_page.dart';
import 'ERP Dashboard/organization_settings_page.dart';
import 'features/erp/presentation/pages/theme_settings_page.dart';
import 'features/erp/presentation/pages/module_layout_settings_page.dart';
import 'features/erp/presentation/pages/glassmorphism_settings_page.dart';
import 'features/erp/presentation/pages/role_management_page.dart';
import 'features/erp/presentation/pages/permission_management_page.dart';
import 'features/erp/presentation/pages/feature_flags_page.dart';
import 'features/erp/presentation/pages/product_list_page.dart';
import 'features/erp/presentation/pages/customer_list_page.dart';
import 'features/erp/presentation/pages/inventory_page.dart';
import 'features/erp/presentation/pages/inventory_dashboard_page.dart';
import 'features/erp/presentation/pages/stock_transfer_page.dart';
import 'features/erp/presentation/pages/stock_adjustment_page.dart';
import 'features/erp/presentation/pages/stock_movement_tracking_page.dart';
import 'features/erp/presentation/pages/stocktake_config_page.dart';
import 'features/erp/presentation/pages/goods_receipt_page.dart';
import 'features/erp/presentation/pages/procurement_page.dart';
import 'features/erp/presentation/pages/cart_page.dart';
import 'features/erp/presentation/pages/checkout_page.dart';
import 'features/erp/presentation/pages/delivery_orders_page.dart';
import 'features/erp/presentation/pages/vendor_contracts_page.dart';
import 'features/erp/presentation/pages/payment_channels_page.dart';
import 'features/erp/presentation/pages/counter_pos_page.dart';
import 'features/erp/presentation/pages/clinic_pos_page.dart';
import 'features/erp/presentation/pages/order_success_page.dart';
import 'features/erp/presentation/pages/employee_list_page.dart';
import 'features/erp/presentation/pages/gl_entries_page.dart';
import 'features/erp/presentation/pages/dashboard_analytics_page.dart';
import 'features/erp/presentation/pages/chart_of_accounts_page.dart';
import 'features/erp/presentation/pages/accounts_receivable_page.dart';
import 'features/erp/presentation/pages/accounts_payable_page.dart';
import 'features/erp/presentation/pages/shift_management_page.dart';
import 'features/erp/presentation/pages/emr_list_page.dart';
import 'features/erp/presentation/pages/opd_visit_page.dart';
import 'features/erp/presentation/pages/prescription_page.dart';
import 'features/erp/presentation/pages/lab_results_page.dart';
import 'features/erp/presentation/pages/patient_cohort_page.dart';
import 'features/erp/presentation/pages/refund_list_page.dart';
import 'features/erp/presentation/pages/loyalty_rules_page.dart';
import 'features/erp/presentation/pages/report_export_page.dart';

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

  // Load app settings from Supabase
  await SyncConfig.loadFromSupabase();

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

  runApp(
    const ProviderScope(
      child: SheservedApp(),
    ),
  );
}

class SheservedApp extends StatelessWidget {
  const SheservedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sheserved',
      debugShowCheckedModeBanner: false,
      showPerformanceOverlay: false,
      scrollBehavior: AppScrollBehavior(),
      navigatorObservers: [
        dashboardRouteObserver,
        RouteLoggerObserver(),
      ],
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
      home: const MainAppLayout(),
      routes: {
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterWizardPage(),
        '/register-simple': (context) => const RegisterPage(),
        '/health': (context) => const HealthPage(),
        '/health-data-entry': (context) => const HealthDataEntryPage(),
        '/package-healthcare': (context) => const PackageHealthCarePage(),
        '/test': (context) => const TestWebSocketWidget(),
        '/home': (context) => const MainAppLayout(),

        '/admin/professions': (context) => const AuthGuardWidget(requiredRole: 'admin', child: ProfessionAdminPage()),
        '/admin/applications': (context) => const AuthGuardWidget(requiredRole: 'admin', child: ApplicationReviewPage()),
        '/admin/body_regions': (context) => const AuthGuardWidget(requiredRole: 'admin', child: BodyRegionAdminPage()),
        '/settings/sync': (context) => const SyncSettingsPage(),
        '/chat-list': (context) => const ChatListPage(),
        '/chat-contacts': (context) => ContactListPage(),
        '/health-program-requests': (context) => const AuthGuardWidget(requiredRole: 'provider', child: HealthProgramRequestDashboard()),
        '/admin/packages': (context) => const AuthGuardWidget(requiredRole: 'admin', child: PackageAdminPage()),
        '/admin/user-categories': (context) => const AuthGuardWidget(requiredRole: 'admin', child: UserCategoryAdminPage()),
        '/admin/system-monitor': (context) => const AuthGuardWidget(requiredRole: 'admin', child: SystemMonitorPage()),
        '/donate': (context) => const DonationDashboardPage(),
        '/admin/donations': (context) => const AuthGuardWidget(requiredRole: 'admin', child: DonationAdminPage()),
        '/admin/pharmacy_filters': (context) => const AuthGuardWidget(requiredRole: 'admin', child: PharmacyFiltersAdminPage()),
        '/admin/video-control': (context) => const AuthGuardWidget(requiredRole: 'admin', child: VideoAdminPage()),
        '/admin/watermark': (context) => const AuthGuardWidget(requiredRole: 'admin', child: WatermarkManagementPage()),
        '/admin/platform-settings': (context) => const AuthGuardWidget(requiredRole: 'admin', child: PlatformSettingsPage()),
        
        '/profile': (context) => const ProfilePage(),
        '/emergency-live': (context) => const EmergencyLivePage(),
        '/rescue-map': (context) => const RescuePage(),
        '/my-consultations': (context) => const MyConsultationsPage(),
        '/provider-history': (context) => const AuthGuardWidget(requiredRole: 'provider', child: ProviderHistoryPage()),
        '/kpi/dashboard': (context) => const KpiDashboardPage(),
        '/kpi/target/form': (context) => const KpiTargetFormPage(),
        '/kpi/refresh/history': (context) => const KpiRefreshHistoryPage(),
      },
      onGenerateRoute: (settings) {
        // ERP Shell Routes (Drawer + AppBar + Branch Selector)
        if (settings.name == '/erp' || settings.name == '/erp/dashboard') {
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => const ErpDashboardShell(child: ErpDashboardPage()),
          );
        }
        if (settings.name == '/erp/settings' || settings.name == '/organizationSettings') {
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => const ErpDashboardShell(child: OrganizationSettingsPage()),
          );
        }
        if (settings.name == '/erp/settings/theme') {
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => const ErpDashboardShell(child: ThemeSettingsPage()),
          );
        }
        if (settings.name == '/erp/settings/modules') {
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => const ErpDashboardShell(child: ModuleLayoutSettingsPage()),
          );
        }
        if (settings.name == '/erp/settings/glass') {
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => const ErpDashboardShell(child: GlassmorphismSettingsPage()),
          );
        }
        if (settings.name == '/erp/roles') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: RoleManagementPage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/feature-flags') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: FeatureFlagsPage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/products') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: ProductListPage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/customers') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: CustomerListPage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/inventory') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: InventoryPage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/inventory/dashboard') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: InventoryDashboardPage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/inventory/transfer') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: StockTransferPage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/inventory/adjustment') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: StockAdjustmentPage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/inventory/movements') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: StockMovementTrackingPage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/inventory/stocktake-config') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: StocktakeConfigPage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/inventory/receipt') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: GoodsReceiptPage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/suppliers') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: ProcurementPage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/cart') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: CartPage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/checkout') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          final sessionId = args?['sessionId'] as String?;
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: CheckoutPage(professionId: professionId, sessionId: sessionId)),
          );
        }
        if (settings.name == '/erp/delivery') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: DeliveryOrdersPage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/vendor-contracts') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: VendorContractsPage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/payment-channels') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: PaymentChannelsPage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/pos/counter') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: CounterPosPage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/pos/clinic') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: ClinicPosPage(professionId: professionId)),
          );
        }
        if (settings.name == '/order/success') {
          final args = settings.arguments as Map<String, dynamic>?;
          final orderId = args?['orderId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => OrderSuccessPage(orderId: orderId),
          );
        }
        if (settings.name == '/erp/employees') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: EmployeeListPage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/gl-entries') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: GlEntriesPage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/analytics') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: DashboardAnalyticsPage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/chart-of-accounts') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: ChartOfAccountsPage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/accounts-receivable') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: AccountsReceivablePage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/accounts-payable') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: AccountsPayablePage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/shifts') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: ShiftManagementPage(professionId: professionId)),
          );
        }
        if (settings.name == '/clinical/emr') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: EmrListPage(professionId: professionId)),
          );
        }
        if (settings.name == '/clinical/opd') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: OpdVisitPage(professionId: professionId)),
          );
        }
        if (settings.name == '/clinical/prescriptions') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: PrescriptionPage(professionId: professionId)),
          );
        }
        if (settings.name == '/clinical/lab') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: LabResultsPage(professionId: professionId)),
          );
        }
        if (settings.name == '/clinical/cohorts') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: PatientCohortPage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/refunds') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: RefundListPage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/loyalty') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: LoyaltyRulesPage(professionId: professionId)),
          );
        }
        if (settings.name == '/erp/reports') {
          final args = settings.arguments as Map<String, dynamic>?;
          final professionId = args?['professionId'] as String? ?? '';
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => ErpDashboardShell(child: ReportExportPage(professionId: professionId)),
          );
        }

        if (settings.name == '/main-app') {
          final args = settings.arguments as Map<String, dynamic>?;
          final int initialIndex = args?['index'] ?? 0;
          return MaterialPageRoute(
            builder: (context) => MainAppLayout(initialIndex: initialIndex),
          );
        }

        if (settings.name == '/chat-room') {
          final roomId = settings.arguments as String;
          return MaterialPageRoute(
            builder: (context) => ChatRoomPage(roomId: roomId),
          );
        }

        if (settings.name == '/consultation-history-chat') {
          final consultationId = settings.arguments as String;
          return MaterialPageRoute(
            builder: (context) => ConsultationChatHistoryPage(consultationId: consultationId),
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

        if (settings.name == '/analyze-body') {
          final request = settings.arguments as ConsultationRequestModel;
          return MaterialPageRoute(
            builder: (context) => AnalyzeBodyAreaPage(request: request),
          );
        }

        if (settings.name == '/vega-ai-chat') {
          final request = settings.arguments as ConsultationRequestModel;
          return MaterialPageRoute(
            builder: (context) => VegaAiChatPage(request: request),
          );
        }

        if (settings.name == '/chart-board') {
          final args = settings.arguments;
          bool readOnly = false;
          bool hasFinished = false;
          ConsultationEntry? entry;
          ConsultationRequestModel? request;

          if (args is Map<String, dynamic>) {
            entry = args['entry'] as ConsultationEntry?;
            request = args['request'] as ConsultationRequestModel?;
            readOnly = args['readOnly'] as bool? ?? false;
            hasFinished = args['hasFinished'] as bool? ?? false;
          } else if (args is ConsultationRequestModel) {
            request = args;
          } else if (args is ConsultationEntry) {
            entry = args;
          }

          if (request != null || entry != null) {
            return MaterialPageRoute(
              builder: (context) => ChartBoardPage(
                request: request,
                entry: entry,
                readOnly: readOnly,
                hasFinished: hasFinished,
              ),
            );
          }
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
            builder: (context) => AuthGuardWidget(
              requiredRole: 'admin',
              child: RegistrationFieldAdminPage(profession: profession),
            ),
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
      onUnknownRoute: (settings) {
        debugPrint('Security: Unknown route accessed: ${settings.name}');
        return MaterialPageRoute(
          builder: (context) => NotFoundPage(route: settings.name ?? 'unknown'),
        );
      },
    );
  }
}
