#!/bin/bash

# Get current directory for path references
CURRENT_DIR=$(pwd)

# Download Mooncake trace if it doesn't exist
TRACE_FILE="DS_V3_anonymous_trace3.jsonl"
if [ ! -f "$TRACE_FILE" ]; then
    echo "Downloading Mooncake trace..."
    curl -o "$TRACE_FILE" "https://raw.githubusercontent.com/kvcache-ai/Mooncake/refs/heads/main/mooncake_trace.jsonl"
fi

# Default parameters - modify as needed
MODEL="${MODEL:-NousResearch/Llama-3.2-1B}"
HOST="${HOST:-localhost}"
PORT="${PORT:-8000}"
BACKEND="${BACKEND:-vllm}"
DURATION="${DURATION:-60}"
START_TIME="${START_TIME:-0}"
PRESERVE_TIMING="${PRESERVE_TIMING:-true}"
TIME_SCALE="${TIME_SCALE:-1.0}"

echo "Replaying Mooncake trace with:"
echo "  Model: $MODEL"
echo "  Server: $HOST:$PORT"
echo "  Backend: $BACKEND"
echo "  Duration: $DURATION seconds"
echo "  Start time: $START_TIME seconds"
echo "  Preserve timing: $PRESERVE_TIMING"
echo "  Time scale: $TIME_SCALE"

# Build the command arguments
ARGS=(
    --trace-file "$CURRENT_DIR/$TRACE_FILE"
    --model "$MODEL"
    --host "$HOST"
    --port "$PORT"
    --backend "$BACKEND"
    --duration "$DURATION"
    --start-time "$START_TIME"
    --time-scale "$TIME_SCALE"
    --ignore-eos
    --output-file "$CURRENT_DIR/mooncake_replay_results.json"
)

# Add preserve-timing flag if enabled
if [ "$PRESERVE_TIMING" = "true" ]; then
    ARGS+=(--preserve-timing)
    echo "  Mode: Timed replay (preserving original request timestamps)"
else
    echo "  Mode: Fast replay (ignoring original timestamps)"
fi

# Run the replay script from outside the vLLM source directory to avoid import conflicts
cd /home/ie-user
source "$CURRENT_DIR/.venv/bin/activate"
# Temporarily rename the vllm directory to avoid local import conflicts
mv "$CURRENT_DIR/vllm" "$CURRENT_DIR/vllm_temp" 2>/dev/null || true
python3 "$CURRENT_DIR/replay_mooncake_trace.py" "${ARGS[@]}" "$@"
# Restore the vllm directory
mv "$CURRENT_DIR/vllm_temp" "$CURRENT_DIR/vllm" 2>/dev/null || true
cd "$CURRENT_DIR"

echo "Replay completed. Results saved to mooncake_replay_results.json"

# Show some quick stats
if [ -f "$CURRENT_DIR/mooncake_replay_results.json" ]; then
    echo ""
    echo "Quick Results Summary:"
    python3 -c "
import json
try:
    with open('$CURRENT_DIR/mooncake_replay_results.json', 'r') as f:
        data = json.load(f)
    if 'metrics' in data:
        metrics = data['metrics']
        print(f\"  Successful requests: {data.get('successful_requests', 'N/A')}\")
        print(f\"  Failed requests: {data.get('failed_requests', 'N/A')}\")
        print(f\"  Total duration: {data.get('actual_duration', 'N/A'):.2f}s\")
        if 'mean_ttft_ms' in metrics:
            print(f\"  Mean TTFT: {metrics['mean_ttft_ms']:.2f}ms\")
        if 'mean_tpot_ms' in metrics:
            print(f\"  Mean TPOT: {metrics['mean_tpot_ms']:.2f}ms\")
        if 'throughput_token_per_s' in metrics:
            print(f\"  Throughput: {metrics['throughput_token_per_s']:.2f} tokens/s\")
    else:
        print('  (Legacy format - see full results in JSON file)')
except Exception as e:
    print(f'  Error reading results: {e}')
"
fi 