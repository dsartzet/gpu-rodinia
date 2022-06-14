/*
 * Copyright 1993-2013 NVIDIA Corporation.  All rights reserved.
 *
 * Please refer to the NVIDIA end user license agreement (EULA) associated
 * with this source code for terms and conditions that govern your use of
 * this software. Any use, reproduction, disclosure, or distribution of
 * this software and related documentation outside the terms of the EULA
 * is strictly prohibited.
 *
 */



///////////////////////////////////////////////////////////////////////////////
// On G80-class hardware 24-bit multiplication takes 4 clocks per warp
// (the same as for floating point  multiplication and addition),
// whereas full 32-bit multiplication takes 16 clocks per warp.
// So if integer multiplication operands are  guaranteed to fit into 24 bits
// (always lie withtin [-8M, 8M - 1] range in signed case),
// explicit 24-bit multiplication is preferred for performance.
///////////////////////////////////////////////////////////////////////////////
#define IMUL(a, b) __mul24(a, b)



///////////////////////////////////////////////////////////////////////////////
// Calculate scalar products of VectorN vectors of ElementN elements on GPU
// Parameters restrictions:
// 1) ElementN is strongly preferred to be a multiple of warp size to
//    meet alignment constraints of memory coalescing.
// 2) ACCUM_N must be a power of two.
///////////////////////////////////////////////////////////////////////////////
#define ACCUM_N 1024
__global__ void scalarProdGPU(
    float *d_C,
    float *d_A,
    float *d_B,
    int vectorN,
    int elementN
)
{
    //Accumulators cache
    __shared__ float accumResult[ACCUM_N*3]; // L

    ////////////////////////////////////////////////////////////////////////////
    // Cycle through every pair of vectors,
    // taking into account that vector counts can be different
    // from total number of thread blocks
    ////////////////////////////////////////////////////////////////////////////
    for (int vec = blockIdx.x; vec < vectorN; vec += gridDim.x)
    {
        int vectorBase = IMUL(elementN, vec);
        int vectorEnd  = vectorBase + elementN;

        ////////////////////////////////////////////////////////////////////////
        // Each accumulator cycles through vectors with
        // stride equal to number of total number of accumulators ACCUM_N
        // At this stage ACCUM_N is only preferred be a multiple of warp size
        // to meet memory coalescing alignment constraints.
        ////////////////////////////////////////////////////////////////////////
        for (int iAccum = threadIdx.x; iAccum < ACCUM_N; iAccum += blockDim.x)
        {
            float sum = 0;

            for (int pos = vectorBase + iAccum; pos < vectorEnd; pos += ACCUM_N)
                sum += d_A[pos] * d_B[pos];

            accumResult[iAccum+ACCUM_N*threadIdx.y] = sum; // L
        }

        ////////////////////////////////////////////////////////////////////////
        // Perform tree-like reduction of accumulators' results.
        // ACCUM_N has to be power of two at this stage
        ////////////////////////////////////////////////////////////////////////
        for (int stride = ACCUM_N / 2; stride > 0; stride >>= 1)
        {
            __syncthreads();

            for (int iAccum = threadIdx.x; iAccum < stride; iAccum += blockDim.x)
                accumResult[iAccum+ACCUM_N*threadIdx.y] += accumResult[stride + iAccum+ACCUM_N*threadIdx.y]; // L
        }

        if (threadIdx.x == 0) d_C[vec+256*threadIdx.y] = accumResult[0+ACCUM_N*threadIdx.y]; // L
    }
    if (threadIdx.x == 0 && threadIdx.y == 0 && blockIdx.x == 0) d_C[0] = 1;
}




/* START of Lishan add */
__global__ void check_correctness(float* result, int size)
{
    int tid = threadIdx.x + blockIdx.x * blockDim.x;
    if (tid >= size) return;
    if (result[tid] != result[tid+size])
    {
        if (result[tid] != result[tid+size*2] && result[tid+size]!= result[tid+size*2])
        {
            printf ("DUE %f %f %f\n", result[tid], result[tid+size], result[tid+size*2]);
            // All three copies have different results. This is considered as DUE, not SDC.
        }
        else
        {
          //printf ("correcting tid=%d %.10f %.10f %.10f\n", tid,result[tid], result[tid+size], result[tid+size*2]);  
            result[tid] = result[tid+size*2];
        }
    }
}
/* END of Lishan add */

