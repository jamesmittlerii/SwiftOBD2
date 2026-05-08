import 'dart:async';
import 'dart:io';

import 'package:flutter_obd2/flutter_obd2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConnectionState', () {
    test('describes and classifies connection states', () {
      expect(ConnectionState.disconnected.description, 'Disconnected');
      expect(ConnectionState.connecting.description, 'Connecting');
      expect(ConnectionState.connectedToAdapter.description,
          'Connected to Adapter');
      expect(ConnectionState.connectedToVehicle.description,
          'Connected to Vehicle');
      expect(ConnectionState.error.description, 'Error');

      expect(ConnectionState.disconnected.isConnected, isFalse);
      expect(ConnectionState.connecting.isConnected, isFalse);
      expect(ConnectionState.connectedToAdapter.isConnected, isTrue);
      expect(ConnectionState.connectedToVehicle.isConnected, isTrue);
      expect(ConnectionState.error.isConnected, isFalse);
    });
  });

  group('WifiManager', () {
    late ServerSocket server;
    final sockets = <Socket>[];

    tearDown(() async {
      for (final socket in sockets) {
        socket.destroy();
      }
      sockets.clear();
      await server.close();
    });

    test(
        'connects, writes commands, parses prompted responses, and disconnects',
        () async {
      final received = <String>[];
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((socket) {
        sockets.add(socket);
        socket.listen((data) {
          final command = String.fromCharCodes(data).trim();
          received.add(command);
          socket.write('\r\n$command\r\n7E8 03 41 0D 28\r\n\r\n>');
        });
      });

      final manager = WifiManager(
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
      );
      final states = <ConnectionState>[];
      final sub = manager.connectionStatePublisher.listen(states.add);

      await manager.connectAsync(timeout: 1);
      final response = await manager.sendCommand('010D');
      manager.disconnectPeripheral();
      await pumpEventQueue();

      expect(received, ['010D']);
      expect(response, ['010D', '7E8 03 41 0D 28']);
      expect(
          states,
          containsAllInOrder([
            ConnectionState.connecting,
            ConnectionState.connectedToAdapter,
            ConnectionState.disconnected,
          ]));

      await sub.cancel();
    });

    test('serializes concurrent commands over one socket', () async {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      var speed = 40;
      server.listen((socket) {
        sockets.add(socket);
        socket.listen((data) {
          final command = String.fromCharCodes(data).trim();
          final hex = speed.toRadixString(16).padLeft(2, '0').toUpperCase();
          speed += 1;
          socket.write('$command\r7E8 03 41 0D $hex\r>');
        });
      });

      final manager = WifiManager(
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
      );

      await manager.connectAsync(timeout: 1);
      final responses = await Future.wait([
        manager.sendCommand('010D'),
        manager.sendCommand('010D'),
      ]);
      manager.disconnectPeripheral();

      expect(responses[0].last, endsWith('28'));
      expect(responses[1].last, endsWith('29'));
    });

    test('fails pending command when disconnected', () async {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((socket) {
        sockets.add(socket);
        socket.listen((_) {});
      });

      final manager = WifiManager(
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
      );
      await manager.connectAsync(timeout: 1);

      final pending = manager.sendCommand('010C', retries: 1);
      await pumpEventQueue();
      manager.disconnectPeripheral();

      await expectLater(pending, throwsException);
    });
  });
}
