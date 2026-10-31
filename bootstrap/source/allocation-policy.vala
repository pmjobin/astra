// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
namespace Astra.Source {
public enum AllocationKind {
	HEAP, REGION, POOL, STATIC, CUSTOM, CONTEXT, INVALID;
	public static AllocationKind parse(string name) {
		switch (name) {
		case "heap":
			return HEAP;
		case "region":
			return REGION;
		case "pool":
			return POOL;
		case "static":
			return STATIC;
		case "custom":
			return CUSTOM;
		case "context":
			return CONTEXT;
		default:
			return INVALID;
		}
	}
	public string spelling() {
		switch (this) {
		case HEAP:
			return "heap";
		case REGION:
			return "region";
		case POOL:
			return "pool";
		case STATIC:
			return "static";
		case CUSTOM:
			return "custom";
		case CONTEXT:
			return "context";
		default:
			return "invalid";
		}
	}
}

// Primitive declaration authority only: no symbols, types, pointers or IR
// backlinks. Every stage owns a copy, including its immutable admitted ID.
public class AllocationPolicy : Object {
	public AllocationKind kind { get; internal set; }
	private string domain_name;
	public string domain { get { return domain_name; } }
	public uint capacity { get; internal set; }
	public uint blocks { get; internal set; }
	public uint alignment { get; internal set; }
	private string context_contract;
	public string context_mode { get { return context_contract; } }
	private string? allocation_callback;
	private string? release_callback;
	public string? allocate_hook { get { return allocation_callback; } }
	public string? release_hook { get { return release_callback; } }
	private string admitted_identity;
	private string admitted_domain_identity;
	public string identity { get { return admitted_identity; } }
	public string domain_identity { get { return admitted_domain_identity; } }

	public AllocationPolicy (AllocationKind kind, string domain, uint capacity, uint blocks, uint alignment = 1, string? allocate_hook = null, string? release_hook = null, string context_mode = "") {
		this.kind = kind;
		this.domain_name = domain;
		this.capacity = capacity;
		this.blocks = blocks;
		this.alignment = alignment;
		this.context_contract = context_mode;
		this.allocation_callback = allocate_hook;
		this.release_callback = release_hook;
		admitted_identity = Checksum.compute_for_string (ChecksumType.SHA256, canonical (true));
		admitted_domain_identity = Checksum.compute_for_string (ChecksumType.SHA256, canonical (false));
	}
	private AllocationPolicy.snapshot (AllocationPolicy source) {
		kind = source.kind;
		domain_name = source.domain;
		capacity = source.capacity;
		blocks = source.blocks;
		alignment = source.alignment;
		context_contract = source.context_mode;
		allocation_callback = source.allocate_hook;
		release_callback = source.release_hook;
		admitted_identity = source.admitted_identity;
		admitted_domain_identity = source.admitted_domain_identity;
	}
	public AllocationPolicy copy() {
		return new AllocationPolicy.snapshot (this);
	}
	public bool checked_initialization() {
		return valid () && kind == AllocationKind.CONTEXT;
	}
	public string dump() {
		return "(allocation-policy %s domain=\"%s\" capacity=%u blocks=%u alignment=%u identity=%s)".printf (kind.spelling (), domain.escape (), capacity, blocks, alignment, identity);
	}
	public static bool reserved_symbol(string name) {
		return name.has_prefix ("astra_alloc12_") || name == "astra_context17_allocate_mode" || name == "astra_context17_release_origin_checked" || name == "astra_context17_origin" || name == "astra_context17_frame_descriptor" || name == "astra_context17_open_scoped";
	}
	public static bool valid_context_mode(string mode) {
		return mode == "owned-affine" || mode == "owned-transfer" || mode == "owned-concurrent" || mode == "scoped-affine";
	}
	private string canonical(bool include_alignment) {
		return "allocation/1;%d;%d:%s;%u;%u;%u;%s;%s".printf ((int) kind, domain.length, domain, capacity, blocks, include_alignment ? alignment : 0, allocate_hook ?? "", release_hook ?? "") + (kind == AllocationKind.CONTEXT ? ";runtime-contexts/1;" + context_mode : "");
	}
	public static bool identifier(string name, bool dotted = false) {
		if (name.length == 0 || name.length > 128) {
			return false;
		}
		for (int i = 0; i < name.length; i++) {
			char value = name[i];
			if (!(value >= 'a' && value <= 'z' || value >= 'A' && value <= 'Z' || value == '_' || i > 0 && (value >= '0' && value <= '9' || dotted && value == '.'))) {
				return false;
			}
		}
		return true;
	}
	public static bool power_of_two(uint value) {
		return value > 0 && (value & (value - 1)) == 0;
	}
	public bool valid() {
		if (Checksum.compute_for_string (ChecksumType.SHA256, canonical (true)) != admitted_identity || !identifier (domain, true) || !power_of_two (alignment) || alignment > 4096 || kind < AllocationKind.HEAP || kind >= AllocationKind.INVALID) {
			return false;
		}
		if (kind == AllocationKind.CONTEXT) {
			return valid_context_mode (context_mode) && capacity == 0 && blocks == 0 && allocate_hook == null && release_hook == null;
		}
		if (context_mode != "") {
			return false;
		}
		if (kind == AllocationKind.HEAP) {
			return capacity == 0 && blocks == 0 && allocate_hook == null && release_hook == null;
		}
		if (capacity == 0 || capacity > 16777216 || blocks == 0 || blocks > 4096 || blocks > capacity) {
			return false;
		}
		if (kind == AllocationKind.POOL && (capacity % blocks != 0 || !power_of_two (capacity / blocks) || capacity / blocks < alignment)) {
			return false;
		}
		if (kind == AllocationKind.STATIC && blocks != 1) {
			return false;
		}
		return kind == AllocationKind.CUSTOM ? allocate_hook != null && release_hook != null && allocate_hook != release_hook && identifier (allocate_hook) && identifier (release_hook) : allocate_hook == null && release_hook == null;
	}
	public static bool matches(AllocationPolicy? policy, string identity) {
		return policy == null ? identity == "" : policy.valid () && policy.identity == identity;
	}
}

public class AllocationDomains : Object {
	private HashTable<string, string> domains = new HashTable<string, string> (str_hash, str_equal);
	public bool admit(AllocationPolicy? policy) {
		if (policy == null) {
			return true;
		}
		if (!policy.valid ()) {
			return false;
		}
		if (policy.kind == AllocationKind.CONTEXT) {
			return true;
		}
		var prior = domains.lookup (policy.domain);
		if (prior != null) {
			return prior == policy.domain_identity;
		}
		domains.insert (policy.domain, policy.domain_identity);
		return true;
	}
}
// Lexical backing authority contains only stable local/region identities.
// Each IR binds these identities to its own storage and cleanup facts.
public class ScopedBackingLoan : Object {
	public const uint ABI = 1;
	public int context_ordinal { get; private set; }
	public int backing_ordinal { get; private set; }
	public int region_ordinal { get; private set; }
	public ScopedBackingLoan (int context, int backing, int region) {
		context_ordinal = context;
		backing_ordinal = backing;
		region_ordinal = region;
	}
	public bool valid() {
		return backing_ordinal >= 0 && context_ordinal > backing_ordinal && region_ordinal >= 0;
	}
	public string identity() {
		return "scoped-backing/1:context=%d;backing=%d;region=%d;owned-u8-buffer;exclusive-until-context-drop".printf (context_ordinal, backing_ordinal, region_ordinal);
	}
}
}
