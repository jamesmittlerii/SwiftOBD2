import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_obd2/flutter_obd2.dart';

void main() {
  final canProtocols = [
    ObdProtocol.protocol6,
    ObdProtocol.protocol8,
  ];

  group('CAN Protocol Tests', () {
    test('single frame parse', () {
      for (final proto in canProtocols) {
        final parser = CanProtocol(proto);
        var data = parser.parse(["7E8 06 41 00 00 01 02 03"]).first.data;
        expect(data, isNotNull);
        expect(data, [0x41, 0x00, 0x00, 0x01, 0x02, 0x03]);

        data = parser.parse(["7E8 01 41"]).first.data;
        expect(data, isNotNull);

        final short = parser.parse(["7E8 01"]);
        expect(short, isEmpty);
      }
    });
  });
}
