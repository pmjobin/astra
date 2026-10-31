/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <dirent.h>
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>

static void inventory(const char *phase) {
	DIR *directory = opendir("/proc/self/task");
	assert(directory);
	struct dirent *entry;
	int count = 0;
	printf("{\"phase\":\"%s\",\"threads\":[", phase);
	while ((entry = readdir(directory))) {
		if (entry->d_name[0] == '.') continue;
		char path[512], name[64];
		int length = snprintf(path, sizeof(path), "/proc/self/task/%s/comm", entry->d_name);
		assert(length > 0 && (size_t)length < sizeof(path));
		FILE *file = fopen(path, "r");
		if (!file && (errno == ENOENT || errno == ESRCH)) continue;
		assert(file);
		char *read = fgets(name, sizeof(name), file);
		int read_error = errno;
		assert(fclose(file) == 0);
		if (!read && (read_error == ENOENT || read_error == ESRCH)) continue;
		assert(read);
		for (size_t i = 0; i < strlen(name); ++i)
			if (name[i] == '\n')
				name[i] = 0;
			else if (name[i] == '"' || name[i] == '\\')
				name[i] = '_';
		printf("%s{\"tid\":%s,\"name\":\"%s\"}", count++ ? "," : "", entry->d_name, name);
	}
	assert(closedir(directory) == 0);
	printf("],\"count\":%d}\n", count);
	assert(fflush(stdout) == 0);
}
static void *empty(void *argument) {
	return argument;
}
static void batch(void) {
	pthread_t threads[2];
	for (int i = 0; i < 2; ++i)
		assert(pthread_create(&threads[i], NULL, empty, NULL) == 0);
	for (int i = 0; i < 2; ++i)
		assert(pthread_join(threads[i], NULL) == 0);
}
int main(void) {
	inventory("before");
	batch();
	inventory("after-first-joined-batch");
	batch();
	inventory("after-second-joined-batch");
	return 0;
}
