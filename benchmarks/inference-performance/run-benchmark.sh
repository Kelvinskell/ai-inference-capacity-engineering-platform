#!/usr/bin/env bash

set -Eeuo pipefail

###############################################################################
# Benchmark Orchestrator
#
# Responsibilities
#   - Load benchmark profiles
#   - Patch KServe configuration
#   - Recycle the single-GPU predictor workload
#   - Wait for service readiness
#   - Maintain local inference endpoint access
#   - Execute loadgen.py
#   - Execute statistic.py
#   - Execute metrics.py
#   - Persist unified benchmark results
#
# Non-Responsibilities
#   - Load generation
#   - Prometheus querying
#   - Latency calculations
#
# Those concerns live in:
#
#   python/loadgen.py
#   python/statistic.py
#   python/metrics.py
###############################################################################

###############################################################################
# Paths
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIG_DIR="${SCRIPT_DIR}/configs"
PROFILE_DIR="${CONFIG_DIR}/profiles"
PYTHON_DIR="${SCRIPT_DIR}/python"
CORPUS_FILE="${SCRIPT_DIR}/corpus/capacity-engineering.txt"
MATRIX_CONFIG="${CONFIG_DIR}/benchmark-matrix.sh"

source "${MATRIX_CONFIG}"

RESULTS_DIR="${SCRIPT_DIR}/results"
REQUEST_RESULTS_DIR="${RESULTS_DIR}/request-level"

BENCHMARK_RESULTS_FILE="${RESULTS_DIR}/benchmark-results.csv"
LOG_FILE="${RESULTS_DIR}/benchmark.log"

###############################################################################
# Logging
###############################################################################

init_logging() {

	mkdir -p "${RESULTS_DIR}"
	mkdir -p "${REQUEST_RESULTS_DIR}"

	exec > >(tee -a "${LOG_FILE}")
	exec 2>&1
}

log() {
	printf '%s [INFO] %s\n' \
		"$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		"$*"
}

warn() {
	printf '%s [WARN] %s\n' \
		"$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		"$*"
}

fatal() {
	printf '%s [ERROR] %s\n' \
		"$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		"$*" >&2
	exit 1
}

###############################################################################
# Runtime Configuration
###############################################################################

NAMESPACE="${NAMESPACE:-llm-serving}"
INFERENCE_SERVICE="${INFERENCE_SERVICE:-deepseek-r1-14b}"

PROM_URL="${PROM_URL:-http://127.0.0.1:9090}"
INFER_URL="${INFER_URL:-http://127.0.0.1:18080/v1/completions}"
INFER_API_KEY="${INFER_API_KEY:-notforprod}"

AUTO_PORT_FORWARD_INFER="${AUTO_PORT_FORWARD_INFER:-true}"
ENVOY_NAMESPACE="${ENVOY_NAMESPACE:-envoy-gateway-system}"
ENVOY_GATEWAY_NAMESPACE="${ENVOY_GATEWAY_NAMESPACE:-llm-serving}"
ENVOY_GATEWAY_NAME="${ENVOY_GATEWAY_NAME:-envoy-ai-gateway}"
ENVOY_SERVICE="${ENVOY_SERVICE:-}"

AUTO_PORT_FORWARD_PROM="${AUTO_PORT_FORWARD_PROM:-true}"
PROM_NAMESPACE="${PROM_NAMESPACE:-monitoring}"
PROM_SERVICE="${PROM_SERVICE:-kube-prometheus-stack-prometheus}"

MODEL_PATH="${MODEL_PATH:-/models}"
MODEL_ID="${MODEL_ID:-/models}"
TOKENIZER_ID="${TOKENIZER_ID:-casperhansen/deepseek-r1-distill-qwen-14b-awq}"
TOKENIZER_REVISION="${TOKENIZER_REVISION:-bc43ec1bbf08de53452630806d5989208b4186db}"

POD_REGEX="${POD_REGEX:-${INFERENCE_SERVICE}-predictor-.*}"

WARMUP_SECONDS="${WARMUP_SECONDS:-120}"
DURATION_SECONDS="${DURATION_SECONDS:-480}"

