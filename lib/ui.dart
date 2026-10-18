import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'controller.dart';
import 'domain.dart';
import 'registration.dart';
import 'services.dart';

const lime = Color(0xffdceeb1),
    navy = Color(0xff24264b),
    cream = Color(0xfff4ecd6),
    lilac = Color(0xffc5b0f4),
    ink = Color(0xff141414);
final yardlineTheme = ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: Colors.white,
  colorScheme: ColorScheme.fromSeed(
    seedColor: ink,
    primary: ink,
    secondary: lime,
    surface: Colors.white,
    onPrimary: Colors.white,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white,
    foregroundColor: ink,
    surfaceTintColor: Colors.transparent,
    centerTitle: false,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 38,
      height: 1.05,
      letterSpacing: -1.2,
      fontWeight: FontWeight.w400,
      color: ink,
    ),
    headlineMedium: TextStyle(
      fontSize: 28,
      height: 1.15,
      letterSpacing: -.6,
      color: ink,
    ),
    titleLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    bodyLarge: TextStyle(fontSize: 17, height: 1.45, color: ink),
    bodyMedium: TextStyle(fontSize: 15, height: 1.45, color: ink),
    labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: ink,
      foregroundColor: Colors.white,
      minimumSize: const Size(0, 52),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      shape: const StadiumBorder(),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: ink,
      minimumSize: const Size(0, 50),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      side: const BorderSide(color: ink),
      shape: const StadiumBorder(),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.all(16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xffc9c9c9)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xffc9c9c9)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: ink, width: 2),
    ),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: Colors.white,
    indicatorColor: lime,
    labelTextStyle: WidgetStateProperty.all(
      const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ink),
    ),
  ),
);
Widget eyebrow(String text) => Text(
  text.toUpperCase(),
  style: const TextStyle(
    fontFamily: 'monospace',
    fontSize: 12,
    letterSpacing: 1.2,
    fontWeight: FontWeight.w400,
    color: ink,
  ),
);
Widget pageTitle(BuildContext context, String title, String subtitle) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(title, style: Theme.of(context).textTheme.headlineLarge),
    const SizedBox(height: 10),
    Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
    const SizedBox(height: 28),
  ],
);
Widget panel({required Widget child, Color color = lime}) => Container(
  width: double.infinity,
  padding: const EdgeInsets.all(24),
  decoration: BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(24),
  ),
  child: child,
);
Widget pill(String label, {bool dark = false}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
  decoration: BoxDecoration(
    color: dark ? navy : lime,
    borderRadius: BorderRadius.circular(40),
  ),
  child: Text(
    label,
    style: TextStyle(
      color: dark ? Colors.white : ink,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
  ),
);
Widget bodyList(List<Widget> children) => Align(
  alignment: Alignment.topCenter,
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 760),
    child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      children: children,
    ),
  ),
);
void message(BuildContext context, Object e) {
  final text = e is ApiFailure
      ? '${e.message}${e.uncertain ? ' The outcome is unknown. Review the latest record before retrying.' : ''}'
      : e.toString();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 7),
      showCloseIcon: true,
    ),
  );
}

