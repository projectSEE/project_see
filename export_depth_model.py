"""
Export Depth Anything V2 to ONNX using LEGACY exporter (dynamo=False)
This bypasses TorchDynamo which forces opset 18+
"""
import torch
import os
import subprocess
import sys

# Configuration
INPUT_SIZE = 252  # 14 × 18, mobile-friendly
OPSET_VERSION = 17

def clone_depth_anything():
    if not os.path.exists('Depth-Anything-V2'):
        print("Cloning Depth Anything V2 repository...")
        subprocess.run([
            'git', 'clone', '--depth', '1',
            'https://github.com/DepthAnything/Depth-Anything-V2.git'
        ], check=True)
    else:
        print("Depth Anything V2 repository already exists")

def export_model():
    clone_depth_anything()
    sys.path.insert(0, 'Depth-Anything-V2')
    
    from depth_anything_v2.dpt import DepthAnythingV2
    
    model_configs = {
        'vits': {'encoder': 'vits', 'features': 64, 'out_channels': [48, 96, 192, 384]},
    }
    
    print(f"\n=== Depth Anything V2 ONNX Export (Legacy Mode) ===")
    print(f"Input size: {INPUT_SIZE}x{INPUT_SIZE}")
    print(f"Target opset: {OPSET_VERSION}")
    
    pth_file = 'depth_anything_v2_vits.pth'
    if not os.path.exists(pth_file):
        print(f"\n❌ Error: {pth_file} not found!")
        return False
    
    print(f"✅ Found model: {pth_file}")
    
    # Load model
    print("Loading model...")
    model = DepthAnythingV2(**model_configs['vits'])
    model.load_state_dict(torch.load(pth_file, map_location='cpu', weights_only=True))
    model.eval()
    model.cpu()
    print("✅ Model loaded!")
    
    # Dummy input
    dummy_input = torch.randn(1, 3, INPUT_SIZE, INPUT_SIZE)
    
    output_path = f'depth_anything_v2_{INPUT_SIZE}x{INPUT_SIZE}_opset{OPSET_VERSION}.onnx'
    
    print(f"\nExporting to ONNX with dynamo=False...")
    
    # ★★★ KEY: Force legacy exporter ★★★
    try:
        # Method 1: dynamo=False parameter
        torch.onnx.export(
            model,
            dummy_input,
            output_path,
            dynamo=False,  # Force legacy TorchScript exporter
            opset_version=OPSET_VERSION,
            input_names=['input'],
            output_names=['depth'],
            dynamic_axes=None,
            do_constant_folding=True,
        )
    except TypeError as e:
        if "dynamo" in str(e):
            print("dynamo parameter not supported, trying environment variable...")
            # Method 2: Environment variable
            os.environ["PYTORCH_ONNX_USE_LEGACY_EXPORTER"] = "1"
            torch.onnx.export(
                model,
                dummy_input,
                output_path,
                opset_version=OPSET_VERSION,
                input_names=['input'],
                output_names=['depth'],
                dynamic_axes=None,
                do_constant_folding=True,
            )
        else:
            raise e
    
    # Verify
    file_size = os.path.getsize(output_path) / (1024 * 1024)
    print(f"\n✅ Exported to: {output_path}")
    print(f"   File size: {file_size:.1f} MB")
    
    if file_size < 10:
        print("⚠️ Warning: File too small, export may have failed!")
        return False
    
    # Validate with ONNX
    try:
        import onnx
        model_onnx = onnx.load(output_path)
        onnx.checker.check_model(model_onnx)
        print(f"   Opset version: {model_onnx.opset_import[0].version}")
        print("✅ ONNX validation passed!")
    except Exception as e:
        print(f"⚠️ ONNX validation warning: {e}")
    
    # Test inference
    try:
        import onnxruntime as ort
        import numpy as np
        
        session = ort.InferenceSession(output_path)
        test_input = np.random.randn(1, 3, INPUT_SIZE, INPUT_SIZE).astype(np.float32)
        result = session.run(None, {'input': test_input})
        print(f"   Output shape: {result[0].shape}")
        print(f"   Output range: [{result[0].min():.3f}, {result[0].max():.3f}]")
        print("✅ Inference test passed!")
    except Exception as e:
        print(f"⚠️ Inference test error: {e}")
    
    print("\n=== Next Steps ===")
    print(f"Copy-Item -Path '{output_path}' -Destination 'assets\\models\\depth_anything_v2.onnx' -Force")
    print("flutter run")
    
    return True

if __name__ == '__main__':
    try:
        success = export_model()
        if not success:
            sys.exit(1)
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