REQUEST_TIMEOUT_SECONDS="${REQUEST_TIMEOUT_SECONDS:-120}"

TEMPERATURE="${TEMPERATURE:-0.2}"

READY_TIMEOUT_SECONDS="${READY_TIMEOUT_SECONDS:-3}"
READY_WAIT_TIMEOUT_SECONDS="${READY_WAIT_TIMEOUT_SECONDS:-180}"
POST_READY_SETTLE_SECONDS="${POST_READY_SETTLE_SECONDS:-240}"

PF_INFER_PID=""
PF_PROM_PID=""
PREDICTOR_NODE=""

###############################################################################
# Cleanup
###############################################################################

cleanup() {

	if [[ -n "${PF_INFER_PID}" ]]; then
		kill "${PF_INFER_PID}" >/dev/null 2>&1 || true
	fi

	if [[ -n "${PF_PROM_PID}" ]]; then
		kill "${PF_PROM_PID}" >/dev/null 2>&1 || true
	fi
}

trap cleanup EXIT INT TERM

###############################################################################
# Validation
###############################################################################

require_tools() {

	command -v kubectl >/dev/null || fatal "kubectl not found"
	command -v jq >/dev/null || fatal "jq not found"
	command -v curl >/dev/null || fatal "curl not found"
	command -v python3 >/dev/null || fatal "python3 not found"
}

configured_level() {

	local selected="$1"
	local levels="$2"

	[[ " ${levels} " == *" ${selected} "* ]]
}

validate_profile() {

	local required
	local engine
	local prompt_tokens
	local output_tokens
	local gpu_memory
	local model_len
	local concurrency
	local stream_mode

	for required in \
		PROFILE_ID \
		PROFILE_HYPOTHESIS \
		ENGINE_CONFIGS \
		PROMPT_TOKEN_VALUES \
		OUTPUT_TOKEN_VALUES \
		GPU_MEMORY_UTILIZATION_VALUES \
		MAX_MODEL_LEN_VALUES \
		CONCURRENCY_VALUES \
		STREAM_MODE_VALUES
	do
		[[ -n "${!required:-}" ]] || fatal "Profile is missing ${required}"
	done

	for engine in ${ENGINE_CONFIGS}; do
		[[ "${engine}" =~ ^[0-9]+:[0-9]+$ ]] \
			|| fatal "Profile ${PROFILE_ID} has invalid engine configuration ${engine}"
	done

	for prompt_tokens in ${PROMPT_TOKEN_VALUES}; do
		configured_level "${prompt_tokens}" "${PROMPT_TOKEN_LEVELS}" \
			|| fatal "Profile ${PROFILE_ID} has unsupported prompt length ${prompt_tokens}"
	done

	for output_tokens in ${OUTPUT_TOKEN_VALUES}; do
		configured_level "${output_tokens}" "${OUTPUT_TOKEN_LEVELS}" \
			|| fatal "Profile ${PROFILE_ID} has unsupported output length ${output_tokens}"
	done

	for gpu_memory in ${GPU_MEMORY_UTILIZATION_VALUES}; do
		configured_level "${gpu_memory}" "${GPU_MEMORY_UTILIZATION_LEVELS}" \
			|| fatal "Profile ${PROFILE_ID} has unsupported GPU memory target ${gpu_memory}"
	done

	for model_len in ${MAX_MODEL_LEN_VALUES}; do
		configured_level "${model_len}" "${MAX_MODEL_LEN_LEVELS}" \
			|| fatal "Profile ${PROFILE_ID} has unsupported model length ${model_len}"

		for prompt_tokens in ${PROMPT_TOKEN_VALUES}; do
			for output_tokens in ${OUTPUT_TOKEN_VALUES}; do
				(( prompt_tokens + output_tokens <= model_len )) \
					|| fatal "Profile ${PROFILE_ID}: prompt ${prompt_tokens} + output ${output_tokens} exceeds model length ${model_len}"
			done
		done
	done

	for concurrency in ${CONCURRENCY_VALUES}; do
		configured_level "${concurrency}" "${CONCURRENCY_LEVELS}" \
			|| fatal "Profile ${PROFILE_ID} has unsupported concurrency ${concurrency}"
	done

	for stream_mode in ${STREAM_MODE_VALUES}; do
		configured_level "${stream_mode}" "${STREAM_MODE_LEVELS}" \
			|| fatal "Profile ${PROFILE_ID} has unsupported stream mode ${stream_mode}"
	done
}

