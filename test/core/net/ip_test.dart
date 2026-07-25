import 'package:cfnb_app/core/net/ip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isIp IPv4', () {
    expect(isIp('1.2.3.4'), isTrue);
    expect(isIp('999.1.1.1'), isFalse);
    expect(isIp('1.2.3'), isFalse);
    expect(isIp('example.com'), isFalse);
  });
  test('isIp IPv6', () {
    expect(isIp('[::1]'), isTrue);
    expect(isIp('2001:db8::1'), isTrue);
    expect(isIp('::1'), isTrue);
    expect(isIp('example.com'), isFalse);
  });
  test('isCloudflareIp', () {
    expect(isCloudflareIp('104.16.0.1'), isTrue);
    expect(isCloudflareIp('104.31.255.255'), isTrue);
    expect(isCloudflareIp('162.158.0.1'), isTrue);
    expect(isCloudflareIp('162.159.255.255'), isTrue);
    expect(isCloudflareIp('172.64.0.1'), isTrue);
    expect(isCloudflareIp('172.71.255.255'), isTrue);
    expect(isCloudflareIp('108.162.192.1'), isTrue);
    expect(isCloudflareIp('8.8.8.8'), isFalse);
    expect(isCloudflareIp('1.1.1.1'), isFalse);
    expect(isCloudflareIp('192.168.1.1'), isFalse);
  });
}
