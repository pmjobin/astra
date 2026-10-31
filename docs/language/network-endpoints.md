# Numeric IPv4 and IPv6 endpoints

Select `hosted/network.astra` with `base/errors.astra`, the explicit
`network-posix.o` provider and ordinary text support. The current hosted provider
uses Linux nonblocking sockets. The endpoint value carries the address, family,
port and IPv6 scope together. Parsing an endpoint does not open a socket.

```astra
NetworkEndpoint remote = network_endpoint("192.0.2.2", 4, 17431, 0);
NetworkEndpoint remote6 = network_endpoint("fd17:6173:7472::2", 6, 41743, 0);
var output = new u8[96];
int count = network_format(remote6, output);
```

Catch or declare `SocketError`. Family is 4 or 6, port is 0–65535, and scope is
an explicit nonnegative IPv6 interface index. Address text is numeric; hostname
resolution is separate work. Address words contain opaque network-order bytes.
Use the parser and `network_endpoint_equal` instead of host-order arithmetic.
Formatting writes exactly the returned byte count without a trailing NUL;
insufficient output capacity throws. IPv6 output brackets the address and includes
its scope when nonzero.

| Operation | Behavior |
| --- | --- |
| `TcpSocket.open_family(family)` | Opens one nonblocking socket of the chosen family. |
| `listen_at(endpoint, backlog)` | Binds that address and port, then listens. Port 0 requests a kernel-selected port. |
| `connect_to(endpoint)` | Initiates a connection; `NetAgain` or `NetInterrupted` requires readiness observation and `connected()`. |
| `local_address()` / `peer_address()` | Returns actual kernel address metadata. |
| `accept_from(target, &peer)` | Transfers an accepted descriptor into an unopened target and returns its actual peer; false means retry. |
| `try_read` / `try_write` | Returns actual byte progress; zero read means EOF. Retain offsets across short progress. |
| `UdpSocket.open_at(endpoint)` | Opens and binds a datagram socket of the endpoint's family. |
| `send_to(endpoint, bytes, offset, count)` | Sends one datagram, including a valid zero-length datagram. |
| `receive_from(bytes, offset, count)` | Returns actual peer, initialized byte count, full message length and truncation flag. |

`NetAgain` and `NetInterrupted` are retry results for the try operations.
`receive_from` instead reports retry conditions through `SocketError.code`; callers
must distinguish them from other errors. A datagram consumes one message even
when its output is truncated. An empty datagram is distinct from TCP EOF.
The legacy loopback helpers retain their existing behavior.

Each socket Class owns one descriptor. Explicit `close()` disarms it before
closing; automatic destruction closes any remaining descriptor. Calls borrow
buffers only for the actual nonblocking syscall and retain neither pointer nor
slice afterward. A caller that suspends must keep its own socket and complete
buffer owner alive. Eligible context-selected byte owners can supply temporary
synchronous views while retaining their original allocator and release authority.

`network_deadline(start, timeout)` checks elapsed milliseconds, with timeout
0–60000. Existing cooperative async loops combine nonblocking attempts, readiness
checks and ordinary timer suspension. Socket operations are not io_uring socket
requests. Streaming A separately overlaps these sockets with actual io_uring file
requests and worker computation; see its
[protocol and build guide](../../examples/runtime-composition-17/README.md).

The public [client witness](../../tests/runtime-composition-17/endpoint-client.astra)
handles partial TCP progress, EOF, deadlines, empty UDP and full peer metadata.
The endpoint, server and error recipes cover both families, rejected addresses,
output bounds and datagram truncation. The specifically authorized separate-peer
recipe used isolated namespaces and a private veth. Its completed M17 scope is
recorded in the final qualification.
Fresh M18 private-peer execution requires new scoped host permission.
