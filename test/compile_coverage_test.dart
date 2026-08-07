// Imports every library under lib/ so `flutter test` type-checks the whole
// app, not just the parts the other tests happen to touch.
//
// Added after an audit found that lib/screens/settings_screen.dart did not
// compile against the Flutter version the pubspec claimed to support: no test
// imported it, so the suite stayed green and only a real `flutter build`
// surfaced the error.
//
// ignore_for_file: unused_import
import 'package:flutter_test/flutter_test.dart';
import 'package:vibetube/api/innertube_client.dart';
import 'package:vibetube/main.dart';
import 'package:vibetube/models/video.dart';
import 'package:vibetube/providers/app_provider.dart';
import 'package:vibetube/providers/mini_player_controller.dart';
import 'package:vibetube/screens/downloads_screen.dart';
import 'package:vibetube/screens/home_screen.dart';
import 'package:vibetube/screens/library_screen.dart';
import 'package:vibetube/screens/player_screen.dart';
import 'package:vibetube/screens/search_screen.dart';
import 'package:vibetube/screens/settings_screen.dart';
import 'package:vibetube/screens/shorts_screen.dart';
import 'package:vibetube/services/audio_helper.dart';
import 'package:vibetube/services/caption_service.dart';
import 'package:vibetube/services/download_service.dart';
import 'package:vibetube/services/hls_parser.dart';
import 'package:vibetube/services/native_player.dart';
import 'package:vibetube/services/storage_service.dart';
import 'package:vibetube/services/update_service.dart';
import 'package:vibetube/utils/share_links.dart';
import 'package:vibetube/utils/theme.dart';
import 'package:vibetube/widgets/caption_overlay.dart';
import 'package:vibetube/widgets/mini_player_bar.dart';
import 'package:vibetube/widgets/update_dialog.dart';
import 'package:vibetube/widgets/video_card.dart';

void main() {
  test('every library under lib/ type-checks', () {
    // Reaching this point means the imports above all compiled.
    expect(true, isTrue);
  });
}
