import json
import os

with open('../Sources/SwiftOBD2/Resources/commands.json', 'r', encoding='utf-8') as f:
    commands_data = json.load(f)

# write obd_command.dart
with open('lib/src/commands/obd_command.dart', 'w', encoding='utf-8') as f:
    f.write('''import '../decoders.dart';
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
''')

with open('lib/src/commands/commands.dart', 'w', encoding='utf-8') as f:
    f.write('''import '../decoders.dart';
import 'obd_command.dart';

class Commands {
''')
    
    # We will just instantiate them as static const properties or a map
    f.write('  static final Map<String, ObdCommand> allCommands = {\n')
    for cmd in commands_data:
        cmd_str = cmd['command']
        desc = cmd['description'].replace('"', '\\"')
        bytes_len = cmd['bytes']
        live = 'true' if cmd.get('live', False) else 'false'
        maxV = cmd.get('maxValue', 100)
        minV = cmd.get('minValue', 0)
        
        # parse decoder
        decoder_dict = cmd.get('decoder', {})
        decoder_str = 'null'
        if decoder_dict:
            dec_key = list(decoder_dict.keys())[0]
            if dec_key == 'none': decoder_str = 'null'
            elif dec_key == 'pid': decoder_str = 'null' # no PID decoder yet
            elif dec_key == 'status': decoder_str = 'StatusDecoder()'
            elif dec_key == 'singleDTC': decoder_str = 'SingleDtcDecoder()'
            elif dec_key == 'dtc': decoder_str = 'DtcDecoder()'
            elif dec_key == 'percent': decoder_str = 'PercentDecoder()'
            elif dec_key == 'percentCentered': decoder_str = 'PercentDecoder()' # stub
            elif dec_key == 'temp': decoder_str = 'TemperatureDecoder()'
            elif dec_key == 'pressure': decoder_str = 'PercentDecoder()' # stub
            elif dec_key == 'encoded_string': decoder_str = 'StringDecoder()'
            elif dec_key == 'uas':
                val = decoder_dict[dec_key].get('_0', 0)
                decoder_str = f'UasDecoder({val})'
            else:
                decoder_str = 'null' # fallback for unimplemented decoders
                
        f.write(f'    "{cmd_str}": ObdCommand(CommandProperties("{cmd_str}", "{desc}", {bytes_len}, {decoder_str}, live: {live}, maxValue: {maxV}, minValue: {minV})),\n')
    f.write('  };\n')
    
    f.write('}\n')
