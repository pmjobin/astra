# M17 separate-peer qualification plan

Status: approved in the native M17 session. The approved topology probe and
generated Astra IPv4/IPv6 TCP+UDP client exchanges passed; see
`m17-peer-topology-1.json` and `m17-peer-endpoints-O2-1.json` in the task receipts.
These are isolated namespace results, not physical-host or Internet evidence.
The current bounded-byte-view compiler refresh passes in
`m17-peer-endpoints-O2-2.json`. The integrated streaming A execution passes
both families/protocols in `m17-stream-private-peer-1.json`, including native
CPU/network/CQE overlap and exact cleanup. Final source-bound application/SDK/
failure refreshes remain required.

The read-only native inventory found installed `unshare`, `nsenter` and `ip`,
user namespace capacity enabled, IPv6 enabled, and no named network namespaces.
Other unnamed namespaces and the existing VM interfaces are outside this plan.
The ordinary Codex sandbox denies netlink and io_uring setup; native execution
as the existing unprivileged user permits the read-only inventory and the exact
existing io_uring profile. This does not establish that namespace creation works.

## Requested actions

Create a fresh user namespace with `unshare --user --map-root-user --net` as
the existing user. Inside it create a second network namespace in a child
process, then one task-owned veth pair connecting only those two private network
namespaces. Configure only the pair and the private loopback interfaces. Use
PID namespace handles with `nsenter --net=/proc/<task-child-pid>/ns/net`;
do not create persistent named namespaces or mount namespace handles.

| Property | Exact scope |
| --- | --- |
| Astra side | Private namespace A, `m17a`, `192.0.2.1/30`, `fd17:6173:7472::1/64` |
| Independent peer | Private namespace B, `m17b`, `192.0.2.2/30`, `fd17:6173:7472::2/64` |
| Transport | TCP and UDP over the private veth only; test IPv4 and IPv6 separately |
| Ports | Explicit test ports and kernel-selected ephemeral ports within 1024–65535, recorded per execution |
| Processes | Task-owned Astra binaries and independent Python/C socket oracles, all under the current user |
| Data | Deterministic generated binary/numeric records, checksums and protocol errors; no user data or secrets |
| Bounds | At most 10 minutes and 64 MiB transferred per invocation; per-operation deadlines; bounded concurrent clients |
| Files | Products under `~/Workspace/codex/work/astra/build/runtime-composition-17/`; receipts/data under the matching `runtime/native-current/` |
| Cleanup | Join/terminate only task-owned children, close sockets, remove the private veth if still present, exit both temporary namespaces |

The two namespaces provide separate non-loopback network stacks. Record their
namespace IDs, interfaces, local/peer addresses, source/compiler/runtime hashes,
exact payload/count/error observations and clean joined shutdown. An independent
peer uses its own platform socket implementation. Label this isolated namespace
evidence; do not claim a separate physical host or public-network qualification.

This plan creates no host route, firewall rule, public listener or host interface.
It does not contact the LAN/Internet, access an existing container/VM, alter
sysctls/security/accounts, install software, or request host-root privileges.
Namespace capabilities are confined to the fresh user namespace. If the kernel
or policy refuses the operation, retain the exact failure, continue safe work,
and request a different specific peer plan before changing topology or privilege.

Approval covers bounded repeat invocations with these endpoints, including the
final source-bound application/SDK/failure matrix. Changing the topology, using
an existing guest or making an external connection needs a separate decision.
