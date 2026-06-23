import 'package:flutter/material.dart';
import '../../services/auth_service.dart';

/// Route Logger Observer
/// ─────────────────────────────────────────────────────────────
/// Phase 7 — Route Security Implementation Plan (Backlog)
///
/// Logs route access for security monitoring and analytics.
/// Tracks who accessed which route and when, which is useful for:
/// - Security audit trails
/// - Detecting unauthorized access attempts
/// - Usage analytics
/// - Debugging navigation issues
///
/// Usage: Add to MaterialApp.navigatorObservers
class RouteLoggerObserver extends NavigatorObserver {
  /// Set of sensitive routes that should always be logged
  static const Set<String> _sensitiveRoutes = {
    '/admin/professions',
    '/admin/user-categories',
    '/admin/system-monitor',
    '/admin/applications',
    '/admin/registration-fields',
    '/admin/body-regions',
    '/admin/packages',
    '/admin/platform-settings',
    '/admin/video-management',
    '/admin/watermark-management',
    '/erp',
    '/erp/dashboard',
    '/erp/inventory',
    '/erp/pos/counter',
    '/erp/pos/clinic',
    '/health-program-requests',
    '/provider-history',
    '/emergency-live',
  };

  void _log(String action, Route<dynamic> route, Route<dynamic>? previousRoute) {
    final routeName = route.settings.name ?? 'unknown';
    final previousRouteName = previousRoute?.settings.name;
    final user = AuthService.instance.currentUser;
    final userId = user?.id ?? 'anonymous';
    final role = user?.role ?? 'none';

    // Always log sensitive routes; log others in debug mode only
    final isSensitive = _sensitiveRoutes.contains(routeName) ||
        routeName.startsWith('/admin/') ||
        routeName.startsWith('/erp/');

    if (isSensitive) {
      debugPrint(
        '[RouteSecurity] $action: user=$userId role=$role route=$routeName'
        '${previousRouteName != null ? ' from=$previousRouteName' : ''}',
      );
    } else {
      // Non-sensitive routes only logged in debug mode to avoid noise
      assert(() {
        debugPrint(
          '[RouteLogger] $action: user=$userId route=$routeName'
          '${previousRouteName != null ? ' from=$previousRouteName' : ''}',
        );
        return true;
      }());
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _log('PUSH', route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _log('POP', route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _log('REMOVE', route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) {
      _log('REPLACE', newRoute, oldRoute);
    }
  }
}
