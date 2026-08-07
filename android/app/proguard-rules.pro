# VibeTube R8 / ProGuard rules
#
# The Flutter Gradle plugin already contributes its own rules for the embedding
# and for the Dart VM entry points, and AndroidX / Media3 ship consumer rules
# inside their AARs. What follows covers the pieces R8 cannot see:
# reflection-reached platform classes and our own MethodChannel surface.

# ---- Flutter embedding -------------------------------------------------------
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# ---- Our platform channel surface -------------------------------------------
# MainActivity is instantiated by the system from the manifest and
# PlaybackService is started via Intent, so both must survive by name.
-keep class com.blazenxt.vibetube.MainActivity { *; }
-keep class com.blazenxt.vibetube.PlaybackService { *; }
-keep class com.blazenxt.vibetube.** { *; }

# ---- Media / playback --------------------------------------------------------
# MediaSession callbacks and ExoPlayer's renderer/extractor discovery are
# reflective; losing them shows up only at runtime as "no suitable renderer".
-keep class android.media.session.** { *; }
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# ---- Plugins that use reflection --------------------------------------------
-keep class com.baseflow.permissionhandler.** { *; }
-keep class dev.fluttercommunity.plus.share.** { *; }
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }

# ---- Kotlin metadata / coroutines -------------------------------------------
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.coroutines.**

# ---- Keep annotations & signatures needed for generics/serialization --------
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Keep line numbers so release crash reports stay readable, but hide the
# original file name.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
