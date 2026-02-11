"""
Convert Depth Anything V2 PyTorch model to ONNX with opset 17
This script does NOT require pip installation of Depth-Anything-V2

Steps:
1. Download depth_anything_v2_vits.pth to this directory
2. Run: python convert_to_onnx.py
"""
import torch
import torch.nn as nn
import os
import subprocess
import sys

# Configuration
INPUT_SIZE = 252  # Must be multiple of 14 (ViT patch size). 252 = 18*14
OPSET_VERSION = 17  # Compatible with mobile ONNX Runtime
MODEL_VARIANT = 'vits'  # Small model

def clone_depth_anything():
    """Clone Depth Anything V2 repo if not exists"""
    if not os.path.exists('Depth-Anything-V2'):
        print("Cloning Depth Anything V2 repository...")
        subprocess.run([
            'git', 'clone', '--depth', '1',
            'https://github.com/DepthAnything/Depth-Anything-V2.git'
        ], check=True)
        print("Repository cloned successfully!")
    else:
        print("Depth Anything V2 repository already exists")

def convert_to_onnx():
    # Clone repository first
    clone_depth_anything()
    
    # Add to path
    sys.path.insert(0, 'Depth-Anything-V2')
    
    # Import after adding to path
    from depth_anything_v2.dpt import DepthAnythingV2
    
    # Model configuration for ViT-S (Small)
    model_configs = {
        'vits': {'encoder': 'vits', 'features': 64, 'out_channels': [48, 96, 192, 384]},
        'vitb': {'encoder': 'vitb', 'features': 128, 'out_channels': [96, 192, 384, 768]},
        'vitl': {'encoder': 'vitl', 'features': 256, 'out_channels': [256, 512, 1024, 1024]},
    }
    
    print(f"\n=== Converting Depth Anything V2 ({MODEL_VARIANT}) to ONNX ===")
    print(f"Input size: {INPUT_SIZE}x{INPUT_SIZE}")
    print(f"Opset version: {OPSET_VERSION}")
    
    # Check for .pth file
    pth_file = f'depth_anything_v2_{MODEL_VARIANT}.pth'
    if not os.path.exists(pth_file):
        print(f"\n❌ Error: {pth_file} not found!")
        print("\nPlease download it from:")
        print("https://huggingface.co/depth-anything/Depth-Anything-V2-Small/resolve/main/depth_anything_v2_vits.pth")
        print(f"\nThen save it as: {pth_file}")
        return False
    
    print(f"\n✅ Found model: {pth_file}")
    
    # Create model
    print("Loading model...")
    model = DepthAnythingV2(**model_configs[MODEL_VARIANT])
    model.load_state_dict(torch.load(pth_file, map_location='cpu'))
    model.eval()
    print("✅ Model loaded successfully!")
    
    # Create dummy input (NCHW format, float32)
    dummy_input = torch.randn(1, 3, INPUT_SIZE, INPUT_SIZE)
    
    # Output path
    output_path = f'depth_anything_v2_opset{OPSET_VERSION}.onnx'
    
    print(f"\nExporting to ONNX...")
    
    # Export to ONNX with opset 17
    torch.onnx.export(
        model,
        dummy_input,
        output_path,
        export_params=True,
        opset_version=OPSET_VERSION,
        do_constant_folding=True,
        input_names=['input'],
        output_names=['depth'],
        dynamic_axes=None  # Fixed size for mobile
    )
    
    file_size = os.path.getsize(output_path) / 1024 / 1024
    print(f"\n✅ Successfully exported to: {output_path}")
    print(f"   File size: {file_size:.1f} MB")
    
    print("\n=== Next Steps ===")
    print(f"1. Copy the model to your Flutter project:")
    print(f"   cp {output_path} assets/models/depth_anything_v2.onnx")
    print("2. Run: flutter run")
    
    return True

if __name__ == '__main__':
    try:
        success = convert_to_onnx()
        if not success:
            sys.exit(1)
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
