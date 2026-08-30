import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dartssh2/dartssh2.dart';
import 'package:http/http.dart' as http;
import 'package:workfromphone/models/backend_profile.dart';

typedef HostKeyVerifier = Future<bool> Function(
  String keyType,
  String fingerprint,
);

class RemoteSetupRequest {
  final String name;
  final String host;
  final int sshPort;
  final String username;
  final String password;
  final bool rememberPassword;
  final BackendTransport transport;
  final String? cloudflareHostname;
  final String? cloudflareTunnelToken;

  const RemoteSetupRequest({
    required this.name,
    required this.host,
    required this.sshPort,
    required this.username,
    required this.password,
    required this.rememberPassword,
    required this.transport,
    this.cloudflareHostname,
    this.cloudflareTunnelToken,
  });
}

class RemoteSetupResult {
  final BackendProfile profile;
  final String backendAccessToken;
  final SSHClient? sshClient;

  const RemoteSetupResult({
    required this.profile,
    required this.backendAccessToken,
    required this.sshClient,
  });
}

class BackendRelease {
  final String version;
  final String url;
  final String sha256;

  const BackendRelease({
    required this.version,
    required this.url,
    required this.sha256,
  });
}

class RemoteSetupService {
  static const releaseRepository = String.fromEnvironment(
    'WFP_BACKEND_RELEASE_REPO',
  );

  Future<SSHClient> connectExisting(
    BackendProfile profile, {
    required String password,
  }) async {
    final socket = await SSHSocket.connect(
      profile.host,
      profile.sshPort,
      timeout: const Duration(seconds: 15),
    );
    final client = SSHClient(
      socket,
      username: profile.username,
      onPasswordRequest: () => password,
      onUserInfoRequest: (info) => info.prompts.map((_) => password).toList(),
      onVerifyHostKey: (type, fingerprint) {
        return type == profile.hostKeyType &&
            utf8.decode(fingerprint) == profile.hostKeyFingerprint;
      },
      handshakeTimeout: const Duration(seconds: 20),
      authTimeout: const Duration(seconds: 30),
    );
    try {
      await _runChecked(client, 'true');
      return client;
    } catch (_) {
      client.close();
      rethrow;
    }
  }

  Future<RemoteSetupResult> install({
    required RemoteSetupRequest request,
    required HostKeyVerifier verifyHostKey,
    required void Function(String message) onProgress,
  }) async {
    onProgress('Connecting to ${request.host}:${request.sshPort}…');
    final socket = await SSHSocket.connect(
      request.host,
      request.sshPort,
      timeout: const Duration(seconds: 15),
    );

    String hostKeyType = '';
    String hostKeyFingerprint = '';
    final client = SSHClient(
      socket,
      username: request.username,
      onPasswordRequest: () => request.password,
      onUserInfoRequest: (info) {
        return info.prompts.map((_) => request.password).toList();
      },
      onVerifyHostKey: (type, fingerprint) async {
        hostKeyType = type;
        hostKeyFingerprint = utf8.decode(fingerprint);
        return verifyHostKey(type, hostKeyFingerprint);
      },
      handshakeTimeout: const Duration(seconds: 20),
      authTimeout: const Duration(seconds: 30),
    );

    try {
      onProgress('Verifying Linux host and architecture…');
      final probe = await _runChecked(
        client,
        "printf '%s\\n' \"\$(uname -s)\" \"\$(uname -m)\" "
        "\"\$(command -v systemctl || true)\"",
      );
      final probeLines = const LineSplitter().convert(probe);
      if (probeLines.isEmpty || probeLines.first.trim() != 'Linux') {
        throw const FormatException(
          'The remote backend is supported only on Linux.',
        );
      }
      if (probeLines.length < 3 || probeLines[2].trim().isEmpty) {
        throw const FormatException(
          'systemd is required to keep the backend running.',
        );
      }
      final architecture = _normalizeArchitecture(probeLines[1].trim());

      onProgress('Resolving the latest compatible backend release…');
      final release = await _fetchRelease(architecture);
      final backendAccessToken = _generateToken();

      onProgress('Installing WorkFromPhone backend ${release.version}…');
      await _installBackend(
        client,
        release: release,
        accessToken: backendAccessToken,
      );

      if (request.transport == BackendTransport.cloudflareTunnel) {
        final hostname = request.cloudflareHostname?.trim() ?? '';
        final tunnelToken = request.cloudflareTunnelToken?.trim() ?? '';
        if (hostname.isEmpty || tunnelToken.isEmpty) {
          throw const FormatException(
            'A Cloudflare hostname and named-tunnel token are required.',
          );
        }
        onProgress('Installing and starting Cloudflare Tunnel…');
        await _installCloudflared(
          client,
          architecture: architecture,
          tunnelToken: tunnelToken,
        );
      }

      onProgress('Backend installation is healthy.');
      final profileId =
          '${request.username}@${request.host}:${request.sshPort}';
      final profile = BackendProfile(
        id: base64Url.encode(utf8.encode(profileId)).replaceAll('=', ''),
        name: request.name.trim().isEmpty ? request.host : request.name.trim(),
        host: request.host.trim(),
        sshPort: request.sshPort,
        username: request.username.trim(),
        transport: request.transport,
        hostKeyType: hostKeyType,
        hostKeyFingerprint: hostKeyFingerprint,
        cloudflareHostname: request.cloudflareHostname?.trim(),
        architecture: architecture,
        installedVersion: release.version,
        rememberPassword: request.rememberPassword,
      );

      if (request.transport == BackendTransport.cloudflareTunnel) {
        client.close();
        await client.done;
      }
      return RemoteSetupResult(
        profile: profile,
        backendAccessToken: backendAccessToken,
        sshClient: request.transport == BackendTransport.sshTunnel
            ? client
            : null,
      );
    } catch (_) {
      client.close();
      rethrow;
    }
  }

