"""
Convert ONNX model to TFLite format.
"""

import os

ONNX_PATH = "assets/models/dpt_swin2_tiny_256.onnx"
TFLITE_PATH = "assets/models/midas_small.tflite"

def main():
    print("=" * 60)
    print("ONNX → TFLite Converter")
    print("=" * 60)
    
    if not os.path.exists(ONNX_PATH):
        print(f"❌ Error: {ONNX_PATH} not found!")
        return
    
    print(f"📥 Input: {ONNX_PATH}")
    print(f"   Size: {os.path.getsize(ONNX_PATH) / (1024*1024):.2f} MB")
    
    # Import required libraries
    print("📦 Loading libraries...")
    import onnx
    import tensorflow as tf
    from onnx_tf.backend import prepare
    
    # Load ONNX model
    print("🔄 Loading ONNX model...")
    onnx_model = onnx.load(ONNX_PATH)
    
    # Convert to TensorFlow
    print("🔄 Converting to TensorFlow...")
    tf_rep = prepare(onnx_model)
    
    saved_model_path = "temp_saved_model"
    tf_rep.export_graph(saved_model_path)
    print(f"✅ TensorFlow SavedModel exported")
    
    # Convert to TFLite
    print("🔄 Converting to TFLite...")
    converter = tf.lite.TFLiteConverter.from_saved_model(saved_model_path)
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS,
        tf.lite.OpsSet.SELECT_TF_OPS
    ]
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    
    tflite_model = converter.convert()
    
    # Save TFLite model
    with open(TFLITE_PATH, 'wb') as f:
        f.write(tflite_model)
    
    # Cleanup
    import shutil
    shutil.rmtree(saved_model_path, ignore_errors=True)
    
    print("\n" + "=" * 60)
    print(f"✅ TFLite saved: {TFLITE_PATH}")
    print(f"   Size: {os.path.getsize(TFLITE_PATH) / (1024*1024):.2f} MB")
    print("=" * 60)

if __name__ == "__main__":
    main()
