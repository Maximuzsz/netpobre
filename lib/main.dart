import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/services/download_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await DownloadManager.instance.initialize();
  } catch (error, stackTrace) {
    debugPrint('Falha ao iniciar os downloads: $error\n$stackTrace');
  }
  runApp(const CasaFlixApp());
}
