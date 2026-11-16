/* SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception */
/* Private synchronous counted-view transport. No parsing, compiler phases,
 * subprocesses, network, shared state, or new public runtime ABI. */
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <stdio.h>

static uint32_t rotate(uint32_t value, unsigned shift) {
	return (value >> shift) | (value << (32 - shift));
}

static void sha_block(uint32_t state[8], const unsigned char block[64]) {
	static const uint32_t constants[64] = {
	    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};
	uint32_t words[64];
	for (int i = 0; i < 16; i++)
		words[i] = ((uint32_t)block[i * 4] << 24) | ((uint32_t)block[i * 4 + 1] << 16) | ((uint32_t)block[i * 4 + 2] << 8) | block[i * 4 + 3];
	for (int i = 16; i < 64; i++) {
		uint32_t x = words[i - 15], y = words[i - 2];
		words[i] = words[i - 16] + (rotate(x,7) ^ rotate(x,18) ^ (x >> 3)) + words[i - 7] + (rotate(y,17) ^ rotate(y,19) ^ (y >> 10));
	}
	uint32_t a = state[0], b = state[1], c = state[2], d = state[3], e = state[4], f = state[5], g = state[6], h = state[7];
	for (int i = 0; i < 64; i++) {
		uint32_t first = h + (rotate(e,6) ^ rotate(e,11) ^ rotate(e,25)) + ((e & f) ^ (~e & g)) + constants[i] + words[i];
		uint32_t second = (rotate(a,2) ^ rotate(a,13) ^ rotate(a,22)) + ((a & b) ^ (a & c) ^ (b & c));
		h = g;
		g = f;
		f = e;
		e = d + first;
		d = c;
		c = b;
		b = a;
		a = first + second;
	}
	state[0] += a;
	state[1] += b;
	state[2] += c;
	state[3] += d;
	state[4] += e;
	state[5] += f;
	state[6] += g;
	state[7] += h;
}

int32_t astrac_doc_sha256(const unsigned char *input, int32_t length, unsigned char *output, int32_t capacity) {
	if (length < 0 || (length && !input) || !output || capacity != 32) return -EINVAL;
	uint32_t state[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
	size_t at = 0, size = (size_t)length;
	while (size - at >= 64) {
		sha_block(state,input+at);
		at += 64;
	}
	unsigned char tail[128] = {0};
	size_t remaining = size - at;
	if (remaining) memcpy(tail,input+at,remaining);
	tail[remaining] = 128;
	size_t blocks = remaining < 56 ? 64 : 128;
	uint64_t bits = (uint64_t)size * 8;
	for (int i = 0; i < 8; i++)
		tail[blocks - 1 - (size_t)i] = (unsigned char)(bits >> (i * 8));
	sha_block(state,tail);
	if (blocks == 128) sha_block(state,tail+64);
	for (int i = 0; i < 32; i++)
		output[i] = (unsigned char)(state[i / 4] >> (24 - (i % 4) * 8));
	return 0;
}

/* Resolve each directory via descriptor with O_NOFOLLOW. A destination is
 * either new or a regular generated document. Atomic replacement never
 * follows a destination symlink or truncates an input hardlink. */
int32_t astrac_doc_publish(const unsigned char *path, int32_t length, const unsigned char *text, int32_t bytes) {
	if (!path || length <= 0 || length > 4096 || !text || bytes < 1 || bytes > 67108864) return -EINVAL;
	char name[4097];
	for (int32_t i = 0; i < length; i++) {
		if (path[i] < 32 || path[i] == '\\') return -EINVAL;
		name[i] = (char)path[i];
	}
	name[length] = 0;
	int directory = open(name[0]=='/' ? "/" : ".",O_RDONLY|O_DIRECTORY|O_CLOEXEC);
	if (directory < 0) return -errno;
	char *part = name + (name[0] == '/');
	char *slash;
	while ((slash = strchr(part,'/')) != NULL) {
		*slash = 0;
		if (!*part || strcmp(part,"..") == 0) {
			close(directory);
			return -EINVAL;
		}
		int next = openat(directory,part,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
		close(directory);
		if (next < 0) return -errno;
		directory = next;
		part = slash + 1;
	}
	if (!*part || strcmp(part,".") == 0 || strcmp(part,"..") == 0) {
		close(directory);
		return -EINVAL;
	}
	int existing = openat(directory,part,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);
	if (existing >= 0) {
		char prefix[80] = {0};
		struct stat info;
		int regular = fstat(existing,&info) == 0 && S_ISREG(info.st_mode);
		ssize_t count = regular ? read(existing,prefix,sizeof(prefix)-1) : -1;
		int valid = count > 0 && (strncmp(prefix,"{\"format\":\"astra-api-docs/1\",",29) == 0 || strncmp(prefix,"<!doctype html>\n<!-- astra-api-docs/1 -->\n",42) == 0);
		close(existing);
		if (!valid) {
			close(directory);
			return -EEXIST;
		}
	} else if (errno != ENOENT) {
		int error = errno;
		close(directory);
		return -error;
	}
	char temporary[64];
	int written = snprintf(temporary,sizeof(temporary),".astra-doc-%ld.tmp",(long)getpid());
	if (written <= 0 || (size_t)written >= sizeof(temporary)) {
		close(directory);
		return -EINVAL;
	}
	int fd = openat(directory,temporary,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0644);
	if (fd < 0) {
		int error = errno;
		close(directory);
		return -error;
	}
	int error = 0;
	int32_t at = 0;
	while (at < bytes) {
		ssize_t count = write(fd,text+at,(size_t)(bytes-at));
		if (count < 0 && errno == EINTR) continue;
		if (count <= 0) {
			error = count == 0 ? EIO : errno;
			break;
		}
		at += (int32_t)count;
	}
	if (!error && fsync(fd) < 0) error = errno;
	if (close(fd) < 0 && !error) error = errno;
	if (!error && renameat(directory,temporary,directory,part) < 0) error = errno;
	if (error) unlinkat(directory,temporary,0);
	close(directory);
	return -error;
}
