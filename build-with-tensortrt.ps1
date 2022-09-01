# See --cmake_extra_defines
# 52=Maxwell GM200/GM204/GM206
# 61=Pascal GP10* (GTX Series 10**)
# 75=Turing TU10* (GTX 16**, RTX 20**)
# 86=Ampere GA10* (RTX 30**)
# Inspiration https://github.com/microsoft/onnxruntime/blob/e810480403ebdd5f3438431ef2fc060c70a52b66/tools/ci_build/github/linux/docker/Dockerfile.ubuntu_cuda11_6_tensorrt8_4
./build.bat --config RelWithDebInfo --build_shared_lib --build_csharp --parallel --use_cuda --cuda_version 11.6 --cuda_home "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v11.6" --cmake_extra_defines CMAKE_CUDA_ARCHITECTURES='52;61;75;86' LINK_DIRECTORIES=C:\git\nvidia\cudnn-windows-x86_64-8.5.0.96_cuda11-archive\lib --cudnn_home "C:\git\nvidia\cudnn-windows-x86_64-8.5.0.96_cuda11-archive" --use_tensorrt --tensorrt_home "C:\git\nvidia\TensorRT-8.4.3.1.Windows10.x86_64.cuda-11.6.cudnn8.4\TensorRT-8.4.3.1" --use_dnnl --use_dml --cmake_generator "Visual Studio 16 2019" --skip_tests