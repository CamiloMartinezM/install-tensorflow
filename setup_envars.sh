#!/bin/bash

# If $CONDA_PREFIX is not set, then we are not in a Conda environment
if [ -z "$CONDA_PREFIX" ]; then
    echo "Not in a Conda environment. Please activate a Conda environment first."
    exit 1
fi

# Navigate to the Conda environment directory
cd "$CONDA_PREFIX" || { echo "Failed to navigate to $CONDA_PREFIX"; exit 1; }

# Create necessary directories
mkdir -p ./etc/conda/activate.d

# Define paths for activation and deactivation scripts
ACTIVATE_SCRIPT="$CONDA_PREFIX/etc/conda/activate.d/env_vars.sh"

# Locate TensorRT, cuDNN and CUDA paths
TENSORRT_LIBS_PATH=$(dirname $(python -c "import tensorrt_libs;print(tensorrt_libs.__file__)"))
SITE_PACKAGES_PATH="$CONDA_PREFIX/lib/python$(python -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')/site-packages"
CUDNN_PATH="$SITE_PACKAGES_PATH/nvidia/cudnn/lib"
CUDA_PATH="/usr/local/cuda/lib64"

# Make sure that all paths exist
[ -d "$TENSORRT_LIBS_PATH" ] || { echo "TensorRT path not found: $TENSORRT_LIBS_PATH"; exit 1; }
[ -d "$CUDNN_PATH" ] || { echo "cuDNN path not found: $CUDNN_PATH"; exit 1; }

# Write the activation script to set LD_LIBRARY_PATH
cat > "$ACTIVATE_SCRIPT" << EOF
#!/bin/sh

export LD_LIBRARY_PATH="$TENSORRT_LIBS_PATH:\$LD_LIBRARY_PATH"
export LD_LIBRARY_PATH="$CUDNN_PATH:\$LD_LIBRARY_PATH"
export LD_LIBRARY_PATH="$CUDA_PATH:\$LD_LIBRARY_PATH"
export PATH="$CUDA_PATH:\$PATH"
EOF

# Make the scripts executable
chmod +x "$ACTIVATE_SCRIPT" 

# Provide feedback to the user
echo "LD_LIBRARY_PATH activation script has been set up."
echo "Activation script: $ACTIVATE_SCRIPT"