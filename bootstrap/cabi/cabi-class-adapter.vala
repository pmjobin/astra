// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;

namespace Astra.CAbi {
public class CAbiForeignSignal : Object {
	public ForeignSignalBinding binding { get; private set; }
	public int native_function { get; private set; }
	internal CAbiForeignSignal (ForeignSignalBinding binding, int native_function) {
		this.binding = new ForeignSignalBinding (binding.root, binding.member_index);
		this.native_function = native_function;
	}

	public bool valid(CAbiProgram program) {
		if (!binding.valid () || native_function < 0) {
			return false;
		}
		int matches = 0;
		foreach (var adapter in program.class_adapters) {
			if (adapter.policy.identity () != binding.root.identity ()) {
				continue;
			}
			if (!adapter.valid () || adapter.member_target (binding.member_index) != native_function) {
				return false;
			}
			matches++;
		}
		return matches == 1;
	}

}
public enum CAbiClassRole {
	CREATE, ACQUIRE, RELEASE, GET, SET, ROOT_IDENTITY,
	WEAK, WEAK_CLONE, WEAK_UPGRADE, WEAK_RELEASE,
	CHECK_THREAD, PERSONALITY, ATTACH;
}

// A finite opaque-pointer protocol, independent of the native Class layout.
// Roles carry ownership effects; pointer width alone never grants ownership.
public class CAbiClassAdapter : Object {
	public ForeignClassPolicy policy { get; internal set; }
	public int ordinal { get; internal set; }
	public int native_class { get; internal set; }
	public int constructor { get; internal set; }
	public int getter { get; internal set; }
	public int setter { get; internal set; }
	public SourceSpan span { get; private set; }
	private string identity;
	private int original_class;
	private int original_constructor;
	private int original_getter;
	private int original_setter;
	private WeakRef program = WeakRef (null);
	private bool claimed;
	private int[] declared_targets;
	public int member_target(uint index) {
		return declared_targets[index];
	}

	public static bool byte_sequence(ForeignValueKind kind) {
		return kind == ForeignValueKind.BYTES || kind == ForeignValueKind.TEXT;
	}

	public static bool record_forwarder(ForeignMemberContract member) {
		if (member.result.value_type.kind == ForeignValueKind.RECORD) {
			return true;
		}
		for (uint p = 0; p < member.parameter_count; p++) {
			if (member.parameter (p).value_type.kind == ForeignValueKind.RECORD) {
				return true;
			}
		}
		return false;
	}

	public static string member_symbol(ForeignApiContract api, ForeignMemberContract member, bool canonical = false) {
		return (canonical && record_forwarder (member) ? "astra_foreign16_" : "") + api.prefix + "_" + member.name;
	}

	public static string record_name(ForeignValueType type) {
		return "astra_record_" + Checksum.compute_for_string (ChecksumType.SHA256, type.identity ());
	}

	public static string record_field_name(ForeignRecordField field, uint ordinal) {
		return "astra_field_%u_%s".printf (ordinal, field.name);
	}

	public static uint field_size(ForeignValueKind kind) {
		switch (kind) {
		case ForeignValueKind.BOOL:
			return 1;
		case ForeignValueKind.I32:
		case ForeignValueKind.U32:
		case ForeignValueKind.F32:
			return 4;
		case ForeignValueKind.I64:
		case ForeignValueKind.U64:
		case ForeignValueKind.F64:
			return 8;
		default:
			return 0;
		}
	}

	public static uint record_alignment(ForeignValueType type) {
		uint alignment = 1;
		for (uint f = 0; f < type.field_count; f++) {
			alignment = uint.max (alignment, field_size (type.field (f).kind));
		}
		return alignment;
	}

	public static uint record_offset(ForeignValueType type, uint field) {
		uint position = 0;
		for (uint f = 0; f <= field; f++) {
			uint size = field_size (type.field (f).kind);
			if (size == 0) {
				return uint.MAX;
			}
			position = (position + size - 1) / size * size;
			if (f == field) {
				return position;
			}
			position += size;
		}
		return uint.MAX;
	}

