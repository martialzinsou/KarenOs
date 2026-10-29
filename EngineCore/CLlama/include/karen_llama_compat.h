#ifndef KAREN_LLAMA_COMPAT_H
#define KAREN_LLAMA_COMPAT_H

#include "llama.h"

/*
 * KarenOS — compatibilité KV cache.
 *
 * b8967 (et les versions récentes) exposent llama_memory_seq_rm/add via
 * llama_get_memory(ctx). Les versions antérieures exposaient directement
 * llama_kv_cache_seq_rm/add. Ce shim garde le code Swift stable ; pour une
 * version legacy, compiler avec -DKAREN_LLAMA_LEGACY_KV et adapter les
 * appels ci-dessous.
 */
static inline bool karen_llama_kv_seq_rm(struct llama_context * ctx,
                                         llama_seq_id seq_id,
                                         llama_pos p0,
                                         llama_pos p1) {
#if defined(KAREN_LLAMA_LEGACY_KV)
    return llama_kv_cache_seq_rm(ctx, seq_id, p0, p1);
#else
    return llama_memory_seq_rm(llama_get_memory(ctx), seq_id, p0, p1);
#endif
}

static inline void karen_llama_kv_seq_add(struct llama_context * ctx,
                                          llama_seq_id seq_id,
                                          llama_pos p0,
                                          llama_pos p1,
                                          llama_pos delta) {
#if defined(KAREN_LLAMA_LEGACY_KV)
    llama_kv_cache_seq_add(ctx, seq_id, p0, p1, delta);
#else
    llama_memory_seq_add(llama_get_memory(ctx), seq_id, p0, p1, delta);
#endif
}

static inline void karen_llama_kv_clear(struct llama_context * ctx, bool data) {
#if defined(KAREN_LLAMA_LEGACY_KV)
    (void) ctx;
    (void) data;
    llama_kv_cache_clear(ctx);
#else
    llama_memory_clear(llama_get_memory(ctx), data);
#endif
}

#endif
