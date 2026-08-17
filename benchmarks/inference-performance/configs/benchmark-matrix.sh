#!/usr/bin/env bash

# Validation allowlist only. This file does not define or multiply executed
# cases; active configs/profiles/*.sh files define the plan.
# 39,872 input tokens plus 128 output tokens fills a 40,000-token context.
export PROMPT_TOKEN_LEVELS="128 1024 4096 8192 15000 30000 39872"
export OUTPUT_TOKEN_LEVELS="128 512 1024"
export CONCURRENCY_LEVELS="1 5 10 20 40 50 100"
export GPU_MEMORY_UTILIZATION_LEVELS="0.80 0.85 0.90 0.95"
export MAX_MODEL_LEN_LEVELS="8192 15000 30000 40000"
export STREAM_MODE_LEVELS="false true"