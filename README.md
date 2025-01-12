# install-tensorflow

## Setup
According to [this thread](https://github.com/tensorflow/tensorflow/issues/63109#issuecomment-2543966974):

```
conda create --name tensorflow python=3.12
conda activate tensorflow

conda install cuda -c nvidia/label/cuda-12.3.0
conda env config vars set LD_LIBRARY_PATH=$CONDA_PREFIX/lib
conda env config vars set XLA_FLAGS=--xla_gpu_cuda_data_dir=$CONDA_PREFIX

conda deactivate
conda activate tensorflow

conda install cudnn=8.9
```

## Installation
According to [this thread](https://github.com/tensorflow/tensorflow/issues/61986#issuecomment-1811284728), as of the tensorflow release `2.15`, it will successfully install using:
```
python -m pip install "tensorflow[and-cuda]==2.15" --extra-index-url https://pypi.nvidia.com
```
### Fixes
After that, we can install `nvidia-tensorrt` if not already installed by running: `pip install nvidia-tensorrt`. 

Then, we can run:

```
./setup_envars.sh
python create_symlinks.py
```
Where:
* `setup_envars.sh` sets the environment variables `$LD_LIBRARY_PATH` and `$PATH` to include the necessary paths for `tensorrt_libs`, `CUDA` and `cudnn`.
* `create_symlinks.py` creates the necessary symlinks for the `tensorrt_libs` folder.

Finally, we can test whether `tensorflow` is correctly installed and can access the GPU as well as `tensorrt` by running the following command:

```
python3 -c "import tensorflow as tf; print(tf.config.list_physical_devices('GPU'))"
```
*<sub>This command is included in `test_gpu.sh`.</sub>*

The correct output should be something like:

```
2025-01-12 13:17:52.565350: I tensorflow/core/util/port.cc:113] oneDNN custom operations are on. You may see slightly different numerical results due to floating-point round-off errors from different computation orders. To turn them off, set the environment variable `TF_ENABLE_ONEDNN_OPTS=0`.
2025-01-12 13:17:52.604063: I tensorflow/core/platform/cpu_feature_guard.cc:210] This TensorFlow binary is optimized to use available CPU instructions in performance-critical operations.
To enable the following instructions: AVX2 AVX512F AVX512_VNNI AVX512_BF16 FMA, in other operations, rebuild TensorFlow with the appropriate compiler flags.
[PhysicalDevice(name='/physical_device:GPU:0', device_type='GPU')]
```

### Explanation
After installing `tensorflow`, it will probably print something like the following after running `import tensorflow`:

```
2024-04-21 08:00:13.414353: I tensorflow/core/util/port.cc:113] oneDNN custom operations are on. You may see slightly different numerical results due to floating-point round-off errors from different computation orders. To turn them off, set the environment variable `TF_ENABLE_ONEDNN_OPTS=0`.
2024-04-21 08:00:13.552935: I tensorflow/core/platform/cpu_feature_guard.cc:210] This TensorFlow binary is optimized to use available CPU instructions in performance-critical operations.
To enable the following instructions: AVX2 AVX512F AVX512_VNNI FMA, in other operations, rebuild TensorFlow with the appropriate compiler flags.
2024-04-21 08:00:14.655097: W tensorflow/compiler/tf2tensorrt/utils/py_utils.cc:38] TF-TRT Warning: Could not find TensorRT
2024-04-21 08:00:16.735268: I external/local_xla/xla/stream_executor/cuda/cuda_executor.cc:984] could not open file to read NUMA node: /sys/bus/pci/devices/0000:17:00.0/numa_node
Your kernel may have been built without NUMA support.
2024-04-21 08:00:16.828498: W tensorflow/core/common_runtime/gpu/gpu_device.cc:2251] Cannot dlopen some GPU libraries. Please make sure the missing libraries mentioned above are installed properly if you would like to use GPU. Follow the guide at https://www.tensorflow.org/install/gpu for how to download and setup the required libraries for your platform.
```

From there, the most important warning is: `TF-TRT Warning: Could not find TensorRT`, which can be `strace`'d to check which files is `tensorrt` looking for, by running this command (from [this thread](https://github.com/tensorflow/tensorflow/issues/61468#issuecomment-2027387370)):

```
strace -e open,openat python -c "import tensorflow as tf" 2>&1 | grep "libnvinfer\|TF-TRT"
```
*<sub>This command is included in `strace_tensorrt.sh`.</sub>*

This will print something like the following:

```
openat(AT_FDCWD, "miniconda3/envs/tf-2.16/lib/libnvinfer.so.8.6.1", O_RDONLY|O_CLOEXEC) = -1 ENOENT (No existe el fichero o el directorio)
openat(AT_FDCWD, "miniconda3/envs/tf-2.16/lib/python3.10/site-packages/tensorflow/compiler/tf2tensorrt/../../../_solib_local/_Utensorflow/glibc-hwcaps/x86-64-v4/libnvinfer.so.8.6.1", O_RDONLY|O_CLOEXEC) = -1 ENOENT (No existe el fichero o el directorio)
openat(AT_FDCWD, "miniconda3/envs/tf-2.16/lib/python3.10/site-packages/tensorflow/compiler/tf2tensorrt/../../../_solib_local/_Utensorflow/glibc-hwcaps/x86-64-v3/libnvinfer.so.8.6.1", O_RDONLY|O_CLOEXEC) = -1 ENOENT (No existe el fichero o el directorio)
```

From that stacktrace, we can check that the two important files "missing" are `libnvinfer.so.8.6.1` and `libnvinfer_plugin.so.8.6.1`. To fix that, we need to install `nvidia-tensorrt` if not already installed, by running: 

```
pip install nvidia-tensorrt
```
This will install the packages: `tensorrt_cu12`, `tensorrt`, `nvidia-tensorrt`. After that, we need to add the `tensorrt_libs` folder created in our environment to the `LD_LIBRARY_PATH` environment variable, doing something like the following (suggested in [this thread](https://github.com/tensorflow/tensorflow/issues/61986#issuecomment-1815315673)):

```
TENSORRT_LIBS_PATH=$(dirname $(python -c "import tensorrt_libs;print(tensorrt_libs.__file__)"))
LD_LIBRARY_PATH=$TENSORRT_LIBS_PATH:$CONDA_PREFIX/lib/:$LD_LIBRARY_PATH
```
**Note:** It's also recommended to add the location of `CUDA` in our system, as well as `nvidia/cudnn` (which should have been installed to the current environment's `site-packages` by the previous commands) to `$LD_LIBRARY_PATH`.

After that, running the `strace` command again sometimes still gives `-1` errors, meaning it could not find the files. For that, we need to symlink the wanted files to the corresponding files in `tensorrt_libs`. For example, sometimes the wanted files are `libnvinfer.so.8.6.1` and `libnvinfer_plugin.so.8.6.1`, but in `tensorrt_libs` only `libnvinfer.so.8` and `libnvinfer_plugin.so.8.6.1` exist. Thus, we need to create the symlinks such that:

```
/miniconda3/envs/tf-2.16/lib/python3.10/site-packages/tensorrt_libs/libnvinfer.so.8.6.1 -> /home/camilo/miniconda3/envs/tf-2.16/lib/python3.10/site-packages/tensorrt_libs/libnvinfer.so.8
/miniconda3/envs/tf-2.16/lib/python3.10/site-packages/tensorrt_libs/libnvinfer_plugin.so.8.6.1 -> /home/camilo/miniconda3/envs/tf-2.16/lib/python3.10/site-packages/tensorrt_libs/libnvinfer_plugin.so.8
```

## References
* StackOverflow. [Cuda 12 + `tf-nightly 2.12`: Could not find cuda drivers on your machine, GPU will not be used, while every checking is fine and in torch it works](https://stackoverflow.com/questions/75614728/cuda-12-tf-nightly-2-12-could-not-find-cuda-drivers-on-your-machine-gpu-will).
* Tensorflow Issue Thread. [TF-TRT Warning: Could not find TensorRT #61468](https://github.com/tensorflow/tensorflow/issues/61468)
* Tensorflow Issue Thread. [TensorFlow `2.10.0` not compatible with TensorRT `8.4.3` #57679](https://github.com/tensorflow/tensorflow/issues/57679)
* Tensorflow Issue Thread. [`tensorrt==8.5.3.1` from `[and-cuda]` not available in Python `3.11` #61986](https://github.com/tensorflow/tensorflow/issues/61986)
* Tensorflow Issue Thread. [WSL2 - TensorFlow Install Issue Unable to register cuDNN factory: Attempting to register factory for plugin cuDNN when one has already been registered](https://github.com/tensorflow/tensorflow/issues/63109)

