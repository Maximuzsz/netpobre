import 'dart:io';

import 'package:flutter/material.dart';

import '../services/app_updater.dart';
import '../theme.dart';

class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AppUpdateDialog(),
    );
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  final _updater = AppUpdater();
  AppUpdateInfo? _update;
  File? _apk;
  String? _error;
  String _message = 'Procurando uma versão mais recente…';
  double? _progress;
  bool _checking = true;
  bool _downloading = false;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _updater.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
      _message = 'Procurando uma versão mais recente…';
    });
    try {
      final update = await _updater.check();
      if (!mounted) return;
      setState(() {
        _update = update;
        _checking = false;
        _message = update.updateAvailable
            ? 'NetPobre ${update.latestVersion} está disponível.'
            : 'Você já está usando a versão mais recente (${update.currentVersion}).';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _download() async {
    final update = _update;
    if (update == null) return;
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
      _message = 'Baixando NetPobre ${update.latestVersion}…';
    });
    try {
      final apk = await _updater.download(
        update,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _progress = total > 0 ? received / total : null;
            _message = total > 0
                ? 'Baixando… ${(received / total * 100).round()}%'
                : 'Baixando atualização…';
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _apk = apk;
        _downloading = false;
        _progress = 1;
        _message = 'Download verificado. Pronto para instalar.';
      });
      await _install();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _progress = null;
        _error = error.toString();
      });
    }
  }

  Future<void> _install() async {
    final apk = _apk;
    if (apk == null) return;
    setState(() {
      _installing = true;
      _error = null;
      _message = 'Abrindo o instalador do Android…';
    });
    try {
      final result = await _updater.install(apk);
      if (!mounted) return;
      setState(() {
        _installing = false;
        _message = result == 'permissionRequested'
            ? 'Autorize o NetPobre a instalar atualizações. Ao voltar, o instalador abrirá automaticamente.'
            : 'Confirme a atualização na tela do Android.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final updateAvailable = _update?.updateAvailable ?? false;
    return AlertDialog(
      backgroundColor: CasaFlixColors.deepSea,
      icon: const Icon(
        Icons.system_update_alt_rounded,
        color: CasaFlixColors.sky,
        size: 38,
      ),
      title: const Text('Atualizar NetPobre'),
      content: SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_checking) const LinearProgressIndicator(),
            if (_progress != null && !_checking)
              LinearProgressIndicator(value: _progress),
            const SizedBox(height: 18),
            Text(_error ?? _message, textAlign: TextAlign.center),
            if (_error != null) ...[
              const SizedBox(height: 10),
              const Text(
                'Confira a internet e tente novamente.',
                style: TextStyle(color: CasaFlixColors.muted),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _downloading || _installing
              ? null
              : () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
        if (_error != null)
          FilledButton(
            onPressed: _check,
            child: const Text('Tentar novamente'),
          ),
        if (updateAvailable && !_downloading && _apk == null && _error == null)
          FilledButton.icon(
            autofocus: true,
            onPressed: _download,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Baixar atualização'),
          ),
        if (_apk != null && !_installing)
          FilledButton.icon(
            autofocus: true,
            onPressed: _install,
            icon: const Icon(Icons.install_mobile_rounded),
            label: const Text('Instalar agora'),
          ),
      ],
    );
  }
}