	public static uint record_size(ForeignValueType type) {
		uint alignment = record_alignment (type);
		uint end = record_offset (type, type.field_count - 1) + field_size (type.field (type.field_count - 1).kind);
		return (end + alignment - 1) / alignment * alignment;
	}

	public static uint declared_width(ForeignChannel channel) {
		return byte_sequence (channel.value_type.kind) && channel.intrinsic_length || channel.value_type.kind == ForeignValueKind.CALLBACK && channel.intrinsic_context ? 2 : 1;
	}

	public static string callback_name(string prefix, ForeignValueType type) {
		return prefix + "_callback_" + Checksum.compute_for_string (ChecksumType.SHA256, type.identity ());
	}

	public static string native_projection_symbol(ForeignClassPolicy policy) {
		return "astra_foreign16_" + policy.prefix + "_native_project";
	}

	public static uint declared_argument(ForeignMemberContract member, uint index) {
		uint offset = member.kind == ForeignMemberKind.CONSTRUCTOR ? 0 : 1;
		for (uint p = 0; p < index; p++) {
			offset += declared_width (member.parameter (p));
		}
		return offset;
	}

	public static uint declared_result(ForeignMemberContract member) {
		return declared_argument (member, member.parameter_count);
	}

	public static uint declared_result_width(ForeignMemberContract member) {
		return member.result.value_type.kind == ForeignValueKind.VOID ? 0 : byte_sequence (member.result.value_type.kind) ? 2 : 1;
	}

	public static uint declared_count(ForeignMemberContract member, uint parameter) {
		var channel = member.parameter (parameter);
		return channel.intrinsic_length ? declared_argument (member, parameter) + 1 : declared_argument (member, (uint) (channel.direction == ForeignDirection.IN ? channel.length_index : channel.capacity_index));
	}

	public CAbiProgram? owner { owned get { return (CAbiProgram?) program.get (); } }
	internal CAbiClassAdapter (ForeignClassPolicy policy, SourceSpan span, int ordinal, int native_class, int constructor, int getter, int setter, int[]? declared_targets = null) {
		this.policy = policy.copy ();
		identity = policy.identity ();
		this.span = span;
		this.ordinal = ordinal;
		this.native_class = original_class = native_class;
		this.constructor = original_constructor = constructor;
		this.getter = original_getter = getter;
		this.setter = original_setter = setter;
		if (declared_targets != null) {
			this.declared_targets = declared_targets.copy ();
		}
	}

	internal void claim_owner(CAbiProgram owner) throws CAbiError {
		if (claimed) {
			throw new CAbiError.INVALID_ABI ("opaque Class adapter cannot be shared between programs");
		}
		claimed = true;
		program = WeakRef (owner);
	}

	public bool valid() {
		if (policy == null || !policy.valid () || policy.identity () != identity || native_class < 0 || native_class != original_class || constructor != original_constructor || getter != original_getter || setter != original_setter) {
			return false;
		}
		if (policy.declared_api == null) {
			return constructor >= 0 && getter >= 0 && setter >= 0 && declared_targets.length == 0;
		}
		if (constructor != -1 || getter != -1 || setter != -1 || declared_targets.length != policy.declared_api.member_count) {
			return false;
		}
		foreach (var target in declared_targets) {
			if (target < 0) {
				return false;
			}
		}
		return true;
	}