String displayTime(String raw) {
  final t = DateTime.tryParse(raw)?.toLocal();
  if (t == null) return raw;
  return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} · ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class ConnectScreen extends StatefulWidget {
  final AppConfig config;
  final VoidCallback onConnect;
  const ConnectScreen({
    super.key,
    required this.config,
    required this.onConnect,
  });
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final email = TextEditingController(), password = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> connect() async {
    setState(() => busy = true);
    try {
      if (widget.config.authMode == 'supabase' &&
          Supabase.instance.client.auth.currentSession == null) {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
      if (mounted) widget.onConnect();
    } catch (_) {
      if (mounted) {
        message(
          context,
          const ApiFailure(
            'LOGIN',
            'Could not sign in. Check your credentials and connection.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: bodyList([
        const SizedBox(height: 16),
        const Text(
          '▦ yardline',
          style: TextStyle(
            fontSize: 32,
            letterSpacing: -1,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 48),
        panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              eyebrow('Worker companion'),
              const SizedBox(height: 28),
              Text(
                'On the ground.\nIn the know.',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 20),
              const Text(
                'Scan a container. Find its place. Keep the whole yard in sync.',
                style: TextStyle(fontSize: 20, height: 1.4),
              ),
              const SizedBox(height: 36),
              const Icon(Icons.document_scanner_outlined, size: 80, color: ink),
            ],
          ),
        ),
        const SizedBox(height: 32),
        eyebrow(
          widget.config.authMode == 'demo'
              ? 'Shared demonstration yard'
              : 'Worker sign in',
        ),
        const SizedBox(height: 16),
        if (widget.config.authMode == 'demo')
          const Text(
            'Connect as a demo operator to the same yard used by the web dashboard. Changes are shared.',
          ),
        if (widget.config.authMode == 'supabase') ...[
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username],
            decoration: const InputDecoration(labelText: 'Work email'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: password,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (_) => connect(),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: busy ? null : connect,
          child: Text(
            busy
                ? 'Connecting…'
                : widget.config.authMode == 'demo'
                ? 'Enter demo yard'
                : 'Sign in',
          ),
        ),
        const SizedBox(height: 16),
        Text(
          Uri.parse(widget.config.baseUrl).host,
          textAlign: TextAlign.center,
        ),
      ]),
    ),
  );
}

class WorkerShell extends StatefulWidget {
  final YardController controller;
  final Future<void> Function() onDisconnect;
  const WorkerShell({
    super.key,
    required this.controller,
    required this.onDisconnect,
  });
  @override
  State<WorkerShell> createState() => _WorkerShellState();
}

