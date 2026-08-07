import 'package:permission_handler/permission_handler.dart';

/// Requests the Android 13+ notification permission.
///
/// Deliberately *not* called from main(): asking before the first frame put a
/// bare system dialog on top of the splash screen with no explanation, on
/// every cold start until granted. It now runs the first time playback
/// actually needs a media notification, which is both better UX and what
/// Play's in-context permission guidance asks for.
Future<void> ensureNotificationPermission() async {
  try {
    final status = await Permission.notification.status;
    if (!status.isGranted && !status.isPermanentlyDenied) {
      await Permission.notification.request();
    }
  } catch (_) {}
}
