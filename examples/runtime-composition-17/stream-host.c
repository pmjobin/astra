/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "signal stop requires a lock-free atomic");
static _Atomic int stopped;
static struct sigaction previous_int, previous_term;
static struct timespec began;
static int verbose;
static _Atomic unsigned events;

static void request_stop(int signal) {
	(void)signal;
	atomic_store_explicit(&stopped, 1, memory_order_relaxed);
}

int stream_requested_port(void) {
	const char *value = getenv("ASTRA_STREAM_PORT");
	if (!value) {
		return 0;
	}
	errno = 0;
	char *end = NULL;
	long port = strtol(value, &end, 10);
	return errno || end == value || *end || port < 0 || port > 65535 ? -1 : (int)port;
}

/* Configuration is supplied by the launching client; libraries receive the
 * resulting typed contexts and queues rather than consulting these options. */
static int option(const char *name, int fallback, int minimum, int maximum) {
	const char *value = getenv(name);
	if (!value) {
		return fallback;
	}
	errno = 0;
	char *end = NULL;
	long parsed = strtol(value, &end, 10);
	return errno || end == value || *end || parsed < minimum || parsed > maximum ? -1 : (int)parsed;
}

int stream_queue_capacity(void) {
	return option("ASTRA_STREAM_CAPACITY", 2, 1, 8);
}

int stream_worker_count(void) {
	return option("ASTRA_STREAM_WORKERS", 2, 2, 8);
}

int stream_context_bytes(void) {
	return option("ASTRA_STREAM_CONTEXT_BYTES", 262147, 131071, 1048576);
}

int stream_frame_bytes(void) {
	return option("ASTRA_STREAM_FRAME_BYTES", 524309, 524309, 2097152);
}

int stream_chunk_limit(void) {
	return option("ASTRA_STREAM_CHUNK_LIMIT", 4093, 31, 4093);
}

int stream_alignment(void) {
	int value = option("ASTRA_STREAM_ALIGNMENT", 128, 64, 256);
	return value > 0 && (value & (value - 1)) == 0 ? value : -1;
}

void stream_prepare(void) {
	struct sigaction action = {.sa_handler = request_stop};
	if (sigemptyset(&action.sa_mask) || sigaction(SIGINT, &action, &previous_int) ||
	    sigaction(SIGTERM, &action, &previous_term) || clock_gettime(CLOCK_MONOTONIC, &began)) {
		abort();
	}
	verbose = getenv("ASTRA_STREAM_EVENTS") != NULL;
}

int stream_stop_requested(void) {
	return atomic_load_explicit(&stopped, memory_order_relaxed) != 0;
}

void stream_ready(int tcp, int udp) {
	printf("{\"tcp\":%d,\"udp\":%d,\"pid\":%ld}\n", tcp, udp, (long)getpid());
	if (fflush(stdout)) {
		abort();
	}
}

void stream_event(int kind, int sequence, int value) {
	atomic_fetch_add_explicit(&events, 1, memory_order_relaxed);
	if (verbose) {
		printf("{\"event\":%d,\"sequence\":%d,\"value\":%d}\n", kind, sequence, value);
		if (fflush(stdout)) {
			abort();
		}
	}
}

void stream_error(const unsigned char *message, int length) {
	if (!message || length < 0) {
		abort();
	}
	if (length > 1024) {
		length = 1024;
	}
	fputs("stream: ", stderr);
	fwrite(message, 1, (size_t)length, stderr);
	fputc('\n', stderr);
}

int stream_finish(int result) {
	struct timespec ended;
	if (clock_gettime(CLOCK_MONOTONIC, &ended) || sigaction(SIGINT, &previous_int, NULL) ||
	    sigaction(SIGTERM, &previous_term, NULL)) {
		abort();
	}
	long long milliseconds = (long long)(ended.tv_sec - began.tv_sec) * 1000 + (ended.tv_nsec - began.tv_nsec) / 1000000;
	printf("{\"result\":%d,\"milliseconds\":%lld,\"events\":%u}\n", result, milliseconds, atomic_load_explicit(&events, memory_order_relaxed));
	return result;
}
