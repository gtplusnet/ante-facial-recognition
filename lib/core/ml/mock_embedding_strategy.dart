import 'dart:math' as math;
import 'dart:typed_data';

import 'package:injectable/injectable.dart';

import '../config/face_quality_config.dart';
import '../utils/logger.dart';
import 'embedding_strategy.dart';

/// Mock implementation of embedding extraction strategy for testing
///
/// This strategy generates consistent pseudo-random embeddings based on
/// image content for development and testing when the real TFLite model
/// is not available or desired.
@injectable
class MockEmbeddingStrategy implements EmbeddingStrategy {
  static const int outputSize = 192;  // Match MobileFaceNet output dimensions
  bool _isInitialized = false;

  @override
  bool get isInitialized => _isInitialized;

  @override
  String get strategyName => 'Mock Testing';

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    Logger.info('Initializing mock embedding strategy...');

    // Mock initialization - just set flag
    await Future.delayed(const Duration(milliseconds: 100));

    _isInitialized = true;
    Logger.success('Mock embedding strategy initialized');
  }

  @override
  Future<Float32List> extractEmbedding(Uint8List imageBytes) async {
    if (!_isInitialized) {
      throw StateError('Mock strategy not initialized');
    }

    Logger.debug('Generating mock embedding for testing');

    // Generate a consistent embedding based on image bytes
    final embedding = Float32List(outputSize);

    // Use image bytes to generate pseudo-random but consistent values
    int seed = 0;
    final sampleSize = imageBytes.length.clamp(0, FaceQualityConfig.embeddingSeedSampleSize);

    for (int i = 0; i < sampleSize; i++) {
      seed = (seed + imageBytes[i]) % FaceQualityConfig.embeddingSeedModulo;
    }

    // Generate normalized values using configuration constants
    for (int i = 0; i < outputSize; i++) {
      final rawValue = (seed + i * FaceQualityConfig.embeddingValueMultiplier) % FaceQualityConfig.embeddingSeedModulo;
      embedding[i] = (rawValue / (FaceQualityConfig.embeddingSeedModulo - 1)) - 0.5;
    }

    return normalizeEmbedding(embedding);
  }

  @override
  Float32List normalizeEmbedding(Float32List embedding) {
    // Calculate L2 norm
    double norm = 0.0;
    for (int i = 0; i < embedding.length; i++) {
      norm += embedding[i] * embedding[i];
    }
    norm = math.sqrt(norm);

    // Avoid division by zero
    if (norm == 0.0) {
      Logger.warning('Embedding has zero norm, returning original');
      return embedding;
    }

    // Normalize to unit length
    final normalized = Float32List(embedding.length);
    for (int i = 0; i < embedding.length; i++) {
      normalized[i] = embedding[i] / norm;
    }

    return normalized;
  }

  @override
  void dispose() {
    _isInitialized = false;
    Logger.info('Mock embedding strategy disposed');
  }

  /// Generate a mock embedding with specific characteristics for testing
  ///
  /// This method can be used in tests to create embeddings with known
  /// properties for validation purposes.
  Float32List generateTestEmbedding({
    int? seed,
    double? targetNorm,
  }) {
    final testSeed = seed ?? 12345;
    final embedding = Float32List(outputSize);

    // Generate values based on seed
    final random = math.Random(testSeed);
    for (int i = 0; i < outputSize; i++) {
      embedding[i] = (random.nextDouble() - 0.5) * 2.0; // Range [-1, 1]
    }

    // Apply target norm if specified
    if (targetNorm != null && targetNorm > 0) {
      final currentNorm = math.sqrt(
        embedding.fold<double>(0.0, (sum, value) => sum + value * value),
      );

      if (currentNorm > 0) {
        final scale = targetNorm / currentNorm;
        for (int i = 0; i < outputSize; i++) {
          embedding[i] *= scale;
        }
        return embedding;
      }
    }

    return normalizeEmbedding(embedding);
  }

  /// Check if two embeddings would be considered similar by this mock strategy
  ///
  /// This can be useful for testing face matching logic without real embeddings
  bool areEmbeddingsSimilar(Float32List embedding1, Float32List embedding2, {double threshold = 0.8}) {
    if (embedding1.length != embedding2.length) return false;

    // Calculate cosine similarity
    double dotProduct = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;

    for (int i = 0; i < embedding1.length; i++) {
      dotProduct += embedding1[i] * embedding2[i];
      norm1 += embedding1[i] * embedding1[i];
      norm2 += embedding2[i] * embedding2[i];
    }

    final similarity = dotProduct / (math.sqrt(norm1) * math.sqrt(norm2));
    return similarity >= threshold;
  }
}