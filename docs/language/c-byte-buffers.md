# Counted bytes at a synchronous C import

On the qualified GNU Linux x86-64 LP64 host, an import may explicitly promise a
nonretaining synchronous byte-buffer operation:

```astra
[CCode(buffer_abi="u8-i32")]
extern(C) int transfer(int fd, borrowed u8[] bytes, int offset, int count);
```

The matching C signature is:

```c
int32_t transfer(int32_t fd, unsigned char *data, int32_t byte_length,
                 int32_t offset, int32_t count);
```

Pass a fixed array with `slice(array)` or `slice(array,start,count)`. Pass an
owned byte array directly for a temporary borrow, or forward a native borrowed
byte parameter. The array owner stays live through the complete call. A later
argument cannot move or replace that owner. A completed call permits subsequent
owner movement normally. Mutable views may overlap and do not grant exclusivity.

The C implementation must stay within `byte_length`, finish all access before
returning and retain no pointer, alias or asynchronous operation. This is a
trusted foreign obligation, like the existing counted text contract. For length
zero, the pointer may be null. No NUL terminator, UTF-8 validity or decoding is
implied; `0x00`, `0x80` and `0xff` are ordinary payload octets.
The C implementation must not free or resize the backing storage or consume its
Astra owner; the call transfers no ownership.

Only annotated imported `borrowed u8[]` is supported. Other C slice parameters,
borrowed C array results, C array ownership transfer, exports and VAPI buffer
syntax remain rejected. Count and index types remain `int`/I32.
Buffer-annotated imports return only supported copied scalars or void; raw
pointer and nominal-handle results, including owned handles, are rejected.

`FileHandle.read_bytes(bytes,offset,count)` and `write_bytes(...)` return actual
progress and throw `FileError` with operation 2 or 3 and negative errno. Reads
return zero at EOF. A requested zero-length operation returns zero without a
syscall; it validates the range first. A nonempty write returning zero becomes
`-EIO`; EAGAIN is an ordinary checked error. EINTR is retried. Every call performs
at most 64 KiB of transfer; callers loop over short positive progress.

`read_file`, `write_file`, `FileBytes.write` and `write_text_file` now use those
bulk operations, with Astra still responsible for loops, storage and error
cleanup. `FileHandle.next_byte` and `put_byte` preserve their scalar behavior.
`flush` checks `fsync`; `close` invalidates the descriptor before checking the
result and never retries Linux close after EINTR. Output is truncated on open;
an error can leave partial output. Full-file storage retains the I32 size limit
and existing fatal allocation-failure policy.
