import 'dart:typed_data';
import 'utils.dart';

enum FrameType {
  singleFrame(0x00),
  firstFrame(0x10),
  consecutiveFrame(0x20);

  final int value;
  const FrameType(this.value);

  static FrameType? fromValue(int value) {
    for (var type in FrameType.values) {
      if (type.value == value) {
        return type;
      }
    }
    return null;
  }
}

enum EcuId {
  engine(0x00, "Engine"),
  transmission(0x01, "Transmission"),
  unknown(0x02, "Unknown");

  final int value;
  final String description;
  const EcuId(this.value, this.description);

  static EcuId fromValue(int value) {
    for (var type in EcuId.values) {
      if (type.value == value) {
        return type;
      }
    }
    return EcuId.unknown;
  }
}

class ParserError implements Exception {
  final String message;
  ParserError(this.message);
  @override
  String toString() => "ParserError: $message";
}

abstract class ParsedMessage {
  EcuId get ecu;
  Uint8List? get data;
}

class CANParser {
  late final List<CanMessage> messages;
  late final List<Frame> frames;

  CANParser(List<String> lines, {required int idBits}) {
    var obdLines =
        lines.map((e) => e.replaceAll(' ', '')).where((e) => e.isHex).toList();

    var parsedFrames = <Frame>[];
    for (var raw in obdLines) {
      try {
        parsedFrames.add(Frame(raw, idBits));
      } catch (e) {
        // Log or handle error?
      }
    }
    frames = parsedFrames;

    var framesByECU = <String, List<Frame>>{};
    for (var f in frames) {
      framesByECU.putIfAbsent(f.canID, () => []).add(f);
    }

    var parsedMessages = <CanMessage>[];
    for (var framesList in framesByECU.values) {
      try {
        parsedMessages.add(CanMessage(framesList));
      } catch (e) {
        // ignore invalid messages
      }
    }
    messages = parsedMessages;
  }
}

class CanMessage implements ParsedMessage {
  final List<Frame> frames;
  @override
  Uint8List? data;

  @override
  EcuId get ecu => frames.isNotEmpty ? frames.first.txID : EcuId.unknown;

  CanMessage(this.frames) {
    if (frames.isEmpty) {
      throw ParserError("Invalid frame count");
    }
    if (frames.length == 1) {
      data = _parseSingleFrameMessage(frames);
    } else {
      data = _parseMultiFrameMessage(frames);
    }
  }

  Uint8List _parseSingleFrameMessage(List<Frame> frames) {
    var frame = frames.first;
    if (frame.type != FrameType.singleFrame) {
      throw ParserError("Not a single frame");
    }
    var dataLen = frame.dataLen;
    if (dataLen == null || dataLen <= 0 || frame.data.length < dataLen + 1) {
      throw ParserError("Frame validation failed");
    }
    return Uint8List.fromList(frame.data.sublist(1, 1 + dataLen));
  }

  Uint8List _parseMultiFrameMessage(List<Frame> frames) {
    var firstFrameIndex =
        frames.indexWhere((f) => f.type == FrameType.firstFrame);
    if (firstFrameIndex == -1) {
      throw ParserError("Failed to parse multi frame message: No first frame");
    }
    var firstFrame = frames[firstFrameIndex];
    var consecutiveFrames =
        frames.where((f) => f.type == FrameType.consecutiveFrame).toList();
    return _assembleData(firstFrame, consecutiveFrames);
  }

  Uint8List _assembleData(Frame firstFrame, List<Frame> consecutiveFrames) {
    var assembledData = BytesBuilder();
    assembledData.add(firstFrame.data);

    for (var frame in consecutiveFrames) {
      if (frame.data.isNotEmpty) {
        assembledData.add(frame.data.skip(1).toList());
      }
    }

    return _extractDataFromBytes(assembledData.toBytes(), firstFrame.dataLen,
        startIndex: 2);
  }

  Uint8List _extractDataFromBytes(Uint8List rawData, int? dataLen,
      {required int startIndex}) {
    if (dataLen == null) {
      throw ParserError("Failed to extract data: unknown length");
    }
    var endIndex = startIndex + dataLen;
    if (endIndex <= rawData.length) {
      return Uint8List.fromList(rawData.sublist(startIndex, endIndex));
    }
    return Uint8List.fromList(rawData.skip(startIndex).toList());
  }
}

class LegacyParser {
  late final List<LegacyMessage> messages;
  late final List<LegacyFrame> frames;

  LegacyParser(List<String> lines) {
    final obdLines =
        lines.map((e) => e.replaceAll(' ', '')).where((e) => e.isHex).toList();

    final parsedFrames = <LegacyFrame>[];
    for (final raw in obdLines) {
      try {
        parsedFrames.add(LegacyFrame(raw));
      } catch (_) {
        // ignore malformed lines
      }
    }
    frames = parsedFrames;

    final framesByEcu = <EcuId, List<LegacyFrame>>{};
    for (final frame in frames) {
      framesByEcu.putIfAbsent(frame.txID, () => []).add(frame);
    }

    final parsedMessages = <LegacyMessage>[];
    for (final groupedFrames in framesByEcu.values) {
      try {
        parsedMessages.add(LegacyMessage(groupedFrames));
      } catch (_) {
        // ignore malformed messages
      }
    }
    messages = parsedMessages;
  }
}

