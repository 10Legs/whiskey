// llama_bridge.cpp — thin C wrapper around llama.cpp for WhisKey's LLM cleanup layer.
//
// This file depends on llama.cpp headers vendored at Vendor/llama.cpp.
// It is intentionally thin: all sampling and context management stays here so
// that the Swift layer (LlamaCppProvider) only deals with plain C types.

#include "include/llama_bridge.h"

#include "llama.h"

#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#if defined(__APPLE__)
#include <mach-o/dyld.h>   // _NSGetExecutablePath
#include <climits>

// Point ggml_metal at the app bundle's Resources dir before any llama init.
// Uses _NSGetExecutablePath to derive the path — immune to CFBundle / NSBundle
// quirks that return the flat DerivedData build dir in SPM/Xcode hybrids.
// Always overwrites the env var so it cannot be poisoned by earlier callers.
static void set_metal_path_from_bundle() {
    char execPath[PATH_MAX];
    uint32_t size = sizeof(execPath);
    if (_NSGetExecutablePath(execPath, &size) != 0) return;

    // Resolve symlinks so we get the canonical path.
    char resolved[PATH_MAX];
    if (!realpath(execPath, resolved)) return;

    // Executable is at: WhisKey.app/Contents/MacOS/WhisKey
    // Resources are at: WhisKey.app/Contents/Resources/
    std::string path(resolved);
    auto pos = path.rfind("/MacOS/");
    if (pos == std::string::npos) return;

    std::string resourcePath = path.substr(0, pos) + "/Resources";
    setenv("GGML_METAL_PATH_RESOURCES", resourcePath.c_str(), 1);
    fprintf(stderr, "llama_bridge: GGML_METAL_PATH_RESOURCES = %s\n", resourcePath.c_str());
}
#endif

// ---------------------------------------------------------------------------
// Context struct
// ---------------------------------------------------------------------------

struct llama_bridge_ctx {
    llama_model   * model   = nullptr;
    llama_context * context = nullptr;
    int             n_ctx   = 2048;
    int             n_threads = 4;
};

// ---------------------------------------------------------------------------
// Init / free
// ---------------------------------------------------------------------------

extern "C"
llama_bridge_ctx * llama_bridge_init(const char * model_path, int n_ctx, int n_threads) {
#if defined(__APPLE__)
    set_metal_path_from_bundle();
#endif
    llama_model_params mparams = llama_model_default_params();
    mparams.use_mmap = true;

    llama_model * model = llama_load_model_from_file(model_path, mparams);
    if (!model) return nullptr;

    llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx      = static_cast<uint32_t>(n_ctx);
    cparams.n_threads  = static_cast<uint32_t>(n_threads);

    llama_context * lctx = llama_new_context_with_model(model, cparams);
    if (!lctx) {
        llama_free_model(model);
        return nullptr;
    }

    auto * bridge = new llama_bridge_ctx();
    bridge->model     = model;
    bridge->context   = lctx;
    bridge->n_ctx     = n_ctx;
    bridge->n_threads = n_threads;
    return bridge;
}

extern "C"
void llama_bridge_free(llama_bridge_ctx * ctx) {
    if (!ctx) return;
    if (ctx->context) llama_free(ctx->context);
    if (ctx->model)   llama_free_model(ctx->model);
    delete ctx;
}

// ---------------------------------------------------------------------------
// Completion
// ---------------------------------------------------------------------------

extern "C"
llama_bridge_completion llama_bridge_complete(
    llama_bridge_ctx * ctx,
    const char * system_prompt,
    const char * user_prompt,
    int max_tokens,
    float temperature
) {
    llama_bridge_completion result{};
    result.text        = nullptr;
    result.tokens_used = 0;

    if (!ctx || !ctx->context || !ctx->model) {
        result.text = strdup("");
        return result;
    }

    // Build a simple chat prompt: <|system|>...<|user|>...<|assistant|>
    // The exact template is model-agnostic; llama.cpp applies the model's
    // chat template if available via llama_chat_apply_template, but we use
    // a plain concatenation to avoid template format dependencies.
    std::string prompt;
    if (system_prompt && system_prompt[0] != '\0') {
        prompt += "<|system|>\n";
        prompt += system_prompt;
        prompt += "\n";
    }
    prompt += "<|user|>\n";
    prompt += (user_prompt ? user_prompt : "");
    prompt += "\n<|assistant|>\n";

    const struct llama_vocab * vocab = llama_model_get_vocab(ctx->model);

    // Tokenise
    const int prompt_len_estimate = static_cast<int>(prompt.size()) + 16;
    std::vector<llama_token> tokens(prompt_len_estimate);
    int n_tokens = llama_tokenize(
        vocab,
        prompt.c_str(),
        static_cast<int>(prompt.size()),
        tokens.data(),
        static_cast<int>(tokens.size()),
        /*add_special=*/true,
        /*parse_special=*/true
    );

    if (n_tokens < 0) {
        // Buffer was too small — retry with exact size.
        tokens.resize(-n_tokens);
        n_tokens = llama_tokenize(
            vocab,
            prompt.c_str(),
            static_cast<int>(prompt.size()),
            tokens.data(),
            static_cast<int>(tokens.size()),
            true, true
        );
    }

    if (n_tokens <= 0) {
        result.text = strdup("");
        return result;
    }
    tokens.resize(n_tokens);

    // Clear memory (replaces deprecated llama_kv_cache_clear)
    llama_memory_clear(llama_get_memory(ctx->context), true);

    // Decode prompt
    llama_batch batch = llama_batch_get_one(tokens.data(), static_cast<int32_t>(tokens.size()));
    if (llama_decode(ctx->context, batch) != 0) {
        result.text = strdup("");
        return result;
    }

    // Sample loop
    std::string output;
    output.reserve(512);
    int tokens_generated = 0;

    llama_sampler * sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
    llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature));
    llama_sampler_chain_add(sampler, llama_sampler_init_greedy());

    while (tokens_generated < max_tokens) {
        llama_token token_id = llama_sampler_sample(sampler, ctx->context, -1);

        if (llama_vocab_is_eog(vocab, token_id)) break;

        // Convert token to text
        char piece[256] = {};
        int n_piece = llama_token_to_piece(vocab, token_id, piece, sizeof(piece), 0, true);
        if (n_piece > 0) {
            output.append(piece, n_piece);
        }

        llama_sampler_accept(sampler, token_id);

        llama_batch next = llama_batch_get_one(&token_id, 1);
        if (llama_decode(ctx->context, next) != 0) break;

        ++tokens_generated;
    }

    llama_sampler_free(sampler);

    result.text        = strdup(output.c_str());
    result.tokens_used = tokens_generated;
    return result;
}

extern "C"
void llama_bridge_completion_free(llama_bridge_completion * result) {
    if (!result) return;
    if (result->text) {
        free(const_cast<char *>(result->text));
        result->text = nullptr;
    }
}
