// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Text {
// Stage-neutral immutable leaf. No source, name, type or program backlink.
// The explicit declared count also lets independent verifiers reject forged
// lower-stage payloads without allocating source-sized storage.
public class TextBytes : Object {
	private uint8[] bytes;
	public int64 byte_length { get; private set; }
	public TextBytes (uint8[] bytes, int64 declared_length = -1) {
		this.bytes = bytes.copy ();
		this.byte_length = declared_length == -1 ? bytes.length : declared_length;
	}

	public uint8 byte_at(int index) {
		return bytes[index];
	}

	public bool valid() {
		return byte_length >= 0 && byte_length <= int32.MAX && byte_length == bytes.length && valid_utf8 (bytes);
	}

	public bool equal_content(TextBytes other) {
		if (byte_length != other.byte_length || bytes.length != other.bytes.length) {
			return false;
		}
		for (int i = 0; i < bytes.length; i++) {
			if (bytes[i] != other.bytes[i]) {
				return false;
			}
		}
		return true;
	}

	public string hex() {
		var result = new StringBuilder ();
		foreach (uint8 value in bytes) {
			result.append_printf ("%02x", value);
		}
		return result.str;
	}

	public static bool scalar(uint32 value) {
		return value <= 0x10ffff && (value < 0xd800 || value > 0xdfff);
	}

	public static bool valid_utf8(uint8[] bytes) {
		for (int i = 0; i < bytes.length;) {
			uint32 first = bytes[i++];
			if (first < 0x80) {
				continue;
			}
			int count;
			uint32 value;
			uint32 minimum;
			if (first >= 0xc2 && first <= 0xdf) {
				count = 1;
				value = first & 0x1f;
				minimum = 0x80;
			} else if (first >= 0xe0 && first <= 0xef) {
				count = 2;
				value = first & 0x0f;
				minimum = 0x800;
			} else if (first >= 0xf0 && first <= 0xf4) {
				count = 3;
				value = first & 7;
				minimum = 0x10000;
			} else {
				return false;
			}
			if (count > bytes.length - i) {
				return false;
			}
			for (int n = 0; n < count; n++) {
				uint8 next = bytes[i++];
				if ((next & 0xc0) != 0x80) {
					return false;
				}
				value = (value << 6) | (next & 0x3f);
			}
			if (value < minimum || !scalar (value)) {
				return false;
			}
		}
		return true;
	}

}
}
