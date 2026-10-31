// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

// Stage-neutral identities and rules. No symbols, syntax, ABI or runtime data.
namespace Astra {
public enum GenericCapabilityIdentity {
	EQ, ORDERED, NUMERIC, BITWISE, SHIFT, OWNABLE;
	public bool valid() {
		return this >= EQ && this <= OWNABLE;
	}
	public uint bit() {
		return valid () ? 1u << (uint) this : 0;
	}
	public string spelling() {
		switch (this) {
		case EQ:
			return "Eq";
		case ORDERED:
			return "Ordered";
		case NUMERIC:
			return "Numeric";
		case BITWISE:
			return "Bitwise";
		case SHIFT:
			return "Shift";
		case OWNABLE:
			return "Ownable";
		default:
			return "invalid-capability";
		}
	}
}

// Immutable ordered list plus exact identity membership. No implication closure.
public class GenericCapabilitySet : Object {
	private GenericCapabilityIdentity[] ordered;
	private uint membership = 0;
	public int length { get { return ordered.length; } }
	public GenericCapabilitySet (GenericCapabilityIdentity[]? capabilities = null) {
		ordered = capabilities == null ? null : capabilities.copy ();
		foreach (var capability in ordered) {
			membership |= capability.bit ();
		}
	}
	public GenericCapabilityIdentity at(int index) {
		return ordered[index];
	}
	public bool contains(GenericCapabilityIdentity capability) {
		return capability.valid () && (membership & capability.bit ()) != 0;
	}
}
// A single stage-neutral capability matrix. Each stage derives the domain
// from its own exact type facts before consulting these language rules.
public enum GenericCapabilityDomain {
	NONE, INTEGER, FLOATING, BOOLEAN, RAW_POINTER, OWNER;
	public uint capabilities() {
		switch (this) {
		case INTEGER:
			return GenericCapabilityIdentity.EQ.bit () | GenericCapabilityIdentity.ORDERED.bit () | GenericCapabilityIdentity.NUMERIC.bit () | GenericCapabilityIdentity.BITWISE.bit () | GenericCapabilityIdentity.SHIFT.bit ();
		case FLOATING:
			return GenericCapabilityIdentity.EQ.bit () | GenericCapabilityIdentity.ORDERED.bit () | GenericCapabilityIdentity.NUMERIC.bit ();
		case BOOLEAN:
		case RAW_POINTER:
			return GenericCapabilityIdentity.EQ.bit ();
		case OWNER:
			return GenericCapabilityIdentity.OWNABLE.bit ();
		default:
			return 0;
		}
	}
}
}
