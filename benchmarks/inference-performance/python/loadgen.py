#!/usr/bin/env python3

"""
loadgen.py

Async load generator for vLLM / KServe benchmarking.

Goals
-----
- Maintain true target concurrency.
- Separate warmup from measurement.
- Persist request-level results.
- Persist benchmark summary JSON.
- Provide live benchmark progress.

This script intentionally contains:
- NO Prometheus logic
- NO aggregate result writing
- NO Kubernetes logic

Those responsibilities belong elsewhere.
"""

import argparse
import asyncio
import hashlib
import importlib
import itertools
import json
import signal
import statistics as statistics_lib
import time
from pathlib import Path

import aiohttp


STOP_REQUESTED = False


class CorpusPromptFactory:
    """Build deterministic, request-unique prompts at an exact token length."""

    def __init__(
        self,
        *,
        corpus_file,
        prompt_tokens,
        tokenizer_id,
        tokenizer_revision,
    ):
        transformers = importlib.import_module("transformers")

        self.prompt_tokens = prompt_tokens
        tokenizer_path = Path(tokenizer_id)

        if not tokenizer_path.is_dir():
            raise ValueError(
                f"Local tokenizer directory not found: {tokenizer_path}"
            )

        self.tokenizer = transformers.AutoTokenizer.from_pretrained(
            tokenizer_path,
            local_files_only=True,
        )

        corpus_text = Path(corpus_file).read_text(encoding="utf-8")
        self.corpus_tokens = self.tokenizer.encode(
            corpus_text,
            add_special_tokens=False,
        )

        if not self.corpus_tokens:
            raise ValueError("Corpus must contain at least one token.")

    def build(self, request_key):
        request_fingerprint = hashlib.sha256(
            str(request_key).encode("ascii")
        ).hexdigest()
        prefix_tokens = self.tokenizer.encode(
            f"{request_fingerprint} independent benchmark request.\n",
            add_special_tokens=False,
        )

        if len(prefix_tokens) >= self.prompt_tokens:
            raise ValueError(
                "Prompt token target is too small for the unique request prefix."
            )

        body_length = self.prompt_tokens - len(prefix_tokens)
        start = (request_key * 7919) % len(self.corpus_tokens)
        body_tokens = [
            self.corpus_tokens[(start + offset) % len(self.corpus_tokens)]
            for offset in range(body_length)
        ]

        prompt_tokens = prefix_tokens + body_tokens
        actual_tokens = []
        prompt = self.tokenizer.decode(
            prompt_tokens,
            skip_special_tokens=True,
            clean_up_tokenization_spaces=False,
        )

        for _ in range(8):
            actual_tokens = self.tokenizer.encode(
                prompt,
                add_special_tokens=False,
            )

            if len(actual_tokens) == self.prompt_tokens:
                return prompt

            if len(actual_tokens) > self.prompt_tokens:
                prompt = self.tokenizer.decode(
                    actual_tokens[:self.prompt_tokens],
                    skip_special_tokens=True,
                    clean_up_tokenization_spaces=False,
                )
                continue

            for filler_token in self.corpus_tokens:
                suffix = self.tokenizer.decode(
                    [filler_token],
                    skip_special_tokens=True,
                    clean_up_tokenization_spaces=False,
                )
                candidate = prompt + suffix
                candidate_length = len(self.tokenizer.encode(
                    candidate,
                    add_special_tokens=False,
                ))
                if len(actual_tokens) < candidate_length <= self.prompt_tokens:
                    prompt = candidate
                    break
            else:
                break

        raise ValueError(
            "Unable to construct a corpus prompt at the requested token count: "
            f"requested={self.prompt_tokens}, actual={len(actual_tokens)}"
        )

    def count_tokens(self, text):
        return len(self.tokenizer.encode(text, add_special_tokens=False))


def handle_signal(signum, frame):
    """Gracefully stop on SIGINT/SIGTERM."""
    global STOP_REQUESTED
    STOP_REQUESTED = True


signal.signal(signal.SIGINT, handle_signal)
signal.signal(signal.SIGTERM, handle_signal)


