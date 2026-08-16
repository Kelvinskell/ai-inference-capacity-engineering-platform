#!/usr/bin/env bash

export PROFILE_ID="output-length-scaling"
export PROFILE_HYPOTHESIS="Longer outputs increase decode time and reduce completed-request throughput."

export ENGINE_CONFIGS="16:2048"
export PROMPT_TOKEN_VALUES="1024"
export OUTPUT_TOKEN_VALUES="128 512 1024"
export GPU_MEMORY_UTILIZATION_VALUES="0.90"
export MAX_MODEL_LEN_VALUES="15000"
export CONCURRENCY_VALUES="20"
export STREAM_MODE_VALUES="false"