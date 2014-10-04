#include<stdio.h>
#include<stdlib.h>
#include<assert.h>
#include<pthread.h>
#include<stdint.h>

#include "city.h"
#include "util.h"

#define NUM_THREADS 4
#define WRITER_COMPUTE 30

#define NUM_LOCKS 1024
#define NUM_LOCKS_ (NUM_LOCKS - 1)

#define NUM_NODES (1024 * 1024)
#define NUM_NODES_ (NUM_NODES - 1)

#define GHZ_CPS 1000000000
#define ITERS_PER_MEASUREMENT 10000000

typedef struct {
	long long a;
	long long b;
} node_t;

typedef struct {
	pthread_spinlock_t lock;
	int index;
	long long pad[7];
} lock_t;

void *reader(void *ptr);
void *writer(void *ptr);

/** < Only shared variables here */
node_t *nodes;
lock_t *locks;

int main()
{
	int i;
	int tid[NUM_THREADS];
	pthread_t thread[NUM_THREADS];

	/** < Ensure that locks are cacheline aligned */
	assert(sizeof(lock_t) == 64);

	/** < Allocate the shared nodes */
	red_printf("Allocting %d nodes\n", NUM_NODES);
	nodes = (node_t *) malloc(NUM_NODES * sizeof(node_t));
	assert(nodes != NULL);
	
	for(i = 0; i < NUM_NODES; i ++) {
		nodes[i].a = rand();
		nodes[i].b = nodes[i].a + 1;
	}

	/** < Allocate the striped spinlocks */
	red_printf("Allocting %d locks\n", NUM_LOCKS);
	locks = (lock_t *) malloc(NUM_LOCKS * sizeof(lock_t));
	assert(locks != NULL);
	
	for(i = 0; i < NUM_LOCKS; i++) {
		pthread_spin_init(&locks[i].lock, 0);
	}
	
	/** < Launch several reader threads and a writer thread */
	for(i = 0; i < NUM_THREADS; i++) {
		tid[i] = i;
		if(i == 0) {
			red_printf("Launching writer thread with tid = %d\n", tid[i]);
			pthread_create(&thread[i], NULL, writer, &tid[i]);
		} else {
			red_printf("Launching reader thread with tid = %d\n", tid[i]);
			pthread_create(&thread[i], NULL, reader, &tid[i]);
		}
	}

	for(i = 0; i < NUM_THREADS; i++) {
		pthread_join(thread[i], NULL);
	}

	exit(0);
}

void *reader( void *ptr)
{
	struct timespec start, end;
	int tid = *((int *) ptr);
	uint64_t seed = 0xdeadbeef + tid;
	int sum = 0;

	/** < The node and lock to use in an iteration */
	int node_id, lock_id;

	/** < Total number of iterations (for measurement) */
	int num_iters = 0;

	clock_gettime(CLOCK_REALTIME, &start);

	while(1) {
		if(num_iters == ITERS_PER_MEASUREMENT) {
			clock_gettime(CLOCK_REALTIME, &end);
			double seconds = (end.tv_sec - start.tv_sec) + 
				(double) (end.tv_nsec - start.tv_nsec) / GHZ_CPS;
		
			printf("Reader thread %d: rate = %.2f M/s. Sum = %d\n", tid, 
				num_iters / (1000000 * seconds), sum);
				
			num_iters = 0;
			clock_gettime(CLOCK_REALTIME, &start);
		}

		node_id = fastrand(&seed) & NUM_NODES_;
		lock_id = node_id & NUM_LOCKS_;

		pthread_spin_lock(&locks[lock_id].lock);

		/** < Critical section begin */
		if(nodes[node_id].b != nodes[node_id].a + 1) {
			red_printf("Invariant violated\n");
		}
		sum += nodes[node_id].a + nodes[node_id].b;
		
		/** < Critical section end */

		pthread_spin_unlock(&locks[lock_id].lock);

		num_iters ++;
	}
}


void *writer( void *ptr)
{
	struct timespec start, end;
	int tid = *((int *) ptr);
	uint64_t seed = 0xdeadbeef + tid;
	int sum = 0;

	/** < The node and lock to use in an iteration */
	int i, node_id, lock_id;
	
	/** < Total number of iterations (for measurement) */
	int num_iters = 0;

	clock_gettime(CLOCK_REALTIME, &start);

	while(1) {
		if(num_iters == ITERS_PER_MEASUREMENT) {
			clock_gettime(CLOCK_REALTIME, &end);
			double seconds = (end.tv_sec - start.tv_sec) + 
				(double) (end.tv_nsec - start.tv_nsec) / GHZ_CPS;
		
			node_id = fastrand(&seed) & NUM_NODES_;

			red_printf("Writer thread %d: rate = %.2f M/s. "
				"Random node: (%lld, %lld)\n", tid, 
				num_iters / (1000000 * seconds),
				nodes[node_id].a, nodes[node_id].b);
				
			num_iters = 0;
			clock_gettime(CLOCK_REALTIME, &start);
		}

		node_id = fastrand(&seed) & NUM_NODES_;
		lock_id = node_id & NUM_LOCKS_;

		pthread_spin_lock(&locks[lock_id].lock);

		/** < Critical section begin */
		nodes[node_id].a ++;
		nodes[node_id].b ++;
		
		/** < Critical section end */

		pthread_spin_unlock(&locks[lock_id].lock);

		num_iters ++;
	}
}