  Future<BackendRelease> _fetchRelease(String architecture) async {
    if (releaseRepository.trim().isEmpty) {
      throw const FormatException(
        'No backend release repository is configured. Build the app with '
        '--dart-define=WFP_BACKEND_RELEASE_REPO=owner/repository.',
      );
    }
    final manifestUri = Uri.parse(
      'https://github.com/$releaseRepository/releases/latest/download/'
      'backend-manifest.json',
    );
    final response = await http
        .get(manifestUri)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw HttpException(
        'Could not download backend release manifest '
        '(HTTP ${response.statusCode}).',
      );
    }
    final manifest = jsonDecode(response.body) as Map<String, dynamic>;
    final artifacts = manifest['artifacts'] as Map<String, dynamic>? ?? {};
    final artifact = artifacts[architecture] as Map<String, dynamic>?;
    if (artifact == null) {
      throw FormatException(
        'Backend release does not support Linux $architecture.',
      );
    }
    return BackendRelease(
      version: manifest['version'] as String? ?? 'unknown',
      url: artifact['url'] as String? ?? '',
      sha256: artifact['sha256'] as String? ?? '',
    );
  }

  Future<void> _installBackend(
    SSHClient client, {
    required BackendRelease release,
    required String accessToken,
  }) {
    if (release.url.isEmpty || release.sha256.length != 64) {
      throw const FormatException('Backend release manifest is invalid.');
    }
    final version = _shellEscape(release.version);
    final url = _shellEscape(release.url);
    final checksum = _shellEscape(release.sha256);
    final token = _shellEscape(accessToken);
    final script =
        '''
set -eu
base="\$HOME/.local/share/workfromphone"
version_dir="\$base/server/$version"
archive="\$(mktemp)"
mkdir -p "\$version_dir" "\$HOME/.config/workfromphone" "\$HOME/.config/systemd/user"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL $url -o "\$archive"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "\$archive" $url
else
  echo "curl or wget is required" >&2
  exit 12
fi
printf '%s  %s\\n' $checksum "\$archive" | sha256sum -c -
tar -xzf "\$archive" -C "\$version_dir"
chmod 700 "\$version_dir/workfromphone-backend"
ln -sfn "\$version_dir" "\$base/current"
{
  printf 'HOST=127.0.0.1\\n'
  printf 'PORT=8000\\n'
  printf 'DEBUG=false\\n'
  printf 'ACCESS_TOKEN=%s\\n' $token
} > "\$HOME/.config/workfromphone/backend.env"
chmod 600 "\$HOME/.config/workfromphone/backend.env"
cat > "\$HOME/.config/systemd/user/workfromphone-backend.service" <<'EOF'
[Unit]
Description=WorkFromPhone Backend
After=network-online.target

[Service]
Type=simple
EnvironmentFile=%h/.config/workfromphone/backend.env
ExecStart=%h/.local/share/workfromphone/current/workfromphone-backend
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now workfromphone-backend.service
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if command -v curl >/dev/null 2>&1 &&
     curl -fsS http://127.0.0.1:8000/api/v1/health >/dev/null; then
    rm -f "\$archive"
    exit 0
  fi
  sleep 1
done
systemctl --user status workfromphone-backend.service --no-pager >&2 || true
exit 13
''';
    return _runChecked(client, 'sh -lc ${_shellEscape(script)}').then((_) {});
  }

  Future<void> _installCloudflared(
    SSHClient client, {
    required String architecture,
    required String tunnelToken,
  }) {
    final cloudflareArchitecture = architecture == 'aarch64'
        ? 'arm64'
        : 'amd64';
    final downloadUrl =
        'https://github.com/cloudflare/cloudflared/releases/latest/download/'
        'cloudflared-linux-$cloudflareArchitecture';
    final script =
        '''
set -eu
mkdir -p "\$HOME/.local/bin" "\$HOME/.config/workfromphone" "\$HOME/.config/systemd/user"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL ${_shellEscape(downloadUrl)} -o "\$HOME/.local/bin/cloudflared"
else
  wget -qO "\$HOME/.local/bin/cloudflared" ${_shellEscape(downloadUrl)}
fi
chmod 700 "\$HOME/.local/bin/cloudflared"
printf 'CLOUDFLARE_TUNNEL_TOKEN=%s\\n' ${_shellEscape(tunnelToken)} > "\$HOME/.config/workfromphone/cloudflared.env"
chmod 600 "\$HOME/.config/workfromphone/cloudflared.env"
cat > "\$HOME/.config/systemd/user/workfromphone-tunnel.service" <<'EOF'
[Unit]
Description=WorkFromPhone Cloudflare Tunnel
After=network-online.target workfromphone-backend.service

[Service]
Type=simple
EnvironmentFile=%h/.config/workfromphone/cloudflared.env
ExecStart=%h/.local/bin/cloudflared tunnel --no-autoupdate run --token \${CLOUDFLARE_TUNNEL_TOKEN}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now workfromphone-tunnel.service
systemctl --user is-active --quiet workfromphone-tunnel.service
''';
    return _runChecked(client, 'sh -lc ${_shellEscape(script)}').then((_) {});
  }

  Future<String> _runChecked(SSHClient client, String command) async {
    final result = await client.runWithResult(command);
    final stdout = utf8.decode(result.stdout, allowMalformed: true).trim();
    final stderr = utf8.decode(result.stderr, allowMalformed: true).trim();
    if ((result.exitCode ?? 1) != 0) {
      throw ProcessException(
        'ssh',
        [command],
        stderr.isEmpty ? stdout : stderr,
        result.exitCode ?? -1,
      );
    }
    return stdout;
  }

  String _normalizeArchitecture(String architecture) {
    switch (architecture.toLowerCase()) {
      case 'x86_64':
      case 'amd64':
        return 'x86_64';
      case 'aarch64':
      case 'arm64':
        return 'aarch64';
      default:
        throw FormatException('Unsupported Linux architecture: $architecture');
    }
  }

  String _generateToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String _shellEscape(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";
}

