// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <limits.h>
#include <poll.h>
#include <stddef.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
#include "network-posix.h"

/* Explicit Linux numeric endpoints, with legacy IPv4 loopback wrappers.
 * No syscall retains a supplied byte
 * pointer after returning; waiting uses poll(..., 0), never a blocking recv. */
static int32_t failure(void) {
	return errno == EWOULDBLOCK ? -EAGAIN : -errno;
}
static int endpoint(struct sockaddr_in *address, int32_t port, int allow_zero) {
	if (port < (allow_zero ? 0 : 1) || port > 65535) return -EINVAL;
	memset(address, 0, sizeof(*address));
	address->sin_family = AF_INET;
	address->sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	address->sin_port = htons((uint16_t)port);
	return 0;
}
static int buffer(uint8_t *bytes, int32_t length, int32_t offset, int32_t count) {
	return length >= 0 && offset >= 0 && count >= 0 && offset <= length &&
	       count <= length - offset && (count == 0 || bytes != NULL);
}
static int32_t progress(ssize_t result) {
	return result < 0 ? failure() : (int32_t)result;
}

int32_t astra_net_socket(int32_t datagram) {
	if (datagram != 0 && datagram != 1) return -EINVAL;
	return progress(socket(AF_INET, (datagram ? SOCK_DGRAM : SOCK_STREAM) | SOCK_NONBLOCK | SOCK_CLOEXEC, 0));
}
int32_t astra_net_bind(int32_t fd, int32_t port) {
	struct sockaddr_in address;
	int result = endpoint(&address, port, 1);
	if (result < 0) return result;
	return progress(bind(fd, (struct sockaddr *)&address, sizeof(address)));
}
int32_t astra_net_port(int32_t fd) {
	struct sockaddr_in address;
	socklen_t length = sizeof(address);
	if (getsockname(fd, (struct sockaddr *)&address, &length) < 0) return failure();
	if (length != sizeof(address) || address.sin_family != AF_INET) return -EAFNOSUPPORT;
	return ntohs(address.sin_port);
}
int32_t astra_net_listen(int32_t fd, int32_t backlog) {
	if (backlog < 1 || backlog > 128) return -EINVAL;
	return progress(listen(fd, backlog));
}
int32_t astra_net_connect(int32_t fd, int32_t port) {
	struct sockaddr_in address;
	int result = endpoint(&address, port, 0);
	if (result < 0) return result;
	if (connect(fd, (struct sockaddr *)&address, sizeof(address)) == 0 || errno == EISCONN) return 0;
	if (errno == EINPROGRESS || errno == EALREADY) return -EAGAIN;
	return failure();
}
int32_t astra_net_ready(int32_t fd, int32_t write_ready) {
	struct pollfd event = {.fd = fd, .events = write_ready ? POLLOUT : POLLIN};
	int result = poll(&event, 1, 0);
	if (result < 0) return failure();
	if (event.revents & POLLNVAL) return -EBADF;
	return result ? 1 : 0; /* HUP/ERR are readiness: the next operation gives EOF/error. */
}
int32_t astra_net_connected(int32_t fd) {
	int error = 0;
	socklen_t length = sizeof(error);
	if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) < 0) return failure();
	return error == 0 ? 0 : -error;
}
int32_t astra_net_accept(int32_t fd) {
	return progress(accept4(fd, NULL, NULL, SOCK_NONBLOCK | SOCK_CLOEXEC));
}
int32_t astra_net_read(int32_t fd, uint8_t *bytes, int32_t length, int32_t offset, int32_t count) {
	if (!buffer(bytes, length, offset, count)) return -EINVAL;
	return progress(recv(fd, count ? bytes + offset : NULL, (size_t)count, MSG_DONTWAIT));
}
int32_t astra_net_write(int32_t fd, uint8_t *bytes, int32_t length, int32_t offset, int32_t count) {
	if (!buffer(bytes, length, offset, count)) return -EINVAL;
	return progress(send(fd, count ? bytes + offset : NULL, (size_t)count, MSG_DONTWAIT | MSG_NOSIGNAL));
}
int32_t astra_net_udp_send(int32_t fd, int32_t port, uint8_t *bytes, int32_t length, int32_t offset, int32_t count) {
	struct sockaddr_in address;
	int result = endpoint(&address, port, 0);
	if (result < 0) return result;
	if (!buffer(bytes, length, offset, count) || count > 65507) return -EMSGSIZE;
	return progress(sendto(fd, count ? bytes + offset : NULL, (size_t)count,
	                       MSG_DONTWAIT | MSG_NOSIGNAL, (struct sockaddr *)&address, sizeof(address)));
}
/* One datagram is consumed. An oversized packet returns -EMSGSIZE and never
 * presents its truncated bytes as a complete message. An empty packet is 0. */
