#!/bin/bash

add_to_path() {
    local new_paths="$1"
    local current_paths
    local path_to_add
    
    # Split current LD_LIBRARY_PATH into an array
    IFS=':' read -ra current_paths <<< "${LD_LIBRARY_PATH:-}"
    
    # Split new paths into an array
    IFS=':' read -ra paths_to_add <<< "$new_paths"
    
    # Process each new path
    for path_to_add in "${paths_to_add[@]}"; do
        # Skip empty paths
        [ -z "$path_to_add" ] && continue
        
        # Remove trailing slash if present
        path_to_add="${path_to_add%/}"
        
        # Check if path already exists
        local is_duplicate=false
        for existing_path in "${current_paths[@]}"; do
            # Remove trailing slash for comparison
            existing_path="${existing_path%/}"
            if [ "$existing_path" = "$path_to_add" ]; then
                echo -e "\033[33m⚠\033[0m \033[1mWARN\033[0m: Path already exists in LD_LIBRARY_PATH: $path_to_add"
                is_duplicate=true
                break
            fi
        done
        
        # Add path if it's not a duplicate
        if [ "$is_duplicate" = false ]; then
            if [ -z "$LD_LIBRARY_PATH" ]; then
                LD_LIBRARY_PATH="$path_to_add"
            else
                LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$path_to_add"
            fi
            echo -e "\033[34m🛈\033[0m \033[1mINFO\033[0m: Added to LD_LIBRARY_PATH: $path_to_add"
        fi
    done
}

# If $CONDA_PREFIX is not set, then we are not in a Conda environment
if [ -z "$CONDA_PREFIX" ]; then
    echo -e "\033[31m✘\033[0m \033[1mERROR\033[0m: Not in a Conda environment. Please activate a Conda environment first."
    exit 1
fi

# Navigate to the Conda environment directory
cd "$CONDA_PREFIX" || { echo -e "\033[31m✘\033[0m \033[1mERROR\033[0m: Failed to navigate to $CONDA_PREFIX"; exit 1; }

# Create necessary directories
mkdir -p ./etc/conda/activate.d

# Define paths for activation and deactivation scripts
ACTIVATE_SCRIPT="$CONDA_PREFIX/etc/conda/activate.d/env_vars.sh"

# First add $CONDA_PREFIX/lib to LD_LIBRARY_PATH
add_to_path "$CONDA_PREFIX/lib"

# Try to locate TensorRT path
TENSORRT_LIBS_PATH=$(dirname $(python -c "import tensorrt_libs;print(tensorrt_libs.__file__)" 2>/dev/null) 2>/dev/null)
if [ -d "$TENSORRT_LIBS_PATH" ]; then
    echo -e "\033[34m🛈\033[0m \033[1mINFO\033[0m: Found TensorRT path: $TENSORRT_LIBS_PATH"
    add_to_path "$TENSORRT_LIBS_PATH"
else
    echo -e "\033[33m⚠\033[0m \033[1mWARN\033[0m: TensorRT path not found, not adding it to LD_LIBRARY_PATH"
fi

# Try to locate CUDA path
CUDA_PATH="/usr/local/cuda/lib64"
if [ -d "$CUDA_PATH" ]; then
    echo -e "\033[34m🛈\033[0m \033[1mINFO\033[0m: Found CUDA path: $CUDA_PATH"
    add_to_path "$CUDA_PATH"
else
    echo -e "\033[33m⚠\033[0m \033[1mWARN\033[0m: CUDA path $CUDA_PATH not found, not adding it to LD_LIBRARY_PATH"
fi

# Try to locate NVIDIA/cuda paths
NVIDIA_DIR=$(dirname $(dirname $(python -c "import nvidia.cudnn;print(nvidia.cudnn.__file__)" 2>/dev/null)) 2>/dev/null)
if [ -d "$NVIDIA_DIR" ]; then
    CUDNN_PATHS=$(echo ${NVIDIA_DIR}/*/lib/ | sed -r 's/\s+/:/g')
    echo -e "\033[34m🛈\033[0m \033[1mINFO\033[0m: Found CUDA paths: $CUDNN_PATHS"
    add_to_path "$CUDNN_PATHS"
else
    echo -e "\033[33m⚠\033[0m \033[1mWARN\033[0m: nvidia/cuda, cuDNN, cuFFT, etc. paths not found, not adding it to LD_LIBRARY_PATH"
fi

# Write the activation script only if we found at least one path
if [ -n "$LD_LIBRARY_PATH" ]; then
    echo -e "\033[34m🛈\033[0m \033[1mINFO\033[0m: New LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
    cat > "$ACTIVATE_SCRIPT" << EOF
#!/bin/sh
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
EOF

    # Make the script executable
    chmod +x "$ACTIVATE_SCRIPT"

    # Provide feedback to the user
    echo -e "\033[34m🛈\033[0m \033[1mINFO\033[0m: LD_LIBRARY_PATH activation script has been set up."
    echo -e "\033[34m🛈\033[0m \033[1mINFO\033[0m: Activation script: $ACTIVATE_SCRIPT"
else
    echo -e "\033[33m⚠\033[0m \033[1mWARN\033[0m: No valid library paths found. No activation script created."
fi