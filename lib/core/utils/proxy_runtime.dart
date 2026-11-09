import '../models/proxies/proxy_config.dart';
import '../models/proxies/proxy_parser.dart';

/// Runtime defaults must never change a saved URI used as a profile/server key.
ProxyConfig proxyWithFallbackFingerprint(
  ProxyConfig source,
  String fingerprint,
) {
  if (source.fp.isNotEmpty) return source;
  final runtime = ProxyParser.fromMap(source.toMap());
  runtime.fp = fingerprint;
  return runtime;
}
