import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_obd2/flutter_obd2.dart';

void main() {
  final legacyProtocols = [
    ObdProtocol.protocol1,
    ObdProtocol.protocol2,
    ObdProtocol.protocol3,
    ObdProtocol.protocol4,
    ObdProtocol.protocol5,
  ];

  group('Legacy Protocol Tests', () {
    test('single frame parse', () {
      for (final proto in legacyProtocols) {
        final parser = CanProtocol(proto);

        var data = parser.parse(["48 6B 10 41 00 FF"]).first.data;
        expect(data, [0x00]);

        data = parser.parse(["48 6B 10 41 00 00 01 02 03 04 FF"]).first.data;
        expect(data, [0x00, 0x00, 0x01, 0x02, 0x03, 0x04]);

        final tooShort = parser.parse(["48 6B 10 41"]);
        expect(tooShort, isEmpty);
      }
    });
  });
}
