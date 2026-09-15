import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:workfromphone/services/local_container_service.dart';
import 'package:workfromphone/services/storage_service.dart';

/// On-device container setup wizard (No-PC mode).
///
/// Flow: Begin Setup (rootfs download → verify → extract, with progress) →
/// Start / Stop + status → Test Connection (public `/health`, then authed
/// `/system/snapshot`) → Save & Activate (stores a `directHttp`
/// `http://127.0.0.1:8000` profile; the token lives in secure storage).
class OnDeviceSetupScreen extends StatefulWidget {
  const OnDeviceSetupScreen({super.key});

  @override
  State<OnDeviceSetupScreen> createState() => _OnDeviceSetupScreenState();
}

class _OnDeviceSetupScreenState extends State<OnDeviceSetupScreen> {
  OnDeviceStatus? _status;
  RootfsRelease? _release;
  String? _statusError;
  bool _loadingStatus = true;

  bool _resolvingRelease = false;
  String? _releaseError;
  bool _settingUp = false;
  String _setupPhase = '';
  double _setupProgress = 0;
  String? _setupError;
  StreamSubscription? _progressSub;

  bool _starting = false;
  bool _testing = false;
  OnDeviceTestResult? _testResult;
  bool _saving = false;
  bool _batteryExempt = false;
  bool _batteryExemptKnown = false;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    if (!LocalContainerService.isSupportedPlatform) {
      setState(() {
        _loadingStatus = false;
        _statusError = 'On-device mode needs the Android app on a device.';
      });
      return;
    }
    setState(() {
      _loadingStatus = true;
      _statusError = null;
    });
    try {
      final status = await LocalContainerService.getStatus();
      final exempt = await LocalContainerService.isBatteryExemptionGranted();
      if (!mounted) return;
      setState(() {
        _status = status;
        _batteryExempt = exempt;
        _batteryExemptKnown = true;
        _loadingStatus = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingStatus = false;
        _statusError = 'Could not reach the container bridge ($e).';
      });
    }
  }

  Future<void> _resolveRelease() async {
    final arch = LocalContainerService.releaseArchitecture(
      _status?.abi ?? 'unknown',
    );
    setState(() {
      _resolvingRelease = true;
      _releaseError = null;
    });
    try {
      final release = await LocalContainerService.fetchRootfsRelease(arch);
      if (!mounted) return;
      setState(() => _release = release);
    } catch (e) {
      if (!mounted) return;
      setState(() => _releaseError = '$e');
    } finally {
      if (mounted) setState(() => _resolvingRelease = false);
    }
  }

  Future<void> _beginSetup() async {
    final release = _release;
    if (release == null) return;
    setState(() {
      _settingUp = true;
      _setupError = null;
      _setupPhase = 'download';
      _setupProgress = 0;
    });
    await _progressSub?.cancel();
    _progressSub = LocalContainerService.progressStream().listen((event) {
      if (!mounted) return;
      final phase = event['phase'] as String? ?? '';
      final progress = (event['progress'] as num?)?.toDouble() ?? 0;
      setState(() {
        _setupPhase = phase;
        _setupProgress = progress / 100;
      });
      if (phase == 'done') {
        setState(() => _settingUp = false);
        _refreshStatus();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Debian rootfs installed. Start the container.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (phase == 'error') {
        setState(() {
          _settingUp = false;
          _setupError = event['message'] as String? ?? 'Setup failed.';
        });
      }
    });
    try {
      await LocalContainerService.beginSetup(
        url: release.url,
        sha256: release.sha256,
        version: release.version,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _settingUp = false;
        _setupError = '$e';
      });
    }
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _testResult = null;
    });
    try {
      final token = await LocalContainerService.ensureAccessToken();
      await LocalContainerService.start(
        accessToken: token,
        port: LocalContainerService.defaultPort,
      );
      // Give the guest a moment, then re-read native health state.
      await Future<void>.delayed(const Duration(seconds: 3));
      await _refreshStatus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start the container: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop() async {
    try {
      await LocalContainerService.stop();
      await Future<void>.delayed(const Duration(seconds: 1));
      await _refreshStatus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not stop the container: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final token = await LocalContainerService.ensureAccessToken();
      final result = await LocalContainerService.testConnection(
        baseUrl: LocalContainerService.localUrl(
          _status?.port ?? LocalContainerService.defaultPort,
        ),
        token: token,
      );
      if (!mounted) return;
      setState(() => _testResult = result);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _saveAndActivate() async {
    final status = _status;
    if (status == null) return;
    setState(() => _saving = true);
    try {
      final profile = await LocalContainerService.saveAsActiveProfile(
        port: status.port,
        rootfsVersion: status.version ?? 'unknown',
        architecture: LocalContainerService.releaseArchitecture(status.abi),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${profile.name} is now the active backend.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save the profile: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'On-device container',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _loadingStatus
          ? const Center(child: CircularProgressIndicator())
          : _statusError != null
          ? _buildError(theme)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildExplainer(theme),
                const SizedBox(height: 16),
                _buildStatusCard(theme),
                const SizedBox(height: 16),
                if (!(_status?.installed ?? false)) _buildSetupCard(theme),
                if (_status?.installed ?? false) ...[
                  _buildControlsCard(theme),
                  const SizedBox(height: 16),
                  _buildConnectionCard(theme),
                ],
                const SizedBox(height: 16),
              ],
            ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 40,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(_statusError ?? 'Unavailable', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _refreshStatus,
              icon: const Icon(CupertinoIcons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExplainer(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(CupertinoIcons.cube_box, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'No-PC mode',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Runs the WorkFromPhone backend inside a Debian container on '
              'this phone (proot, no root needed). The app then talks to '
              'http://127.0.0.1:8000 directly — no PC, no Termux. '
              'First setup downloads ~150–300MB once.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(ThemeData theme) {
    final status = _status;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Container status',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  key: const Key('ondevice-refresh-status'),
                  icon: const Icon(CupertinoIcons.refresh, size: 18),
                  tooltip: 'Refresh status',
                  onPressed: _refreshStatus,
                ),
              ],
            ),
            const SizedBox(height: 4),
            _statusRow(
              'Rootfs',
              status?.installed ?? false
                  ? 'Installed (${status?.version ?? '?'})'
                  : 'Not installed',
              ok: status?.installed ?? false,
            ),
            _statusRow(
              'Backend',
              (status?.running ?? false)
                  ? (status?.healthy ?? false
                        ? 'Running · healthy'
                        : 'Running · starting…')
                  : 'Stopped',
              ok: status?.healthy ?? false,
            ),
            _statusRow(
              'proot binary',
              (status?.prootFound ?? false) ? 'Present' : 'Missing',
              ok: status?.prootFound ?? false,
            ),
            if ((status?.workspace ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Workspace: ${status!.workspace}',
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            if (!(status?.prootFound ?? true))
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'The app build is missing the patched proot binary '
                  '(jniLibs). Rebuild after running scripts/fetch-proot.sh.',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(String label, String value, {required bool ok}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            ok
                ? CupertinoIcons.check_mark_circled_solid
                : CupertinoIcons.circle,
            size: 16,
            color: ok ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupCard(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Step 1 · Download Debian',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_release == null) ...[
              const Text(
                'Resolves the signed rootfs for this device from the release manifest.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                key: const Key('ondevice-check-release'),
                onPressed: _resolvingRelease ? null : _resolveRelease,
                icon: _resolvingRelease
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(CupertinoIcons.cloud_download),
                label: Text(
                  _resolvingRelease ? 'Resolving…' : 'Check for rootfs',
                ),
              ),
              if (_releaseError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _releaseError!,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ] else ...[
              Text(
                'Rootfs v${_release!.version} · SHA-256 verified after download.',
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('ondevice-begin-setup'),
                onPressed: _settingUp ? null : _beginSetup,
                icon: const Icon(CupertinoIcons.arrow_down_circle),
                label: Text(_settingUp ? 'Setting up…' : 'Begin Setup'),
              ),
              if (_settingUp) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _setupProgress),
                const SizedBox(height: 6),
                Text(
                  'Phase: $_setupPhase · ${(_setupProgress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
              if (_setupError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _setupError!,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildControlsCard(ThemeData theme) {
    final running = _status?.running ?? false;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Step 2 · Run the backend',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('ondevice-start'),
                    onPressed: (running || _starting) ? null : _start,
                    icon: _starting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(CupertinoIcons.play),
                    label: Text(_starting ? 'Starting…' : 'Start'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('ondevice-stop'),
                    onPressed: running ? _stop : null,
                    icon: const Icon(CupertinoIcons.stop),
                    label: const Text('Stop'),
                  ),
                ),
              ],
            ),
            if (_batteryExemptKnown && !_batteryExempt && running) ...[
              const SizedBox(height: 12),
              const Text(
                'Android may kill the container in the background. '
                'Exempt the app to keep the backend alive.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await LocalContainerService.requestBatteryExemption();
                  await _refreshStatus();
                },
                icon: const Icon(CupertinoIcons.battery_0, size: 16),
                label: const Text(
                  'Allow background execution',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionCard(ThemeData theme) {
    final test = _testResult;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Step 3 · Connect the app',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: const Key('ondevice-test-connection'),
              onPressed: _testing ? null : _testConnection,
              icon: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(CupertinoIcons.wifi),
              label: Text(_testing ? 'Testing…' : 'Test Connection'),
            ),
            if (test != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    test.passed
                        ? CupertinoIcons.check_mark_circled_solid
                        : CupertinoIcons.clear_circled_solid,
                    color: test.passed ? Colors.green : Colors.red,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      test.detail,
                      style: TextStyle(
                        fontSize: 12,
                        color: test.passed ? Colors.green : Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('ondevice-save-profile'),
              onPressed: _saving ? null : _saveAndActivate,
              icon: const Icon(CupertinoIcons.arrow_down_doc),
              label: Text(_saving ? 'Saving…' : 'Save & Use On-device Backend'),
            ),
            const SizedBox(height: 6),
            FutureBuilder<String>(
              future: StorageService.loadBackendSecret(
                LocalContainerService.profileId,
                'access_token',
              ).then((value) => (value ?? '').isEmpty ? 'none yet' : 'stored'),
              builder: (context, snapshot) {
                return Text(
                  'ACCESS_TOKEN: ${snapshot.data ?? '…'} in secure storage '
                  '(mandatory even on loopback).',
                  style: const TextStyle(fontSize: 11),
                );
              },
            ),
            // Token scoping is enforced by ApiService: the saved token is only
            // ever sent to this loopback origin.
          ],
        ),
      ),
    );
  }
}