	public GenericArray<string> declared_symbols() {
		var names = new GenericArray<string> ();
		var api = policy.declared_api;
		if (api == null) {
			return names;
		}
		for (uint m = 0; m < api.member_count; m++) {
			names.add (policy.prefix + "_" + api.member (m).name);
		}
		for (uint m = 0; m < api.member_count; m++) {
			if (record_forwarder (api.member (m))) {
				names.add (member_symbol (api, api.member (m), true));
			}
		}
		for (uint m = 0; m < api.member_count; m++) {
			if (api.member (m).result.value_type.kind == ForeignValueKind.BYTES) {
				names.add (policy.prefix + "_bytes_release");
				break;
			}
		}
		for (uint m = 0; m < api.member_count; m++) {
			if (api.member (m).result.value_type.kind == ForeignValueKind.TEXT) {
				names.add (policy.prefix + "_text_release");
				break;
			}
		}
		names.add (policy.prefix + "_root_identity");
		if (api.lifetime == ForeignLifetime.UNIQUE) {
			names.add (policy.prefix + "_destroy");
		} else {
			foreach (var suffix in new string[] { "acquire", "release", "weak", "weak_clone", "weak_upgrade", "weak_release" }) {
				names.add (policy.prefix + "_" + suffix);
			}
		}
		foreach (var suffix in new string[] { "check_thread", "personality", "attach" }) {
			names.add ("astra_foreign14_" + policy.prefix + "_" + suffix);
		}
		if (api.lifetime == ForeignLifetime.SHARED && policy.active (ForeignClassPolicy.GOBJECT)) {
			names.add (native_projection_symbol (policy));
		}
		return names;
	}

	public static CAbiClassRole[] roles() {
		return {
				   CAbiClassRole.CREATE, CAbiClassRole.ACQUIRE, CAbiClassRole.RELEASE, CAbiClassRole.GET, CAbiClassRole.SET, CAbiClassRole.ROOT_IDENTITY, CAbiClassRole.WEAK, CAbiClassRole.WEAK_CLONE, CAbiClassRole.WEAK_UPGRADE, CAbiClassRole.WEAK_RELEASE, CAbiClassRole.CHECK_THREAD, CAbiClassRole.PERSONALITY, CAbiClassRole.ATTACH
		};
	}

	public static string suffix(CAbiClassRole role) {
		switch (role) {
		case CAbiClassRole.CREATE: return "create";
		case CAbiClassRole.ACQUIRE: return "acquire";
		case CAbiClassRole.RELEASE: return "release";
		case CAbiClassRole.GET:
			return "get";
		case CAbiClassRole.SET:
			return "set";
		case CAbiClassRole.ROOT_IDENTITY:
			return "root_identity";
		case CAbiClassRole.WEAK:
			return "weak";
		case CAbiClassRole.WEAK_CLONE:
			return "weak_clone";
		case CAbiClassRole.WEAK_UPGRADE:
			return "weak_upgrade";
		case CAbiClassRole.WEAK_RELEASE:
			return "weak_release";
		case CAbiClassRole.CHECK_THREAD:
			return "check_thread";
		case CAbiClassRole.PERSONALITY:
			return "personality";
		case CAbiClassRole.ATTACH:
			return "attach";
		default:
			return "<invalid>";
		}
	}

	public string symbol(CAbiClassRole role) {
		return (role >= CAbiClassRole.CHECK_THREAD ? "astra_foreign14_" : "") + policy.prefix + "_" + suffix (role);
	}

	public static bool returns_void(CAbiClassRole role) {
		return role == CAbiClassRole.WEAK_RELEASE;
	}

	public static CAbiScalarType result(CAbiClassRole role) {
		return role == CAbiClassRole.CREATE || role == CAbiClassRole.ROOT_IDENTITY || role == CAbiClassRole.WEAK || role == CAbiClassRole.WEAK_CLONE || role == CAbiClassRole.WEAK_UPGRADE || role == CAbiClassRole.PERSONALITY ? CAbiScalarType.PTR : CAbiScalarType.I32;
	}

	public static int parameter_count(CAbiClassRole role) {
		return role == CAbiClassRole.ATTACH ? 3 : role == CAbiClassRole.GET || role == CAbiClassRole.SET ? 2 : 1;
	}

	public static CAbiScalarType parameter(CAbiClassRole role, int index) {
		return role == CAbiClassRole.CREATE || (role == CAbiClassRole.SET && index == 1) ? CAbiScalarType.I32 : CAbiScalarType.PTR;
	}

