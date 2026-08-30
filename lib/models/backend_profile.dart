enum BackendTransport { sshTunnel, cloudflareTunnel }

class BackendProfile {
  final String id;
  final String name;
  final String host;
  final int sshPort;
  final String username;
  final BackendTransport transport;
  final String hostKeyType;
  final String hostKeyFingerprint;
  final String? cloudflareHostname;
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
    required this.hostKeyType,
    required this.hostKeyFingerprint,
    required this.architecture,
    required this.installedVersion,
    this.cloudflareHostname,
    this.rememberPassword = false,
  });

  String get backendUrl => transport == BackendTransport.cloudflareTunnel
      ? 'https://${cloudflareHostname!}'
      : 'http://127.0.0.1:8000';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'ssh_port': sshPort,
      'username': username,
      'transport': transport.name,
      'host_key_type': hostKeyType,
      'host_key_fingerprint': hostKeyFingerprint,
      'cloudflare_hostname': cloudflareHostname,
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
      hostKeyType: json['host_key_type'] as String? ?? '',
      hostKeyFingerprint: json['host_key_fingerprint'] as String? ?? '',
      cloudflareHostname: json['cloudflare_hostname'] as String?,
      architecture: json['architecture'] as String? ?? '',
      installedVersion: json['installed_version'] as String? ?? '',
      rememberPassword: json['remember_password'] as bool? ?? false,
    );
  }
}
