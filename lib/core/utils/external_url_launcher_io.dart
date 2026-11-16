import 'dart:io';

Future<bool> launchExternalUrl(Uri uri) async {
  try {
    final ProcessResult result;
    if (Platform.isWindows) {
      final edgeCandidates = <String>[
        if (Platform.environment['PROGRAMFILES(X86)'] case final root?)
          '$root\\Microsoft\\Edge\\Application\\msedge.exe',
        if (Platform.environment['PROGRAMFILES'] case final root?)
          '$root\\Microsoft\\Edge\\Application\\msedge.exe',
        if (Platform.environment['LOCALAPPDATA'] case final root?)
          '$root\\Microsoft\\Edge\\Application\\msedge.exe',
      ];
      final edge = edgeCandidates
          .where((path) => File(path).existsSync())
          .firstOrNull;
      if (edge != null) {
        result = await Process.run(edge, ['--inprivate', uri.toString()]);
      } else {
        result = await Process.run('rundll32', [
          'url.dll,FileProtocolHandler',
          uri.toString(),
        ]);
      }
    } else if (Platform.isMacOS) {
      result = await Process.run('open', [uri.toString()]);
    } else {
      result = await Process.run('xdg-open', [uri.toString()]);
    }
    return result.exitCode == 0;
  } on Object {
    return false;
  }
}
