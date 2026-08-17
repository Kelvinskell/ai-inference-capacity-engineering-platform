#!/usr/bin/env bash

export PROFILE_ID="prompt-length-scaling"
export PROFILE_HYPOTHESIS="Longer prompts increase prefill latency and KV-cache pressure, reducing stable concurrency."

export ENGINE_CONFIGS="16:2048"
export PROMPT_TOKEN_VALUES="128 1024 4096 8192 15000 30000 39872"
export OUTPUT_TOKEN_VALUES="128"
export GPU_MEMORY_UTILIZATION_VALUES="0.90"
export MAX_MODEL_LEN_VALUES="40000"
export CONCURRENCY_VALUES="1 5 10 20 40 50 100"
export STREAM_MODE_VALUES="false"