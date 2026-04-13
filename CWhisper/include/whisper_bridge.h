#ifndef WHISPER_BRIDGE_H
#define WHISPER_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct whisper_context whisper_context;

/// Load a whisper model from the given file path.
/// Returns NULL on failure.
whisper_context * whisper_bridge_init(const char * model_path);

/// Free a previously allocated context.
void whisper_bridge_free(whisper_context * ctx);

typedef struct {
    const char * text;       // heap-allocated; caller must call whisper_bridge_result_free
    int64_t duration_ms;
    const char * language;   // heap-allocated; caller must call whisper_bridge_result_free
} whisper_bridge_result;

/// Transcribe PCM audio (16kHz, mono, Float32).
/// language_hint: NULL for auto-detect; "en", "es", etc. for forced language.
/// n_threads: number of CPU threads (recommend 4 on Apple Silicon).
whisper_bridge_result whisper_bridge_transcribe(
    whisper_context * ctx,
    const float * pcm_data,
    int pcm_len,
    const char * language_hint,
    int n_threads
);

/// Free strings inside a whisper_bridge_result.
void whisper_bridge_result_free(whisper_bridge_result * result);

/// Returns true when the loaded model supports multiple languages.
bool whisper_bridge_is_multilingual(whisper_context * ctx);

#ifdef __cplusplus
}
#endif

#endif /* WHISPER_BRIDGE_H */
