import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_obd2/flutter_obd2.dart';

void main() {
  group('Parser Tests', () {
    test('SingleFrameInitialization', () {
      final rawFrameString = "7E8064100BE3FA81300";
      final frame = Frame(rawFrameString, 11);

      expect(frame.type, FrameType.singleFrame);
      expect(frame.canID, "7E8");
      expect(frame.data.length, 8); // total data length 8 bytes (padded)
      expect(frame.data, [0x06, 0x41, 0x00, 0xBE, 0x3F, 0xA8, 0x13, 0x00]);
    });

    test('MultiFrameInitialization First Frame', () {
      final rawFrameString = "7E8103E000000000000";
      final frame = Frame(rawFrameString, 11);

      expect(frame.type, FrameType.firstFrame);
      expect(frame.canID, "7E8");
      expect(frame.data.length, 8);
    });

    test('MessageInitialization', () {
      final rawFrameString = "7E8064100BE3FA81300";
      final frame = Frame(rawFrameString, 11);
      
      final message = CanMessage([frame]);

      expect(message, isNotNull);
      expect(message.data, isNotNull);
      expect(message.data!.length, 6);
      expect(message.data, [0x41, 0x00, 0xBE, 0x3F, 0xA8, 0x13]);
    });
    
    test('Multi-frame CANParser assembly', () {
      final lines = [
        "7E8 10 14 49 02 01 31 4E 34 ", 
        "7E8 21 41 4C 33 41 50 37 44 ", 
        "7E8 22 43 31 39 39 35 38 33 "
      ];
      
      final messages = CANParser(lines, idBits: 11).messages;
      expect(messages.length, 1);
      final message = messages.first;
      
      expect(message.data!.length, 20); // 0x14 = 20 bytes
    });
  });
}