usage() {

	cat <<EOF
Usage:

  ./run-benchmark.sh all
	./run-benchmark.sh PROFILE
	./run-benchmark.sh plan [PROFILE]

Profiles:

	concurrency-saturation
	prompt-length-scaling
	output-length-scaling
	gpu-memory-scaling
	model-length-scaling
	scheduler-batching
	streaming-comparison
EOF
}

###############################################################################
# Result Initialisation
###############################################################################

init_results_files() {

	if [[ ! -f "${BENCHMARK_RESULTS_FILE}" ]]; then
		echo "timestamp,run_id,profile,profile_hypothesis,stream,prompt_tokens,max_tokens,gpu_memory_utilization,max_model_len,max_num_seqs,max_num_batched_tokens,concurrency,requests_total,successes,errors,success_rate_pct,error_rate_pct,attempted_rps,successful_rps,output_length_match_rate_pct,actual_prompt_tokens_total,actual_output_tokens_total,actual_prompt_tokens_per_sec,actual_output_tokens_per_sec,actual_total_tokens_per_sec,latency_avg_ms,latency_min_ms,latency_max_ms,latency_p50_ms,latency_p90_ms,latency_p95_ms,latency_p99_ms,error_duration_avg_ms,error_duration_p95_ms,ttft_avg_ms,ttft_p50_ms,ttft_p95_ms,ttft_p99_ms,time_per_output_token_avg_ms,time_per_output_token_p95_ms,server_output_tokens_total,server_output_tokens_per_sec,preemptions_total,prefix_cache_hits_total,requests_running_avg,requests_running_max,requests_waiting_avg,requests_waiting_max,kv_cache_pct_avg,kv_cache_pct_max,gpu_util_avg,gpu_util_max,gpu_memory_used_mib_avg,gpu_memory_used_mib_max,gpu_memory_free_mib_min,gpu_memory_pct_avg,gpu_memory_pct_max,tensor_active_avg,tensor_active_max,dram_active_avg,dram_active_max" \
			> "${BENCHMARK_RESULTS_FILE}"
	fi
}

###############################################################################
# Endpoint Management
###############################################################################

