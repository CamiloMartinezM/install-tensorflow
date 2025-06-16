#!/bin/bash

# Default values
ENV_NAME="tensorflow-2.16"
PYTHON_VERSION="3.12"
CUDA_VERSION="12.3.0"
CUDNN_VERSION="8.9"
TF_VERSION="2.16.1"
ENV_MANAGER="micromamba"  # Default environment manager

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
    echo "  -m, --env-manager TYPE     Environment manager: conda or micromamba (default: $ENV_MANAGER)"
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
        -m|--env-manager)
            ENV_MANAGER="$2"
            # Validate env manager
            if [[ "$ENV_MANAGER" != "conda" && "$ENV_MANAGER" != "micromamba" ]]; then
                echo -e "\033[31m✘\033[0m \033[1mERROR\033[0m: Environment manager must be either 'conda' or 'micromamba'"
                exit 1
            fi
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
echo "    Environment manager: $ENV_MANAGER"
echo "    Environment name: $ENV_NAME"
echo "    Python version: $PYTHON_VERSION"
echo "    CUDA version: $CUDA_VERSION"
echo "    cuDNN version: $CUDNN_VERSION"
echo "    TensorFlow version: $TF_VERSION"

# Create and activate conda environment
$ENV_MANAGER create --name $ENV_NAME python=$PYTHON_VERSION -y || {
    echo -e "\033[31m✘\033[0m \033[1mERROR\033[0m: Failed to create conda environment $ENV_NAME"
    exit 1
}

# Source conda.sh to enable conda activate in scripts
if [[ "$ENV_MANAGER" == "conda" ]]; then
    source "$(conda info --base)/etc/profile.d/conda.sh"
elif [[ "$ENV_MANAGER" == "micromamba" ]]; then
    eval "$(micromamba shell hook --shell bash)"
else
    echo -e "\033[31m✘\033[0m \033[1mERROR\033[0m: Unknown environment manager: $ENV_MANAGER"
    exit 1
fi

$ENV_MANAGER activate "$ENV_NAME" || {
    echo -e "\033[31m✘\033[0m \033[1mERROR\033[0m: Failed to activate $ENV_MANAGER environment $ENV_NAME"
    exit 1
}

# Install CUDA toolkit
# conda install cuda "nvidia/label/cuda-$CUDA_VERSION::cuda-toolkit" -c "nvidia/label/cuda-$CUDA_VERSION" -y
$ENV_MANAGER install "nvidia/label/cuda-$CUDA_VERSION::cuda-toolkit" -c "nvidia/label/cuda-$CUDA_VERSION" -y || {
    echo -e "\033[33m⚠\033[0m \033[1mWARN\033[0m: CUDA toolkit installation failed, continuing anyway"
    # check_command "cuda-toolkit=$CUDA_VERSION installation"
}

# Set XLA flags
# $ENV_MANAGER env config vars set LD_LIBRARY_PATH="$CONDA_PREFIX/lib"
# $ENV_MANAGER env config vars set XLA_FLAGS="--xla_gpu_cuda_data_dir=$CONDA_PREFIX"
$ENV_MANAGER deactivate
$ENV_MANAGER activate "$ENV_NAME"

# Install cuDNN
# conda install "cudnn=$CUDNN_VERSION" "cuda-version=$CUDA_MAJOR_MINOR" -y
$ENV_MANAGER config --remove channels nvidia
$ENV_MANAGER install -c nvidia "cudnn=$CUDNN_VERSION" "cuda-version=$CUDA_MAJOR_MINOR" -y || {
    echo -e "\033[33m⚠\033[0m \033[1mWARN\033[0m: Failed to install cuDNN using NVIDIA channel, trying conda-forge"
    $ENV_MANAGER install -c conda-forge "cudnn=$CUDNN_VERSION" "cuda-version=$CUDA_MAJOR_MINOR" -y || {
        echo -e "\033[33m⚠\033[0m \033[1mWARN\033[0m: Failed to install cuDNN using conda-forge, continuing anyway"
        # check_command "cuDNN=$CUDNN_VERSION with cuda-version=$CUDA_MAJOR_MINOR installation"
    }
}

# Upgrade pip
pip install --upgrade pip setuptools wheel 

# Install numpy<2.0
pip install 'numpy<2.0'

# Install TensorFlow
pip install "tensorflow[and-cuda]==$TF_VERSION" --extra-index-url https://pypi.nvidia.com || {
    echo -e "\033[33m⚠\033[0m \033[1mWARN\033[0m: tensorflow[and-cuda]=$TF_VERSION installation failed, continuing anyway"
}

# Install TensorRT
pip install nvidia-pyindex || {
    echo -e "\033[33m⚠\033[0m \033[1mWARN\033[0m: nvidia-pyindex installation failed, continuing anyway"
}
pip install nvidia-tensorrt tensorrt --extra-index-url https://pypi.nvidia.com || {
    echo -e "\033[33m⚠\033[0m \033[1mWARN\033[0m: nvidia-tensorrt installation failed, continuing anyway"
}

# Install numpy<2.0
pip install 'numpy<2.0'

# Run additional setup scripts
source setup_envars.sh 

$ENV_MANAGER deactivate
$ENV_MANAGER activate "$ENV_NAME"

python "$SCRIPT_DIR/create_symlinks.py" || {
    echo -e "\033[33m⚠\033[0m \033[1mWARN\033[0m: create_symlinks.py script failed, continuing anyway"
}

$ENV_MANAGER deactivate
$ENV_MANAGER activate "$ENV_NAME"

# Test GPU
echo -e "\033[34m🛈\033[0m \033[1mINFO\033[0m: Navigating to $SCRIPT_DIR"
cd "$SCRIPT_DIR"
source test_gpu.sh || {
    echo -e "\033[33m⚠\033[0m \033[1mWARN\033[0m: test_gpu.sh script failed, continuing anyway"
}

echo -e "\033[34m🛈\033[0m \033[1mINFO\033[0m: Setup finished successfully"