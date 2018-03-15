#!/bin/bash

Usage() {
  echo "Usage: bash tools/build_run_throughput_test.sh run_seconds merged_lib_file model_input_dir"
}

if [ $# -lt 1 ]; then
  Usage
  exit 1
fi

RUN_SECONDS=$1
MERGED_LIB_FILE=$2
MODEL_INPUT_DIR=$3

CURRENT_DIR=`dirname $0`
source ${CURRENT_DIR}/env.sh


if [ "$CPU_MODEL_TAG" != '' ]; then
  CPU_MODEL_TAG_BUILD_FLAGS="--copt=-DMACE_CPU_MODEL_TAG=${CPU_MODEL_TAG}"
fi

if [ "$GPU_MODEL_TAG" != '' ]; then
  GPU_MODEL_TAG_BUILD_FLAGS="--copt=-DMACE_GPU_MODEL_TAG=${GPU_MODEL_TAG}"
fi

if [ "$DSP_MODEL_TAG" != '' ]; then
  DSP_MODEL_TAG_BUILD_FLAGS="--copt=-DMACE_DSP_MODEL_TAG=${DSP_MODEL_TAG}"
fi

cp $MERGED_LIB_FILE mace/benchmark/libmace_merged.a

bazel build --verbose_failures -c opt --strip always //mace/benchmark:model_throughput_test \
    --crosstool_top=//external:android/crosstool \
    --host_crosstool_top=@bazel_tools//tools/cpp:toolchain \
    --cpu=${TARGET_ABI} \
    --copt="-std=c++11" \
    --copt="-D_GLIBCXX_USE_C99_MATH_TR1" \
    --copt="-Werror=return-type" \
    ${CPU_MODEL_TAG_BUILD_FLAGS} \
    ${GPU_MODEL_TAG_BUILD_FLAGS} \
    ${DSP_MODEL_TAG_BUILD_FLAGS} \
    --define openmp=true \
    --copt="-O3" || exit 1

rm mace/benchmark/libmace_merged.a

adb shell "mkdir -p ${PHONE_DATA_DIR}" || exit 1

adb push ${MODEL_INPUT_DIR}/${INPUT_FILE_NAME}_${INPUT_NODES} ${PHONE_DATA_DIR} || exit 1
adb push bazel-bin/mace/benchmark/model_throughput_test ${PHONE_DATA_DIR} || exit 1
if [ "$EMBED_MODEL_DATA" = 0 ]; then
  adb push codegen/models/${CPU_MODEL_TAG}/${CPU_MODEL_TAG}.data ${PHONE_DATA_DIR} || exit 1
  adb push codegen/models/${GPU_MODEL_TAG}/${GPU_MODEL_TAG}.data ${PHONE_DATA_DIR} || exit 1
  adb push codegen/models/${DSP_MODEL_TAG}/${DSP_MODEL_TAG}.data ${PHONE_DATA_DIR} || exit 1
fi
adb push mace/core/runtime/hexagon/libhexagon_controller.so ${PHONE_DATA_DIR} || exit 1

adb </dev/null shell \
LD_LIBRARY_PATH=${PHONE_DATA_DIR} \
MACE_CPP_MIN_VLOG_LEVEL=$VLOG_LEVEL \
MACE_RUN_PARAMETER_PATH=${PHONE_DATA_DIR}/mace_run.config \
MACE_KERNEL_PATH=$KERNEL_DIR \
MACE_LIMIT_OPENCL_KERNEL_TIME=${LIMIT_OPENCL_KERNEL_TIME} \
${PHONE_DATA_DIR}/model_throughput_test \
--input_shape="${INPUT_SHAPES}" \
--output_shape="${OUTPUT_SHAPES}" \
--input_file=${PHONE_DATA_DIR}/${INPUT_FILE_NAME}_${INPUT_NODES} \
--cpu_model_data_file=${PHONE_DATA_DIR}/${CPU_MODEL_TAG}.data \
--gpu_model_data_file=${PHONE_DATA_DIR}/${GPU_MODEL_TAG}.data \
--dsp_model_data_file=${PHONE_DATA_DIR}/${DSP_MODEL_TAG}.data \
--run_seconds=$RUN_SECONDS || exit 1