is_local_infer_url() {
	[[ "${INFER_URL}" =~ ^http://(127\.0\.0\.1|localhost): ]]
}

infer_health_url() {
	echo "${INFER_URL%/v1/completions}/health"
}

resolve_envoy_service() {

	if [[ -n "${ENVOY_SERVICE}" ]]; then
		return 0
	fi

	local service_prefix
	local services
	local service_count

	service_prefix="envoy-${ENVOY_GATEWAY_NAMESPACE}-${ENVOY_GATEWAY_NAME}-"
	services="$(
		kubectl -n "${ENVOY_NAMESPACE}" get services -o json |
			jq -r --arg prefix "${service_prefix}" '
				.items[]
				| select(.metadata.name | startswith($prefix))
				| .metadata.name
			'
	)"
	service_count="$(printf '%s\n' "${services}" | grep -c . || true)"

	(( service_count == 1 )) \
		|| fatal "Expected one Envoy Service with prefix ${service_prefix}, found ${service_count}; set ENVOY_SERVICE explicitly"

	ENVOY_SERVICE="${services}"
	log "Discovered Envoy Service=${ENVOY_SERVICE}"
}

is_local_prom_url() {
	[[ "${PROM_URL}" =~ ^http://(127\.0\.0\.1|localhost): ]]
}

ensure_prom_endpoint() {

	if [[ "${AUTO_PORT_FORWARD_PROM}" != "true" ]] || ! is_local_prom_url; then
		return 0
	fi

	local ready_url
	ready_url="${PROM_URL%/}/-/ready"

	if curl -s --max-time 3 -f "${ready_url}" >/dev/null 2>&1; then
		return 0
	fi

	log "Recovering Prometheus endpoint"

	[[ -n "${PF_PROM_PID}" ]] && \
		kill "${PF_PROM_PID}" >/dev/null 2>&1 || true

	kubectl -n "${PROM_NAMESPACE}" \
		port-forward "svc/${PROM_SERVICE}" 9090:9090 \
		>/tmp/benchmark-prometheus-portforward.log 2>&1 &

	PF_PROM_PID="$!"

	sleep 5

	curl -s --max-time 5 -f "${ready_url}" >/dev/null \
		|| fatal "Unable to recover Prometheus endpoint"
}

ensure_infer_endpoint() {

	if [[ "${AUTO_PORT_FORWARD_INFER}" != "true" ]]; then
		return 0
	fi

	if ! is_local_infer_url; then
		return 0
	fi

	local health_url
	health_url="$(infer_health_url)"

	if curl \
		-s \
		--max-time 3 \
		-f \
		-H "Authorization: Bearer ${INFER_API_KEY}" \
		"${health_url}" >/dev/null 2>&1; then
		return 0
	fi

	log "Recovering inference endpoint"

	[[ -n "${PF_INFER_PID}" ]] && \
		kill "${PF_INFER_PID}" >/dev/null 2>&1 || true

	resolve_envoy_service

	kubectl -n "${ENVOY_NAMESPACE}" \
		port-forward "svc/${ENVOY_SERVICE}" 18080:80 \
		>/tmp/benchmark-portforward.log 2>&1 &

	PF_INFER_PID="$!"

	sleep 10

	curl \
		-s \
		--max-time 5 \
		-f \
		-H "Authorization: Bearer ${INFER_API_KEY}" \
		"${health_url}" >/dev/null \
		|| fatal "Unable to recover inference endpoint"
}

###############################################################################
# ISVC Lifecycle
###############################################################################

wait_for_isvc_ready() {

	if kubectl \
		-n "${NAMESPACE}" \
		get \
		"inferenceservice/${INFERENCE_SERVICE}" \
		-o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null \
		| grep -q 'True'; then
		log "InferenceService already Ready"
	else
		log "Waiting for InferenceService readiness"

		kubectl \
			-n "${NAMESPACE}" \
			wait \
			--for=condition=Ready \
			"inferenceservice/${INFERENCE_SERVICE}" \
			--timeout="${READY_WAIT_TIMEOUT_SECONDS}s" \
			|| fatal "InferenceService did not become Ready within ${READY_WAIT_TIMEOUT_SECONDS}s"

		log "InferenceService ready"
	fi

	log "Allowing service to stabilise"

	sleep "${POST_READY_SETTLE_SECONDS}"
}

resolve_predictor_node() {

	PREDICTOR_NODE="$(
		kubectl \
			-n "${NAMESPACE}" \
			get pods \
			-l "serving.kserve.io/inferenceservice=${INFERENCE_SERVICE}" \
			-o jsonpath='{.items[0].spec.nodeName}'
	)"

	[[ -n "${PREDICTOR_NODE}" ]] \
		|| fatal "Unable to resolve predictor node for DCGM metric scoping"

	log "Predictor node=${PREDICTOR_NODE}"
}

patch_isvc_profile() {

	local seqs="$1"
	local batched="$2"
	local gpu_memory="$3"
	local model_len="$4"

	local deploy_name
	deploy_name="${INFERENCE_SERVICE}-predictor"

	log "Scaling predictor deployment to zero"

	kubectl \
		-n "${NAMESPACE}" \
		scale deployment "${deploy_name}" \
		--replicas=0

	sleep 15

	log "Waiting for predictor pods to terminate"

	while kubectl \
		-n "${NAMESPACE}" \
		get pods \
		-l "serving.kserve.io/inferenceservice=${INFERENCE_SERVICE}" \
		--no-headers 2>/dev/null | grep -q .; do
		sleep 5
	done

	log "Applying runtime seqs=${seqs} batched=${batched} gpu_memory=${gpu_memory} model_len=${model_len}"

	local args_json

	args_json=$(
		cat <<EOF
[
 "${MODEL_PATH}",
 "--host","0.0.0.0",
 "--port","8000",
 "--gpu-memory-utilization","${gpu_memory}",
 "--max-num-seqs","${seqs}",
 "--max-num-batched-tokens","${batched}",
 "--max-model-len","${model_len}"
]
EOF
	)

	kubectl \
		-n "${NAMESPACE}" \
		get inferenceservice "${INFERENCE_SERVICE}" \
		-o json |
	jq \
		--argjson args "${args_json}" '
		.spec.predictor.containers |= map(
			if .name == "kserve-container"
			then . + {args: $args}
			else .
			end
		)
	' |
	kubectl apply -f -

	log "Scaling predictor deployment back to one"

	kubectl \
		-n "${NAMESPACE}" \
		scale deployment "${deploy_name}" \
		--replicas=1

	wait_for_isvc_ready
	resolve_predictor_node
}

###############################################################################
# Benchmark Execution
###############################################################################

run_concurrency_test() {

	local profile="$1"
	local seqs="$2"
	local batched="$3"
	local prompt_tokens="$4"
	local output_tokens="$5"
	local gpu_memory="$6"
	local model_len="$7"
	local stream_mode="$8"
	local concurrency="$9"

	local ts
	ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

	local request_file
	local profile_summary_file
	local run_key

	run_key="${RUN_ID}-${profile}-s${seqs}-b${batched}-p${prompt_tokens}-o${output_tokens}-g${gpu_memory/./}-m${model_len}-stream${stream_mode}-c${concurrency}"
	request_file="${REQUEST_RESULTS_DIR}/${run_key}.jsonl"
	profile_summary_file="${REQUEST_RESULTS_DIR}/${run_key}-summary.json"

	log "Running profile=${profile} stream=${stream_mode} prompt=${prompt_tokens} output=${output_tokens} concurrency=${concurrency}"

	export PYTHON_DIR="${PYTHON_DIR:-${SCRIPT_DIR}/python}"
	export INFER_URL
	export INFER_API_KEY
	export MODEL_ID
	export CORPUS_FILE
	export PROMPT_TOKENS="${prompt_tokens}"
	export TOKENIZER_ID
	export TOKENIZER_REVISION
	export CONCURRENCY="${concurrency}"
	export WARMUP_SECONDS
	export DURATION_SECONDS
	export REQUEST_TIMEOUT_SECONDS
	export MAX_TOKENS="${output_tokens}"
	export TEMPERATURE
	export STREAM_MODE="${stream_mode}"
	export REQUEST_FILE="${request_file}"
	export PROFILE_SUMMARY_FILE="${profile_summary_file}"

	python3 - <<'PY'
import os
import signal
import subprocess
import sys

cmd = [
    "python3",
    os.path.join(os.environ["PYTHON_DIR"], "loadgen.py"),
    "--url", os.environ["INFER_URL"],
	"--api-key", os.environ["INFER_API_KEY"],
	"--model", os.environ["MODEL_ID"],
	"--corpus-file", os.environ["CORPUS_FILE"],
	"--prompt-tokens", os.environ["PROMPT_TOKENS"],
	"--tokenizer-id", os.environ["TOKENIZER_ID"],
	"--tokenizer-revision", os.environ["TOKENIZER_REVISION"],
    "--concurrency", os.environ["CONCURRENCY"],
    "--warmup", os.environ["WARMUP_SECONDS"],
    "--duration", os.environ["DURATION_SECONDS"],
    "--timeout", os.environ["REQUEST_TIMEOUT_SECONDS"],
    "--max-tokens", os.environ["MAX_TOKENS"],
    "--temperature", os.environ["TEMPERATURE"],
    "--output", os.environ["REQUEST_FILE"],
    "--summary-file", os.environ["PROFILE_SUMMARY_FILE"],
]

if os.environ["STREAM_MODE"] == "true":
	cmd.append("--stream")

proc = subprocess.Popen(cmd)
try:
    proc.wait(timeout=1800)
except subprocess.TimeoutExpired:
    proc.send_signal(signal.SIGTERM)
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
    sys.exit(124)

sys.exit(proc.returncode)
PY

	local run_start
	local run_end

	run_start="$(jq -r '.run_start' "${profile_summary_file}")"
	run_end="$(jq -r '.run_end' "${profile_summary_file}")"

	local stats_json
	local metrics_json

	stats_json="$(
		python3 "${PYTHON_DIR}/statistic.py" \
			--input "${request_file}" \
			--summary-file "${profile_summary_file}"
	)"

	ensure_prom_endpoint

	metrics_json="$(
		python3 "${PYTHON_DIR}/metrics.py" \
			--prom-url "${PROM_URL}" \
			--namespace "${NAMESPACE}" \
			--pod-regex "${POD_REGEX}" \
			--gpu-hostname "${PREDICTOR_NODE}" \
			--start "${run_start}" \
			--end "${run_end}"
	)"

	jq -nr \
		--arg timestamp "${ts}" \
		--arg run_id "${RUN_ID}" \
		--arg profile "${profile}" \
		--arg hypothesis "${PROFILE_HYPOTHESIS}" \
		--argjson stream "${stream_mode}" \
		--argjson prompt_tokens "${prompt_tokens}" \
		--argjson output_tokens "${output_tokens}" \
		--argjson gpu_memory "${gpu_memory}" \
		--argjson model_len "${model_len}" \
		--argjson seqs "${seqs}" \
		--argjson batched "${batched}" \
		--argjson concurrency "${concurrency}" \
		--argjson stats "${stats_json}" \
		--argjson metrics "${metrics_json}" '
		[
			$timestamp, $run_id, $profile, $hypothesis, $stream,
			$prompt_tokens, $output_tokens, $gpu_memory, $model_len,
			$seqs, $batched, $concurrency,
			$stats.requests_total, $stats.successes, $stats.errors,
			$stats.success_rate_pct, $stats.error_rate_pct,
			$stats.attempted_rps, $stats.successful_rps,
			$stats.output_length_match_rate_pct,
			$stats.prompt_tokens_total, $stats.output_tokens_total,
			$stats.prompt_tokens_per_sec, $stats.output_tokens_per_sec,
			$stats.total_tokens_per_sec,
			$stats.latency_avg_ms, $stats.latency_min_ms, $stats.latency_max_ms,
			$stats.latency_p50_ms, $stats.latency_p90_ms,
			$stats.latency_p95_ms, $stats.latency_p99_ms,
			$stats.error_duration_avg_ms, $stats.error_duration_p95_ms,
			$stats.ttft_avg_ms, $stats.ttft_p50_ms,
			$stats.ttft_p95_ms, $stats.ttft_p99_ms,
			$stats.time_per_output_token_avg_ms,
			$stats.time_per_output_token_p95_ms,
			$metrics.server_output_tokens_total,
			$metrics.server_output_tokens_per_sec,
			$metrics.preemptions_total, $metrics.prefix_cache_hits_total,
			$metrics.requests_running_avg, $metrics.requests_running_max,
			$metrics.requests_waiting_avg, $metrics.requests_waiting_max,
			$metrics.kv_cache_pct_avg, $metrics.kv_cache_pct_max,
			$metrics.gpu_util_avg, $metrics.gpu_util_max,
			$metrics.gpu_memory_used_mib_avg,
			$metrics.gpu_memory_used_mib_max,
			$metrics.gpu_memory_free_mib_min,
			$metrics.gpu_memory_pct_avg, $metrics.gpu_memory_pct_max,
			$metrics.tensor_active_avg, $metrics.tensor_active_max,
			$metrics.dram_active_avg, $metrics.dram_active_max
		] | @csv
	' >> "${BENCHMARK_RESULTS_FILE}"
}

