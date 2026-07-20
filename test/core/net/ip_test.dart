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
}
