import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:workfromphone/models/system_snapshot.dart';
import 'package:workfromphone/models/task_stats.dart';
import 'package:workfromphone/services/system_monitor_session.dart';

class ProjectSystemTab extends StatefulWidget {
  final String backendUrl;
  final String accessToken;
  final TaskStats stats;
  final bool active;

  const ProjectSystemTab({
    super.key,
    required this.backendUrl,
    this.accessToken = '',
    required this.stats,
    required this.active,
  });

  @override
  State<ProjectSystemTab> createState() => _ProjectSystemTabState();
}

class _ProjectSystemTabState extends State<ProjectSystemTab> {
  late SystemMonitorSession _session;
  SystemMonitorState _state = SystemMonitorState.disconnected;
  SystemSnapshot? _snapshot;
  String? _error;
  final List<double> _cpuHistory = [];
  final List<double> _memoryHistory = [];
  final List<double> _networkHistory = [];
  final List<double> _diskHistory = [];

  @override
  void initState() {
    super.initState();
    _createSession();
    if (widget.active) {
      unawaited(_session.start());
    }
  }

  @override
  void didUpdateWidget(ProjectSystemTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backendUrl != widget.backendUrl ||
        oldWidget.accessToken != widget.accessToken) {
      _session.dispose();
      _createSession();
      if (widget.active) {
        unawaited(_session.start());
      }
    } else if (!oldWidget.active && widget.active) {
      unawaited(_session.start());
    } else if (oldWidget.active && !widget.active) {
      unawaited(_session.stop());
    }
  }

  void _createSession() {
    _session = SystemMonitorSession(
      backendUrl: widget.backendUrl,
      accessToken: widget.accessToken,
      onSnapshot: (snapshot) {
        if (!mounted) return;
        setState(() {
          _snapshot = snapshot;
          _error = null;
          _appendHistory(_cpuHistory, snapshot.cpu.usagePercent);
          _appendHistory(_memoryHistory, snapshot.memory.usagePercent);
          _appendHistory(
            _networkHistory,
            snapshot.network.sentBytesPerSecond +
                snapshot.network.receivedBytesPerSecond,
          );
          _appendHistory(
            _diskHistory,
            snapshot.disks.isEmpty ? 0 : snapshot.disks.first.usagePercent,
          );
        });
      },
      onStateChange: (state) {
        if (mounted) setState(() => _state = state);
      },
      onError: (error) {
        if (mounted) setState(() => _error = error);
      },
    );
  }

  void _appendHistory(List<double> history, double value) {
    history.add(value);
    if (history.length > 30) history.removeAt(0);
  }

  Future<void> _reconnect() async {
    await _session.stop();
    if (mounted && widget.active) {
      setState(() => _error = null);
      await _session.start();
    }
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return ColoredBox(
      key: const Key('system-monitor-tab'),
      color: Theme.of(context).colorScheme.surface,
      child: RefreshIndicator(
        onRefresh: _reconnect,
        child: snapshot == null
            ? _buildEmptyState()
            : _buildDashboard(snapshot),
      ),
    );
  }

  Widget _buildEmptyState() {
    final connecting = _state == SystemMonitorState.connecting;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.58,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (connecting)
                    const CircularProgressIndicator()
                  else
                    Icon(
                      CupertinoIcons.heart,
                      size: 54,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  const SizedBox(height: 18),
                  Text(
                    connecting
                        ? 'Connecting to Linux host…'
                        : 'System monitor unavailable',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: widget.active ? _reconnect : null,
                    icon: const Icon(CupertinoIcons.refresh),
                    label: const Text('Reconnect'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDashboard(SystemSnapshot snapshot) {
    final networkRate =
        snapshot.network.sentBytesPerSecond +
        snapshot.network.receivedBytesPerSecond;
    final diskRate =
        snapshot.diskIo.readBytesPerSecond +
        snapshot.diskIo.writeBytesPerSecond;
    final primaryDisk = snapshot.disks.isNotEmpty ? snapshot.disks.first : null;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
      children: [
        _HostHeader(
          identity: snapshot.identity,
          connected: _state == SystemMonitorState.connected,
          onRefresh: _reconnect,
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          MaterialBanner(
            content: Text(_error!),
            actions: [
              TextButton(onPressed: _reconnect, child: const Text('Retry')),
            ],
          ),
        ],
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 700
                ? (constraints.maxWidth - 24) / 4
                : (constraints.maxWidth - 8) / 2;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricCard(
                  key: const Key('system-cpu-card'),
                  width: width,
                  title: 'CPU',
                  value: '${snapshot.cpu.usagePercent.toStringAsFixed(0)}%',
                  subtitle:
                      '${snapshot.cpu.logicalCores} threads · ${snapshot.cpu.loadAverage.first.toStringAsFixed(2)} load',
                  progress: snapshot.cpu.usagePercent / 100,
                  history: _cpuHistory,
                  icon: CupertinoIcons.gear,
                  color: Colors.blue,
                ),
                _MetricCard(
                  key: const Key('system-memory-card'),
                  width: width,
                  title: 'Memory',
                  value: '${snapshot.memory.usagePercent.toStringAsFixed(0)}%',
                  subtitle:
                      '${_formatBytes(snapshot.memory.usedBytes)} / ${_formatBytes(snapshot.memory.totalBytes)}',
                  progress: snapshot.memory.usagePercent / 100,
                  history: _memoryHistory,
                  icon: CupertinoIcons.archivebox,
                  color: Colors.purple,
                ),
                _MetricCard(
                  width: width,
                  title: 'Network',
                  value: _formatRate(networkRate),
                  subtitle:
                      '↓ ${_formatRate(snapshot.network.receivedBytesPerSecond)}  ↑ ${_formatRate(snapshot.network.sentBytesPerSecond)}',
                  history: _networkHistory,
                  icon: CupertinoIcons.arrow_up_arrow_down_circle,
                  color: Colors.teal,
                ),
                _MetricCard(
                  width: width,
                  title: 'Disk',
                  value: primaryDisk == null
                      ? _formatRate(diskRate)
                      : '${primaryDisk.usagePercent.toStringAsFixed(0)}%',
                  subtitle:
                      'R ${_formatRate(snapshot.diskIo.readBytesPerSecond)} · W ${_formatRate(snapshot.diskIo.writeBytesPerSecond)}',
                  progress: primaryDisk == null
                      ? null
                      : primaryDisk.usagePercent / 100,
                  history: _diskHistory,
                  icon: CupertinoIcons.archivebox,
                  color: Colors.orange,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        _buildTokenUsage(),
        const SizedBox(height: 10),
        _buildCpuDetails(snapshot),
        const SizedBox(height: 10),
        if (snapshot.gpus.isNotEmpty) ...[
          _buildGpuDetails(snapshot),
          const SizedBox(height: 10),
        ],
        _buildStorage(snapshot),
        const SizedBox(height: 10),
        _buildNetwork(snapshot),
        const SizedBox(height: 10),
        if (snapshot.temperatures.isNotEmpty) ...[
          _buildTemperatures(snapshot),
          const SizedBox(height: 10),
        ],
        _buildProcesses(snapshot),
        const SizedBox(height: 10),
        _buildBackend(snapshot),
      ],
    );
  }

  Widget _buildTokenUsage() {
    final stats = widget.stats;
    final accuracy = stats.usageIsEstimated ? 'Estimated' : 'Provider reported';
    return _SectionCard(
      key: const Key('session-token-usage'),
      title: 'Current conversation',
      icon: CupertinoIcons.chart_bar,
      trailing: Chip(
        visualDensity: VisualDensity.compact,
        label: Text(accuracy, style: const TextStyle(fontSize: 10)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _ValueCell(
                label: 'Session tokens',
                value: stats.formattedSessionTokens,
              ),
              _ValueCell(
                label: 'Current context',
                value: stats.formattedContextRatio,
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: (stats.contextUsagePercent / 100).clamp(0.0, 1.0),
            minHeight: 7,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _TinyStat('Prompt', _formatCount(stats.promptTokens)),
              _TinyStat('Completion', _formatCount(stats.completionTokens)),
              _TinyStat('Reasoning', _formatCount(stats.reasoningTokens)),
              _TinyStat('Cached', _formatCount(stats.cachedTokens)),
              _TinyStat('Cost', stats.formattedCost),
              _TinyStat('Speed', stats.formattedTps),
              _TinyStat('Tools', '${stats.toolCallsCount}'),
              _TinyStat('Steps', '${stats.stepsCount}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCpuDetails(SystemSnapshot snapshot) {
    return _SectionCard(
      title: 'Processor',
      icon: CupertinoIcons.cube_box,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            snapshot.identity.cpuModel ?? 'Processor information unavailable',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '${snapshot.cpu.physicalCores ?? '—'} cores · '
            '${snapshot.cpu.logicalCores} threads'
            '${snapshot.cpu.frequencyMhz == null ? '' : ' · ${snapshot.cpu.frequencyMhz!.toStringAsFixed(0)} MHz'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 90,
              mainAxisExtent: 38,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemCount: snapshot.cpu.perCorePercent.length,
            itemBuilder: (context, index) {
              final usage = snapshot.cpu.perCorePercent[index];
              return Tooltip(
                message: 'CPU ${index + 1}: ${usage.toStringAsFixed(1)}%',
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${index + 1}',
                        style: const TextStyle(fontSize: 10),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: usage / 100,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGpuDetails(SystemSnapshot snapshot) {
    return _SectionCard(
      title: 'Graphics',
      icon: CupertinoIcons.gamecontroller,
      child: Column(
        children: snapshot.gpus.map((gpu) {
          final memoryPercent =
              gpu.memoryUsedBytes != null && (gpu.memoryTotalBytes ?? 0) > 0
              ? gpu.memoryUsedBytes! / gpu.memoryTotalBytes!
              : null;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(gpu.name),
            subtitle: Text(
              [
                if (gpu.memoryUsedBytes != null)
                  '${_formatBytes(gpu.memoryUsedBytes!)} / ${_formatBytes(gpu.memoryTotalBytes ?? 0)}',
                if (gpu.temperatureCelsius != null)
                  '${gpu.temperatureCelsius!.toStringAsFixed(0)}°C',
                if (gpu.powerWatts != null)
                  '${gpu.powerWatts!.toStringAsFixed(0)} W',
              ].join(' · '),
            ),
            trailing: Text(
              gpu.usagePercent == null
                  ? '—'
                  : '${gpu.usagePercent!.toStringAsFixed(0)}%',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            leading: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                value: gpu.usagePercent != null
                    ? gpu.usagePercent! / 100
                    : memoryPercent,
                strokeWidth: 5,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStorage(SystemSnapshot snapshot) {
    return _SectionCard(
      title: 'Storage',
      icon: CupertinoIcons.cube_box,
      child: Column(
        children: snapshot.disks.map((disk) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        disk.mountpoint,
                        style: const TextStyle(fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${_formatBytes(disk.usedBytes)} / ${_formatBytes(disk.totalBytes)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                LinearProgressIndicator(
                  value: disk.usagePercent / 100,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(5),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildNetwork(SystemSnapshot snapshot) {
    final active = snapshot.network.interfaces.where(
      (interface) => interface.isUp,
    );
    return _SectionCard(
      title: 'Network interfaces',
      icon: CupertinoIcons.globe,
      child: Column(
        children: active.map((interface) {
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(CupertinoIcons.link, size: 20),
            title: Text(interface.name),
            subtitle: Text(
              interface.addresses.isEmpty
                  ? 'No address'
                  : interface.addresses.join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
            trailing: Text(
              interface.speedMbps > 0 ? '${interface.speedMbps} Mbps' : 'UP',
              style: const TextStyle(fontSize: 11),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTemperatures(SystemSnapshot snapshot) {
    return _SectionCard(
      title: 'Temperatures',
      icon: CupertinoIcons.thermometer,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: snapshot.temperatures.map((temperature) {
          return Chip(
            avatar: const Icon(CupertinoIcons.thermometer, size: 16),
            label: Text(
              '${temperature.label}: '
              '${temperature.currentCelsius.toStringAsFixed(0)}°C',
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildProcesses(SystemSnapshot snapshot) {
    return _SectionCard(
      title: 'Top processes',
      icon: CupertinoIcons.list_bullet,
      child: Column(
        children: snapshot.topProcesses.map((process) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    '${process.pid}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(process.name, overflow: TextOverflow.ellipsis),
                ),
                SizedBox(
                  width: 58,
                  child: Text(
                    '${process.cpuPercent.toStringAsFixed(1)}% CPU',
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 54,
                  child: Text(
                    _formatBytes(process.residentBytes),
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBackend(SystemSnapshot snapshot) {
    final backend = snapshot.backendProcess;
    return _SectionCard(
      title: 'WorkFromPhone backend',
      icon: CupertinoIcons.cube_box,
      child: Wrap(
        spacing: 20,
        runSpacing: 10,
        children: [
          _TinyStat('PID', '${backend.pid}'),
          _TinyStat('CPU', '${backend.cpuPercent.toStringAsFixed(1)}%'),
          _TinyStat('Memory', _formatBytes(backend.residentBytes)),
          _TinyStat('Threads', '${backend.threads}'),
          _TinyStat('Open files', '${backend.openFiles ?? '—'}'),
        ],
      ),
    );
  }
}

class _HostHeader extends StatelessWidget {
  final SystemIdentity identity;
  final bool connected;
  final VoidCallback onRefresh;

  const _HostHeader({
    required this.identity,
    required this.connected,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: connected
              ? Colors.green.withValues(alpha: 0.14)
              : Colors.orange.withValues(alpha: 0.14),
          child: Icon(
            CupertinoIcons.desktopcomputer,
            color: connected ? Colors.green : Colors.orange,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                identity.hostname,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                '${identity.operatingSystem} · ${identity.architecture} · '
                'up ${_formatDuration(identity.uptimeSeconds)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onRefresh,
          tooltip: 'Reconnect monitor',
          icon: const Icon(CupertinoIcons.refresh),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final double width;
  final String title;
  final String value;
  final String subtitle;
  final double? progress;
  final List<double> history;
  final IconData icon;
  final Color color;

  const _MetricCard({
    super.key,
    required this.width,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.history,
    required this.icon,
    required this.color,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 128,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 17, color: color),
                  const SizedBox(width: 6),
                  Text(title, style: const TextStyle(fontSize: 12)),
                  const Spacer(),
                  Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                height: 32,
                width: double.infinity,
                child: CustomPaint(
                  painter: _SparklinePainter(
                    values: history,
                    color: color,
                    fixedMaximum: progress == null ? null : 100,
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double? fixedMaximum;

  const _SparklinePainter({
    required this.values,
    required this.color,
    this.fixedMaximum,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maximum =
        fixedMaximum ??
        math.max(values.reduce(math.max), values.reduce(math.min) + 1);
    final minimum = fixedMaximum == null ? values.reduce(math.min) : 0.0;
    final range = math.max(0.001, maximum - minimum);
    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = values.length == 1
          ? size.width
          : index / (values.length - 1) * size.width;
      final y = size.height - ((values[index] - minimum) / range * size.height);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return true;
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 13),
            child,
          ],
        ),
      ),
    );
  }
}

class _ValueCell extends StatelessWidget {
  final String label;
  final String value;

  const _ValueCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _TinyStat extends StatelessWidget {
  final String label;
  final String value;

  const _TinyStat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

String _formatBytes(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value.abs() >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

String _formatRate(num bytes) => '${_formatBytes(bytes)}/s';

String _formatCount(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(2)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
  return '$value';
}

String _formatDuration(double seconds) {
  final duration = Duration(seconds: seconds.round());
  final days = duration.inDays;
  final hours = duration.inHours.remainder(24);
  final minutes = duration.inMinutes.remainder(60);
  if (days > 0) return '${days}d ${hours}h';
  if (duration.inHours > 0) return '${duration.inHours}h ${minutes}m';
  return '${duration.inMinutes}m';
}
