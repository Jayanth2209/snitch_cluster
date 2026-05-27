// Copyright 2023 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author: Tim Fischer <fischeti@iis.ee.ethz.ch>
//         Luca Colagrande <colluca@iis.ee.ethz.ch>
//         Viviane Potocnik <vivianep@iis.ee.ethz.ch>

#include <math.h>
#include <stdint.h>

#include "blas.h"

#include "data.h"
#include "snrt.h"

int main() {

    uint32_t prec_dst = args.prec_dst;
    uint32_t dual_ssr = args.dual_ssr;
    uint32_t src_type = args.src_type;

    if (dual_ssr) {
        write_csr(3, (1 << 10)); // Enable dual SSRs for scales
    }

    uint32_t fmode = 0;

    // src_type: 0=FP8, 1=FP8ALT, 2=FP6, 3=FP6ALT, 4=FP4, 5=INT8
    if (src_type == 1 || src_type == 3) {
        fmode |= 2;  // ALT variants
    }

    if (prec_dst == 2) {
        fmode |= 1;  // BF16 destination
    }

    write_csr(2048, fmode);

    int retcode = mxgemm(&args);

    snrt_cluster_hw_barrier();

#ifdef BIST
    // Aliases
    uint32_t M = args.M;
    uint32_t N = args.N;

    int errors = M * N;

    if (snrt_cluster_core_idx() == 0) {
        for (uint32_t m = 0; m < M; m++) {
            for (uint32_t n = 0; n < N; n++) {
                uint32_t idx = m * N + n;

                if (prec_dst == 2) {
                    uint16_t c_val = ((uint16_t*)c)[idx];
                    uint16_t r_val = ((uint16_t*)result)[idx];
                    if (c_val == r_val) {
                        errors--;
                    } else {
                        printf("Mismatch at %d: C = 0x%04x, R = 0x%04x\n", idx, c_val, r_val);
                    }
                } else {
                    uint32_t c_val = ((uint32_t*)c)[idx];
                    uint32_t r_val = ((uint32_t*)result)[idx];
                    if (c_val == r_val) {
                        errors--;
                    } else {
                        printf("Mismatch at %d: C = 0x%08x, R = 0x%08x\n", idx, c_val, r_val);
                    }
                }
            }
        }
        printf("%d/%d Errors\n", errors, M * N);

        return errors;
    }
#endif

    return retcode;
}