int64_t astra_net_udp_receive(int32_t fd, uint8_t *bytes, int32_t length, int32_t offset, int32_t count) {
	if (!buffer(bytes, length, offset, count)) return -EINVAL;
	struct iovec vector = {.iov_base = count ? bytes + offset : NULL, .iov_len = (size_t)count};
	struct sockaddr_in peer;
	struct msghdr message = {.msg_name = &peer, .msg_namelen = sizeof(peer), .msg_iov = &vector, .msg_iovlen = 1};
	ssize_t result = recvmsg(fd, &message, MSG_DONTWAIT | MSG_TRUNC);
	if (result < 0) return failure();
	if (result > count || (message.msg_flags & MSG_TRUNC)) return -EMSGSIZE;
	if (message.msg_namelen != sizeof(peer) || peer.sin_family != AF_INET || ntohl(peer.sin_addr.s_addr) != INADDR_LOOPBACK) return -EAFNOSUPPORT;
	return ((int64_t)result << 16) | ntohs(peer.sin_port);
}
int32_t astra_net_send_buffer(int32_t fd, int32_t capacity) {
	if (capacity < 512 || capacity > 65536) return -EINVAL;
	int value = capacity;
	return progress(setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &value, sizeof(value)));
}
int32_t astra_net_shutdown_write(int32_t fd) {
	return progress(shutdown(fd, SHUT_WR));
}
int32_t astra_net_close(int32_t fd) {
	return progress(close(fd));
}
int32_t astra_net_milliseconds(void) {
	struct timespec now;
	if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return failure();
	/* Bounded nonnegative modulo clock; source computes elapsed across wrap. */
	uint64_t value = (uint64_t)now.tv_sec * 1000 + (uint64_t)now.tv_nsec / 1000000;
	return (int32_t)(value % UINT64_C(1000000000));
}

_Static_assert(sizeof(AstraNetEndpoint) == 28, "numeric endpoint/1 extent");
_Static_assert(offsetof(AstraNetEndpoint, address) == 4, "endpoint address offset");
_Static_assert(offsetof(AstraNetEndpoint, port) == 20, "endpoint port offset");
_Static_assert(offsetof(AstraNetEndpoint, scope) == 24, "endpoint scope offset");

