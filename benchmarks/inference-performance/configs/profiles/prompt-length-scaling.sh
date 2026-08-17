#!/usr/bin/env bash

export PROFILE_ID="prompt-length-scaling"
export PROFILE_HYPOTHESIS="Longer prompts increase prefill latency and KV-cache pressure, reducing stable concurrency."

export ENGINE_CONFIGS="16:2048"
export PROMPT_TOKEN_VALUES="128 4096 8192 15000 39872"
export OUTPUT_TOKEN_VALUES="128"
export GPU_MEMORY_UTILIZATION_VALUES="0.90"
export MAX_MODEL_LEN_VALUES="40000"
export CONCURRENCY_VALUES="1 10"
export STREAM_MODE_VALUES="false"