class BenchmarkState:
    """
    Shared benchmark state.

    Tracks:
    - Request counts
    - Success/failure counts
    - Active requests
    - Latency distribution
    """

    def __init__(self):
        self.started = 0
        self.completed = 0
        self.successes = 0
        self.errors = 0
        self.active_requests = 0
        self.success_latencies_ms = []
        self.error_durations_ms = []
        self.ttft_ms = []
        self.time_per_output_token_ms = []
        self.prompt_tokens_total = 0
        self.output_tokens_total = 0


async def single_request(
    session,
    url,
    payload,
    timeout_seconds,
    stream,
    count_tokens,
):
    """
    Execute a single inference request.
    """

    start = time.perf_counter()

    try:
        async with session.post(
            url,
            json=payload,
            timeout=aiohttp.ClientTimeout(
                total=timeout_seconds
            ),
        ) as response:

            if response.status != 200:
                error_body = await response.text()
                duration_ms = (time.perf_counter() - start) * 1000
                return {
                    "status": response.status,
                    "success": False,
                    "latency_ms": None,
                    "error_duration_ms": round(duration_ms, 3),
                    "ttft_ms": None,
                    "time_per_output_token_ms": None,
                    "prompt_tokens": 0,
                    "output_tokens": 0,
                    "error": error_body[:1000],
                }

            first_token_at = None
            response_text = ""
            prompt_tokens = 0
            output_tokens = 0

            if stream:
                while True:
                    raw_line = await response.content.readline()
                    if not raw_line:
                        break

                    line = raw_line.decode("utf-8").strip()
                    if not line.startswith("data:"):
                        continue

                    data = line[5:].strip()
                    if not data or data == "[DONE]":
                        continue

                    chunk = json.loads(data)
                    choices = chunk.get("choices", [])
                    text = choices[0].get("text", "") if choices else ""

                    if text and first_token_at is None:
                        first_token_at = time.perf_counter()

                    response_text += text

                    usage = chunk.get("usage") or {}
                    prompt_tokens = usage.get("prompt_tokens", prompt_tokens)
                    output_tokens = usage.get("completion_tokens", output_tokens)
            else:
                body = await response.json(content_type=None)
                choices = body.get("choices", [])
                response_text = choices[0].get("text", "") if choices else ""
                usage = body.get("usage") or {}
                prompt_tokens = usage.get("prompt_tokens", 0)
                output_tokens = usage.get("completion_tokens", 0)

            if output_tokens <= 0:
                output_tokens = await asyncio.to_thread(
                    count_tokens,
                    response_text,
                )

            latency_ms = (time.perf_counter() - start) * 1000
            ttft_ms = (
                (first_token_at - start) * 1000
                if first_token_at is not None
                else None
            )
            time_per_output_token_ms = None

            if ttft_ms is not None and output_tokens > 1:
                time_per_output_token_ms = (
                    latency_ms - ttft_ms
                ) / (output_tokens - 1)

            return {
                "status": response.status,
                "success": True,
                "latency_ms": round(latency_ms, 3),
                "error_duration_ms": None,
                "ttft_ms": round(ttft_ms, 3) if ttft_ms is not None else None,
                "time_per_output_token_ms": (
                    round(time_per_output_token_ms, 3)
                    if time_per_output_token_ms is not None
                    else None
                ),
                "prompt_tokens": prompt_tokens,
                "output_tokens": output_tokens,
                "error": None,
            }

    except Exception as exc:

        latency_ms = (
            time.perf_counter() - start
        ) * 1000

        return {
            "status": 0,
            "success": False,
            "latency_ms": None,
            "error_duration_ms": round(latency_ms, 3),
            "ttft_ms": None,
            "time_per_output_token_ms": None,
            "prompt_tokens": 0,
            "output_tokens": 0,
            "error": str(exc),
        }


