// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Generated input, independent scalar oracle and observation/platform edges.
// The actual transform, filter state, report collection and lifetimes are Astra.
#define _POSIX_C_SOURCE 200809L
#include <inttypes.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#if defined(TELEMETRY_WORKERS) || defined(TELEMETRY_IO)
#include <pthread.h>
#include "context-17.h"
#endif

#ifdef TELEMETRY_EXTRA_AUDIT
enum { AUDITS = 4 };
#else
enum { AUDITS = 3 };
#endif

typedef struct {
	int count, failed, retired, kinds[AUDITS], shared_retired[2], shared_result;
	_Atomic int entered, reported;
	unsigned long allocations;
	uint64_t started, elapsed;
	double energy, maximum_error;
} Window;
static Window *windows;
static double *expected, *actual;
static _Atomic unsigned char *seen;
static int samples, window_size, window_count, seed;
static _Atomic int emitted, bad;
static _Thread_local int active = -1;
#ifdef TELEMETRY_IO
static pthread_mutex_t io_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_t io_issuer, io_threads[4];
static int io_jobs, io_distinct;
#endif

void *calloc(size_t count, size_t size) {
	if (size && count > SIZE_MAX / size) return NULL;
	void *result = malloc(count * size);
	if (result) memset(result, 0, count * size);
	if (active >= 0 && windows) windows[active].allocations++;
	return result;
}
static int setting(const char *name, int fallback, int minimum, int maximum) {
	const char *text = getenv(name);
	if (!text) return fallback;
	char *end;
	long value = strtol(text, &end, 10);
	if (*end || value < minimum || value > maximum) abort();
	return (int)value;
}
static uint64_t now(void) {
	struct timespec value;
	if (clock_gettime(CLOCK_MONOTONIC, &value)) abort();
	return (uint64_t)value.tv_sec * UINT64_C(1000000000) + (uint64_t)value.tv_nsec;
}
static uint64_t bits(double value) {
	uint64_t result;
	memcpy(&result, &value, sizeof result);
	return result;
}
static int equal_value(Window *window, double value, double reference_value) {
	double error = value - reference_value;
	if (error < 0) error = -error;
	if (error > window->maximum_error) window->maximum_error = error;
#ifdef TELEMETRY_CONTRACT
	return window->failed ? bits(value) == bits(reference_value) : error <= 0x1p-36 * (1.0 + window->count);
#else
	return bits(value) == bits(reference_value);
#endif
}
double telemetry18_input(int index) {
	uint32_t value = (uint32_t)index ^ (uint32_t)seed * UINT32_C(0x9e3779b9);
	value ^= value >> 16;
	value *= UINT32_C(0x7feb352d);
	value ^= value >> 15;
	value *= UINT32_C(0x846ca68b);
	value ^= value >> 16;
	return ((int)(value & 65535) - 32768) / 32768.0;
}
static void reference(int sequence, int start, int count) {
	Window *window = &windows[sequence];
	window->count = count;
	window->failed = !count || sequence % 97 == 96;
	if (window->failed) return;
	double affine[64], z1 = 0, z2 = 0, energy = 0;
	double gain = (0.5 + (sequence % 7) * 0.03125) + 0.25;
	double stage = sequence % 2 ? 0.25 : 0.5;
	static const double taps[] = {0.125, 0.25, 0.25, 0.25, 0.125};
	for (int i = 0; i < count; i++)
		affine[i] = telemetry18_input(start + i) * gain + 0.0625;
	for (int i = 0; i < count; i++) {
		// Independent direct convolution, rather than the library's circular
		// history implementation. Preserve coefficient/reduction order.
		double filtered = 0;
		for (int tap = 0; tap < 5; tap++)
			filtered = filtered + taps[tap] * (tap <= i ? affine[i - tap] : 0.0);
		double result = 0.5 * filtered + z1;
		z1 = (0.25 * filtered - (-0.25) * result) + z2;
		z2 = 0.125 * filtered - 0.125 * result;
		double output = result * stage;
		expected[start + i] = output;
		energy = energy + output * output;
	}
	window->energy = energy;
}
void telemetry18_prepare(void) {
	if (windows) abort();
#ifdef TELEMETRY_IO
	io_issuer = pthread_self();
#endif
	samples = setting("ASTRA_TELEMETRY_SAMPLES", 48013, 1, 200000);
	window_size = setting("ASTRA_TELEMETRY_WINDOW", 31, 1, 64);
	seed = setting("ASTRA_TELEMETRY_SEED", 17, 0, 2147483647);
	window_count = (samples + window_size - 1) / window_size + 1;
	windows = calloc((size_t)window_count, sizeof *windows);
	expected = calloc((size_t)samples, sizeof *expected);
	actual = calloc((size_t)samples, sizeof *actual);
	seen = calloc((size_t)samples, sizeof *seen);
	if (!windows || !expected || !actual || !seen) abort();
	for (int index = 0; index < samples; index++)
		atomic_init(&seen[index], 0);
	for (int sequence = 0; sequence < window_count; sequence++) {
		atomic_init(&windows[sequence].entered, 0);
		atomic_init(&windows[sequence].reported, 0);
		int start = sequence * window_size;
		int count = start < samples ? samples - start : 0;
		if (count > window_size) count = window_size;
		reference(sequence, start, count);
	}
}
int telemetry18_samples(void) {
	return samples;
}
int telemetry18_window_size(void) {
	return window_size;
}
int telemetry18_workers(void) {
	return setting("ASTRA_TELEMETRY_WORKERS", 2, 1, 4);
}
int telemetry18_granularity(void) {
	return setting("ASTRA_TELEMETRY_GRANULARITY", 1, 1, 256);
}
int telemetry18_idle_ticks(void) {
	return setting("ASTRA_TELEMETRY_IDLE_TICKS", 0, 0, 1000);
}
#if defined(TELEMETRY_WORKERS) || defined(TELEMETRY_IO)
int telemetry18_context_observe(AstraContext17 *context, int identity, int64_t capacity, int slots) {
	AstraContext17Snapshot state;
	if (astra_context17_snapshot(context, &state) || state.live || state.live_bytes || state.reserved_bytes || state.allocations != state.releases ||
	    state.threading != ASTRA_CONTEXT17_CONCURRENT || state.borrowed || state.closed) return 1;
	printf("telemetry18 context=%d instance=%" PRIu64 " kind=%u backing_capacity=%" PRId64 " slots=%d peak_live_payload=%" PRIu64
	       " live=%" PRIu64 " live_reserved=%" PRIu64 " allocations=%" PRIu64 " releases=%" PRIu64 " anchors=%" PRIu64 "\n",
	       identity, state.instance, state.kind, capacity, slots, state.peak_bytes, state.live, state.reserved_bytes, state.allocations, state.releases, state.anchors);
	return 0;
}
#endif
#ifdef TELEMETRY_WORKERS
static pthread_mutex_t job_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t job_ready = PTHREAD_COND_INITIALIZER;
static pthread_t job_threads[4];
static int job_seen[4], jobs_entered, jobs_left, busy, maximum_busy;
void telemetry18_job_enter(int lane) {
	if (lane < 0 || lane >= 4 || pthread_mutex_lock(&job_lock)) abort();
	if (job_seen[lane]) abort();
	job_seen[lane] = 1;
	job_threads[lane] = pthread_self();
	jobs_entered++;
	busy++;
	if (busy > maximum_busy) maximum_busy = busy;
	if (pthread_cond_broadcast(&job_ready)) abort();
	if (setting("ASTRA_TELEMETRY_BARRIER", 0, 0, 1)) {
		struct timespec deadline;
		if (clock_gettime(CLOCK_REALTIME, &deadline)) abort();
		deadline.tv_sec += 5;
		while (jobs_entered < telemetry18_workers()) {
			if (pthread_cond_timedwait(&job_ready, &job_lock, &deadline)) abort();
		}
	}
	if (pthread_mutex_unlock(&job_lock)) abort();
}
void telemetry18_job_leave(int lane) {
	if (lane < 0 || lane >= 4 || pthread_mutex_lock(&job_lock) || job_seen[lane] != 1 || !pthread_equal(job_threads[lane], pthread_self())) abort();
	job_seen[lane] = 2;
	jobs_left++;
	busy--;
	if (pthread_mutex_unlock(&job_lock)) abort();
}
#endif
#ifdef TELEMETRY_IO
int telemetry18_create_input(const unsigned char *path, int length) {
	if (length < 1 || length > 4096 || memchr(path, 0, (size_t)length)) return 1;
	char *name = malloc((size_t)length + 1);
	if (!name) return 1;
	memcpy(name, path, (size_t)length);
	name[length] = 0;
	FILE *file = fopen(name, "wb");
	free(name);
	if (!file) return 1;
	int success = 1;
	for (int index = 0; index < samples; index++) {
		unsigned sample = (unsigned)(int)(telemetry18_input(index) * 32768.0) & 65535;
		unsigned char bytes[2] = {(unsigned char)sample, (unsigned char)(sample >> 8)};
		if (fwrite(bytes, 1, 2, file) != 2) {
			success = 0;
			break;
		}
	}
	if (fclose(file)) success = 0;
	return success ? 0 : 1;
}
void telemetry18_io_worker(int sequence) {
	if (sequence < 0 || sequence >= window_count || pthread_mutex_lock(&io_lock)) abort();
	pthread_t current = pthread_self();
	if (pthread_equal(io_issuer, current)) abort();
	int fresh = 1;
	for (int i = 0; i < io_distinct; i++) {
		if (pthread_equal(io_threads[i], current)) fresh = 0;
	}
	if (fresh) {
		if (io_distinct == 4) abort();
		io_threads[io_distinct++] = current;
	}
	io_jobs++;
	if (pthread_mutex_unlock(&io_lock)) abort();
}
#endif
void telemetry18_begin_window(int sequence) {
	if (active != -1 || sequence < 0 || sequence >= window_count || atomic_exchange(&windows[sequence].entered, 1)) abort();
	active = sequence;
	windows[sequence].started = now();
}
void telemetry18_end_window(int sequence) {
	if (active != sequence) abort();
	windows[sequence].elapsed = now() - windows[sequence].started;
	active = -1;
}
void telemetry18_retire(int sequence, int kind) {
	if (sequence < 0 || sequence >= window_count) abort();
	Window *window = &windows[sequence];
	int rank = window->retired++;
	if (rank < AUDITS)
		window->kinds[rank] = kind;
	else
		atomic_store(&bad, 1);
}
void telemetry18_shared_retire(int sequence, int kind) {
	if (sequence < 0 || sequence >= window_count || kind < 0 || kind > 1) abort();
	windows[sequence].shared_retired[kind]++;
}
int telemetry18_shared_result(int sequence, double value) {
	if (sequence < 0 || sequence >= window_count) return 1;
	double expected_value = (sequence % 17) + (sequence % 2 ? 3.5 : 3.0);
	if (windows[sequence].shared_result++ || bits(value) != bits(expected_value)) return 1;
	return 0;
}
int telemetry18_emit(int index, double value) {
	if (index < 0 || index >= samples) return 1;
	if (atomic_exchange(&seen[index], 1)) return 1;
	actual[index] = value;
	atomic_fetch_add(&emitted, 1);
	if (equal_value(&windows[index / window_size], value, expected[index])) return 0;
	fprintf(stderr, "sample=%d actual=%016" PRIx64 " expected=%016" PRIx64 "\n", index, bits(value), bits(expected[index]));
	return 1;
}
int telemetry18_summary(int sequence, int count, double energy, int failed) {
	if (sequence < 0 || sequence >= window_count) return 1;
	Window *window = &windows[sequence];
	if (!atomic_exchange(&window->reported, 1) && count == window->count && failed == window->failed && equal_value(window, energy, window->energy)) return 0;
	fprintf(stderr, "summary=%d count=%d/%d failed=%d/%d energy=%016" PRIx64 "/%016" PRIx64 "\n",
	        sequence, count, window->count, failed, window->failed, bits(energy), bits(window->energy));
	return 1;
}
int telemetry18_finish(void) {
	unsigned long allocations = 0;
	uint64_t elapsed = 0;
	int failures = 0, expected_emitted = 0, retired = 0;
	double maximum_error = 0;
	for (int sequence = 0; sequence < window_count; sequence++) {
		Window *window = &windows[sequence];
		if (!atomic_load(&window->reported) || !atomic_load(&window->entered) || !window->elapsed || window->retired != AUDITS ||
		    window->shared_retired[0] != 1 || window->shared_retired[1] != 1 || window->shared_result != 1) return 1;
		for (int rank = 0; rank < AUDITS; rank++) {
			if (window->kinds[rank] != AUDITS - rank) return 1;
		}
		allocations += window->allocations;
		elapsed += window->elapsed;
		retired += window->retired;
		failures += window->failed;
		if (!window->failed) expected_emitted += window->count;
	}
	if (atomic_load(&bad) || atomic_load(&emitted) != expected_emitted) return 2;
	for (int index = 0; index < samples; index++) {
		Window *window = &windows[index / window_size];
		if (atomic_load(&seen[index]) != !window->failed || !equal_value(window, actual[index], expected[index])) return 2;
	}
	for (int sequence = 0; sequence < window_count; sequence++) {
		if (windows[sequence].maximum_error > maximum_error) maximum_error = windows[sequence].maximum_error;
	}
	const char *destination = getenv("ASTRA_TELEMETRY_OUTPUT");
	if (destination) {
		FILE *file = fopen(destination, "wb");
		if (!file) return 3;
		int success = fwrite(actual, sizeof *actual, (size_t)samples, file) == (size_t)samples;
		if (fclose(file) || !success) return 4;
	}
#ifdef TELEMETRY_WORKERS
	if (jobs_entered != 4 || jobs_left != 4 || busy != 0) return 5;
	int distinct = 0;
	for (int lane = 0; lane < 4; lane++) {
		int fresh = 1;
		for (int before = 0; before < lane; before++) {
			if (pthread_equal(job_threads[lane], job_threads[before])) fresh = 0;
		}
		distinct += fresh;
	}
	printf("telemetry18 workers=%d granularity=%d distinct_threads=%d max_active_jobs=%d\n", telemetry18_workers(), telemetry18_granularity(), distinct, maximum_busy);
#endif
#ifdef TELEMETRY_IO
	if (io_jobs != window_count || !io_distinct) return 5;
	printf("telemetry18 io_jobs=%d worker_threads=%d issuer_separate=1\n", io_jobs, io_distinct);
#endif
	printf("telemetry18 samples=%d windows=%d emitted=%d failed=%d allocations=%lu retired=%d kernel_ns=%" PRIu64 " max_error=%a\n",
	       samples, window_count, expected_emitted, failures, allocations, retired, elapsed, maximum_error);
	free(seen);
	free(actual);
	free(expected);
	free(windows);
	windows = NULL;
	return 0;
}
