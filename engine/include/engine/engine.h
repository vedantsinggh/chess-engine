#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define ENGINE_API __declspec(dllexport)
#else
#define ENGINE_API __attribute__((visibility("default")))
#endif

// Static evaluation of a FEN in centipawns from white's perspective.
// Returns 0 for an invalid FEN.
ENGINE_API int eval(const char* fen);

#ifdef __cplusplus
}
#endif
