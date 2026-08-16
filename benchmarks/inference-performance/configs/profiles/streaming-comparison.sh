#!/usr/bin/env bash

export PROFILE_ID="streaming-comparison"
export PROFILE_HYPOTHESIS="Streaming improves time to first token without materially changing completed-token throughput."

export ENGINE_CONFIGS="16:2048"
export PROMPT_TOKEN_VALUES="1024"
export OUTPUT_TOKEN_VALUES="512"
export GPU_MEMORY_UTILIZATION_VALUES="0.90"
export MAX_MODEL_LEN_VALUES="15000"
export CONCURRENCY_VALUES="20"
export STREAM_MODE_VALUES="false true"