run_profile() {

	local cfg_file="$1"
	local engine
	local seqs
	local batched
	local gpu_memory
	local model_len
	local prompt_tokens
	local output_tokens
	local concurrency
	local stream_mode

	unset PROFILE_ID PROFILE_HYPOTHESIS ENGINE_CONFIGS PROMPT_TOKEN_VALUES \
		OUTPUT_TOKEN_VALUES GPU_MEMORY_UTILIZATION_VALUES MAX_MODEL_LEN_VALUES \
		CONCURRENCY_VALUES STREAM_MODE_VALUES
	source "${cfg_file}"
	validate_profile

	if [[ "${PLAN_ONLY}" == "true" ]]; then
		printf '\n%s: %s\n' "${PROFILE_ID}" "${PROFILE_HYPOTHESIS}"
	else
		log "Executing profile=${PROFILE_ID} hypothesis=${PROFILE_HYPOTHESIS}"
	fi

	for engine in ${ENGINE_CONFIGS}; do
		IFS=: read -r seqs batched <<< "${engine}"

		for gpu_memory in ${GPU_MEMORY_UTILIZATION_VALUES}; do
			for model_len in ${MAX_MODEL_LEN_VALUES}; do

				if [[ "${PLAN_ONLY}" != "true" ]]; then
					patch_isvc_profile "${seqs}" "${batched}" "${gpu_memory}" "${model_len}"
					ensure_infer_endpoint
				fi

				for prompt_tokens in ${PROMPT_TOKEN_VALUES}; do
					for output_tokens in ${OUTPUT_TOKEN_VALUES}; do
						for stream_mode in ${STREAM_MODE_VALUES}; do
							for concurrency in ${CONCURRENCY_VALUES}; do
								if [[ "${PLAN_ONLY}" == "true" ]]; then
									((PLAN_COUNT += 1))
									printf '  %03d seqs=%s batch=%s prompt=%s output=%s gpu=%s model_len=%s stream=%s concurrency=%s\n' \
										"${PLAN_COUNT}" "${seqs}" "${batched}" "${prompt_tokens}" \
										"${output_tokens}" "${gpu_memory}" "${model_len}" "${stream_mode}" "${concurrency}"
								else
									ensure_infer_endpoint
									run_concurrency_test \
										"${PROFILE_ID}" "${seqs}" "${batched}" \
										"${prompt_tokens}" "${output_tokens}" "${gpu_memory}" \
										"${model_len}" "${stream_mode}" "${concurrency}"
								fi
							done
						done
					done
				done
			done
		done
	done
}

