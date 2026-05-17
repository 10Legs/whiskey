// whisper_bridge.cpp -- thin C++ wrapper over whisper.cpp for Swift consumption.
// Exposes a pure-C API so Swift can call it without a C++ bridging header.

#include "whisper_bridge.h"
#include "whisper.h"

#include <cstdlib>
#include <cstring>
#include <string>
#include <sstream>

extern "C" {

whisper_context * whisper_bridge_init(const char * model_path) {
    if (model_path == nullptr) return nullptr;
    struct whisper_context_params cparams = whisper_context_default_params();
    // Metal disabled: ggml requires a precompiled default.metallib in the app
    // bundle to initialise the GPU backend. When running from an SPM build (no
    // bundle), the shader is unavailable and ggml aborts. CPU path via Accelerate
    // is still fast on Apple Silicon. Re-enable once bundle/metallib is wired up.
    cparams.use_gpu = true;
    struct whisper_context * ctx = whisper_init_from_file_with_params(model_path, cparams);
    return ctx;
}

void whisper_bridge_free(whisper_context * ctx) {
    if (ctx) {
        whisper_free(ctx);
    }
}

whisper_bridge_result whisper_bridge_transcribe(
    whisper_context * ctx,
    const float * pcm_data,
    int pcm_len,
    const char * language_hint,
    int n_threads,
    const char * initial_prompt
) {
    whisper_bridge_result out;
    out.text = nullptr;
    out.duration_ms = 0;
    out.language = nullptr;

    if (!ctx || !pcm_data || pcm_len <= 0) {
        out.text = strdup("");
        out.language = strdup("unknown");
        return out;
    }

    struct whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    wparams.print_progress = false;
    wparams.print_special  = false;
    wparams.print_realtime = false;
    wparams.print_timestamps = false;
    wparams.translate      = false;
    wparams.n_threads      = (n_threads > 0) ? n_threads : 4;

    // Initial prompt: biases the beam search toward specific vocabulary terms.
    // Passed as-is to whisper_full_params.initial_prompt (whisper.cpp stores a
    // char* pointer -- the caller owns the lifetime; safe here because wparams is
    // only alive for the duration of whisper_full below).
    if (initial_prompt && strlen(initial_prompt) > 0) {
        wparams.initial_prompt = initial_prompt;
    }

    // Language: NULL means auto-detect; otherwise force the given language code.
    // .en models have no language detection head -- detect_language=true produces
    // garbage output. Fall back to "en" for non-multilingual models.
    if (language_hint && strlen(language_hint) > 0) {
        wparams.language = language_hint;
        wparams.detect_language = false;
    } else if (!whisper_is_multilingual(ctx)) {
        wparams.language = "en";
        wparams.detect_language = false;
    } else {
        wparams.language = nullptr;
        wparams.detect_language = true;
    }

    int rc = whisper_full(ctx, wparams, pcm_data, pcm_len);
    if (rc != 0) {
        out.text = strdup("");
        out.language = strdup("unknown");
        return out;
    }

    // Concatenate all segment texts
    int n_segments = whisper_full_n_segments(ctx);
    std::ostringstream ss;
    for (int i = 0; i < n_segments; ++i) {
        const char * seg = whisper_full_get_segment_text(ctx, i);
        if (seg) {
            ss << seg;
        }
    }

    // Compute duration from last segment end time (in centiseconds -> ms)
    if (n_segments > 0) {
        int64_t t1_cs = whisper_full_get_segment_t1(ctx, n_segments - 1);
        out.duration_ms = t1_cs * 10; // whisper timestamps are in centiseconds
    }

    std::string result_str = ss.str();
    out.text = strdup(result_str.c_str());

    // Detected language
    int lang_id = whisper_full_lang_id(ctx);
    if (lang_id >= 0) {
        const char * lang_str = whisper_lang_str(lang_id);
        out.language = lang_str ? strdup(lang_str) : strdup("unknown");
    } else {
        out.language = strdup("unknown");
    }

    return out;
}

void whisper_bridge_result_free(whisper_bridge_result * result) {
    if (!result) return;
    if (result->text) {
        free((void *)result->text);
        result->text = nullptr;
    }
    if (result->language) {
        free((void *)result->language);
        result->language = nullptr;
    }
}

bool whisper_bridge_is_multilingual(whisper_context * ctx) {
    if (!ctx) return false;
    return whisper_is_multilingual(ctx) != 0;
}

} // extern "C"
