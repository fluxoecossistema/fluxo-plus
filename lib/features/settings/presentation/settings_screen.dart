import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/sync/cloud_sync_service.dart';
import '../../../core/update/update_prompt.dart';
import '../../../core/update/update_service.dart';
import 'cloud_backup_panel.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
    required this.cloudSyncService,
    required this.biometricEnabled,
    required this.onBiometricChanged,
    required this.updateService,
    required this.onDataChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final CloudSyncService cloudSyncService;
  final bool biometricEnabled;
  final Future<bool> Function(bool) onBiometricChanged;
  final UpdateService updateService;
  final VoidCallback onDataChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Aparência',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: context.colors.primary.withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          themeMode == ThemeMode.dark
                              ? Icons.nightlight_round
                              : Icons.wb_sunny_rounded,
                          color: context.colors.primary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tema do aplicativo',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            SizedBox(height: 3),
                            Text('Escolha como o Fluxo+ aparece para você.'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined),
                        label: Text('Escuro'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined),
                        label: Text('Claro'),
                      ),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (value) => onThemeChanged(value.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Segurança',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              value: biometricEnabled,
              secondary: const Icon(Icons.fingerprint_rounded),
              title: const Text('Bloqueio biométrico'),
              subtitle: const Text(
                'Solicitar biometria ao abrir o aplicativo.',
              ),
              onChanged: (value) async {
                final changed = await onBiometricChanged(value);
                if (!changed && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Biometria indisponível ou autenticação cancelada.',
                      ),
                    ),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Backup na nuvem',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          CloudBackupPanel(
            service: cloudSyncService,
            onDataChanged: onDataChanged,
          ),
          const SizedBox(height: 24),
          Text(
            'Privacidade e dados',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.lock_outline_rounded,
                    color: context.colors.primary,
                  ),
                  title: const Text('Dados locais'),
                  subtitle: const Text(
                    'Suas informações permanecem neste dispositivo.',
                  ),
                  trailing: Icon(Icons.check_circle_rounded,
                      color: context.colors.primary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _UpdatePanel(service: updateService),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              onTap: () => showAboutDialog(
                context: context,
                applicationName: 'Fluxo+',
                applicationVersion: '0.5.0',
                applicationLegalese: '© 2026 Fluxo+ contributors\nLicença MIT',
                children: const [
                  SizedBox(height: 12),
                  Text(
                    'Finanças pessoais offline-first, seguras e open source.',
                  ),
                ],
              ),
              leading: Icon(
                dark ? Icons.nightlight_round : Icons.wb_sunny_outlined,
                color: context.colors.primary,
              ),
              title: const Text('Fluxo+'),
              subtitle: const Text('Open source • Licença MIT'),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdatePanel extends StatefulWidget {
  const _UpdatePanel({required this.service});

  final UpdateService service;

  @override
  State<_UpdatePanel> createState() => _UpdatePanelState();
}

class _UpdatePanelState extends State<_UpdatePanel> {
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final update = await widget.service.check();
      if (!mounted) return;
      if (update == null) {
        final version = await widget.service.currentVersion();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Você já está na versão mais recente: $version')),
        );
      } else {
        await showUpdatePrompt(
          context,
          update: update,
          service: widget.service,
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao verificar: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: FutureBuilder<String>(
        future: widget.service.currentVersion(),
        builder: (context, snapshot) => ListTile(
          leading: const Icon(Icons.system_update_rounded),
          title: const Text('Atualização pela internet'),
          subtitle: Text(
            snapshot.hasData
                ? 'Versão instalada: ${snapshot.data}'
                : 'Consultando versão instalada…',
          ),
          trailing: FilledButton(
            onPressed: _checking ? null : _check,
            child: _checking
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.colors.onPrimary,
                    ),
                  )
                : const Text('Verificar'),
          ),
        ),
      ),
    );
  }
}
