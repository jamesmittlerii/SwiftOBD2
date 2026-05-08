import 'package:flutter_obd2/flutter_obd2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MockManager', () {
    late MockManager manager;

    setUp(() async {
      manager = MockManager();
      await manager.connectAsync(timeout: 1);
    });

    test('emits connection states and rejects commands while disconnected',
        () async {
      final states = <ConnectionState>[];
      final sub = manager.connectionStatePublisher.listen(states.add);

      manager.disconnectPeripheral();
      await pumpEventQueue();

      expect(states, contains(ConnectionState.disconnected));
      await expectLater(
        manager.sendCommand('010C'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('not connected'),
        )),
      );

      await sub.cancel();
    });

    test('handles AT settings, echo, headers, voltage, and timeout commands',
        () async {
      expect(await manager.sendCommand('ATZ'), ['ELM327 v1.5']);
      expect(await manager.sendCommand('ATDPN'), ['06']);
      expect(
          (await manager.sendCommand('ATRV')).single, matches(r'^\d+\.\d{2}$'));
      expect(await manager.sendCommand('ATST64'), ['OK']);
      expect(await manager.sendCommand('ATSTZZ'), ['NO DATA']);
      expect(await manager.sendCommand('ATSP0'), ['OK']);

      expect(await manager.sendCommand('ATE1'), ['ATE1', 'OK']);
      expect(await manager.sendCommand('ATH0'), ['ATH0', 'OK']);
      expect(
          (await manager.sendCommand('010C')).single, startsWith('04 41 0C'));

      expect(await manager.sendCommand('ATE0'), ['OK']);
      expect(await manager.sendCommand('ATH1'), ['OK']);
      expect((await manager.sendCommand('010C')).single,
          startsWith('7E8 04 41 0C'));
    });

    test('returns expected fixed OBD responses', () async {
      final cases = <String, Matcher>{
        '0100': contains('41 00 FF FF FF FF'),
        '0120': contains('41 20 FF FF FF FF'),
        '0140': contains('41 40 FF FF FF FE'),
        '0902': hasLength(3),
        '03': hasLength(3),
        '04': contains('44'),
        'FFFF': contains('NO DATA'),
      };

      for (final entry in cases.entries) {
        final response = await manager.sendCommand(entry.key);
        if (response.length == 1) {
          expect(response.single, entry.value, reason: entry.key);
        } else {
          expect(response, entry.value, reason: entry.key);
        }
      }
    });

    test('generates supported live PID frames with valid hex bytes', () async {
      const commands = [
        '0101',
        '0103',
        '0104',
        '0105',
        '0106',
        '0107',
        '0108',
        '0109',
        '010A',
        '010B',
        '010C',
        '010D',
        '010E',
        '010F',
        '0110',
        '0111',
        '0114',
        '0115',
        '0118',
        '0119',
        '011F',
        '0121',
        '0122',
        '0123',
        '012C',
        '012E',
        '012F',
        '0131',
        '0133',
        '013C',
        '013D',
        '013E',
        '013F',
        '0142',
        '0143',
        '0144',
        '0145',
        '0146',
        '0147',
        '0148',
        '0149',
        '014A',
        '014B',
        '014C',
        '0159',
        '015A',
        '015B',
      ];

      for (final command in commands) {
        final response = (await manager.sendCommand(command)).single;
        expect(response, startsWith('7E8'), reason: command);
        expect(response, contains('41 ${command.substring(2)}'),
            reason: command);
        final bytes = response.split(' ').skip(1);
        expect(
          bytes,
          everyElement(matches(RegExp(r'^[0-9A-F]{2}$'))),
          reason: command,
        );
      }
    });

    test('serializes concurrent commands', () async {
      final responses = await Future.wait([
        manager.sendCommand('010C'),
        manager.sendCommand('010D'),
        manager.sendCommand('0105'),
      ]);

      expect(responses[0].single, contains('41 0C'));
      expect(responses[1].single, contains('41 0D'));
      expect(responses[2].single, contains('41 05'));
    });
  });
}
