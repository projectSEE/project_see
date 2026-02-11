"""
Convert dpt_swin2_tiny_256.pt to TFLite directly using ONNX as intermediate format.
Uses the pre-downloaded .pt file from GitHub releases.
"""

import torch
import numpy as np
import os
import sys

# Input/output paths
PT_PATH = "assets/models/dpt_swin2_tiny_256.pt"
ONNX_PATH = "assets/models/dpt_swin2_tiny_256.onnx"
TFLITE_PATH = "assets/models/midas_small.tflite"

def load_model_from_checkpoint():
    """Load model directly from checkpoint file"""
    print("🔽 Loading dpt_swin2_tiny_256.pt...")
    
    # Clone MiDaS repo for model architecture
    if not os.path.exists("MiDaS"):
        print("📥 Cloning MiDaS repository for model definition...")
        os.system("git clone --depth 1 https://github.com/isl-org/MiDaS.git")
    
    # Add MiDaS to path
    sys.path.insert(0, "MiDaS")
    
    from midas.dpt_depth import DPTDepthModel
    
    # Create model
    model = DPTDepthModel(
        path=PT_PATH,
        backbone="swin2t16_256",
        non_negative=True,
    )
    model.eval()
    
    print(f"✅ Model loaded from {PT_PATH}")
    return model

def convert_to_onnx(model):
    """Convert to ONNX format"""
    print("📦 Converting to ONNX...")
    
    dummy_input = torch.randn(1, 3, 256, 256)
    
    with torch.no_grad():
        torch.onnx.export(
            model,
            dummy_input,
            ONNX_PATH,
            export_params=True,
            opset_version=14,
            do_constant_folding=True,
            input_names=['input'],
            output_names=['output'],
        )
    
    print(f"✅ ONNX saved: {ONNX_PATH}")
    print(f"   Size: {os.path.getsize(ONNX_PATH) / (1024*1024):.2f} MB")

def convert_to_tflite():
    """Convert ONNX to TFLite"""
    print("🔄 Converting ONNX to TFLite...")
    
    import onnx
    import tensorflow as tf
    from onnx_tf.backend import prepare
    
    # Load ONNX
    onnx_model = onnx.load(ONNX_PATH)
    
    # Convert to TF
    tf_rep = prepare(onnx_model)
    tf_rep.export_graph("temp_saved_model")
    
    # Convert to TFLite
    converter = tf.lite.TFLiteConverter.from_saved_model("temp_saved_model")
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS,
        tf.lite.OpsSet.SELECT_TF_OPS
    ]
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    
    tflite_model = converter.convert()
    
    with open(TFLITE_PATH, 'wb') as f:
        f.write(tflite_model)
    
    # Cleanup
    import shutil
    shutil.rmtree("temp_saved_model", ignore_errors=True)
    os.remove(ONNX_PATH)
    
    print(f"✅ TFLite saved: {TFLITE_PATH}")
    print(f"   Size: {os.path.getsize(TFLITE_PATH) / (1024*1024):.2f} MB")

def main():
    print("=" * 60)
    print("DPT Swin2 Tiny 256 → TFLite Converter")
    print("=" * 60)
    
    if not os.path.exists(PT_PATH):
        print(f"❌ Error: {PT_PATH} not found!")
        return
    
    try:
        model = load_model_from_checkpoint()
        convert_to_onnx(model)
        convert_to_tflite()
        
        print("\n" + "=" * 60)
        print("✅ Conversion complete!")
        print("=" * 60)
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()
