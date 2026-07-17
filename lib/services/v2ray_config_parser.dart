import 'dart:convert';

enum V2RayProtocol {
  vmess,
  vless,
  trojan,
  shadowsocks,
  unknown,
}

class ParsedV2RayConfig {
  final V2RayProtocol protocol;
  final String name;
  final String address;
  final int port;
  final String jsonConfig;
  final Map<String, dynamic> metadata;

  ParsedV2RayConfig({
    required this.protocol,
    required this.name,
    required this.address,
    required this.port,
    required this.jsonConfig,
    this.metadata = const {},
  });
}

class V2RayConfigParser {
  V2RayConfigParser._();

  static ParsedV2RayConfig? parse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    try {
      if (trimmed.startsWith('{')) {
        return _parseRawJson(trimmed);
      }
      if (trimmed.startsWith('vmess://')) {
        return _parseVmess(trimmed);
      }
      if (trimmed.startsWith('vless://')) {
        return _parseVless(trimmed);
      }
      if (trimmed.startsWith('trojan://')) {
        return _parseTrojan(trimmed);
      }
      if (trimmed.startsWith('ss://')) {
        return _parseShadowsocks(trimmed);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static List<ParsedV2RayConfig> parseSubscription(String response) {
    if (response.trim().isEmpty) return [];

    try {
      final decoded = utf8.decode(base64.decode(response.trim()));
      return decoded
          .split(RegExp(r'[\r\n]+'))
          .where((line) => line.trim().isNotEmpty)
          .map((line) => parse(line.trim()))
          .whereType<ParsedV2RayConfig>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static ParsedV2RayConfig? _parseRawJson(String input) {
    final json = jsonDecode(input) as Map<String, dynamic>;
    final outbounds = (json['outbounds'] as List?) ?? [];
    if (outbounds.isEmpty) return null;

    final firstOutbound = outbounds[0] as Map<String, dynamic>;
    final protocolStr = (firstOutbound['protocol'] as String?) ?? 'unknown';
    final protocol = _protocolFromString(protocolStr);

    final settings = (firstOutbound['settings'] as Map<String, dynamic>?) ?? {};
    String address = '';
    int port = 10808;

    final vnext = settings['vnext'] as List?;
    if (vnext != null && vnext.isNotEmpty) {
      final server = vnext[0] as Map<String, dynamic>;
      address = (server['address'] as String?) ?? '';
      port = (server['port'] as num?)?.toInt() ?? 10808;
    }

    final servers = settings['servers'] as List?;
    if (servers != null && servers.isNotEmpty) {
      final server = servers[0] as Map<String, dynamic>;
      address = (server['address'] as String?) ?? address;
      port = (server['port'] as num?)?.toInt() ?? port;
    }

    final name = _extractNameFromJson(json);

    return ParsedV2RayConfig(
      protocol: protocol,
      name: name,
      address: address,
      port: port,
      jsonConfig: input,
      metadata: {'rawJson': json},
    );
  }

  static ParsedV2RayConfig? _parseVmess(String input) {
    final encoded = input.substring('vmess://'.length);
    final decoded = utf8.decode(base64.decode(encoded));
    final json = jsonDecode(decoded) as Map<String, dynamic>;

    final address = (json['add'] as String?) ?? '';
    final port = int.tryParse((json['port'] as String?) ?? '') ?? 0;
    final name = (json['ps'] as String?) ?? '';

    final streamSettings = _buildVmessStreamSettings(json);

    final outbound = {
      'protocol': 'vmess',
      'settings': {
        'vnext': [
          {
            'address': address,
            'port': port,
            'users': [
              {
                'id': json['id'] ?? '',
                'alterId': int.tryParse((json['aid'] as String?) ?? '0') ?? 0,
                'security': 'auto',
              },
            ],
          },
        ],
      },
      'streamSettings': streamSettings,
    };

    final fullConfig = _buildFullConfig(outbound);

    return ParsedV2RayConfig(
      protocol: V2RayProtocol.vmess,
      name: name,
      address: address,
      port: port,
      jsonConfig: jsonEncode(fullConfig),
      metadata: json,
    );
  }

  static Map<String, dynamic> _buildVmessStreamSettings(Map<String, dynamic> json) {
    final network = (json['net'] as String?) ?? 'tcp';
    final tls = (json['tls'] as String?) ?? '';
    final host = (json['host'] as String?) ?? '';
    final path = (json['path'] as String?) ?? '';
    final sni = (json['sni'] as String?) ?? (json['host'] as String?) ?? '';
    final type = (json['type'] as String?) ?? 'none';

    final streamSettings = <String, dynamic>{
      'network': network,
    };

    if (tls == 'tls') {
      streamSettings['security'] = 'tls';
      streamSettings['tlsSettings'] = {
        'allowInsecure': false,
        if (sni.isNotEmpty) 'serverName': sni,
      };
    }

    switch (network) {
      case 'ws':
        final wsSettings = <String, dynamic>{
          'path': path,
        };
        if (host.isNotEmpty) {
          wsSettings['headers'] = {'Host': host};
        }
        streamSettings['wsSettings'] = wsSettings;
        break;
      case 'grpc':
        final serviceName = (json['path'] as String?) ?? '';
        streamSettings['grpcSettings'] = {
          if (serviceName.isNotEmpty) 'serviceName': serviceName,
        };
        break;
      case 'h2':
      case 'http':
        final h2Settings = <String, dynamic>{
          'path': path,
        };
        if (host.isNotEmpty) {
          h2Settings['host'] = [host];
        }
        streamSettings['httpSettings'] = h2Settings;
        break;
      case 'tcp':
        if (type == 'http') {
          final tcpSettings = <String, dynamic>{
            'header': {
              'type': 'http',
              'request': {
                'path': [path],
                'headers': {
                  if (host.isNotEmpty) 'Host': [host],
                },
              },
            },
          };
          streamSettings['tcpSettings'] = tcpSettings;
        }
        break;
    }

    return streamSettings;
  }

  static ParsedV2RayConfig? _parseVless(String input) {
    final raw = input.substring('vless://'.length);

    String uuid;
    String address;
    int port;
    String name = '';
    final params = <String, String>{};

    final hashIndex = raw.indexOf('#');
    if (hashIndex != -1) {
      name = Uri.decodeComponent(raw.substring(hashIndex + 1));
      raw.substring(0, hashIndex);
    }

    final clean = hashIndex != -1 ? raw.substring(0, hashIndex) : raw;

    final questionIndex = clean.indexOf('?');
    final paramStr = questionIndex != -1 ? clean.substring(questionIndex + 1) : '';
    final authority = questionIndex != -1 ? clean.substring(0, questionIndex) : clean;

    if (paramStr.isNotEmpty) {
      for (final part in paramStr.split('&')) {
        final eqIdx = part.indexOf('=');
        if (eqIdx != -1) {
          params[part.substring(0, eqIdx)] = Uri.decodeComponent(part.substring(eqIdx + 1));
        }
      }
    }

    final atIdx = authority.indexOf('@');
    if (atIdx == -1) return null;

    uuid = authority.substring(0, atIdx);
    final hostPort = authority.substring(atIdx + 1);

    final lastColon = hostPort.lastIndexOf(':');
    if (lastColon == -1) return null;

    address = hostPort.substring(0, lastColon);
    port = int.tryParse(hostPort.substring(lastColon + 1)) ?? 0;

    if (address.isEmpty || port == 0) return null;

    final security = params['security'] ?? 'none';
    final network = params['type'] ?? 'tcp';
    final host = params['host'] ?? '';
    final path = params['path'] ?? '';
    final sni = params['sni'] ?? host;
    final fingerprint = params['fp'] ?? '';
    final publicKey = params['pbk'] ?? '';
    final shortId = params['sid'] ?? '';
    final flow = params['flow'] ?? '';
    final serviceName = params['serviceName'] ?? '';

    final streamSettings = <String, dynamic>{
      'network': network,
    };

    if (security == 'tls') {
      streamSettings['security'] = 'tls';
      final tlsSettings = <String, dynamic>{
        'allowInsecure': false,
      };
      if (sni.isNotEmpty) tlsSettings['serverName'] = sni;
      if (fingerprint.isNotEmpty) tlsSettings['fingerprint'] = fingerprint;
      streamSettings['tlsSettings'] = tlsSettings;
    } else if (security == 'reality') {
      streamSettings['security'] = 'reality';
      streamSettings['realitySettings'] = {
        'show': false,
        if (sni.isNotEmpty) 'serverName': sni,
        if (fingerprint.isNotEmpty) 'fingerprint': fingerprint,
        if (publicKey.isNotEmpty) 'publicKey': publicKey,
        if (shortId.isNotEmpty) 'shortId': shortId,
      };
    }

    switch (network) {
      case 'ws':
        final wsSettings = <String, dynamic>{
          'path': path,
        };
        if (host.isNotEmpty) {
          wsSettings['headers'] = {'Host': host};
        }
        streamSettings['wsSettings'] = wsSettings;
        break;
      case 'grpc':
        streamSettings['grpcSettings'] = {
          if (serviceName.isNotEmpty) 'serviceName': serviceName,
        };
        break;
      case 'h2':
        final h2Settings = <String, dynamic>{
          'path': path,
        };
        if (host.isNotEmpty) {
          h2Settings['host'] = [host];
        }
        streamSettings['httpSettings'] = h2Settings;
        break;
    }

    final user = <String, dynamic>{
      'id': uuid,
      'encryption': params['encryption'] ?? 'none',
    };
    if (flow.isNotEmpty) {
      user['flow'] = flow;
    }

    final outbound = {
      'protocol': 'vless',
      'settings': {
        'vnext': [
          {
            'address': address,
            'port': port,
            'users': [user],
          },
        ],
      },
      'streamSettings': streamSettings,
    };

    final fullConfig = _buildFullConfig(outbound);

    return ParsedV2RayConfig(
      protocol: V2RayProtocol.vless,
      name: name,
      address: address,
      port: port,
      jsonConfig: jsonEncode(fullConfig),
      metadata: params,
    );
  }

  static ParsedV2RayConfig? _parseTrojan(String input) {
    final raw = input.substring('trojan://'.length);
    final params = <String, String>{};

    final hashIndex = raw.indexOf('#');
    String name = '';
    String clean;
    if (hashIndex != -1) {
      name = Uri.decodeComponent(raw.substring(hashIndex + 1));
      clean = raw.substring(0, hashIndex);
    } else {
      clean = raw;
    }

    final questionIndex = clean.indexOf('?');
    final paramStr = questionIndex != -1 ? clean.substring(questionIndex + 1) : '';
    final authority = questionIndex != -1 ? clean.substring(0, questionIndex) : clean;

    if (paramStr.isNotEmpty) {
      for (final part in paramStr.split('&')) {
        final eqIdx = part.indexOf('=');
        if (eqIdx != -1) {
          params[part.substring(0, eqIdx)] = Uri.decodeComponent(part.substring(eqIdx + 1));
        }
      }
    }

    final atIdx = authority.indexOf('@');
    if (atIdx == -1) return null;

    final password = authority.substring(0, atIdx);
    final hostPort = authority.substring(atIdx + 1);

    final lastColon = hostPort.lastIndexOf(':');
    if (lastColon == -1) return null;

    final address = hostPort.substring(0, lastColon);
    final port = int.tryParse(hostPort.substring(lastColon + 1)) ?? 0;

    if (address.isEmpty || port == 0) return null;

    final security = params['security'] ?? 'tls';
    final sni = params['sni'] ?? '';
    final host = params['host'] ?? '';
    final path = params['path'] ?? '';
    final network = params['type'] ?? 'tcp';

    final streamSettings = <String, dynamic>{
      'network': network,
    };

    if (security == 'tls') {
      streamSettings['security'] = 'tls';
      final tlsSettings = <String, dynamic>{
        'allowInsecure': false,
      };
      if (sni.isNotEmpty) tlsSettings['serverName'] = sni;
      streamSettings['tlsSettings'] = tlsSettings;
    }

    switch (network) {
      case 'ws':
        final wsSettings = <String, dynamic>{
          'path': path,
        };
        if (host.isNotEmpty) {
          wsSettings['headers'] = {'Host': host};
        }
        streamSettings['wsSettings'] = wsSettings;
        break;
      case 'grpc':
        final serviceName = params['serviceName'] ?? '';
        streamSettings['grpcSettings'] = {
          if (serviceName.isNotEmpty) 'serviceName': serviceName,
        };
        break;
      case 'h2':
        final h2Settings = <String, dynamic>{
          'path': path,
        };
        if (host.isNotEmpty) {
          h2Settings['host'] = [host];
        }
        streamSettings['httpSettings'] = h2Settings;
        break;
    }

    final outbound = {
      'protocol': 'trojan',
      'settings': {
        'servers': [
          {
            'address': address,
            'port': port,
            'password': password,
          },
        ],
      },
      'streamSettings': streamSettings,
    };

    final fullConfig = _buildFullConfig(outbound);

    return ParsedV2RayConfig(
      protocol: V2RayProtocol.trojan,
      name: name,
      address: address,
      port: port,
      jsonConfig: jsonEncode(fullConfig),
      metadata: params,
    );
  }

  static ParsedV2RayConfig? _parseShadowsocks(String input) {
    final raw = input.substring('ss://'.length);

    String decoded;
    try {
      decoded = utf8.decode(base64.decode(raw));
    } catch (_) {
      try {
        final atIdx = raw.indexOf('@');
        if (atIdx != -1) {
          final beforeAt = raw.substring(0, atIdx);
          decoded = utf8.decode(base64.decode(beforeAt)) + raw.substring(atIdx);
        } else {
          decoded = raw;
        }
      } catch (_) {
        return null;
      }
    }

    final atIdx = decoded.indexOf('@');
    if (atIdx == -1) return null;

    final methodPassword = decoded.substring(0, atIdx);
    final hostPort = decoded.substring(atIdx + 1);

    final colonIdx = methodPassword.indexOf(':');
    if (colonIdx == -1) return null;

    final method = methodPassword.substring(0, colonIdx);
    final password = methodPassword.substring(colonIdx + 1);

    final lastColon = hostPort.lastIndexOf(':');
    if (lastColon == -1) return null;

    final address = hostPort.substring(0, lastColon);
    final port = int.tryParse(hostPort.substring(lastColon + 1)) ?? 0;

    if (address.isEmpty || port == 0) return null;

    final outbound = {
      'protocol': 'shadowsocks',
      'settings': {
        'servers': [
          {
            'address': address,
            'port': port,
            'method': method,
            'password': password,
          },
        ],
      },
    };

    final fullConfig = _buildFullConfig(outbound);

    return ParsedV2RayConfig(
      protocol: V2RayProtocol.shadowsocks,
      name: '',
      address: address,
      port: port,
      jsonConfig: jsonEncode(fullConfig),
      metadata: {
        'method': method,
      },
    );
  }

  static Map<String, dynamic> _buildFullConfig(Map<String, dynamic> outbound) {
    return {
      'log': {'loglevel': 'warning'},
      'dns': {
        'servers': ['1.1.1.1', '8.8.8.8', 'localhost'],
      },
      'inbounds': [
        {
          'port': 10808,
          'protocol': 'socks',
          'settings': {
            'auth': 'noauth',
            'udp': true,
          },
          'sniffing': {
            'enabled': true,
            'destOverride': ['http', 'tls'],
          },
        },
        {
          'port': 10809,
          'protocol': 'http',
          'settings': {},
        },
      ],
      'outbounds': [outbound],
    };
  }

  static V2RayProtocol _protocolFromString(String protocol) {
    switch (protocol.toLowerCase()) {
      case 'vmess':
        return V2RayProtocol.vmess;
      case 'vless':
        return V2RayProtocol.vless;
      case 'trojan':
        return V2RayProtocol.trojan;
      case 'shadowsocks':
      case 'ss':
        return V2RayProtocol.shadowsocks;
      default:
        return V2RayProtocol.unknown;
    }
  }

  static String _extractNameFromJson(Map<String, dynamic> json) {
    if (json.containsKey('ps')) return json['ps'] as String? ?? '';
    if (json.containsKey('name')) return json['name'] as String? ?? '';
    if (json.containsKey('remark')) return json['remark'] as String? ?? '';
    return '';
  }
}