static int native_family(int32_t family) {
	return family == 4 ? AF_INET : family == 6 ? AF_INET6
	                                           : -1;
}
static int valid_endpoint(const AstraNetEndpoint *value, int allow_zero) {
	if (!value || native_family(value->family) < 0) return -EAFNOSUPPORT;
	if (value->port < (allow_zero ? 0 : 1) || value->port > 65535) return -EINVAL;
	if (value->family == 4) {
		if (value->scope != 0) return -EINVAL;
		for (size_t i = 4; i < sizeof(value->address); ++i)
			if (value->address[i] != 0) return -EINVAL;
	}
	return 0;
}
static int socket_address(const AstraNetEndpoint *value, int allow_zero,
                          struct sockaddr_storage *storage, socklen_t *length) {
	int status = valid_endpoint(value, allow_zero);
	if (status < 0) return status;
	memset(storage, 0, sizeof(*storage));
	if (value->family == 4) {
		struct sockaddr_in *address = (struct sockaddr_in *)storage;
		address->sin_family = AF_INET;
		memcpy(&address->sin_addr, value->address, 4);
		address->sin_port = htons((uint16_t)value->port);
		*length = sizeof(*address);
	} else {
		struct sockaddr_in6 *address = (struct sockaddr_in6 *)storage;
		address->sin6_family = AF_INET6;
		memcpy(&address->sin6_addr, value->address, 16);
		address->sin6_port = htons((uint16_t)value->port);
		address->sin6_scope_id = value->scope;
		*length = sizeof(*address);
	}
	return 0;
}
static int source_address(const struct sockaddr_storage *storage,
                          socklen_t length, AstraNetEndpoint *output) {
	AstraNetEndpoint result = {0};
	if (!output) return -EINVAL;
	if (storage->ss_family == AF_INET && length == sizeof(struct sockaddr_in)) {
		const struct sockaddr_in *address = (const struct sockaddr_in *)storage;
		result.family = 4;
		memcpy(result.address, &address->sin_addr, 4);
		result.port = ntohs(address->sin_port);
	} else if (storage->ss_family == AF_INET6 && length == sizeof(struct sockaddr_in6)) {
		const struct sockaddr_in6 *address = (const struct sockaddr_in6 *)storage;
		result.family = 6;
		memcpy(result.address, &address->sin6_addr, 16);
		result.port = ntohs(address->sin6_port);
		result.scope = address->sin6_scope_id;
	} else
		return -EAFNOSUPPORT;
	*output = result;
	return 0;
}

int32_t astra_net_endpoint_parse(const uint8_t *text, int32_t length,
                                 int32_t family, int32_t port, int32_t scope, AstraNetEndpoint *output) {
	if (!text || !output || length <= 0 || length >= INET6_ADDRSTRLEN || scope < 0) return -EINVAL;
	if (native_family(family) < 0) return -EAFNOSUPPORT;
	if (memchr(text, 0, (size_t)length) != NULL) return -EINVAL;
	char numeric[INET6_ADDRSTRLEN];
	memcpy(numeric, text, (size_t)length);
	numeric[length] = 0;
	AstraNetEndpoint result = {.family = family, .port = port, .scope = (uint32_t)scope};
	if (valid_endpoint(&result, 1) < 0 || inet_pton(native_family(family), numeric, result.address) != 1) return -EINVAL;
	*output = result;
	return 0;
}

int32_t astra_net_endpoint_format(const AstraNetEndpoint *value, uint8_t *output, int32_t capacity) {
	int status = valid_endpoint(value, 1);
	if (status < 0) return status;
	if (!output || capacity < 0) return -EINVAL;
	char numeric[INET6_ADDRSTRLEN], formatted[INET6_ADDRSTRLEN + 32];
	if (!inet_ntop(native_family(value->family), value->address, numeric, sizeof(numeric))) return failure();
	int length;
	if (value->family == 4)
		length = snprintf(formatted, sizeof(formatted), "%s:%d", numeric, value->port);
	else if (value->scope)
		length = snprintf(formatted, sizeof(formatted), "[%s%%%u]:%d", numeric, value->scope, value->port);
	else
		length = snprintf(formatted, sizeof(formatted), "[%s]:%d", numeric, value->port);
	if (length < 0 || (size_t)length >= sizeof(formatted)) return -EOVERFLOW;
	if (length > capacity) return -ENOSPC;
	memcpy(output, formatted, (size_t)length);
	return length;
}

