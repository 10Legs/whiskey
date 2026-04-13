#!/usr/bin/env bash
# Download Whisper GGUF models for WhisKey.
# Usage: bash Scripts/download-models.sh [tiny|base|small|medium|large]
# Default: tiny

set -e

MODEL=${1:-tiny}
MODELS_DIR="Resources/Models"
mkdir -p "$MODELS_DIR"

BASE_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

declare -A MODEL_FILES=(
    ["tiny"]="ggml-tiny.en.bin"
    ["base"]="ggml-base.en.bin"
    ["small"]="ggml-small.en.bin"
    ["medium"]="ggml-medium.en.bin"
    ["large"]="ggml-large-v3.bin"
)

FILE=${MODEL_FILES[$MODEL]}
if [ -z "$FILE" ]; then
    echo "Unknown model: $MODEL. Choose: tiny, base, small, medium, large"
    exit 1
fi

DEST="$MODELS_DIR/$FILE"
if [ -f "$DEST" ]; then
    echo "Model already present: $DEST"
    exit 0
fi

echo "Downloading whisper.cpp model: $FILE"
curl -L --progress-bar "$BASE_URL/$FILE" -o "$DEST"
echo "Saved to $DEST"
