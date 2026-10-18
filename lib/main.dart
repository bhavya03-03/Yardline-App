import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'controller.dart';
import 'services.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const config = AppConfig();
  const store = DeviceStore();
  String? setupError;
  try {
    config.validate();
    if (config.authMode == 'supabase') {
      await Supabase.initialize(
        url: config.supabaseUrl,
        publishableKey: config.supabaseKey,
        authOptions: FlutterAuthClientOptions(
          localStorage: SecureSessionStorage(
            store,
            'yardline:auth:${config.supabaseUrl}',
          ),
          detectSessionInUri: false,
        ),
      );
    }
  } catch (e) {
    setupError = e is ApiFailure
        ? e.message
        : 'Could not initialize secure worker authentication.';
  }
  runApp(YardlineApp(config: config, store: store, setupError: setupError));
}

class YardlineApp extends StatefulWidget {
  final AppConfig config;
  final LocalStore store;
  final String? setupError;
  const YardlineApp({
    super.key,
    required this.config,
    required this.store,
    this.setupError,
  });
  @override
  State<YardlineApp> createState() => _YardlineAppState();
}

class _YardlineAppState extends State<YardlineApp> {
  YardController? controller;
  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void connect() {
    controller?.dispose();
    final user = widget.config.authMode == 'supabase'
        ? Supabase.instance.client.auth.currentUser?.id
        : 'demo-operator';
    controller = YardController(
      config: widget.config,
      store: widget.store,
      scope: '${widget.config.baseUrl}:${widget.config.authMode}:$user',
      api: HttpYardApi(
        widget.config,
        token: () => widget.config.authMode == 'supabase'
            ? Supabase.instance.client.auth.currentSession?.accessToken
            : null,
      ),
    );
    controller!.start();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Yardline',
    debugShowCheckedModeBanner: false,
    theme: yardlineTheme,
    home: widget.setupError != null
        ? Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(widget.setupError!),
              ),
            ),
          )
        : controller == null
        ? ConnectScreen(config: widget.config, onConnect: connect)
        : WorkerShell(
            controller: controller!,
            onDisconnect: () async {
              await controller!.clearLocalData();
              if (widget.config.authMode == 'supabase') {
                try {
                  await Supabase.instance.client.auth.signOut();
                } catch (_) {
                  /* Session may already be expired. */
                }
              }
              controller!.dispose();
              controller = null;
              if (mounted) setState(() {});
            },
          ),
  );
}
