import '../decoders.dart';
import 'dart:typed_data';

class CommandProperties {
  final String command;
  final String description;
  final int bytes;
  final Decoder? decoder;
  final bool live;
  final double maxValue;
  final double minValue;

  const CommandProperties(this.command, this.description, this.bytes, this.decoder, {this.live = false, this.maxValue = 100, this.minValue = 0});

  DecodeResult? decode(Uint8List data, MeasurementUnit unit) {
    if (decoder == null) return null;
    return decoder!.decode(data, unit);
  }
}

class ObdCommand {
  final CommandProperties properties;
  const ObdCommand(this.properties);
}
