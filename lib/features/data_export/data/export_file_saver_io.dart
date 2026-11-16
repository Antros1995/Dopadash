import 'dart:io';
import 'dart:typed_data';

Future<String> saveExportFile(Uint8List bytes, String fileName) async {
  final profile = Platform.environment['USERPROFILE'];
  final base = profile == null || profile.isEmpty
      ? Directory.current
      : Directory('$profile${Platform.pathSeparator}Downloads');
  if (!await base.exists()) await base.create(recursive: true);
  final file = File('${base.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
