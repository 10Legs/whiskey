#ifndef LLAMA_BRIDGE_H
#define LLAMA_BRIDGE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct llama_bridge_ctx llama_bridge_ctx;

/// Load a GGUF model from `model_path`.
/// `n_ctx`     — context window size (recommend 2048).
/// `n_threads` — number of CPU threads.
/// Returns NULL on failure.
llama_bridge_ctx * llama_bridge_init(const char * model_path, int n_ctx, int n_threads);

/// Free a previously allocated context.
void llama_bridge_free(llama_bridge_ctx * ctx);

typedef struct {
    const char * text;   // heap-allocated; caller must call llama_bridge_completion_free
    int tokens_used;
} llama_bridge_completion;

/// Run a single chat-style completion.
/// `system_prompt` — instruction message (role: system).
/// `user_prompt`   — transcript to clean (role: user).
/// `max_tokens`    — maximum tokens to generate.
/// `temperature`   — sampling temperature (0.1 for deterministic cleanup).
llama_bridge_completion llama_bridge_complete(
    llama_bridge_ctx * ctx,
    const char * system_prompt,
    const char * user_prompt,
    int max_tokens,
    float temperature
);

/// Free the heap-allocated string inside a `llama_bridge_completion`.
void llama_bridge_completion_free(llama_bridge_completion * result);

#ifdef __cplusplus
}
#endif

#endif /* LLAMA_BRIDGE_H */
