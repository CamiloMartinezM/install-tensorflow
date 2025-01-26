#!/bin/bash

# Default values
ENV_NAME="tensorflow-2.16"
PYTHON_VERSION="3.12"
CUDA_VERSION="12.3.0"
CUDNN_VERSION="8.9"
TF_VERSION="2.16.1"

# Get the directory where the setup script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo -e "Running script from $SCRIPT_DIR"

# Help function
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -e, --env-name NAME        Environment name (default: $ENV_NAME)"
    echo "  -p, --python-version VER   Python version (default: $PYTHON_VERSION)"
    echo "  -c, --cuda-version VER     CUDA version (default: $CUDA_VERSION)"
    echo "  -n, --cudnn-version VER    cuDNN version (default: $CUDNN_VERSION)"
    echo "  -t, --tf-version VER       TensorFlow version (default: $TF_VERSION)"
    echo "  -h, --help                 Show this help message"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--env-name)
            ENV_NAME="$2"
            shift 2
            ;;
        -p|--python-version)
            PYTHON_VERSION="$2"
            shift 2
            ;;
        -c|--cuda-version)
            CUDA_VERSION="$2"
            shift 2
            ;;
        -n|--cudnn-version)
            CUDNN_VERSION="$2"
            shift 2
            ;;
        -t|--tf-version)
            TF_VERSION="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo -e "\033[31m✘\033[0m \033[1mERROR\033[0m: Unknown parameter: $1"
            show_help
            ;;
    esac
done

# Function to check command success
check_command() {
    if [ $? -ne 0 ]; then
        echo -e "\033[31m✘\033[0m \033[1mERROR\033[0m: $1 failed"
        exit 1
    else
        echo -e "\033[34m🛈\033[0m \033[1mINFO\033[0m: $1 completed successfully"
    fi
}

# Extract major.minor version from CUDA_VERSION for cuda-version parameter
CUDA_MAJOR_MINOR=$(echo $CUDA_VERSION | cut -d'.' -f1,2)

# Main setup process
echo -e "\033[34m🛈\033[0m \033[1mINFO\033[0m: Setting up environment with following parameters:"
echo "    Environment name: $ENV_NAME"
echo "    Python version: $PYTHON_VERSION"
echo "    CUDA version: $CUDA_VERSION"
echo "    cuDNN version: $CUDNN_VERSION"
echo "    TensorFlow version: $TF_VERSION"

# Create and activate conda environment
conda create --name "$ENV_NAME" "python=$PYTHON_VERSION" -y
check_command "CONDA environment $ENV_NAME creation"

# Source conda.sh to enable conda activate in scripts
source "$(conda info --base)/etc/profile.d/conda.sh"

conda activate "$ENV_NAME"
check_command "CONDA environment $ENV_NAME activation"

# Install CUDA toolkit
# conda install cuda "nvidia/label/cuda-$CUDA_VERSION::cuda-toolkit" -c "nvidia/label/cuda-$CUDA_VERSION" -y
conda install "nvidia/label/cuda-$CUDA_VERSION::cuda-toolkit" -c "nvidia/label/cuda-$CUDA_VERSION" -y || {
    echo -e "\033[33m⚠\033[0m \033[1mWARN\033[0m: CUDA toolkit installation failed, continuing anyway"
    check_command "cuda-toolkit=$CUDA_VERSION installation"
}

# Set XLA flags
conda env config vars set LD_LIBRARY_PATH="$CONDA_PREFIX/lib"
conda env config vars set XLA_FLAGS="--xla_gpu_cuda_data_dir=$CONDA_PREFIX"
conda deactivate
conda activate "$ENV_NAME"
check_command "XLA flags configuration"

# Install cuDNN
# conda install "cudnn=$CUDNN_VERSION" "cuda-version=$CUDA_MAJOR_MINOR" -y
conda config --remove channels nvidia
conda install -c nvidia "cudnn=$CUDNN_VERSION" "cuda-version=$CUDA_MAJOR_MINOR" -y || {
    echo -e "\033[33m⚠\033[0m \033[1mWARN\033[0m: Failed to install cuDNN using NVIDIA channel, trying conda-forge"
    conda install -c conda-forge "cudnn=$CUDNN_VERSION" "cuda-version=$CUDA_MAJOR_MINOR" -y || {
        echo -e "\033[33m⚠\033[0m \033[1mWARN\033[0m: Failed to install cuDNN using conda-forge, continuing anyway"
        check_command "cuDNN=$CUDNN_VERSION with cuda-version=$CUDA_MAJOR_MINOR installation"
    }
}

# Install TensorFlow
pip install "tensorflow[and-cuda]==$TF_VERSION"
check_command "tensorflow[and-cuda]=$TF_VERSION installation"

# Install TensorRT
pip install --upgrade pip setuptools wheel 
pip install nvidia-pyindex
pip install nvidia-tensorrt tensorrt --extra-index-url https://pypi.nvidia.com
check_command "TensorRT installation"

# Run additional setup scripts
source setup_envars.sh
check_command "Environment variables setup"

conda deactivate
conda activate "$ENV_NAME"
check_command "CONDA environment $ENV_NAME reactivation"

python "$SCRIPT_DIR/create_symlinks.py"
check_command "Symlinks creation"

conda deactivate
conda activate "$ENV_NAME"
check_command "Final CONDA environment $ENV_NAME activation"

# Test GPU
echo -e "\033[34m🛈\033[0m \033[1mINFO\033[0m: Navigating to $SCRIPT_DIR"
cd "$SCRIPT_DIR"
source test_gpu.sh
check_command "GPU test"

echo -e "\033[34m🛈\033[0m \033[1mINFO\033[0m: Setup completed successfully"