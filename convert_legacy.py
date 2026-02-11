"""
Convert Depth Anything V2 PyTorch model to ONNX with opset 11 (legacy mode)
Uses traditional torch.onnx.export instead of TorchDynamo
"""
import torch
import os
import subprocess
import sys

# Configuration
INPUT_SIZE = 518  # Default size that works well - 37*14
OPSET_VERSION = 11  # Very old and compatible opset
MODEL_VARIANT = 'vits'

def clone_depth_anything():
    if not os.path.exists('Depth-Anything-V2'):
        print("Cloning Depth Anything V2 repository...")
        subprocess.run([
            'git', 'clone', '--depth', '1',
            'https://github.com/DepthAnything/Depth-Anything-V2.git'
        ], check=True)
    else:
        print("Depth Anything V2 repository already exists")

def convert_to_onnx():
    clone_depth_anything()
    sys.path.insert(0, 'Depth-Anything-V2')
    
    from depth_anything_v2.dpt import DepthAnythingV2
    
    model_configs = {
        'vits': {'encoder': 'vits', 'features': 64, 'out_channels': [48, 96, 192, 384]},
    }
    
    print(f"\n=== Converting Depth Anything V2 ({MODEL_VARIANT}) to ONNX ===")
    print(f"Input size: {INPUT_SIZE}x{INPUT_SIZE}")
    print(f"Opset version: {OPSET_VERSION}")
    
    pth_file = f'depth_anything_v2_{MODEL_VARIANT}.pth'
    if not os.path.exists(pth_file):
        print(f"\n❌ Error: {pth_file} not found!")
        return False
    
    print(f"\n✅ Found model: {pth_file}")
    
    print("Loading model...")
    model = DepthAnythingV2(**model_configs[MODEL_VARIANT])
    model.load_state_dict(torch.load(pth_file, map_location='cpu', weights_only=True))
    model.eval()
    print("✅ Model loaded successfully!")
    
    # Create dummy input
    dummy_input = torch.randn(1, 3, INPUT_SIZE, INPUT_SIZE)
    
    output_path = f'depth_anything_v2_opset{OPSET_VERSION}.onnx'
    
    print(f"\nExporting to ONNX (legacy mode)...")
    
    # Use legacy export with trace mode
    with torch.no_grad():
        torch.onnx.export(
            model,
            dummy_input,
            output_path,
            export_params=True,
            opset_version=OPSET_VERSION,
            do_constant_folding=True,
            input_names=['input'],
            output_names=['depth'],
            # Use legacy scripting mode
            verbose=False
        )
    
    file_size = os.path.getsize(output_path) / 1024 / 1024
    print(f"\n✅ Successfully exported to: {output_path}")
    print(f"   File size: {file_size:.1f} MB")
    
    if file_size < 10:
        print("⚠️ Warning: File size seems too small!")
    
    print("\n=== Next Steps ===")
    print(f"Copy-Item -Path '{output_path}' -Destination 'assets\\models\\depth_anything_v2.onnx' -Force")
    print("flutter run")
    
    return True

if __name__ == '__main__':
    try:
        # Force use of legacy exporter
        os.environ['TORCH_USE_HOT_SWAP_TRACED_EXPORT'] = '0'
        success = convert_to_onnx()
        if not success:
            sys.exit(1)
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
