import 'package:flutter_obd2/flutter_obd2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Obd2Service continuous updates', () {
    test('uses a stable PID snapshot for a stream subscription', () async {
      await Commands.ensureInitialized();

      final service = Obd2Service(connectionType: ConnectionType.demo);
      await service.startConnection(querySupportedPIDs: false);

      final rpm = Commands.allCommands['010C']!;
      final speed = Commands.allCommands['010D']!;
      service.addPID(rpm);

      final emitted = <Map<ObdCommand, DecodeResult>>[];
      final subscription = service
          .startContinuousUpdates(interval: const Duration(milliseconds: 20))
          .listen(emitted.add);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      service.addPID(speed);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      await subscription.cancel();
      service.stopConnection();

      expect(emitted, isNotEmpty);
      expect(
        emitted.expand((batch) => batch.keys),
        everyElement(isNot(speed)),
      );
    });
  });
}
