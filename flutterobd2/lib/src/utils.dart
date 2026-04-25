import 'dart:typed_data';

extension HexString on String {
  bool get isHex {
    final hexRegExp = RegExp(r'^[0-9a-fA-F]+$');
    return hexRegExp.hasMatch(this);
  }

  Uint8List get hexBytes {
    var hex = this;
    if (hex.length % 2 != 0) {
      hex = '0$hex';
    }
    var result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      var byteString = hex.substring(i * 2, i * 2 + 2);
      result[i] = int.parse(byteString, radix: 16);
    }
    return result;
  }
}


int bytesToInt(List<int> byteArray) {
  int value = 0;
  int power = 0;

  for (var byte in byteArray.reversed) {
    value += byte << power;
    power += 8;
  }
  return value;
}

enum ObdProtocol {
  protocol1('1', '1: SAE J1850 PWM (41.6 kbaud)'),
  protocol2('2', '2: SAE J1850 VPW (10.4 kbaud)'),
  protocol3('3', '3: ISO 9141-2 (5 baud init, 10.4 kbaud)'),
  protocol4('4', '4: ISO 14230-4 KWP (5 baud init, 10.4 kbaud)'),
  protocol5('5', '5: ISO 14230-4 KWP (fast init, 10.4 kbaud)'),
  protocol6('6', '6: ISO 15765-4 CAN (11 bit ID,500 Kbaud)'),
  protocol7('7', '7: ISO 15765-4 CAN (29 bit ID,500 Kbaud)'),
  protocol8('8', '8: ISO 15765-4 CAN (11 bit ID,250 Kbaud)'),
  protocol9('9', '9: ISO 15765-4 CAN (29 bit ID,250 Kbaud)'),
  protocolA('A', 'A: SAE J1939 CAN (11* bit ID, 250* kbaud)'),
  protocolB('B', 'B: USER1 CAN (11* bit ID, 125* kbaud)'),
  protocolC('C', 'C: USER1 CAN (11* bit ID, 50* kbaud)'),
  none('NONE', 'None');

  final String value;
  final String description;

  const ObdProtocol(this.value, this.description);

  int get idBits {
    switch (this) {
      case ObdProtocol.protocol6:
      case ObdProtocol.protocol7:
      case ObdProtocol.protocolA:
      case ObdProtocol.protocol8:
      case ObdProtocol.protocol9:
      case ObdProtocol.protocolB:
        return 11;
      default:
        return 29;
    }
  }

  ObdProtocol nextProtocol() {
    const protocolMap = {
      ObdProtocol.protocolC: ObdProtocol.protocolB,
      ObdProtocol.protocolB: ObdProtocol.protocolA,
      ObdProtocol.protocolA: ObdProtocol.protocol9,
      ObdProtocol.protocol9: ObdProtocol.protocol8,
      ObdProtocol.protocol8: ObdProtocol.protocol7,
      ObdProtocol.protocol7: ObdProtocol.protocol6,
      ObdProtocol.protocol6: ObdProtocol.protocol5,
      ObdProtocol.protocol5: ObdProtocol.protocol4,
      ObdProtocol.protocol4: ObdProtocol.protocol3,
      ObdProtocol.protocol3: ObdProtocol.protocol2,
      ObdProtocol.protocol2: ObdProtocol.protocol1,
      ObdProtocol.protocol1: ObdProtocol.none,
    };

    return protocolMap[this] ?? ObdProtocol.none;
  }

  String get cmd => "ATSP$value";
}
