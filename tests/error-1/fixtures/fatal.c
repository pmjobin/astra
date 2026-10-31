#include <stddef.h>
#include <unistd.h>
void *calloc(size_t count, size_t width) {
	(void)count;
	(void)width;
	(void)write(1, "OOM\n", 4);
	return NULL;
}
