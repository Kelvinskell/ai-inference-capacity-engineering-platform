#!/usr/bin/env bash

export PROFILE_ID="scheduler-batching"
export PROFILE_HYPOTHESIS="Sequence and batched-token ceilings expose a latency-throughput trade-off under queue pressure."

export ENGINE_CONFIGS="8:2048 16:512 16:2048 32:2048"
export PROMPT_TOKEN_VALUES="1024"
export OUTPUT_TOKEN_VALUES="128"
export GPU_MEMORY_UTILIZATION_VALUES="0.90"
export MAX_MODEL_LEN_VALUES="15000"
export CONCURRENCY_VALUES="20"
export STREAM_MODE_VALUES="false"