enum BackendTransport { sshTunnel, cloudflareTunnel, directHttp }

enum BackendProfileType { devHost, centralHub }

class BackendProfile {
  final String id;
  final String name;
  final String host;
  final int sshPort;
  final String username;
  final BackendTransport transport;
  final BackendProfileType type;
  final String hostKeyType;
  final String hostKeyFingerprint;
  final String? cloudflareHostname;
  final String? directUrl;
  final String architecture;
  final String installedVersion;
  final bool rememberPassword;

  const BackendProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.sshPort,
    required this.username,
    required this.transport,
    this.type = BackendProfileType.devHost,
    required this.hostKeyType,
    required this.hostKeyFingerprint,
    required this.architecture,
    required this.installedVersion,
    this.cloudflareHostname,
    this.directUrl,
    this.rememberPassword = false,
  });

  bool get isHub => type == BackendProfileType.centralHub;

  String get backendUrl {
    if (transport == BackendTransport.directHttp &&
        directUrl != null &&
        directUrl!.isNotEmpty) {
      return directUrl!;
    }
    if (transport == BackendTransport.cloudflareTunnel &&
        cloudflareHostname != null &&
        cloudflareHostname!.isNotEmpty) {
      return 'https://$cloudflareHostname';
    }
    return 'http://127.0.0.1:8000';
  }

  BackendProfile copyWith({
    String? id,
    String? name,
    String? host,
    int? sshPort,
    String? username,
    BackendTransport? transport,
    BackendProfileType? type,
    String? hostKeyType,
    String? hostKeyFingerprint,
    String? cloudflareHostname,
    String? directUrl,
    String? architecture,
    String? installedVersion,
    bool? rememberPassword,
  }) {
    return BackendProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      sshPort: sshPort ?? this.sshPort,
      username: username ?? this.username,
      transport: transport ?? this.transport,
      type: type ?? this.type,
      hostKeyType: hostKeyType ?? this.hostKeyType,
      hostKeyFingerprint: hostKeyFingerprint ?? this.hostKeyFingerprint,
      architecture: architecture ?? this.architecture,
      installedVersion: installedVersion ?? this.installedVersion,
      cloudflareHostname: cloudflareHostname ?? this.cloudflareHostname,
      directUrl: directUrl ?? this.directUrl,
      rememberPassword: rememberPassword ?? this.rememberPassword,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'ssh_port': sshPort,
      'username': username,
      'transport': transport.name,
      'type': type.name,
      'host_key_type': hostKeyType,
      'host_key_fingerprint': hostKeyFingerprint,
      'cloudflare_hostname': cloudflareHostname,
      'direct_url': directUrl,
      'architecture': architecture,
      'installed_version': installedVersion,
      'remember_password': rememberPassword,
    };
  }

  factory BackendProfile.fromJson(Map<String, dynamic> json) {
    return BackendProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Linux host',
      host: json['host'] as String? ?? '',
      sshPort: json['ssh_port'] as int? ?? 22,
      username: json['username'] as String? ?? '',
      transport: BackendTransport.values.firstWhere(
        (value) => value.name == json['transport'],
        orElse: () => BackendTransport.sshTunnel,
      ),
      type: BackendProfileType.values.firstWhere(
        (value) => value.name == json['type'],
        orElse: () => BackendProfileType.devHost,
      ),
      hostKeyType: json['host_key_type'] as String? ?? '',
      hostKeyFingerprint: json['host_key_fingerprint'] as String? ?? '',
      cloudflareHostname: json['cloudflare_hostname'] as String?,
      directUrl: json['direct_url'] as String?,
      architecture: json['architecture'] as String? ?? '',
      installedVersion: json['installed_version'] as String? ?? '',
      rememberPassword: json['remember_password'] as bool? ?? false,
    );
  }
}
