#!/usr/bin/env python3
"""
Script to create a Core ML embedding model for HSI iOS.

This script demonstrates how to create a simple neural network model
and convert it to Core ML format for use in the HSI iOS SDK.

Requirements:
    pip install tensorflow coremltools numpy

Usage:
    python create_coreml_model.py

Output:
    HSIEmbeddingModel.mlmodel - Core ML model file
"""

import numpy as np
try:
    import tensorflow as tf
    from tensorflow import keras
    import coremltools as ct
    print("✅ All dependencies loaded successfully")
except ImportError as e:
    print(f"❌ Missing dependency: {e}")
    print("Install with: pip install tensorflow coremltools numpy")
    exit(1)


def create_embedding_model(input_size=7, embedding_size=128):
    """
    Create a simple neural network for embedding generation.

    Architecture:
    - Input: 7 features (HR, HRV, RMSSD, SDNN, typing, scrolling, app switches)
    - Hidden layers with ReLU activation
    - Output: 128-dimensional embedding
    """
    model = keras.Sequential([
        keras.layers.Input(shape=(input_size,), name='input'),
        keras.layers.Dense(64, activation='relu', name='dense1'),
        keras.layers.BatchNormalization(name='bn1'),
        keras.layers.Dropout(0.2, name='dropout1'),
        keras.layers.Dense(128, activation='relu', name='dense2'),
        keras.layers.BatchNormalization(name='bn2'),
        keras.layers.Dense(embedding_size, activation='tanh', name='embedding')
    ])

    model.compile(
        optimizer='adam',
        loss='mse'
    )

    print(f"✅ Created model with input size {input_size} and embedding size {embedding_size}")
    model.summary()

    return model


def train_placeholder_model(model, num_samples=1000):
    """
    Train the model with synthetic data.

    In production, replace this with actual training data:
    - X: Processed signals (HR, HRV, RMSSD, SDNN, typing, scrolling, app switches)
    - y: Target embeddings (from a pre-trained larger model or labeled data)
    """
    print(f"\n🔄 Training with {num_samples} synthetic samples...")

    # Generate synthetic training data
    X = np.random.rand(num_samples, 7).astype(np.float32)

    # Normalize to realistic ranges
    X[:, 0] = X[:, 0] * 0.5 + 0.3  # HR: 60-180 bpm normalized
    X[:, 1] = X[:, 1] * 0.5 + 0.2  # HRV: 20-120 ms normalized
    X[:, 2] = X[:, 2] * 0.5 + 0.2  # RMSSD
    X[:, 3] = X[:, 3] * 0.5 + 0.2  # SDNN
    X[:, 4] = X[:, 4] * 0.3        # Typing rate
    X[:, 5] = X[:, 5] * 0.3        # Scrolling rate
    X[:, 6] = X[:, 6] * 0.2        # App switch rate

    # Create synthetic target embeddings (in production, use real targets)
    y = np.random.rand(num_samples, 128).astype(np.float32) * 2 - 1  # Range: -1 to 1

    # Train the model
    history = model.fit(
        X, y,
        epochs=10,
        batch_size=32,
        validation_split=0.2,
        verbose=1
    )

    print("✅ Training complete")
    return model


def convert_to_coreml(model, output_path='HSIEmbeddingModel.mlmodel'):
    """
    Convert the TensorFlow model to Core ML format.
    """
    print(f"\n🔄 Converting to Core ML format...")

    # Convert to Core ML
    coreml_model = ct.convert(
        model,
        inputs=[ct.TensorType(name='input', shape=(1, 7))],
        outputs=[ct.TensorType(name='embedding')],
        minimum_deployment_target=ct.target.iOS15
    )

    # Add metadata
    coreml_model.author = 'Synheart HSI'
    coreml_model.short_description = 'Embedding generation model for Human State Interface'
    coreml_model.version = '1.0.0'

    # Add input/output descriptions
    coreml_model.input_description['input'] = (
        'Normalized signal features: [HR, HRV, RMSSD, SDNN, typing_rate, '
        'scrolling_rate, app_switch_rate]'
    )
    coreml_model.output_description['embedding'] = (
        '128-dimensional embedding vector representing human state'
    )

    # Save the model
    coreml_model.save(output_path)
    print(f"✅ Core ML model saved to: {output_path}")

    return coreml_model


def main():
    print("=" * 60)
    print("HSI iOS - Core ML Embedding Model Generator")
    print("=" * 60)

    # Create model
    model = create_embedding_model(input_size=7, embedding_size=128)

    # Train with synthetic data
    model = train_placeholder_model(model, num_samples=1000)

    # Convert to Core ML
    coreml_model = convert_to_coreml(model, 'HSIEmbeddingModel.mlmodel')

    print("\n" + "=" * 60)
    print("✅ SUCCESS!")
    print("=" * 60)
    print("\nNext steps:")
    print("1. Add HSIEmbeddingModel.mlmodel to your Xcode project")
    print("2. Xcode will compile it to .mlmodelc format")
    print("3. Use CoreMLEmbeddingModel in FusionEngine:")
    print("")
    print("   let modelURL = Bundle.main.url(")
    print("       forResource: \"HSIEmbeddingModel\",")
    print("       withExtension: \"mlmodelc\"")
    print("   )")
    print("   let embeddingModel = CoreMLEmbeddingModel(modelURL: modelURL)")
    print("   let fusionEngine = FusionEngine(embeddingModel: embeddingModel)")
    print("")
    print("4. Train a real model with actual data for production use")
    print("")


if __name__ == "__main__":
    main()
