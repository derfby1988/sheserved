# Keep kotlinx-coroutines Main dispatcher
-keep class kotlinx.coroutines.android.** { *; }
-keep class kotlinx.coroutines.android.AndroidDispatcherFactory { *; }
-keep class kotlinx.coroutines.android.AndroidExceptionPreHandler { *; }
-keep class kotlinx.coroutines.android.AndroidLogExceptionPreHandler { *; }
-keep class kotlinx.coroutines.android.AndroidExceptionPreHandlerFactory { *; }

# Keep Flutter plugin registrant
-keep class io.flutter.plugins.** { *; }
-keep class **.GeneratedPluginRegistrant { *; }

# Don't warn about missing classes
-dontwarn kotlinx.coroutines.android.**
