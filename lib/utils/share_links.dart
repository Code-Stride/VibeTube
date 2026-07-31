/// Builds the links VibeTube shares and understands.
///
/// Sharing used to hand out a plain `https://youtu.be/<id>` URL, which opens
/// YouTube rather than VibeTube. We now share a VibeTube link that resolves
/// straight into the app when it is installed (Android App Links) and falls
/// back to a small landing page when it is not.
class ShareLinks {
  /// Host serving the landing page and `/.well-known/assetlinks.json`.
  ///
  /// To move to a custom domain, change this and [basePath], publish the same
  /// `assetlinks.json` at `https://<host>/.well-known/assetlinks.json`, and
  /// add a matching `<data>` entry to the App Links intent-filter in
  /// AndroidManifest.xml. All three must agree or Android silently stops
  /// verifying the link and it opens in a browser instead.
  static const String host = 'code-stride.github.io';

  /// Path prefix the site is served under. Empty for a bare domain.
  static const String basePath = '/VibeTube';

  /// Custom scheme, accepted on the way in but never shared: messaging apps
  /// render `vibetube://` as plain text rather than a tappable link, and it
  /// dead-ends for anyone without the app installed.
  static const String scheme = 'vibetube';

  /// Shareable watch link, e.g.
  /// `https://code-stride.github.io/VibeTube/w/dQw4w9WgXcQ`.
  static String watch(String videoId) =>
      'https://$host$basePath/w/$videoId';

  /// Deep link using the private scheme — handy for testing with `adb`.
  static String deepLink(String videoId) => '$scheme://watch?v=$videoId';

  /// Text used for the share sheet body.
  static String shareText(String videoId, String title) {
    final link = watch(videoId);
    return title.trim().isEmpty ? link : '$title\n\n$link';
  }

  /// Extracts a video id from a raw link string.
  ///
  /// Prefer this over [parseVideoId] for anything arriving from outside the
  /// app: `Uri.parse` lowercases the authority, so `vibetube://<id>` loses the
  /// id's capitalisation before it can be read.
  static String? parseVideoIdFromString(String raw) {
    final input = raw.trim();
    final prefix = '$scheme://';
    if (input.toLowerCase().startsWith(prefix)) {
      final rest = input.substring(prefix.length);
      // Bare form: vibetube://<id>
      final head = rest.split(RegExp(r'[/?#]')).first;
      if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(head)) return head;
    }
    final uri = Uri.tryParse(input);
    return uri == null ? null : parseVideoId(uri);
  }

  /// Extracts a video id from any link VibeTube accepts: its own watch links,
  /// the `vibetube://` scheme, and YouTube URLs shared from other apps.
  ///
  /// Returns null when the URI isn't recognised or the id is malformed.
  static String? parseVideoId(Uri uri) {
    String? valid(String? id) {
      if (id == null) return null;
      final t = id.trim();
      // YouTube ids are 11 chars of [A-Za-z0-9_-].
      return RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(t) ? t : null;
    }

    // vibetube://watch?v=ID
    if (uri.scheme == scheme) {
      // Only the query form is supported: Uri lowercases the authority while
      // parsing, so `vibetube://<id>` would silently corrupt a case-sensitive
      // video id and there is no way to recover it from the parsed Uri.
      // Use parseVideoIdFromString for raw input.
      return valid(uri.queryParameters['v']) ??
          valid(uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null);
    }

    final h = uri.host.toLowerCase();
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    // Our own link: /VibeTube/w/ID — find the segment after "w".
    if (h == host) {
      final i = segs.indexOf('w');
      if (i != -1 && i + 1 < segs.length) return valid(segs[i + 1]);
      return valid(uri.queryParameters['v']);
    }

    // youtu.be/ID
    if (h == 'youtu.be') {
      return valid(segs.isNotEmpty ? segs.first : null);
    }

    // youtube.com/watch?v=ID, /shorts/ID, /embed/ID, /live/ID
    if (h.endsWith('youtube.com')) {
      final v = valid(uri.queryParameters['v']);
      if (v != null) return v;
      if (segs.length >= 2 &&
          const {'shorts', 'embed', 'live', 'v'}.contains(segs[0])) {
        return valid(segs[1]);
      }
    }
    return null;
  }
}
