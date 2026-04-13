#!/usr/bin/env bash
# Download models for WhisKey — both Whisper ASR models and LLM cleanup models.
#
# Usage:
#   bash Scripts/download-models.sh [MODEL_KEY]
#
# Whisper ASR models:
#   tiny (default), base, small, medium, large
#
# LLM cleanup models:
#   phi-3.5-mini   — Phi-3.5 Mini Q4_K_M (~2.4 GB) — recommended default
#   llama-3.2-1b   — Llama 3.2 1B Q4_K_M (~0.8 GB)  — fastest option

set -e

MODEL=${1:-tiny}
MODELS_DIR="${MODELS_DIR:-Resources/Models}"
mkdir -p "$MODELS_DIR"

# ---------------------------------------------------------------------------
# Whisper ASR models (ggerganov/whisper.cpp on Hugging Face)
# ---------------------------------------------------------------------------
WHISPER_BASE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

declare -A WHISPER_FILES=(
    ["tiny"]="ggml-tiny.en.bin"
    ["base"]="ggml-base.en.bin"
    ["small"]="ggml-small.en.bin"
    ["medium"]="ggml-medium.en.bin"
    ["large"]="ggml-large-v3.bin"
)

# ---------------------------------------------------------------------------
# LLM cleanup models (GGUF format)
# ---------------------------------------------------------------------------
declare -A LLM_FILES=(
    ["phi-3.5-mini"]="phi-3.5-mini-q4_k_m.gguf"
    ["llama-3.2-1b"]="llama-3.2-1b-q4_k_m.gguf"
)

declare -A LLM_URLS=(
    ["phi-3.5-mini"]="https://huggingface.co/bartowski/Phi-3.5-Mini-Instruct-GGUF/resolve/main/Phi-3.5-Mini-Instruct-Q4_K_M.gguf"
    ["llama-3.2-1b"]="https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf"
)

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

if [[ -n "${WHISPER_FILES[$MODEL]}" ]]; then
    FILE="${WHISPER_FILES[$MODEL]}"
    DEST="$MODELS_DIR/$FILE"
    if [ -f "$DEST" ]; then
        echo "Model already present: $DEST"
        exit 0
    fi
    echo "Downloading whisper.cpp model: $FILE"
    curl -L --progress-bar "$WHISPER_BASE_URL/$FILE" -o "$DEST"
    echo "Saved to $DEST"

elif [[ -n "${LLM_FILES[$MODEL]}" ]]; then
    FILE="${LLM_FILES[$MODEL]}"
    URL="${LLM_URLS[$MODEL]}"
    DEST="$MODELS_DIR/$FILE"
    if [ -f "$DEST" ]; then
        echo "Model already present: $DEST"
        exit 0
    fi
    echo "Downloading LLM cleanup model: $FILE"
    curl -L --progress-bar "$URL" -o "$DEST"
    echo "Saved to $DEST"

else
    echo "Unknown model: $MODEL"
    echo ""
    echo "Whisper ASR:  tiny (default), base, small, medium, large"
    echo "LLM cleanup:  phi-3.5-mini, llama-3.2-1b"
    exit 1
fi
