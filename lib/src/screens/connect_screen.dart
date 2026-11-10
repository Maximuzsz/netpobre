import 'package:flutter/material.dart';

import '../models/jellyfin_session.dart';
import '../services/jellyfin_api.dart';
import '../theme.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({
    super.key,
    required this.api,
    required this.onConnected,
  });

  final JellyfinApi api;
  final ValueChanged<JellyfinSession> onConnected;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _server = TextEditingController(text: JellyfinApi.publicBaseUrl);
  final _user = TextEditingController(text: 'netpobre');
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _message;
  String? _quickCode;
  bool _cancelQuickConnect = false;

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _discover() async {
    setState(() {
      _busy = true;
      _message = 'Procurando pela internet e na rede de casa…';
    });
    try {
      final url = await widget.api.discover();
      if (!mounted) return;
      _server.text = url;
      setState(() => _message = 'Servidor encontrado.');
    } on JellyfinException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = 'Entrando no Jellyfin Casa…';
    });
    try {
      final session = await widget.api.authenticate(
        baseUrl: _server.text,
        username: _user.text,
        password: _password.text,
      );
      widget.onConnected(session);
    } on JellyfinException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Não foi possível conectar. Verifique sua internet e tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _quickConnect() async {
    setState(() {
      _busy = true;
      _cancelQuickConnect = false;
      _quickCode = null;
      _message = 'Preparando o código de acesso…';
    });
    try {
      final baseUrl = _server.text.trim().isEmpty
          ? await widget.api.discover()
          : JellyfinApi.normalizeUrl(_server.text);
      final code = await widget.api.initiateQuickConnect(baseUrl);
      if (!mounted) return;
      setState(() {
        _quickCode = code.code;
        _message =
            'No celular já conectado ao Jellyfin, abra o menu e autorize este código.';
      });
      for (var attempt = 0; attempt < 60 && !_cancelQuickConnect; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (_cancelQuickConnect || !mounted) return;
        if (await widget.api.quickConnectAuthorized(code)) {
          final session = await widget.api.authenticateQuickConnect(code);
          widget.onConnected(session);
          return;
        }
      }
      if (mounted) setState(() => _message = 'O código expirou. Gere outro.');
    } on JellyfinException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Não foi possível gerar o código de acesso.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _quickCode = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: CasaFlixMark(size: 44),
                    ),
                    const SizedBox(height: 54),
                    Text(
                      'Sua sala, em qualquer lugar.',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: CasaFlixColors.ivory,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                        letterSpacing: -1.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Conecte ao notebook de casa e continue de onde estiver.',
                      style: TextStyle(
                        color: CasaFlixColors.muted,
                        fontSize: 17,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 34),
                    TextFormField(
                      controller: _server,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Endereço do servidor',
                        prefixIcon: Icon(Icons.dns_outlined),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Informe o endereço do servidor.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _discover,
                      icon: const Icon(Icons.radar_rounded),
                      label: const Text('Encontrar automaticamente'),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _user,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Usuário',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Informe seu usuário.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      onFieldSubmitted: (_) => _busy ? null : _login(),
                      decoration: InputDecoration(
                        labelText: 'Senha',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Informe sua senha.'
                          : null,
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _message!,
                        style: const TextStyle(
                          color: CasaFlixColors.muted,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (_quickCode != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          color: CasaFlixColors.ink,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          _quickCode!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: CasaFlixColors.sky,
                            fontSize: 38,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 8,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: _busy ? null : _login,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: CasaFlixColors.night,
                              ),
                            )
                          : const Icon(Icons.play_arrow_rounded),
                      label: Text(_busy ? 'Conectando…' : 'Entrar no NetPobre'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? (_quickCode == null
                                ? null
                                : () => setState(
                                    () => _cancelQuickConnect = true,
                                  ))
                          : _quickConnect,
                      icon: Icon(
                        _busy && _quickCode != null
                            ? Icons.close_rounded
                            : Icons.tv_rounded,
                      ),
                      label: Text(
                        _busy && _quickCode != null
                            ? 'Cancelar código'
                            : 'Entrar com código na TV',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