class _WorkerShellState extends State<WorkerShell> with WidgetsBindingObserver {
  int tab = 0;
  XFile? recovered;
  YardController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    recover();
  }

  Future<void> recover() async {
    try {
      final lost = await ImagePicker().retrieveLostData();
      if (!mounted) return;
      if (lost.files?.isNotEmpty == true) {
        setState(() {
          recovered = lost.files!.first;
          tab = 2;
        });
      } else if (lost.exception != null) {
        message(
          context,
          'The camera capture was interrupted. Please try again or enter the number manually.',
        );
      }
    } catch (_) {
      /* Manual entry remains available if a platform has no picker. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      c.setForeground(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final state = c.snapshot;
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            '▦ yardline',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w600,
              letterSpacing: -1,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Connection and settings',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(
                    controller: c,
                    onDisconnect: widget.onDisconnect,
                  ),
                ),
              ),
              icon: const Icon(Icons.tune_rounded),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            if (c.loading)
              const LinearProgressIndicator(
                minHeight: 2,
                color: ink,
                backgroundColor: lime,
              ),
            if (state != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${state.yard.name} · ${string(state.actor['role'])}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      c.online
                          ? 'Synced ${displayTime(state.generatedAt)}'
                          : 'Offline · saved view',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: panel(
                  color: cream,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.error!.message),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: c.loading ? null : () => c.start(),
                        child: const Text('Reconnect'),
                      ),
                    ],
                  ),
                ),
              ),
            if (c.pending != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: panel(
                  color: cream,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'An interrupted operation needs review.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Text(
                        'Submissions are paused until its outcome is checked.',
                      ),
                      TextButton(
                        onPressed: () => showPending(context, c),
                        child: const Text('Review operation'),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: state == null
                  ? Center(
                      child: c.loading
                          ? const CircularProgressIndicator(color: ink)
                          : const Text('Connect to load the shared yard.'),
                    )
                  : switch (tab) {
                      0 => Dashboard(
                        controller: c,
                        onScan: () => setState(() => tab = 2),
                        onSearch: () => setState(() => tab = 1),
                      ),
                      1 => SearchScreen(controller: c),
                      2 => RegistrationScreen(
                        key: ValueKey('scan:${state.yard.id}'),
                        controller: c,
                        recovered: recovered,
                        onRecovered: () {
                          if (mounted) setState(() => recovered = null);
                        },
                      ),
                      _ => HistoryScreen(controller: c),
                    },
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.space_dashboard_outlined),
              selectedIcon: Icon(Icons.space_dashboard),
              label: 'Yard',
            ),
            NavigationDestination(icon: Icon(Icons.search), label: 'Find'),
            NavigationDestination(
              icon: Icon(Icons.document_scanner_outlined),
              label: 'Scan',
            ),
            NavigationDestination(
              icon: Icon(Icons.swap_horiz),
              label: 'Activity',
            ),
          ],
        ),
      );
    },
  );
}

Future<void> showPending(BuildContext context, YardController c) async {
  if (c.pending == null) return;
  final intent = jsonDecode(c.pending!) as Json;
  final payload = intent['payload'] as Json;
  if (!await c.refresh(yardId: payload['yardId'] as String?)) {
    if (context.mounted) message(context, c.error!);
    return;
  }
  if (!context.mounted || c.pending == null) return;
  final container =
      c.snapshot!.container(string(payload['containerId'])) ??
      c.snapshot!.containers
          .where((v) => v.number == payload['number'])
          .firstOrNull;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Check the outcome'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Operation: ${intent['action']}\nStarted: ${displayTime(string(intent['startedAt']))}',
            ),
            const SizedBox(height: 16),
            Text(
              container == null
                  ? 'No matching container appears in this yard snapshot.'
                  : '${container.number}\n${container.status}\n${container.locationCode ?? 'No assigned position'}',
            ),
            const SizedBox(height: 16),
            const Text(
              'Review this record and recent activity on the web dashboard if needed. A missing record does not prove that the request failed. Nothing will be resent automatically.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep paused'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('I reviewed the outcome'),
        ),
      ],
    ),
  );
  if (accepted == true) {
    try {
      await c.acknowledgePending();
    } catch (e) {
      if (context.mounted) message(context, e);
    }
  }
}

class Dashboard extends StatelessWidget {
  final YardController controller;
  final VoidCallback onScan, onSearch;
  const Dashboard({
    super.key,
    required this.controller,
    required this.onScan,
    required this.onSearch,
  });
  @override
  Widget build(BuildContext context) {
    final s = controller.snapshot!;
    return RefreshIndicator(
      onRefresh: () async {
        await controller.refresh();
      },
      child: bodyList([
        const SizedBox(height: 8),
        eyebrow('Your yard, connected'),
        const SizedBox(height: 14),
        pageTitle(
          context,
          'Ready for the\nnext move.',
          'One shared view, from gate to stack.',
        ),
        panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              eyebrow('Yard capacity'),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${integer(s.metrics['occupied'])}',
                    style: const TextStyle(
                      fontSize: 64,
                      height: 1,
                      letterSpacing: -2,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      '/ ${integer(s.metrics['capacity'])} positions',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value:
                      (integer(s.metrics['occupied']) /
                              (integer(s.metrics['capacity']) == 0
                                  ? 1
                                  : integer(s.metrics['capacity'])))
                          .clamp(0, 1),
                  minHeight: 10,
                  color: navy,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 16,
                runSpacing: 10,
                children: [
                  Text('${integer(s.metrics['assignable'])} assignable'),
                  Text('${integer(s.metrics['unassigned'])} unassigned'),
                ],
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onScan,
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Scan a container'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onSearch,
          icon: const Icon(Icons.search),
          label: const Text('Find an existing container'),
        ),
        const SizedBox(height: 36),
        Text(
          'Storage blocks',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 16),
        for (final block in s.blocks)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xffdedede)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                title: Text(
                  block.code,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${block.name}\n${s.slots.where((p) => p.blockId == block.id && s.occupants.containsKey(p.id)).length} occupied / ${block.capacityLimit} positions',
                ),
                trailing: const Icon(Icons.arrow_forward),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => YardPositions(
                      controller: controller,
                      initialBlock: block.id,
                    ),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 24),
        Text(
          'Latest movements',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        if (s.movements.isEmpty) const Text('No movements recorded yet.'),
        for (final movement in s.movements.take(4))
          MovementTile(
            movement: movement,
            onTap: () =>
                openContainer(context, controller, movement.containerId),
          ),
        const SizedBox(height: 16),
        const Text(
          'Changes appear on the web dashboard on its next refresh, normally within 30 seconds.',
        ),
      ]),
    );
  }
}

void openContainer(BuildContext context, YardController c, String id) =>
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ContainerScreen(controller: c, id: id),
      ),
    );

class SearchScreen extends StatefulWidget {
  final YardController controller;
  const SearchScreen({super.key, required this.controller});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String query = '', status = 'All';
  @override
  Widget build(BuildContext context) {
    final results = widget.controller.snapshot!.containers
        .where(
          (c) =>
              (status == 'All' || c.status == status.toLowerCase()) &&
              (normalizeNumber(c.number).contains(normalizeNumber(query)) ||
                  c.owner.toLowerCase().contains(query.toLowerCase())),
        )
        .toList();
    return bodyList([
      pageTitle(
        context,
        'Find a container.',
        'Search the shared yard by number or owner.',
      ),
      TextField(
        decoration: const InputDecoration(
          hintText: 'Container number or owner',
          prefixIcon: Icon(Icons.search),
        ),
        textCapitalization: TextCapitalization.characters,
        onChanged: (v) => setState(() => query = v),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final label in ['All', 'Stored', 'Unassigned', 'Dispatched'])
            ChoiceChip(
              label: Text(label),
              selected: status == label,
              showCheckmark: false,
              selectedColor: ink,
              labelStyle: TextStyle(
                color: status == label ? Colors.white : ink,
              ),
              shape: const StadiumBorder(),
              onSelected: (_) => setState(() => status = label),
            ),
        ],
      ),
      const SizedBox(height: 24),
      eyebrow('${results.length} matching records'),
      const SizedBox(height: 12),
      if (results.isEmpty)
        panel(
          color: cream,
          child: const Text(
            'No match in the selected yard. Try another number, refresh, or select a different yard in settings.',
          ),
        ),
      for (final c in results)
        ContainerTile(
          container: c,
          onTap: () => openContainer(context, widget.controller, c.id),
        ),
    ]);
  }
}

class ContainerTile extends StatelessWidget {
  final YardContainer container;
  final VoidCallback onTap;
  const ContainerTile({
    super.key,
    required this.container,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Material(
      color: const Color(0xfff7f7f5),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    container.number,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w600,
                      letterSpacing: .3,
                    ),
                  ),
                  pill(container.status),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${container.size} ft · ${container.type}${container.owner.isEmpty ? '' : ' · ${container.owner}'}',
              ),
              const SizedBox(height: 6),
              Text(container.locationCode ?? 'No assigned position'),
            ],
          ),
        ),
      ),
    ),
  );
}

class HistoryScreen extends StatelessWidget {
  final YardController controller;
  final String? containerId;
  const HistoryScreen({super.key, required this.controller, this.containerId});
  @override
  Widget build(BuildContext context) {
    final events = controller.snapshot!.movements
        .where((m) => containerId == null || m.containerId == containerId)
        .toList();
    return RefreshIndicator(
      onRefresh: () async {
        await controller.refresh();
      },
      child: bodyList([
        pageTitle(
          context,
          'Every move,\nrecorded.',
          'The latest shared yard activity, with the worker and location.',
        ),
        eyebrow('${events.length} events in this snapshot'),
        const SizedBox(height: 16),
        if (events.isEmpty) const Text('No recorded movements.'),
        for (final event in events)
          MovementTile(
            movement: event,
            onTap: () => openContainer(context, controller, event.containerId),
          ),
        const SizedBox(height: 16),
        const Text(
          'The server returns up to 1,000 recent movements. This is not a lifetime archive.',
        ),
      ]),
    );
  }
}

class MovementTile extends StatelessWidget {
  final Movement movement;
  final VoidCallback? onTap;
  const MovementTile({super.key, required this.movement, this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                movement.number,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(width: 116, child: Center(child: pill(movement.event))),
            ],
          ),
          const SizedBox(height: 8),
          Text('${movement.from ?? '—'} → ${movement.to ?? '—'}'),
          const SizedBox(height: 6),
          Text(
            '${movement.actor} · ${displayTime(movement.occurredAt)}',
            style: const TextStyle(fontSize: 13),
          ),
          if (movement.notes.isNotEmpty) Text(movement.notes),
          const SizedBox(height: 12),
          const Divider(height: 1),
        ],
      ),
    ),
  );
}

class YardPositions extends StatefulWidget {
  final YardController controller;
  final int? size;
  final YardContainer? moving;
  final String? initialBlock;
  const YardPositions({
    super.key,
    required this.controller,
    this.size,
    this.moving,
    this.initialBlock,
  });
  @override
  State<YardPositions> createState() => _YardPositionsState();
}

class _YardPositionsState extends State<YardPositions> {
  String? block, row;
  bool availableOnly = true;
  @override
  void initState() {
    super.initState();
    block =
        widget.initialBlock ??
        widget.controller.snapshot!.blocks.firstOrNull?.id;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final s = widget.controller.snapshot!;
      final blockSlots = s.slots.where((p) => p.blockId == block).toList()
        ..sort((a, b) {
          final r = a.rowOrdinal.compareTo(b.rowOrdinal);
          return r != 0
              ? r
              : a.bayOrdinal != b.bayOrdinal
              ? a.bayOrdinal.compareTo(b.bayOrdinal)
              : a.tier.compareTo(b.tier);
        });
      final rows = {for (final p in blockSlots) p.rowId: p.rowCode};
      String? reason(Slot slot) => widget.size == null
          ? (s.occupants.containsKey(slot.id)
                ? 'Occupied'
                : slot.status != 'available'
                ? slot.status
                : null)
          : s.destinationProblem(slot, widget.size!, moving: widget.moving);
      final filtered = blockSlots
          .where(
            (p) =>
                (row == null || p.rowId == row) &&
                (!availableOnly || reason(p) == null),
          )
          .toList();
      return Scaffold(
        appBar: AppBar(
          title: Text(
            widget.size == null ? 'Yard positions' : 'Choose a position',
          ),
        ),
        body: bodyList([
          panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                eyebrow(
                  widget.size == null
                      ? 'Shared layout'
                      : 'Physical destination',
                ),
                const SizedBox(height: 12),
                Text(
                  widget.size == null
                      ? 'A place for\nevery container.'
                      : 'Assign a ${widget.size} ft container.',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Positions come from the actual yard layout. The server checks occupancy and stack rules again when you submit.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            initialValue: block,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Storage block'),
            items: [
              for (final b in s.blocks)
                DropdownMenuItem(
                  value: b.id,
                  child: Text('${b.code} · ${b.name}'),
                ),
            ],
            onChanged: (v) => setState(() {
              block = v;
              row = null;
            }),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All rows'),
                selected: row == null,
                onSelected: (_) => setState(() => row = null),
              ),
              for (final entry in rows.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: row == entry.key,
                  onSelected: (_) => setState(() => row = entry.key),
                ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              widget.size == null
                  ? 'Show vacant positions only'
                  : 'Show eligible positions only',
            ),
            value: availableOnly,
            onChanged: (v) => setState(() => availableOnly = v),
          ),
          eyebrow('${filtered.length} positions'),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            const Text(
              'No positions match. Try another row or block, or show all positions to see the reason.',
            ),
          for (final slot in filtered)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: reason(slot) == null ? lime : const Color(0xfff2f2f2),
                borderRadius: BorderRadius.circular(16),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  title: Text(
                    '${slot.rowCode} · ${slot.bayCode} · Tier ${slot.tier}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    s.occupants[slot.id]?.number ??
                        reason(slot) ??
                        'Vacant · up to ${slot.maxSize} ft',
                  ),
                  trailing: widget.size != null && reason(slot) == null
                      ? const Icon(Icons.arrow_forward)
                      : null,
                  onTap: widget.size != null && reason(slot) == null
                      ? () => Navigator.pop(context, slot)
                      : s.occupants[slot.id] != null
                      ? () => openContainer(
                          context,
                          widget.controller,
                          s.occupants[slot.id]!.id,
                        )
                      : null,
                ),
              ),
            ),
        ]),
      );
    },
  );
}

class ContainerScreen extends StatelessWidget {
  final YardController controller;
  final String id;
  const ContainerScreen({
    super.key,
    required this.controller,
    required this.id,
  });
  Future<void> operate(
    BuildContext context,
    YardContainer current,
    String action,
  ) async {
    final expected = current.slotId;
    final yardId = controller.snapshot!.yard.id;
    if (!await controller.refresh()) {
      if (context.mounted) message(context, controller.error!);
      return;
    }
    if (!context.mounted) return;
    final latest = controller.snapshot!.container(id);
    if (latest == null || latest.slotId != expected) {
      message(context, 'The location changed. Review the latest details.');
      return;
    }
    Slot? selected;
    if (action == 'move') {
      selected = await Navigator.push<Slot>(
        context,
        MaterialPageRoute(
          builder: (_) => YardPositions(
            controller: controller,
            size: latest.size,
            moving: latest,
          ),
        ),
      );
      if (selected == null || !context.mounted) return;
    }
    final confirmed = await confirmOperation(
      context,
      title: switch (action) {
        'move' => 'Confirm physical placement',
        'dispatch' => 'Confirm gate-out',
        _ => 'Verify physical location',
      },
      details:
          '${latest.number}\n${latest.locationCode ?? 'Unassigned'}${selected == null ? '' : '\n→ ${selected.code}'}',
      confirmation: action == 'dispatch'
          ? 'I confirm this container has physically left the yard.'
          : 'I physically checked the container number and this location.',
    );
    if (confirmed == null || !context.mounted) return;
    try {
      await controller.mutate(action, {
        'yardId': yardId,
        'containerId': id,
        'expectedSlotId': expected,
        if (action == 'move') 'slotId': selected!.id,
        if (action == 'dispatch') 'confirmed': true,
        if (action != 'dispatch') 'physicalConfirmed': true,
        if (action != 'verify') 'notes': confirmed,
      });
      if (context.mounted) {
        message(
          context,
          '${action == 'move'
              ? 'Placement'
              : action == 'dispatch'
              ? 'Dispatch'
              : 'Verification'} recorded in the shared yard.',
        );
      }
    } catch (e) {
      if (context.mounted) message(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final s = controller.snapshot!;
      final c = s.container(id);
      if (c == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Container')),
          body: const Center(child: Text('Not in this yard snapshot.')),
        );
      }
      final sourceProblem = s.sourceProblem(c);
      return Scaffold(
        appBar: AppBar(title: const Text('Container details')),
        body: bodyList([
          panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                pill(c.status, dark: true),
                const SizedBox(height: 20),
                Text(
                  c.number,
                  style: const TextStyle(
                    fontSize: 29,
                    letterSpacing: -.7,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${c.size} ft · ${c.type}',
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(height: 24),
                eyebrow('Recorded position'),
                const SizedBox(height: 10),
                Text(
                  c.locationCode ?? 'Unassigned',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  c.identityVerified
                      ? 'ISO 6346 identity verified'
                      : 'Identity requires administrator review',
                ),
                if (c.verifiedAt != null)
                  Text('Location checked ${displayTime(c.verifiedAt!)}'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (c.owner.isNotEmpty)
            Text(
              'Owner · ${c.owner}',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          if (c.notes.isNotEmpty) ...[const SizedBox(height: 8), Text(c.notes)],
          if (c.hasPhoto) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  final bytes = await controller.api.photo(c.id);
                  if (context.mounted) {
                    showDialog<void>(
                      context: context,
                      builder: (ctx) => Dialog(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: InteractiveViewer(
                                child: Image.memory(
                                  bytes,
                                  errorBuilder: (_, _, _) =>
                                      const Text('Cannot display this image.'),
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) message(context, e);
                }
              },
              icon: const Icon(Icons.photo_outlined),
              label: const Text('View registration photo'),
            ),
          ],
          const SizedBox(height: 28),
          if (sourceProblem != null)
            panel(color: cream, child: Text(sourceProblem)),
          if (c.status != 'dispatched') ...[
            FilledButton.icon(
              onPressed: controller.canWrite && sourceProblem == null
                  ? () => operate(context, c, 'move')
                  : null,
              icon: const Icon(Icons.swap_horiz),
              label: Text(
                c.slotId == null
                    ? 'Assign a yard position'
                    : 'Relocate container',
              ),
            ),
            const SizedBox(height: 12),
            if (c.slotId != null) ...[
              OutlinedButton.icon(
                onPressed: controller.canWrite
                    ? () => operate(context, c, 'verify')
                    : null,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Verify physical location'),
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              onPressed: controller.canWrite && sourceProblem == null
                  ? () => operate(context, c, 'dispatch')
                  : null,
              icon: const Icon(Icons.logout),
              label: const Text('Dispatch / gate-out'),
            ),
          ],
          const SizedBox(height: 36),
          Text(
            'Movement history',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          for (final m in s.movements.where((m) => m.containerId == c.id))
            MovementTile(movement: m),
        ]),
      );
    },
  );
}

Future<String?> confirmOperation(
  BuildContext context, {
  required String title,
  required String details,
  required String confirmation,
  bool notes = true,
}) => showDialog<String>(
  context: context,
  builder: (_) => _ConfirmationDialog(
    title: title,
    details: details,
    confirmation: confirmation,
    notes: notes,
  ),
);

class _ConfirmationDialog extends StatefulWidget {
  final String title, details, confirmation;
  final bool notes;
  const _ConfirmationDialog({
    required this.title,
    required this.details,
    required this.confirmation,
    required this.notes,
  });
  @override
  State<_ConfirmationDialog> createState() => _ConfirmationDialogState();
}

class _ConfirmationDialogState extends State<_ConfirmationDialog> {
  final text = TextEditingController();
  bool checked = false;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.details, style: const TextStyle(fontSize: 17)),
          const SizedBox(height: 20),
          if (widget.notes)
            TextField(
              controller: text,
              maxLength: 1500,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Operation notes (optional)',
              ),
            ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(widget.confirmation),
            value: checked,
            onChanged: (v) => setState(() => checked = v ?? false),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: checked
            ? () => Navigator.pop(context, text.text.trim())
            : null,
        child: const Text('Confirm'),
      ),
    ],
  );
}

class SettingsScreen extends StatelessWidget {
  final YardController controller;
  final Future<void> Function() onDisconnect;
  const SettingsScreen({
    super.key,
    required this.controller,
    required this.onDisconnect,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final s = controller.snapshot;
      return Scaffold(
        appBar: AppBar(title: const Text('Workspace')),
        body: bodyList([
          pageTitle(
            context,
            'Connected to\none shared yard.',
            'The website and this app use the same backend.',
          ),
          if (s != null) ...[
            eyebrow('Active yard'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: s.yard.id,
              isExpanded: true,
              items: [
                for (final y in s.yards)
                  DropdownMenuItem(
                    value: y.id,
                    child: Text(
                      '${y.name} · ${y.code}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: controller.loading || controller.writing
                  ? null
                  : (id) async {
                      if (id != null) await controller.refresh(yardId: id);
                    },
            ),
            const SizedBox(height: 24),
            panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    string(s.actor['name']),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text('${s.actor['role']} · ${s.authMode} authentication'),
                  const SizedBox(height: 12),
                  Text('Snapshot · ${displayTime(s.generatedAt)}'),
                  Text('Storage · ${s.raw['persistence']}'),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          eyebrow('API origin'),
          const SizedBox(height: 8),
          SelectableText(controller.config.baseUrl),
          const SizedBox(height: 24),
          const Text(
            'Foreground synchronization runs every 30 seconds. Pull to refresh for the latest snapshot. Saved views are read-only while offline. Camera recognition runs on this device; a photo is uploaded only if you explicitly attach it.',
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: controller.loading || controller.writing
                ? null
                : () => controller.refresh(),
            icon: const Icon(Icons.sync),
            label: const Text('Sync now'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: controller.writing
                ? null
                : () async {
                    await onDisconnect();
                    if (context.mounted) Navigator.pop(context);
                  },
            child: const Text('Disconnect and clear saved yard data'),
          ),
        ]),
      );
    },
  );
}
