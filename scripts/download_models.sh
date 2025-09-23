#!/bin/bash

# Download MobileFaceNet model for face recognition
# This model converts faces to 128-dimensional embeddings

echo "Downloading MobileFaceNet model..."

MODEL_DIR="../assets/models"
mkdir -p $MODEL_DIR

# Using a smaller, optimized MobileFaceNet model
# Alternative sources if needed:
# - https://github.com/sirius-ai/MobileFaceNet_TF
# - https://github.com/deepinsight/insightface

# For now, we'll create a placeholder and document where to get the actual model
cat > $MODEL_DIR/README.md << EOF
# Face Recognition Models

## MobileFaceNet
- **File**: mobilefacenet.tflite
- **Size**: ~4MB
- **Input**: 112x112x3 RGB image (normalized to [-1, 1])
- **Output**: 128-dimensional face embedding

### Download Instructions
Download the model from one of these sources:
1. https://github.com/sirius-ai/MobileFaceNet_TF/releases
2. Convert from TensorFlow model using:
   - tflite_convert --output_file=mobilefacenet.tflite --graph_def_file=mobilefacenet.pb

### Model Performance
- Accuracy: 99.4% on LFW dataset
- Speed: <50ms on mobile CPU
- Size: 4.1MB

Place the downloaded mobilefacenet.tflite file in this directory.
EOF

echo "Model directory prepared at $MODEL_DIR"
echo "Please download mobilefacenet.tflite and place it in assets/models/"