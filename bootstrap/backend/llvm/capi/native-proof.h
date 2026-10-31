/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#ifndef ASTRA_NATIVE_PROOF_H
#define ASTRA_NATIVE_PROOF_H
#include <stddef.h>
#include <stdint.h>

/* Optional leaf proof, never a general x86 emulator. Zero means unproved.
 * types: 1..8 integer bytes, 16=f32, 17=f64, 32=one nominal pointer.
 * Result bits: 1=capture none, 2=readonly, 4=memory none, 8=proved.
 * Every pointer access must exactly match a checked scalar field interval.
 * LLVM validates instruction boundaries; the checker defines the semantics of
 * each admitted encoding independently of the printed assembly text. */
unsigned astra_native_leaf_proof(const uint8_t *object, int object_length,
                                 const char *symbol, const unsigned *types, int types_length,
                                 unsigned result_type, const unsigned *offsets, int offsets_length,
                                 const unsigned *sizes, int sizes_length);
/* Callee contracts are construction-local typed correspondences, never wire
 * metadata authority. Local entries are rechecked against this object; external
 * entries must already have an independently checked dependency receipt.
 * Contract text: flags,result-type,parameter-type,...; flag 16=local body,
 * flag 32=checked dependency. Low three flags have the meanings above. */
unsigned astra_native_object_proof(const uint8_t *object, int object_length,
                                   const char *symbol, const unsigned *types, int types_length,
                                   unsigned result_type, const unsigned *offsets, int offsets_length,
                                   const unsigned *sizes, int sizes_length,
                                   char *const *callee_symbols, int callee_symbols_length,
                                   char *const *callee_contracts, int callee_contracts_length);
#endif
