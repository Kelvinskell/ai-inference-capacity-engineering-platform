#!/usr/bin/env bash

export PROFILE_ID="concurrency-saturation"
export PROFILE_HYPOTHESIS="Queue depth and tail latency rise after token throughput reaches its stable ceiling."

export ENGINE_CONFIGS="40:2048"
export PROMPT_TOKEN_VALUES="1024"
export OUTPUT_TOKEN_VALUES="128"
export GPU_MEMORY_UTILIZATION_VALUES="0.90"
export MAX_MODEL_LEN_VALUES="15000"
export CONCURRENCY_VALUES="1 5 10 20 40"
export STREAM_MODE_VALUES="false"