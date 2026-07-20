/// 判断 host 是否为 IP 地址（IPv4 或 IPv6，支持方括号包裹的 IPv6）。
bool isIp(String host) => isIpv4(host) || isIpv6(host);

bool isIpv4(String host) {
  if (host.isEmpty) return false;
  final parts = host.split('.');
  if (parts.length != 4) return false;
  return parts.every((p) {
    final n = int.tryParse(p);
    return n != null && n >= 0 && n <= 255;
  });
}

bool isIpv6(String host) {
  final h = host.replaceAll(RegExp(r'[\[\]]'), '');
  if (h.isEmpty) return false;
  return RegExp(r'^[0-9a-fA-F:]+$').hasMatch(h) && h.contains(':');
}
