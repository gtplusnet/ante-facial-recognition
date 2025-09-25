import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

void main() async {
  print('Testing TFLite model loading...\n');

  // Test both models
  await testModel('assets/models/mobilefacenet.tflite', 'Original');
  print('\n' + '='*50 + '\n');
  await testModel('assets/models/mobilefacenet_verified.tflite', 'Verified');
}

Future<void> testModel(String modelPath, String modelName) async {
  print('Testing $modelName model: $modelPath');
  print('-' * 40);

  try {
    // Test 1: Direct asset loading
    print('Test 1: Loading model from asset...');
    Interpreter? interpreter;

    try {
      interpreter = await Interpreter.fromAsset(modelPath);
      print('✓ Model loaded successfully from asset');
    } catch (e) {
      print('✗ Asset loading failed: $e');

      // Test 2: Buffer loading
      print('\nTest 2: Loading model from buffer...');
      try {
        final modelData = await rootBundle.load(modelPath);
        final buffer = Uint8List.fromList(
          modelData.buffer.asUint8List(
            modelData.offsetInBytes,
            modelData.lengthInBytes,
          ),
        );

        print('  Buffer size: ${buffer.length} bytes');
        interpreter = Interpreter.fromBuffer(buffer);
        print('✓ Model loaded successfully from buffer');
      } catch (bufferError) {
        print('✗ Buffer loading failed: $bufferError');
        return;
      }
    }

    // Test 3: Check model structure
    print('\nTest 3: Checking model structure...');
    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);

    print('  Input shape: ${inputTensor.shape}');
    print('  Input type: ${inputTensor.type}');
    print('  Output shape: ${outputTensor.shape}');
    print('  Output type: ${outputTensor.type}');

    // Validate expected shapes
    if (inputTensor.shape.length == 4 &&
        inputTensor.shape[1] == 112 &&
        inputTensor.shape[2] == 112 &&
        inputTensor.shape[3] == 3) {
      print('✓ Input shape is correct for face recognition');
    } else {
      print('✗ Unexpected input shape for face recognition');
    }

    if (outputTensor.shape.length == 2 &&
        (outputTensor.shape[1] == 128 || outputTensor.shape[1] == 192)) {
      print('✓ Output shape is correct for embeddings');
    } else {
      print('✗ Unexpected output shape for embeddings');
    }

    // Test 4: Run inference
    print('\nTest 4: Running test inference...');
    try {
      // Create dummy input [1, 112, 112, 3]
      final input = List.generate(1, (_) =>
        List.generate(112, (_) =>
          List.generate(112, (_) =>
            List.generate(3, (_) => 0.0))));

      // Create output buffer [1, embedding_size]
      final outputSize = outputTensor.shape[1];
      final output = List.generate(1, (_) => List.filled(outputSize, 0.0));

      interpreter.run(input, output);

      // Check output
      final embedding = output[0];
      final hasNonZero = embedding.any((val) => val != 0.0);

      if (hasNonZero) {
        print('✓ Inference successful - generated non-zero embedding');
        print('  Embedding size: ${embedding.length}');
        print('  First 5 values: [${embedding.take(5).map((v) => v.toStringAsFixed(4)).join(', ')}]');
      } else {
        print('⚠ Inference ran but produced all zeros');
      }
    } catch (inferenceError) {
      print('✗ Inference failed: $inferenceError');
    }

    // Cleanup
    interpreter.close();
    print('\n✓ Model test completed successfully for $modelName');

  } catch (e, stackTrace) {
    print('\n✗ Fatal error testing $modelName model: $e');
    print('Stack trace:\n$stackTrace');
  }
}