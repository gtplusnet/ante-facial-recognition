import 'dart:typed_data';

/// Abstract strategy interface for face embedding extraction
///
/// This interface allows switching between different embedding generation
/// strategies (real TFLite model vs mock for testing) without changing
/// the client code. Follows Strategy design pattern.
abstract class EmbeddingStrategy {
  /// Whether this strategy is initialized and ready for use
  bool get isInitialized;

  /// Initialize the strategy with necessary resources
  Future<void> initialize();

  /// Extract face embedding from image bytes
  ///
  /// Returns a normalized Float32List representing the face embedding
  /// Throws exception if extraction fails
  Future<Float32List> extractEmbedding(Uint8List imageBytes);

  /// Normalize an embedding vector to unit length
  ///
  /// This ensures all embeddings have consistent magnitude for comparison
  Float32List normalizeEmbedding(Float32List embedding);

  /// Clean up resources used by this strategy
  void dispose();

  /// Get a human-readable name for this strategy (for logging/debugging)
  String get strategyName;
}