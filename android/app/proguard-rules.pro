# VibeTube ProGuard / R8 rules
#
# minifyEnabled + shrinkResources are on for release builds. Everything the
# platform reaches by reflection or by manifest name must be kept explicitly,
# otherwise R8 removes it and the app fails only at runtime.

# --- Flutter embedding ---
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# --- Our own entry points, instantiated by the framework via the manifest ---
-keep class com.blazenxt.vibetube.MainActivity { *; }
-keep class com.blazenxt.vibetube.PlaybackService { *; }

# MediaSession callbacks and the PiP broadcast receiver are resolved
# reflectively / by intent, so keep their members.
-keepclassmembers class com.blazenxt.vibetube.** {
    public *;
}

# --- Platform media classes referenced from the service ---
-keep class android.media.session.** { *; }
-keep class android.support.v4.media.** { *; }

# Kotlin metadata is used by the reflection in some plugins.
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**

# Plugins used by this app that are known to need reflection.
-keep class androidx.lifecycle.** { *; }
-dontwarn androidx.**

# Keep annotations (used by several plugins for codegen lookups).
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Do not strip line numbers - crash reports from release APKs stay readable.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