	public static string lifetime(CAbiClassRole role) {
		switch (role) {
		case CAbiClassRole.CREATE:
		case CAbiClassRole.WEAK_UPGRADE:
			return "one native strong result on success";
		case CAbiClassRole.ACQUIRE:
			return "acquire one native strong; return exact bounded count";
		case CAbiClassRole.RELEASE:
			return "retire one native strong; last strong retires payload and cached personality";
		case CAbiClassRole.WEAK:
		case CAbiClassRole.WEAK_CLONE:
			return "one native weak result; independent weak wrapper";
		case CAbiClassRole.WEAK_RELEASE:
			return "retire one native weak and its wrapper";
		case CAbiClassRole.ATTACH:
			return "bind one synchronous personality retirement to the native root";
		case CAbiClassRole.ROOT_IDENTITY:
			return "borrowed root; opaque identity token; no layout authority";
		case CAbiClassRole.GET:
		case CAbiClassRole.SET:
			return "borrowed root; constructing-thread data call; HRESULT/out errors";
		default:
			return "borrowed root; explicit constructing-thread personality access";
		}
	}

}
public class CAbiForeignImport : Object {
	public ForeignImportBinding binding { get; private set; }
	private int declared_function;
	private int declared_factory;
	public int native_function { get; internal set; }
	public int error_factory { get; internal set; }
	public GenericArray<CAbiScalarType> parameters { get; private set; default = new GenericArray<CAbiScalarType> (); }
	public CAbiForeignImport (ForeignImportBinding binding, int native_function, int error_factory) {
		this.binding = binding;
		this.native_function = declared_function = native_function;
		this.error_factory = declared_factory = error_factory;
		if (binding.member.kind != ForeignMemberKind.CONSTRUCTOR) {
			parameters.add (CAbiScalarType.PTR);
		}
		for (uint p = 0; p < binding.member.parameter_count; p++) {
			var channel = binding.member.parameter (p);
			parameters.add (channel.by_reference || CAbiClassAdapter.byte_sequence (channel.value_type.kind) ? CAbiScalarType.PTR : scalar (channel.value_type.kind));
			if (CAbiClassAdapter.byte_sequence (channel.value_type.kind) && channel.intrinsic_length) {
				parameters.add (CAbiScalarType.I32);
			} else if (channel.value_type.kind == ForeignValueKind.CALLBACK && channel.intrinsic_context) {
				parameters.add (CAbiScalarType.PTR);
			}
		}
		for (uint r = 0; r < CAbiClassAdapter.declared_result_width (binding.member); r++) {
			parameters.add (CAbiScalarType.PTR);
		}
		parameters.add (CAbiScalarType.PTR);
	}

	public static CAbiScalarType scalar(ForeignValueKind kind) {
		switch (kind) {
		case ForeignValueKind.I32:
		case ForeignValueKind.U32:
			return CAbiScalarType.I32;
		case ForeignValueKind.I64:
			return CAbiScalarType.I64;
		case ForeignValueKind.U64:
			return CAbiScalarType.U64;
		case ForeignValueKind.F32:
			return CAbiScalarType.F32;
		case ForeignValueKind.F64:
			return CAbiScalarType.F64;
		case ForeignValueKind.BOOL:
			return CAbiScalarType.CBOOL;
		default:
			return CAbiScalarType.PTR;
		}
	}

	public string symbol() {
		return (CAbiClassAdapter.record_forwarder (binding.member) ? "astra_foreign16_import_" : "") + binding.root.api.prefix + "_" + binding.member.name;
	}

	public bool valid() {
		if (!binding.valid () || native_function < 0 || error_factory < 0 || native_function != declared_function || error_factory != declared_factory) {
			return false;
		}
		var expected = new CAbiForeignImport (binding, native_function, error_factory);
		if (expected.parameters.length != parameters.length) {
			return false;
		}
		for (int p = 0; p < parameters.length; p++) {
			if (parameters[p] != expected.parameters[p]) {
				return false;
			}
		}
		return true;
	}

}

}