###############################################################################
# Main
###############################################################################

run_requested_profiles() {

	local requested="$1"
	local profile_file

	if [[ "${requested}" == "all" ]]; then
		for profile_file in "${PROFILE_DIR}"/*.sh; do
			run_profile "${profile_file}"
		done
		return 0
	fi

	profile_file="${PROFILE_DIR}/${requested}.sh"
	[[ -f "${profile_file}" ]] || fatal "Unknown profile: ${requested}"
	run_profile "${profile_file}"
}

main() {

	local action="${1:-all}"
	local requested="${action}"

	PLAN_ONLY="false"
	PLAN_COUNT=0

	case "${action}" in
		help|-h|--help)
			(( $# == 1 )) || fatal "Help does not accept additional arguments"
			usage
			return 0
			;;
		plan)
			(( $# <= 2 )) || fatal "Usage: ./run-benchmark.sh plan [PROFILE]"
			PLAN_ONLY="true"
			requested="${2:-all}"
			;;
		*)
			(( $# == 1 )) || fatal "Profiles do not accept manual dimension overrides"
			;;
	esac

	if [[ "${PLAN_ONLY}" == "true" ]]; then
		run_requested_profiles "${requested}"
		printf '\nTotal benchmark cases: %d\n' "${PLAN_COUNT}"
		return 0
	fi

	require_tools
	RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
	init_logging
	init_results_files
	ensure_prom_endpoint
	run_requested_profiles "${requested}"
	log "Benchmark complete run_id=${RUN_ID}"
}

main "$@"