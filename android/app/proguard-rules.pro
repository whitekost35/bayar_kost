# Flutter Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.runtime.** { *; }

# Workmanager Rules
-keep class dev.fluttercommunity.workmanager.** { *; }

# Flutter Local Notifications Rules
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# App Links Rules
-keep class com.llfbandit.app_links.** { *; }

# Shared Preferences Rules
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Url Launcher Rules
-keep class io.flutter.plugins.urllauncher.** { *; }

# Supabase / App Links might need this
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }

# Ignore Play Core missing classes
-dontwarn com.google.android.play.core.**
