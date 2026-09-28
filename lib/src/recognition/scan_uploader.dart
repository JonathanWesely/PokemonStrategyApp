/// Fire-and-forget mirror of the scan-diagnostics folders to Supabase
/// Storage, so a bad scan can be inspected remotely (by Claude, in a
/// Cowork session) without pulling files off the phone by hand. Runs
/// only right after a diagnostics writer produced a dump, so it is
/// gated by the same Settings toggle as the local folders.
///
/// Server side: project `sebxviekcrnnhifdmfdl`, public bucket `scans`.
/// The key below is the publishable (anon) key — safe to ship — and the
/// bucket's RLS restricts anon writes to `last_scan/%` and
/// `last_team_scan/%`, so it can only ever overwrite the diagnostic
/// files themselves. Each upload overwrites the previous scan's copy,
/// mirroring the local folders.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

class ScanUploader {
  static const _url = 'https://sebxviekcrnnhifdmfdl.supabase.co';
  static const _key = 'sb_publishable_xbhCn92UFrDg643-YDdn5A_JXvWlgIz';

  /// Upload every regular file in [dir] to `scans/<remoteFolder>/<name>`.
  /// Errors are logged and swallowed — diagnostics must never break or
  /// slow a scan, and offline just means this dump stays local.
  static Future<void> uploadDir(Directory dir, String remoteFolder) async {
    try {
      final files = dir.listSync().whereType<File>().toList();
      var sent = 0;
      for (final f in files) {
        final name = f.uri.pathSegments.last;
        final r = await http
            .post(
              Uri.parse('$_url/storage/v1/object/scans/$remoteFolder/$name'),
              headers: {
                'apikey': _key,
                'Authorization': 'Bearer $_key',
                'x-upsert': 'true',
                'Content-Type': _mime(name),
              },
              body: await f.readAsBytes(),
            )
            .timeout(const Duration(seconds: 30));
        if (r.statusCode >= 300) {
          debugPrint('scan upload $remoteFolder/$name -> '
              'HTTP ${r.statusCode} ${r.body}');
        } else {
          sent++;
        }
      }
      debugPrint('scan diagnostics uploaded: '
          '$remoteFolder ($sent/${files.length} files)');
    } catch (e) {
      debugPrint('scan upload failed ($remoteFolder): $e');
    }
  }

  static String _mime(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.png')) return 'image/png';
    return 'text/plain';
  }
}