class LegacyMessage implements ParsedMessage {
  final List<LegacyFrame> frames;
  @override
  Uint8List? data;
  @override
  final EcuId ecu;

  LegacyMessage(this.frames)
      : ecu = (frames.isNotEmpty ? frames.first.txID : EcuId.unknown) {
    if (frames.isEmpty) {
      throw ParserError("Invalid frame count");
    }

    if (frames.length == 1) {
      data = _parseSingleFrameMessage(frames);
    } else {
      data = _parseMultiFrameMessage(frames);
    }
  }

  Uint8List _parseSingleFrameMessage(List<LegacyFrame> frames) {
    final frame = frames.first;
    final mode = frame.data.isNotEmpty ? frame.data.first : 0x00;

    if (mode == 0x43) {
      final output = BytesBuilder();
      output.add([0x43, 0x00]);
      for (final f in frames) {
        if (f.data.length > 1) {
          output.add(f.data.sublist(1));
        }
      }
      return output.toBytes();
    }

    if (frame.data.length <= 1) {
      return Uint8List(0);
    }
    return Uint8List.fromList(frame.data.sublist(1));
  }

  Uint8List _parseMultiFrameMessage(List<LegacyFrame> frames) {
    final mode = frames.first.data.isNotEmpty ? frames.first.data.first : 0x00;
    if (mode == 0x43) {
      return _assembleTroubleCodeFrames(frames);
    }

    final sorted = _sortLegacyFrames(frames);

    if (!_hasValidFirstOrderByte(sorted)) {
      throw ParserError("Invalid order byte");
    }

    final output = BytesBuilder();
    for (final frame in sorted) {
      if (frame.data.length > 3) {
        output.add(frame.data.sublist(3));
      }
    }
    return output.toBytes();
  }

  Uint8List _assembleTroubleCodeFrames(List<LegacyFrame> frames) {
    final output = BytesBuilder();
    output.add([0x43, 0x00]);
    for (final f in frames) {
      if (f.data.length > 1) {
        output.add(f.data.sublist(1));
      }
    }
    return output.toBytes();
  }

  List<LegacyFrame> _sortLegacyFrames(List<LegacyFrame> frames) {
    return [...frames]..sort((a, b) {
        final aIndex = _legacyOrderByte(a);
        final bIndex = _legacyOrderByte(b);
        return aIndex.compareTo(bIndex);
      });
  }

  int _legacyOrderByte(LegacyFrame frame) =>
      frame.data.length > 2 ? frame.data[2] : 0xFF;

  bool _hasValidFirstOrderByte(List<LegacyFrame> frames) =>
      frames.isNotEmpty &&
      frames.first.data.length > 2 &&
      frames.first.data[2] == 1;
}

class Frame {
  final String raw;
  late final Uint8List data;
  late final String canID;
  late final int priority;
  late final int addrMode;
  late final int rxID;
  late final EcuId txID;
  late final FrameType type;
  int seqIndex = 0;
  int? dataLen;

  Frame(this.raw, int idBits) {
    canID = raw.substring(0, idBits == 11 ? 3 : 8);

    var paddedRawData = idBits == 11 ? "00000$raw" : raw;
    var dataBytes = paddedRawData.hexBytes;

    if (dataBytes.length >= 4) {
      data = Uint8List.fromList(dataBytes.skip(4).toList());
    } else {
      data = Uint8List(0);
    }

    if (dataBytes.length < 6 || dataBytes.length > 12) {
      throw ParserError("Invalid frame size: ${dataBytes.length} bytes");
    }

    var dataType = data.isNotEmpty ? data[0] : 0;
    var fType = FrameType.fromValue(dataType & 0xF0);
    if (fType == null) {
      throw ParserError("Invalid frame type");
    }
    type = fType;

    priority = dataBytes[2] & 0x0F;
    addrMode = dataBytes[3] & 0xF0;
    rxID = dataBytes[2];
    txID = EcuId.fromValue(dataBytes[3] & 0x07);

    switch (type) {
      case FrameType.singleFrame:
        if (data.isNotEmpty) {
          dataLen = data[0] & 0x0F;
        }
        break;
      case FrameType.firstFrame:
        if (data.length >= 2) {
          dataLen = ((data[0] & 0x0F) << 8) + data[1];
        }
        break;
      case FrameType.consecutiveFrame:
        if (data.isNotEmpty) {
          seqIndex = data[0] & 0x0F;
        }
        break;
    }
  }
}

class LegacyFrame {
  final String raw;
  late final Uint8List data;
  late final int priority;
  late final int rxID;
  late final EcuId txID;

  LegacyFrame(this.raw) {
    final dataBytes = raw.hexBytes;

    if (dataBytes.length < 6 || dataBytes.length > 12) {
      throw ParserError("Invalid frame size: ${dataBytes.length} bytes");
    }

    data = Uint8List.fromList(
        dataBytes.skip(3).take(dataBytes.length - 4).toList());
    priority = dataBytes[0];
    rxID = dataBytes[1];
    txID = EcuId.fromValue(dataBytes[2] & 0x07);
  }
}