async def run_phase(
    *,
    phase_name,
    duration_seconds,
    concurrency,
    url,
    api_key,
    payload,
    prompt_factory,
    request_id_offset,
    stream,
    timeout_seconds,
    state,
    request_file=None,
):
    """
    Maintain the requested concurrency level.

    As soon as one request completes,
    another request is immediately started
    until the phase duration expires.
    """

    print(
        f"\n[{phase_name.upper()}] "
        f"starting "
        f"(duration={duration_seconds}s, "
        f"concurrency={concurrency})",
        flush=True,
    )

    phase_end = time.time() + duration_seconds

    request_counter = itertools.count(1)
    count_tokens = (
        prompt_factory.count_tokens
        if prompt_factory is not None
        else lambda text: 0
    )

    connector = aiohttp.TCPConnector(
        limit=0,
        ttl_dns_cache=300,
    )

    async with aiohttp.ClientSession(
        connector=connector,
        headers={"Authorization": f"Bearer {api_key}"},
    ) as session:

        async def worker():

            while (
                not STOP_REQUESTED
                and time.time() < phase_end
            ):
                request_id = next(request_counter)

                request_payload = payload
                if prompt_factory is not None:
                    request_payload = dict(payload)
                    request_payload["prompt"] = await asyncio.to_thread(
                        prompt_factory.build,
                        request_id_offset + request_id,
                    )

                state.active_requests += 1
                state.started += 1

                result = await single_request(
                    session=session,
                    url=url,
                    payload=request_payload,
                    timeout_seconds=timeout_seconds,
                    stream=stream,
                    count_tokens=count_tokens,
                )

                if (
                    result["success"]
                    and result["prompt_tokens"] <= 0
                    and prompt_factory is not None
                ):
                    result["prompt_tokens"] = prompt_factory.prompt_tokens

                state.active_requests -= 1
                state.completed += 1

                if result["success"]:
                    state.successes += 1
                    state.success_latencies_ms.append(result["latency_ms"])
                    state.prompt_tokens_total += result["prompt_tokens"]
                    state.output_tokens_total += result["output_tokens"]

                    if result["ttft_ms"] is not None:
                        state.ttft_ms.append(result["ttft_ms"])

                    if result["time_per_output_token_ms"] is not None:
                        state.time_per_output_token_ms.append(
                            result["time_per_output_token_ms"]
                        )
                else:
                    state.errors += 1
                    state.error_durations_ms.append(
                        result["error_duration_ms"]
                    )

                #
                # Persist request-level artifacts
                # during measurement phase only.
                #
                if request_file is not None:

                    record = {
                        "request_id": request_id,
                        "timestamp": int(time.time()),
                        **result,
                    }

                    request_file.write(
                        json.dumps(record) + "\n"
                    )

        tasks = [
            asyncio.create_task(worker())
            for _ in range(concurrency)
        ]

        while (
            time.time() < phase_end
            and not STOP_REQUESTED
        ):
            await asyncio.sleep(5)

            recent_latencies = state.success_latencies_ms[-500:]

            avg_latency = (
                statistics_lib.mean(recent_latencies)
                if recent_latencies
                else 0
            )

            print(
                f"""
--------------------------------------------------
Phase              : {phase_name}
Active Requests    : {state.active_requests}
Started Requests   : {state.started}
Completed Requests : {state.completed}
Successes          : {state.successes}
Errors             : {state.errors}
Avg Latency (ms)   : {avg_latency:.2f}
--------------------------------------------------
""",
                flush=True,
            )

        await asyncio.gather(*tasks)


def build_summary(
    *,
    run_start,
    run_end,
    concurrency,
    prompt_tokens,
    requested_output_tokens,
    stream,
    state,
):
    """
    Build a machine-readable summary for downstream
    metrics collection and aggregate reporting.
    """

    return {
        "run_start": int(run_start),
        "run_end": int(run_end),

        "concurrency": concurrency,
        "prompt_tokens": prompt_tokens,
        "requested_output_tokens": requested_output_tokens,
        "stream": stream,

        "requests_started": state.started,
        "requests_completed": state.completed,

        "successes": state.successes,
        "errors": state.errors,

        "prompt_tokens_total": state.prompt_tokens_total,
        "output_tokens_total": state.output_tokens_total,
    }