class SshTunnelManager {
  SshTunnelManager._();

  static final instance = SshTunnelManager._();

  SSHClient? _client;
  ServerSocket? _server;
  final Set<Socket> _localSockets = {};

  int? get localPort => _server?.port;
  bool get isConnected => _client?.isClosed == false && _server != null;

  Future<int> start(SSHClient client, {int remotePort = 8000}) async {
    await close();
    _client = client;
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((localSocket) async {
      _localSockets.add(localSocket);
      try {
        final remote = await client.forwardLocal('127.0.0.1', remotePort);
        localSocket.listen(
          remote.sink.add,
          onDone: remote.close,
          onError: (_) => remote.destroy(),
          cancelOnError: true,
        );
        remote.stream.listen(
          localSocket.add,
          onDone: localSocket.destroy,
          onError: (_) => localSocket.destroy(),
          cancelOnError: true,
        );
        unawaited(
          remote.done.whenComplete(() {
            _localSockets.remove(localSocket);
            localSocket.destroy();
          }),
        );
      } catch (_) {
        _localSockets.remove(localSocket);
        localSocket.destroy();
      }
    });
    return server.port;
  }

  Future<void> close() async {
    for (final socket in _localSockets) {
      socket.destroy();
    }
    _localSockets.clear();
    await _server?.close();
    _server = null;
    _client?.close();
    _client = null;
  }
}
