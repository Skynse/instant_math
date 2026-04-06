import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class MathOcrService {
  MathOcrService._internal();

  static final MathOcrService _instance = MathOcrService._internal();
  factory MathOcrService() => _instance;

  static const String _assetBase = 'assets/models/onnx_math_ocr';
  static const String _modelDirectoryName = 'onnx_math_ocr';
  static const String _encoderFileName = 'encoder_model.onnx';
  static const String _decoderFileName = 'decoder_model.onnx';
  static const String _tokenizerFileName = 'tokenizer.json';
  static const String _configFileName = 'config.json';
  static const String _preprocessorFileName = 'preprocessor_config.json';

  final OnnxRuntime _ort = OnnxRuntime();

  OrtSession? _encoderSession;
  OrtSession? _decoderSession;
  Map<int, String>? _idToToken;
  Map<String, dynamic>? _config;
  int _imageSize = 384;
  int _bosTokenId = 1;
  int _eosTokenId = 2;
  int _padTokenId = 0;
  bool _isInitializing = false;

  Future<void> ensureReady() async {
    if (_encoderSession != null &&
        _decoderSession != null &&
        _idToToken != null &&
        _config != null) {
      return;
    }

    if (_isInitializing) {
      while (_isInitializing) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return;
    }

    _isInitializing = true;
    try {
      final dir = await _getModelDirectory();
      await dir.create(recursive: true);
      await _extractAssetFiles(dir);
      await _loadConfig(dir);
      await _loadTokenizer(dir);
      await _openSessions(dir);
    } finally {
      _isInitializing = false;
    }
  }

  Future<String> recognizeFormula(Uint8List imageBytes) async {
    await ensureReady();

    final pixelValues = _preprocessImage(imageBytes);
    final encoderInputName = _pickRequiredName(
      _encoderSession!.inputNames,
      preferred: const ['pixel_values'],
      fallbackIndex: 0,
    );
    final encoderOutputName = _pickRequiredName(
      _encoderSession!.outputNames,
      preferred: const ['last_hidden_state'],
      fallbackIndex: 0,
    );

    final encoderInputs = <String, OrtValue>{
      encoderInputName: await OrtValue.fromList(
        pixelValues,
        [1, 3, _imageSize, _imageSize],
      ),
    };
    final encoderOutputs = await _encoderSession!.run(encoderInputs);
    final hiddenStatesValue = encoderOutputs[encoderOutputName];
    if (hiddenStatesValue == null) {
      _disposeValues(encoderInputs);
      _disposeValues(encoderOutputs);
      throw Exception('ONNX encoder did not return hidden states.');
    }

    final tokens = <int>[_bosTokenId];
    final maxLength = ((_config?['decoder'] as Map<String, dynamic>?)?['max_position_embeddings']
                as num?)?.toInt() ??
            256;

    try {
      for (var step = 0; step < math.min(maxLength, 256); step++) {
        final nextTokenId = await _decodeNextToken(
          encoderHiddenStates: hiddenStatesValue,
          tokens: tokens,
        );

        if (nextTokenId == _eosTokenId || nextTokenId == _padTokenId) {
          break;
        }
        tokens.add(nextTokenId);
      }
    } finally {
      _disposeValues(encoderInputs);
      _disposeValues(encoderOutputs);
    }

    final decoded = _decodeTokenIds(tokens.skip(1).toList()).trim();
    if (decoded.isEmpty) {
      throw Exception('OCR model returned an empty result.');
    }
    return decoded;
  }

  Future<void> dispose() async {
    await _encoderSession?.close();
    await _decoderSession?.close();
    _encoderSession = null;
    _decoderSession = null;
    _idToToken = null;
    _config = null;
  }

  Future<int> _decodeNextToken({
    required OrtValue encoderHiddenStates,
    required List<int> tokens,
  }) async {
    final decoderInputName = _pickRequiredName(
      _decoderSession!.inputNames,
      preferred: const ['input_ids', 'decoder_input_ids'],
      fallbackIndex: 0,
    );
    final decoderStateName = _pickRequiredName(
      _decoderSession!.inputNames,
      preferred: const ['encoder_hidden_states'],
      fallbackIndex: math.min(1, _decoderSession!.inputNames.length - 1),
    );
    final decoderOutputName = _pickRequiredName(
      _decoderSession!.outputNames,
      preferred: const ['logits'],
      fallbackIndex: 0,
    );

    // Only create OrtValues we own. The encoder hidden states are owned
    // by the caller and must not be disposed here.
    final inputIdsValue = await OrtValue.fromList(
      Int64List.fromList(tokens),
      [1, tokens.length],
    );

    final decoderOutputs = await _decoderSession!.run({
      decoderInputName: inputIdsValue,
      decoderStateName: encoderHiddenStates,
    });

    try {
      final logitsValue = decoderOutputs[decoderOutputName];
      if (logitsValue == null) {
        throw Exception('ONNX decoder did not return logits.');
      }
      final logitsShape = logitsValue.shape; // [1, seqLen, vocabSize]
      return _argmaxLastLogits(await logitsValue.asList(), logitsShape);
    } finally {
      inputIdsValue.dispose();
      _disposeValues(decoderOutputs);
    }
  }

  Float32List _preprocessImage(Uint8List imageBytes) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw Exception('Unable to decode image for OCR.');
    }

    final square = _containOnWhiteCanvas(decoded, _imageSize);
    final normalized = Float32List(3 * _imageSize * _imageSize);
    final channelStride = _imageSize * _imageSize;

    for (var y = 0; y < _imageSize; y++) {
      for (var x = 0; x < _imageSize; x++) {
        final pixel = square.getPixel(x, y);
        final index = y * _imageSize + x;
        normalized[index] = pixel.r / 127.5 - 1.0;
        normalized[channelStride + index] = pixel.g / 127.5 - 1.0;
        normalized[(2 * channelStride) + index] = pixel.b / 127.5 - 1.0;
      }
    }

    return normalized;
  }

  img.Image _containOnWhiteCanvas(img.Image source, int targetSize) {
    final longestSide = math.max(source.width, source.height).toDouble();
    final scale = targetSize / longestSide;
    final resized = img.copyResize(
      source,
      width: math.max(1, (source.width * scale).round()),
      height: math.max(1, (source.height * scale).round()),
      interpolation: img.Interpolation.cubic,
    );

    final canvas = img.Image(width: targetSize, height: targetSize);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    final dx = ((targetSize - resized.width) / 2).round();
    final dy = ((targetSize - resized.height) / 2).round();
    img.compositeImage(canvas, resized, dstX: dx, dstY: dy);
    return canvas;
  }

  Future<void> _extractAssetFiles(Directory dir) async {
    const fileNames = [
      _encoderFileName,
      _decoderFileName,
      _tokenizerFileName,
      _configFileName,
      _preprocessorFileName,
    ];

    for (final fileName in fileNames) {
      final targetFile = File(_resolveModelPath(dir, fileName));
      if (await targetFile.exists()) {
        continue;
      }

      final data = await rootBundle.load('$_assetBase/$fileName');
      await targetFile.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
  }

  Future<void> _loadConfig(Directory dir) async {
    if (_config != null) {
      return;
    }

    final configFile = File(_resolveModelPath(dir, _configFileName));
    final preprocessorFile = File(_resolveModelPath(dir, _preprocessorFileName));
    _config = jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    final preprocessor = jsonDecode(await preprocessorFile.readAsString()) as Map<String, dynamic>;

    _bosTokenId = (_config?['decoder_start_token_id'] as num?)?.toInt() ?? 1;
    _eosTokenId = (_config?['eos_token_id'] as num?)?.toInt() ?? 2;
    _padTokenId = (_config?['pad_token_id'] as num?)?.toInt() ?? 0;
    _imageSize = (preprocessor['size'] as Map<String, dynamic>?)?['height'] as int? ??
        (_config?['encoder'] as Map<String, dynamic>?)?['image_size'] as int? ??
        384;
  }

  Future<void> _loadTokenizer(Directory dir) async {
    if (_idToToken != null) {
      return;
    }

    final tokenizerFile = File(_resolveModelPath(dir, _tokenizerFileName));
    final tokenizerJson =
        jsonDecode(await tokenizerFile.readAsString()) as Map<String, dynamic>;
    final vocab =
        (tokenizerJson['model'] as Map<String, dynamic>)['vocab'] as Map<String, dynamic>;

    _idToToken = <int, String>{};
    vocab.forEach((token, id) {
      _idToToken![id as int] = token;
    });
  }

  Future<void> _openSessions(Directory dir) async {
    _encoderSession ??=
        await _ort.createSession(_resolveModelPath(dir, _encoderFileName));
    _decoderSession ??=
        await _ort.createSession(_resolveModelPath(dir, _decoderFileName));
  }

  Future<Directory> _getModelDirectory() async {
    final baseDir = await getApplicationDocumentsDirectory();
    return Directory('${baseDir.path}${Platform.pathSeparator}$_modelDirectoryName');
  }

  String _resolveModelPath(Directory dir, String fileName) {
    return '${dir.path}${Platform.pathSeparator}$fileName';
  }

  String _pickRequiredName(
    List<String> names, {
    required List<String> preferred,
    required int fallbackIndex,
  }) {
    for (final candidate in preferred) {
      for (final name in names) {
        if (name == candidate || name.contains(candidate)) {
          return name;
        }
      }
    }
    if (names.isEmpty) {
      throw Exception('Model session exposed no tensor names.');
    }
    return names[fallbackIndex];
  }

  // logits from asList() is a nested list: [batch][seqLen][vocabSize]
  // We want the last sequence position: [0][-1][:]
  int _argmaxLastLogits(Object logits, List<int> logitsShape) {
    if (logits is! List || logits.isEmpty) {
      throw Exception('Decoder logits were empty.');
    }
    final lastPos = ((logits[0] as List).last) as List;

    var bestIndex = 0;
    var bestValue = double.negativeInfinity;
    for (var i = 0; i < lastPos.length; i++) {
      final value = (lastPos[i] as num).toDouble();
      if (value > bestValue) {
        bestValue = value;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  String _decodeTokenIds(List<int> tokenIds) {
    final buffer = StringBuffer();
    for (final tokenId in tokenIds) {
      final token = _idToToken?[tokenId];
      if (token == null || token.startsWith('<')) {
        continue;
      }
      buffer.write(token);
    }

    final byteDecoder = _byteDecoder();
    final bytes = <int>[];
    for (final rune in buffer.toString().runes) {
      final character = String.fromCharCode(rune);
      bytes.add(byteDecoder[character] ?? rune);
    }

    return utf8.decode(bytes, allowMalformed: true);
  }

  Map<String, int> _byteDecoder() {
    final baseBytes = <int>[
      ...List<int>.generate(94, (index) => index + 33),
      ...List<int>.generate(12, (index) => index + 161),
      ...List<int>.generate(33, (index) => index + 174),
    ];
    final source = <int>[...baseBytes];
    final target = <int>[...baseBytes];
    var extra = 0;

    for (var byte = 0; byte < 256; byte++) {
      if (!source.contains(byte)) {
        source.add(byte);
        target.add(256 + extra);
        extra++;
      }
    }

    return <String, int>{
      for (var i = 0; i < source.length; i++) String.fromCharCode(target[i]): source[i],
    };
  }

  void _disposeValues(Map<String, OrtValue> values) {
    for (final value in values.values) {
      value.dispose();
    }
  }
}