int32_t astra_net_socket_family(int32_t family, int32_t datagram) {
	if (native_family(family) < 0) return -EAFNOSUPPORT;
	if (datagram != 0 && datagram != 1) return -EINVAL;
	int fd = socket(native_family(family), (datagram ? SOCK_DGRAM : SOCK_STREAM) | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
	if (fd < 0) return failure();
	if (family == 6) {
		/* Explicit families: IPv4-mapped connections are not an implicit default. */
		int only_v6 = 1;
		if (setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &only_v6, sizeof(only_v6)) < 0) {
			int error = failure();
			close(fd);
			return error;
		}
	}
	return fd;
}

int32_t astra_net_bind_at(int32_t fd, const AstraNetEndpoint *value) {
	struct sockaddr_storage address;
	socklen_t length;
	int status = socket_address(value, 1, &address, &length);
	if (status < 0) return status;
	return progress(bind(fd, (struct sockaddr *)&address, length));
}

int32_t astra_net_connect_to(int32_t fd, const AstraNetEndpoint *value) {
	struct sockaddr_storage address;
	socklen_t length;
	int status = socket_address(value, 0, &address, &length);
	if (status < 0) return status;
	if (connect(fd, (struct sockaddr *)&address, length) == 0 || errno == EISCONN) return 0;
	if (errno == EINPROGRESS || errno == EALREADY) return -EAGAIN;
	return failure();
}

int32_t astra_net_address(int32_t fd, int32_t peer, AstraNetEndpoint *output) {
	if (!output || (peer != 0 && peer != 1)) return -EINVAL;
	struct sockaddr_storage address = {0};
	socklen_t length = sizeof(address);
	int status = peer ? getpeername(fd, (struct sockaddr *)&address, &length) : getsockname(fd, (struct sockaddr *)&address, &length);
	return status < 0 ? failure() : source_address(&address, length, output);
}

int32_t astra_net_accept_from(int32_t fd, AstraNetEndpoint *output) {
	if (!output) return -EINVAL;
	struct sockaddr_storage address = {0};
	socklen_t length = sizeof(address);
	int accepted = accept4(fd, (struct sockaddr *)&address, &length, SOCK_NONBLOCK | SOCK_CLOEXEC);
	if (accepted < 0) return failure();
	int status = source_address(&address, length, output);
	if (status < 0) {
		close(accepted);
		return status;
	}
	return accepted;
}

int32_t astra_net_send_to(int32_t fd, const AstraNetEndpoint *value,
                          uint8_t *bytes, int32_t length, int32_t offset, int32_t count) {
	struct sockaddr_storage address;
	socklen_t address_length;
	int status = socket_address(value, 0, &address, &address_length);
	if (status < 0) return status;
	if (!buffer(bytes, length, offset, count)) return -EINVAL;
	if (count > (value->family == 4 ? 65507 : 65527)) return -EMSGSIZE;
	return progress(sendto(fd, count ? bytes + offset : NULL, (size_t)count,
	                       MSG_DONTWAIT | MSG_NOSIGNAL, (struct sockaddr *)&address, address_length));
}

int32_t astra_net_receive_from(int32_t fd, uint8_t *bytes, int32_t length,
                               int32_t offset, int32_t count, AstraNetPacket *output) {
	if (!output || !buffer(bytes, length, offset, count)) return -EINVAL;
	struct iovec vector = {.iov_base = count ? bytes + offset : NULL, .iov_len = (size_t)count};
	struct sockaddr_storage peer = {0};
	struct msghdr message = {.msg_name = &peer, .msg_namelen = sizeof(peer), .msg_iov = &vector, .msg_iovlen = 1};
	ssize_t result = recvmsg(fd, &message, MSG_DONTWAIT | MSG_TRUNC);
	if (result < 0) return failure();
	int status = source_address(&peer, message.msg_namelen, &output->peer);
	if (status < 0) return status;
	if (result > INT32_MAX) return -EOVERFLOW;
	output->message_length = (int32_t)result;
	/* Full datagram length and actual initialized bytes are separate results. */
	return result > count ? count : (int32_t)result;
}