async def main():

    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--url",
        required=True,
    )

    parser.add_argument(
        "--api-key",
        required=True,
    )

    parser.add_argument(
        "--model",
        required=True,
    )

    prompt_group = parser.add_mutually_exclusive_group(required=True)

    prompt_group.add_argument(
        "--prompt",
    )

    prompt_group.add_argument(
        "--corpus-file",
    )

    parser.add_argument(
        "--prompt-tokens",
        type=int,
    )

    parser.add_argument(
        "--tokenizer-id",
    )

    parser.add_argument(
        "--tokenizer-revision",
    )

    parser.add_argument(
        "--concurrency",
        type=int,
        required=True,
    )

    parser.add_argument(
        "--warmup",
        type=int,
        default=120,
    )

    parser.add_argument(
        "--duration",
        type=int,
        default=480,
    )

    parser.add_argument(
        "--timeout",
        type=int,
        default=120,
    )

    parser.add_argument(
        "--max-tokens",
        type=int,
        default=128,
    )

    parser.add_argument(
        "--temperature",
        type=float,
        default=0.2,
    )

    parser.add_argument(
        "--stream",
        action="store_true",
    )

    parser.add_argument(
        "--output",
        required=True,
        help="Request-level JSONL output file",
    )

    parser.add_argument(
        "--summary-file",
        required=True,
        help="Benchmark summary JSON output file",
    )

    args = parser.parse_args()

    prompt_factory = None

    if args.corpus_file:
        if not all((args.prompt_tokens, args.tokenizer_id)):
            parser.error(
                "--corpus-file requires --prompt-tokens and --tokenizer-id"
            )

        prompt_factory = CorpusPromptFactory(
            corpus_file=args.corpus_file,
            prompt_tokens=args.prompt_tokens,
            tokenizer_id=args.tokenizer_id,
            tokenizer_revision=args.tokenizer_revision,
        )

    payload = {
        "model": args.model,
        "max_tokens": args.max_tokens,
        "min_tokens": args.max_tokens,
        "temperature": args.temperature,
        "ignore_eos": True,
        "stream": args.stream,
    }

    if args.stream:
        payload["stream_options"] = {"include_usage": True}

    if args.prompt is not None:
        payload["prompt"] = args.prompt

    output_path = Path(args.output)
    summary_path = Path(args.summary_file)

    output_path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    summary_path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    print(
        "\nBenchmark Configuration\n"
        "=======================\n"
        f"URL          : {args.url}\n"
        f"Model        : {args.model}\n"
        f"Prompt Tokens: {args.prompt_tokens or 'static'}\n"
        f"Output Tokens: {args.max_tokens}\n"
        f"Streaming    : {args.stream}\n"
        f"Concurrency  : {args.concurrency}\n"
        f"Warmup       : {args.warmup}s\n"
        f"Duration     : {args.duration}s\n"
        f"Output       : {output_path}\n"
        f"Summary File : {summary_path}\n",
        flush=True,
    )

    #
    # Warmup phase.
    #
    warmup_state = BenchmarkState()

    await run_phase(
        phase_name="warmup",
        duration_seconds=args.warmup,
        concurrency=args.concurrency,
        url=args.url,
        api_key=args.api_key,
        payload=payload,
        prompt_factory=prompt_factory,
        request_id_offset=0,
        stream=args.stream,
        timeout_seconds=args.timeout,
        state=warmup_state,
        request_file=None,
    )

    print(
        "\nWarmup completed.\n"
        "Beginning measurement phase.\n",
        flush=True,
    )

    #
    # Measurement phase.
    #
    measurement_state = BenchmarkState()

    run_start = time.time()

    with output_path.open(
        "w",
        encoding="utf-8",
    ) as request_file:

        await run_phase(
            phase_name="measurement",
            duration_seconds=args.duration,
            concurrency=args.concurrency,
            url=args.url,
            api_key=args.api_key,
            payload=payload,
            prompt_factory=prompt_factory,
            request_id_offset=1_000_000_000,
            stream=args.stream,
            timeout_seconds=args.timeout,
            state=measurement_state,
            request_file=request_file,
        )

    run_end = time.time()

    summary = build_summary(
        run_start=run_start,
        run_end=run_end,
        concurrency=args.concurrency,
        prompt_tokens=args.prompt_tokens,
        requested_output_tokens=args.max_tokens,
        stream=args.stream,
        state=measurement_state,
    )

    #
    # Persist benchmark summary.
    #
    with summary_path.open(
        "w",
        encoding="utf-8",
    ) as summary_file:

        json.dump(
            summary,
            summary_file,
            indent=2,
        )

    print(
        "\nBenchmark summary written to:\n"
        f"{summary_path}\n",
        flush=True,
    )


if __name__ == "__main__":
    asyncio.run(main())
