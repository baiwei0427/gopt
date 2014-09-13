#include "common.h"

#define G_1 1000000000
__global__ void
vectorAdd(int *A, int N)
{
	int i = blockDim.x * blockIdx.x + threadIdx.x;

	if (i < N) {
		A[i] *= A[i];
	}
}

int cmpfunc (const void *a, const void *b)
{
	double a_d = *(double *) a;
	double b_d = *(double *) b;

	if(a_d > b_d) {
		return 1;
	} else if(a_d < b_d) {
		return -1;
	} else {
		return 0;
	}
}

void dummy_run(int *h_A, int *d_A)
{
	int err = cudaSuccess;
	int threadsPerBlock = 256;
	int blocksPerGrid = (NUM_PKTS + threadsPerBlock - 1) / threadsPerBlock;

	err = cudaMemcpy(d_A, h_A, NUM_PKTS * sizeof(int), cudaMemcpyHostToDevice);
	CPE(err != cudaSuccess, "H2D memcpy failed\n");
	
	vectorAdd<<<blocksPerGrid, threadsPerBlock>>>(d_A, NUM_PKTS);
	err = cudaGetLastError();
	CPE(err != cudaSuccess, "Kernel launch failed\n");
	
	err = cudaMemcpy(h_A, d_A, NUM_PKTS * sizeof(int), cudaMemcpyDeviceToHost);
	CPE(err != cudaSuccess, "D2H memcpy failed\n");
}

void gpu_run(int *h_A, int *d_A)
{
	int err = cudaSuccess;
	struct timespec h2d_start[ITERS], h2d_end[ITERS];
	struct timespec kernel_start[ITERS], kernel_end[ITERS];
	struct timespec d2h_start[ITERS], d2h_end[ITERS];

	/** < Microseconds */
	double h2d_diff[ITERS], kernel_diff[ITERS], d2h_diff[ITERS];
	double h2d_tot = 0, kernel_tot = 0, d2h_tot = 0;
	
	int i, j;
	int threadsPerBlock = 256;
	int blocksPerGrid = (NUM_PKTS + threadsPerBlock - 1) / threadsPerBlock;

	/** < Do a dummy run for warmup */
	dummy_run(h_A, d_A);

	/** < Run several iterations */
	for(i = 0; i < ITERS; i ++) {

		for(j = 0; j < NUM_PKTS; j++)	{
			h_A[j] = i;
		}

		/** < Host-to-device memcpy */
		clock_gettime(CLOCK_REALTIME, &h2d_start[i]);
		err = cudaMemcpy(d_A, h_A, NUM_PKTS * sizeof(int), cudaMemcpyHostToDevice);
		CPE(err != cudaSuccess, "H2D memcpy failed\n");
		clock_gettime(CLOCK_REALTIME, &h2d_end[i]);

		/** < Kernel launch */
		clock_gettime(CLOCK_REALTIME, &kernel_start[i]);
		vectorAdd<<<blocksPerGrid, threadsPerBlock>>>(d_A, NUM_PKTS);
		err = cudaGetLastError();
		CPE(err != cudaSuccess, "Kernel launch failed\n");
		cudaDeviceSynchronize();
		clock_gettime(CLOCK_REALTIME, &kernel_end[i]);

		/** < Device-to-host memcpy */
		clock_gettime(CLOCK_REALTIME, &d2h_start[i]);
		err = cudaMemcpy(h_A, d_A, NUM_PKTS * sizeof(int), cudaMemcpyDeviceToHost);
		CPE(err != cudaSuccess, "D2H memcpy failed\n");
		clock_gettime(CLOCK_REALTIME, &d2h_end[i]);

		/** < Measure the difference */
		h2d_diff[i] =
			(double) (h2d_end[i].tv_nsec - h2d_start[i].tv_nsec) / 1000 +
			(h2d_end[i].tv_sec - h2d_start[i].tv_sec) * 1000000;
		kernel_diff[i] =
			(double) (kernel_end[i].tv_nsec - kernel_start[i].tv_nsec) / 1000 +
			(kernel_end[i].tv_sec - kernel_start[i].tv_sec) * 1000000;
		d2h_diff[i] =
			(double) (d2h_end[i].tv_nsec - d2h_start[i].tv_nsec) / 1000 +
			(d2h_end[i].tv_sec - d2h_start[i].tv_sec) * 1000000;

		printf("ITER %d: h2d: %f us, kernel: %f us, d2h us: %f\n", i,
			h2d_diff[i], kernel_diff[i], d2h_diff[i]);

		h2d_tot += h2d_diff[i];
		kernel_tot += kernel_diff[i];
		d2h_tot += d2h_diff[i];
	
	}

	/** < Sort the times for percentiles */
	qsort(h2d_diff, ITERS, sizeof(double), cmpfunc);
	qsort(kernel_diff, ITERS, sizeof(double), cmpfunc);
	qsort(d2h_diff, ITERS, sizeof(double), cmpfunc);

	red_printf("H2D average: %.2f us, 5th %.2f us, 95th: %.2f\n",
		h2d_tot / ITERS,
		h2d_diff[(ITERS * 5) / 100],
		h2d_diff[(ITERS * 95) / 100]);
	red_printf("Kernel average: %.2f us, 5th %.2f us, 95th: %.2f\n",
		kernel_tot / ITERS,
		kernel_diff[(ITERS * 5) / 100],
		kernel_diff[(ITERS * 95) / 100]);
	red_printf("D2H average: %.2f us, 5th %.2f us, 95th: %.2f\n",
		d2h_tot / ITERS,
		d2h_diff[(ITERS * 5) / 100],
		d2h_diff[(ITERS * 95) / 100]);
	
}

int main(void)
{
	int err = cudaSuccess;
	int *h_A, *d_A;

	printDeviceProperties();

	/** < Allocate host and device buffers */
	h_A = (int *) malloc(NUM_PKTS * sizeof(int));
	err = cudaMalloc((void **) &d_A, NUM_PKTS * sizeof(int));
	CPE(err != cudaSuccess, "Failed to cudaMalloc\n");

	if (h_A == NULL) {
		fprintf(stderr, "Failed to allocate host vectors!\n");
		exit(EXIT_FAILURE);
	}

	/** < Run the measurement code */
	gpu_run(h_A, d_A);
	
	/** < Free host and device memory */
	free(h_A);
	cudaFree(d_A);

	// Reset the device and exit
	err = cudaDeviceReset();
	CPE(err != cudaSuccess, "Failed to de-initialize the device\n");
	return 0;
}

