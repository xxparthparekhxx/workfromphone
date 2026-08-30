double _doubleValue(dynamic value) => (value as num?)?.toDouble() ?? 0;
int _intValue(dynamic value) => (value as num?)?.toInt() ?? 0;

class SystemSnapshot {
  final DateTime timestamp;
  final SystemIdentity identity;
  final CpuMetrics cpu;
  final MemoryMetrics memory;
  final List<DiskMetrics> disks;
  final DiskIoMetrics diskIo;
  final NetworkMetrics network;
  final List<TemperatureMetric> temperatures;
  final List<ProcessMetric> topProcesses;
  final BackendProcessMetrics backendProcess;
  final List<GpuMetrics> gpus;

  const SystemSnapshot({
    required this.timestamp,
    required this.identity,
    required this.cpu,
    required this.memory,
    required this.disks,
    required this.diskIo,
    required this.network,
    required this.temperatures,
    required this.topProcesses,
    required this.backendProcess,
    required this.gpus,
  });

  factory SystemSnapshot.fromJson(Map<String, dynamic> json) {
    return SystemSnapshot(
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      identity: SystemIdentity.fromJson(
        json['identity'] as Map<String, dynamic>? ?? {},
      ),
      cpu: CpuMetrics.fromJson(json['cpu'] as Map<String, dynamic>? ?? {}),
      memory: MemoryMetrics.fromJson(
        json['memory'] as Map<String, dynamic>? ?? {},
      ),
      disks: ((json['disks'] as List<dynamic>?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(DiskMetrics.fromJson)
          .toList(),
      diskIo: DiskIoMetrics.fromJson(
        json['disk_io'] as Map<String, dynamic>? ?? {},
      ),
      network: NetworkMetrics.fromJson(
        json['network'] as Map<String, dynamic>? ?? {},
      ),
      temperatures: ((json['temperatures'] as List<dynamic>?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(TemperatureMetric.fromJson)
          .toList(),
      topProcesses: ((json['top_processes'] as List<dynamic>?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ProcessMetric.fromJson)
          .toList(),
      backendProcess: BackendProcessMetrics.fromJson(
        json['backend_process'] as Map<String, dynamic>? ?? {},
      ),
      gpus: ((json['gpus'] as List<dynamic>?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(GpuMetrics.fromJson)
          .toList(),
    );
  }
}

class SystemIdentity {
  final String hostname;
  final String operatingSystem;
  final String kernel;
  final String architecture;
  final String? cpuModel;
  final DateTime bootTime;
  final double uptimeSeconds;

  const SystemIdentity({
    required this.hostname,
    required this.operatingSystem,
    required this.kernel,
    required this.architecture,
    required this.cpuModel,
    required this.bootTime,
    required this.uptimeSeconds,
  });

  factory SystemIdentity.fromJson(Map<String, dynamic> json) {
    return SystemIdentity(
      hostname: json['hostname'] as String? ?? 'Linux host',
      operatingSystem: json['operating_system'] as String? ?? 'Linux',
      kernel: json['kernel'] as String? ?? '',
      architecture: json['architecture'] as String? ?? '',
      cpuModel: json['cpu_model'] as String?,
      bootTime:
          DateTime.tryParse(json['boot_time'] as String? ?? '') ??
          DateTime.now(),
      uptimeSeconds: _doubleValue(json['uptime_seconds']),
    );
  }
}

class CpuMetrics {
  final double usagePercent;
  final List<double> perCorePercent;
  final int logicalCores;
  final int? physicalCores;
  final double? frequencyMhz;
  final double? maxFrequencyMhz;
  final List<double> loadAverage;

  const CpuMetrics({
    required this.usagePercent,
    required this.perCorePercent,
    required this.logicalCores,
    required this.physicalCores,
    required this.frequencyMhz,
    required this.maxFrequencyMhz,
    required this.loadAverage,
  });

  factory CpuMetrics.fromJson(Map<String, dynamic> json) {
    return CpuMetrics(
      usagePercent: _doubleValue(json['usage_percent']),
      perCorePercent: ((json['per_core_percent'] as List<dynamic>?) ?? [])
          .map(_doubleValue)
          .toList(),
      logicalCores: _intValue(json['logical_cores']),
      physicalCores: (json['physical_cores'] as num?)?.toInt(),
      frequencyMhz: (json['frequency_mhz'] as num?)?.toDouble(),
      maxFrequencyMhz: (json['max_frequency_mhz'] as num?)?.toDouble(),
      loadAverage: [
        _doubleValue(json['load_1m']),
        _doubleValue(json['load_5m']),
        _doubleValue(json['load_15m']),
      ],
    );
  }
}

class MemoryMetrics {
  final int totalBytes;
  final int availableBytes;
  final int usedBytes;
  final double usagePercent;
  final int cachedBytes;
  final int swapTotalBytes;
  final int swapUsedBytes;
  final double swapPercent;

  const MemoryMetrics({
    required this.totalBytes,
    required this.availableBytes,
    required this.usedBytes,
    required this.usagePercent,
    required this.cachedBytes,
    required this.swapTotalBytes,
    required this.swapUsedBytes,
    required this.swapPercent,
  });

  factory MemoryMetrics.fromJson(Map<String, dynamic> json) {
    return MemoryMetrics(
      totalBytes: _intValue(json['total_bytes']),
      availableBytes: _intValue(json['available_bytes']),
      usedBytes: _intValue(json['used_bytes']),
      usagePercent: _doubleValue(json['usage_percent']),
      cachedBytes: _intValue(json['cached_bytes']),
      swapTotalBytes: _intValue(json['swap_total_bytes']),
      swapUsedBytes: _intValue(json['swap_used_bytes']),
      swapPercent: _doubleValue(json['swap_percent']),
    );
  }
}

class DiskMetrics {
  final String device;
  final String mountpoint;
  final String filesystem;
  final int totalBytes;
  final int usedBytes;
  final int freeBytes;
  final double usagePercent;

  const DiskMetrics({
    required this.device,
    required this.mountpoint,
    required this.filesystem,
    required this.totalBytes,
    required this.usedBytes,
    required this.freeBytes,
    required this.usagePercent,
  });

  factory DiskMetrics.fromJson(Map<String, dynamic> json) {
    return DiskMetrics(
      device: json['device'] as String? ?? '',
      mountpoint: json['mountpoint'] as String? ?? '',
      filesystem: json['filesystem'] as String? ?? '',
      totalBytes: _intValue(json['total_bytes']),
      usedBytes: _intValue(json['used_bytes']),
      freeBytes: _intValue(json['free_bytes']),
      usagePercent: _doubleValue(json['usage_percent']),
    );
  }
}

class DiskIoMetrics {
  final int readBytes;
  final int writeBytes;
  final double readBytesPerSecond;
  final double writeBytesPerSecond;

  const DiskIoMetrics({
    required this.readBytes,
    required this.writeBytes,
    required this.readBytesPerSecond,
    required this.writeBytesPerSecond,
  });

  factory DiskIoMetrics.fromJson(Map<String, dynamic> json) {
    return DiskIoMetrics(
      readBytes: _intValue(json['read_bytes']),
      writeBytes: _intValue(json['write_bytes']),
      readBytesPerSecond: _doubleValue(json['read_bytes_per_second']),
      writeBytesPerSecond: _doubleValue(json['write_bytes_per_second']),
    );
  }
}

class NetworkMetrics {
  final int bytesSent;
  final int bytesReceived;
  final double sentBytesPerSecond;
  final double receivedBytesPerSecond;
  final List<NetworkInterfaceMetrics> interfaces;

  const NetworkMetrics({
    required this.bytesSent,
    required this.bytesReceived,
    required this.sentBytesPerSecond,
    required this.receivedBytesPerSecond,
    required this.interfaces,
  });

  factory NetworkMetrics.fromJson(Map<String, dynamic> json) {
    return NetworkMetrics(
      bytesSent: _intValue(json['bytes_sent']),
      bytesReceived: _intValue(json['bytes_received']),
      sentBytesPerSecond: _doubleValue(json['sent_bytes_per_second']),
      receivedBytesPerSecond: _doubleValue(json['received_bytes_per_second']),
      interfaces: ((json['interfaces'] as List<dynamic>?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(NetworkInterfaceMetrics.fromJson)
          .toList(),
    );
  }
}

class NetworkInterfaceMetrics {
  final String name;
  final List<String> addresses;
  final bool isUp;
  final int speedMbps;
  final int bytesSent;
  final int bytesReceived;

  const NetworkInterfaceMetrics({
    required this.name,
    required this.addresses,
    required this.isUp,
    required this.speedMbps,
    required this.bytesSent,
    required this.bytesReceived,
  });

  factory NetworkInterfaceMetrics.fromJson(Map<String, dynamic> json) {
    return NetworkInterfaceMetrics(
      name: json['name'] as String? ?? '',
      addresses: ((json['addresses'] as List<dynamic>?) ?? [])
          .whereType<String>()
          .toList(),
      isUp: json['is_up'] as bool? ?? false,
      speedMbps: _intValue(json['speed_mbps']),
      bytesSent: _intValue(json['bytes_sent']),
      bytesReceived: _intValue(json['bytes_received']),
    );
  }
}

class TemperatureMetric {
  final String sensor;
  final String label;
  final double currentCelsius;
  final double? highCelsius;
  final double? criticalCelsius;

  const TemperatureMetric({
    required this.sensor,
    required this.label,
    required this.currentCelsius,
    required this.highCelsius,
    required this.criticalCelsius,
  });

  factory TemperatureMetric.fromJson(Map<String, dynamic> json) {
    return TemperatureMetric(
      sensor: json['sensor'] as String? ?? '',
      label: json['label'] as String? ?? '',
      currentCelsius: _doubleValue(json['current_celsius']),
      highCelsius: (json['high_celsius'] as num?)?.toDouble(),
      criticalCelsius: (json['critical_celsius'] as num?)?.toDouble(),
    );
  }
}

class ProcessMetric {
  final int pid;
  final String name;
  final String status;
  final double cpuPercent;
  final double memoryPercent;
  final int residentBytes;

  const ProcessMetric({
    required this.pid,
    required this.name,
    required this.status,
    required this.cpuPercent,
    required this.memoryPercent,
    required this.residentBytes,
  });

  factory ProcessMetric.fromJson(Map<String, dynamic> json) {
    return ProcessMetric(
      pid: _intValue(json['pid']),
      name: json['name'] as String? ?? '',
      status: json['status'] as String? ?? '',
      cpuPercent: _doubleValue(json['cpu_percent']),
      memoryPercent: _doubleValue(json['memory_percent']),
      residentBytes: _intValue(json['resident_bytes']),
    );
  }
}

class BackendProcessMetrics {
  final int pid;
  final double cpuPercent;
  final double memoryPercent;
  final int residentBytes;
  final int threads;
  final int? openFiles;

  const BackendProcessMetrics({
    required this.pid,
    required this.cpuPercent,
    required this.memoryPercent,
    required this.residentBytes,
    required this.threads,
    required this.openFiles,
  });

  factory BackendProcessMetrics.fromJson(Map<String, dynamic> json) {
    return BackendProcessMetrics(
      pid: _intValue(json['pid']),
      cpuPercent: _doubleValue(json['cpu_percent']),
      memoryPercent: _doubleValue(json['memory_percent']),
      residentBytes: _intValue(json['resident_bytes']),
      threads: _intValue(json['threads']),
      openFiles: (json['open_files'] as num?)?.toInt(),
    );
  }
}

class GpuMetrics {
  final String name;
  final double? usagePercent;
  final int? memoryUsedBytes;
  final int? memoryTotalBytes;
  final double? temperatureCelsius;
  final double? powerWatts;

  const GpuMetrics({
    required this.name,
    required this.usagePercent,
    required this.memoryUsedBytes,
    required this.memoryTotalBytes,
    required this.temperatureCelsius,
    required this.powerWatts,
  });

  factory GpuMetrics.fromJson(Map<String, dynamic> json) {
    return GpuMetrics(
      name: json['name'] as String? ?? 'GPU',
      usagePercent: (json['usage_percent'] as num?)?.toDouble(),
      memoryUsedBytes: (json['memory_used_bytes'] as num?)?.toInt(),
      memoryTotalBytes: (json['memory_total_bytes'] as num?)?.toInt(),
      temperatureCelsius: (json['temperature_celsius'] as num?)?.toDouble(),
      powerWatts: (json['power_watts'] as num?)?.toDouble(),
    );
  }
}
