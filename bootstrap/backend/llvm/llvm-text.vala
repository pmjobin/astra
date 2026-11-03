// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.NativeAbi;
using Astra.Text;

namespace Astra.Backend.LLVM {
// Construction-only module pool. Full count + hex bytes form an injective
// key, with hash collision equality. First emitted use assigns a local
// ordinal; no quark, source spelling, path or host address is an identity.
internal class LlvmTextLowering : Object {
	private LlvmModuleArtifact artifact;
	private LlvmTypeMapper types;
	private HashTable<string, void*> literals = new HashTable<string, void*> (str_hash, str_equal);
	private CApi.ValueRef helper;
	private CApi.TypeRef helper_type;
	private CApi.ValueRef utf8_helper;
	private CApi.TypeRef utf8_type;
	private CApi.ValueRef nul_helper;
	private CApi.TypeRef nul_type;
	internal LlvmTextLowering (LlvmModuleArtifact artifact, LlvmTypeMapper types) {
		this.artifact = artifact;
		this.types = types;
	}

	private CApi.ValueRef utf8_compare(CApi.BuilderRef builder, CApi.IntPredicate predicate, CApi.ValueRef left, CApi.ValueRef right, string name) throws LlvmError {
		var result = CApi.build_icmp (builder, predicate, left, right, name);
		artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.ICMP, types.scalar (NativeScalarType.B1), new CApi.ValueRef[] { left, right }, "UTF-8 exact range/bounds predicate", -1, (int) predicate));
		return result;
	}

	private CApi.ValueRef utf8_byte(CApi.BuilderRef builder, CApi.ValueRef pointer, CApi.ValueRef index, string name) throws LlvmError {
		var byte = types.scalar (NativeScalarType.U8);
		CApi.ValueRef[] indices = {
			index
		};
		var address = CApi.build_gep (builder, byte, pointer, indices, 1, name + ".address");
		artifact.class_values.add (new LlvmClassValueBinding (address, CApi.Opcode.GEP, types.scalar (NativeScalarType.PTR), new CApi.ValueRef[] { pointer, index }, "UTF-8 bounded byte address"));
		var result = CApi.build_load (builder, byte, address, name);
		CApi.set_alignment (result, 1);
		artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.LOAD, byte, new CApi.ValueRef[] { address }, "UTF-8 counted byte load", -1, -1, 1));
		return result;
	}

	private CApi.ValueRef utf8_range(CApi.BuilderRef builder, CApi.ValueRef value, uint low, uint high, string name) throws LlvmError {
		var byte = types.scalar (NativeScalarType.U8);
		return CApi.build_and (builder, utf8_compare (builder, CApi.IntPredicate.UGE, value, CApi.const_int (byte, low, 0), name + ".low"), utf8_compare (builder, CApi.IntPredicate.ULE, value, CApi.const_int (byte, high, 0), name + ".high"), name);
	}

	private void build_utf8_helper() throws LlvmError {
		if ((void*) utf8_helper != null) {
			return;
		}
		var pointer_type = types.scalar (NativeScalarType.PTR);
		var count_type = types.scalar (NativeScalarType.I32);
		var boolean = types.scalar (NativeScalarType.B1);
		var byte_type = types.scalar (NativeScalarType.U8);
		CApi.TypeRef[] parameters = {
			pointer_type, count_type
		};
		utf8_type = CApi.function_type (boolean, parameters, parameters.length, 0);
		string name = "astra.text.validate.utf8";
		if ((void*) CApi.named_function (artifact.module, name) != null || (void*) CApi.named_global (artifact.module, name) != null) {
			throw new LlvmError.INVALID_INPUT ("UTF-8 validator conflicts with an external declaration");
		}
		utf8_helper = CApi.add_function (artifact.module, name, utf8_type);
		CApi.set_linkage (utf8_helper, CApi.Linkage.INTERNAL);
		CApi.set_function_call_conv (utf8_helper, LlvmLowering.CALL_CONVENTION);
		var entry = CApi.append_basic_block_in_context (artifact.context, utf8_helper, "count");
		var empty = CApi.append_basic_block_in_context (artifact.context, utf8_helper, "empty");
		var backing = CApi.append_basic_block_in_context (artifact.context, utf8_helper, "backing");
		var loop = CApi.append_basic_block_in_context (artifact.context, utf8_helper, "next");
		var lead = CApi.append_basic_block_in_context (artifact.context, utf8_helper, "lead");
		var ascii = CApi.append_basic_block_in_context (artifact.context, utf8_helper, "ascii");
		var yes = CApi.append_basic_block_in_context (artifact.context, utf8_helper, "valid");
		var no = CApi.append_basic_block_in_context (artifact.context, utf8_helper, "invalid");
		var builder = CApi.create_builder_in_context (artifact.context);
		var pointer = CApi.get_param (utf8_helper, 0);
		var length = CApi.get_param (utf8_helper, 1);
		var zero = CApi.const_null (count_type);
		CApi.position_builder_at_end (builder, entry);
		CApi.build_cond_br (builder, utf8_compare (builder, CApi.IntPredicate.SGE, length, zero, "nonnegative"), empty, no);
		CApi.position_builder_at_end (builder, empty);
		CApi.build_cond_br (builder, utf8_compare (builder, CApi.IntPredicate.EQ, length, zero, "zero"), yes, backing);
		CApi.position_builder_at_end (builder, backing);
		CApi.build_cond_br (builder, utf8_compare (builder, CApi.IntPredicate.NE, pointer, CApi.const_null (pointer_type), "nonnull"), loop, no);
		CApi.position_builder_at_end (builder, loop);
		var index = CApi.build_phi (builder, count_type, "index");
		CApi.add_incoming (index, &zero, &backing, 1);
		CApi.build_cond_br (builder, utf8_compare (builder, CApi.IntPredicate.EQ, index, length, "complete"), yes, lead);
		CApi.position_builder_at_end (builder, lead);
		var first = utf8_byte (builder, pointer, index, "lead.byte");
		var wide = CApi.append_basic_block_in_context (artifact.context, utf8_helper, "wide");
		CApi.build_cond_br (builder, utf8_compare (builder, CApi.IntPredicate.ULT, first, CApi.const_int (byte_type, 0x80, 0), "ascii"), ascii, wide);
		CApi.position_builder_at_end (builder, ascii);
		var next = CApi.build_add (builder, index, CApi.const_int (count_type, 1, 0), "ascii.next");
		CApi.build_br (builder, loop);
		CApi.add_incoming (index, &next, &ascii, 1);
		// A remaining >= width guard dominates every lookahead. Index
		// additions are <= length <= INT_MAX, without wrapping arithmetic.
		var selection = wide;
		for (uint width = 2; width <= 4; width++) {
			var bounds = CApi.append_basic_block_in_context (artifact.context, utf8_helper, "width%u.bounds".printf (width));
			var bytes = CApi.append_basic_block_in_context (artifact.context, utf8_helper, "width%u.bytes".printf (width));
			var advance = CApi.append_basic_block_in_context (artifact.context, utf8_helper, "width%u.advance".printf (width));
			var following = width == 4 ? no : CApi.append_basic_block_in_context (artifact.context, utf8_helper, "width%u.select".printf (width + 1));
			CApi.position_builder_at_end (builder, selection);
			var range = utf8_range (builder, first, width == 2 ? 0xc2 : width == 3 ? 0xe0 : 0xf0, width == 2 ? 0xdf : width == 3 ? 0xef : 0xf4, "lead.range");
			CApi.build_cond_br (builder, range, bounds, following);
			CApi.position_builder_at_end (builder, bounds);
			var remaining = CApi.build_sub (builder, length, index, "remaining");
			CApi.build_cond_br (builder, utf8_compare (builder, CApi.IntPredicate.UGE, remaining, CApi.const_int (count_type, width, 0), "complete.sequence"), bytes, no);
			CApi.position_builder_at_end (builder, bytes);
			CApi.ValueRef valid = CApi.const_int (boolean, 1, 0);
			for (uint offset = 1; offset < width; offset++) {
				var position = CApi.build_add (builder, index, CApi.const_int (count_type, offset, 0), "continuation.index");
				var value = utf8_byte (builder, pointer, position, "continuation.byte");
				valid = CApi.build_and (builder, valid, utf8_range (builder, value, 0x80, 0xbf, "continuation"), "continuations.valid");
				if (offset == 1 && width >= 3) {
					var low_lead = utf8_compare (builder, CApi.IntPredicate.NE, first, CApi.const_int (byte_type, width == 3 ? 0xe0 : 0xf0, 0), "not.shortest.boundary");
					var low_byte = utf8_compare (builder, CApi.IntPredicate.UGE, value, CApi.const_int (byte_type, width == 3 ? 0xa0 : 0x90, 0), "shortest.second");
					valid = CApi.build_and (builder, valid, CApi.build_or (builder, low_lead, low_byte, "shortest"), "canonical");
					var high_lead = utf8_compare (builder, CApi.IntPredicate.NE, first, CApi.const_int (byte_type, width == 3 ? 0xed : 0xf4, 0), "not.scalar.boundary");
					var high_byte = utf8_compare (builder, CApi.IntPredicate.ULE, value, CApi.const_int (byte_type, width == 3 ? 0x9f : 0x8f, 0), "scalar.second");
					valid = CApi.build_and (builder, valid, CApi.build_or (builder, high_lead, high_byte, "scalar"), "scalar.valid");
				}
			}
			CApi.build_cond_br (builder, valid, advance, no);
			CApi.position_builder_at_end (builder, advance);
			var advanced = CApi.build_add (builder, index, CApi.const_int (count_type, width, 0), "sequence.next");
			CApi.build_br (builder, loop);
			CApi.add_incoming (index, &advanced, &advance, 1);
			selection = following;
		}
		CApi.position_builder_at_end (builder, yes);
		CApi.build_ret (builder, CApi.const_int (boolean, 1, 0));
		CApi.position_builder_at_end (builder, no);
		CApi.build_ret (builder, CApi.const_null (boolean));
		artifact.class_functions.add (new LlvmClassFunctionBinding (utf8_helper, utf8_type));
		CApi.dispose_builder (builder);
	}

	internal CApi.ValueRef validate_utf8(CApi.BuilderRef builder, CApi.ValueRef input) throws LlvmError {
		var pointer = CApi.build_extract_value (builder, input, 0, "utf8.input.base");
		var count = CApi.build_extract_value (builder, input, 1, "utf8.input.count");
		artifact.class_values.add (new LlvmClassValueBinding (pointer, CApi.Opcode.EXTRACT_VALUE, types.scalar (NativeScalarType.PTR), new CApi.ValueRef[] { input }, "UTF-8 input base", 0));
		artifact.class_values.add (new LlvmClassValueBinding (count, CApi.Opcode.EXTRACT_VALUE, types.scalar (NativeScalarType.I32), new CApi.ValueRef[] { input }, "UTF-8 input count", 1));
		return validate_counted_utf8 (builder, pointer, count);
	}

	internal CApi.ValueRef validate_counted_utf8(CApi.BuilderRef builder, CApi.ValueRef pointer, CApi.ValueRef count) throws LlvmError {
		build_utf8_helper ();
		CApi.ValueRef[] arguments = {
			pointer, count
		};
		var call = CApi.build_call (builder, utf8_type, utf8_helper, arguments, arguments.length, "utf8.valid");
		CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
		artifact.class_calls.add (new LlvmClassCallBinding (call, utf8_helper, utf8_type, arguments, LlvmLowering.CALL_CONVENTION, "UTF-8 exact counted validation"));
		return call;
	}

	// Returns the first NUL offset in [0, limit), or -1. A null base has no
	// searchable bytes. NUL input conversion supplies the maximum native
	// storage extent; output conversion supplies the exact native byte count.
	private void build_nul_helper() throws LlvmError {
		if ((void*) nul_helper != null) {
			return;
		}
		var count = types.scalar (NativeScalarType.I32);
		var pointer = types.scalar (NativeScalarType.PTR);
		CApi.TypeRef[] parameters = {
			pointer, count
		};
		nul_type = CApi.function_type (count, parameters, parameters.length, 0);
		string name = "astra.text.find.nul";
		if ((void*) CApi.named_function (artifact.module, name) != null || (void*) CApi.named_global (artifact.module, name) != null) {
			throw new LlvmError.INVALID_INPUT ("NUL conversion helper conflicts with an external declaration");
		}
		nul_helper = CApi.add_function (artifact.module, name, nul_type);
		CApi.set_linkage (nul_helper, CApi.Linkage.INTERNAL);
		CApi.set_function_call_conv (nul_helper, LlvmLowering.CALL_CONVENTION);
		var entry = CApi.append_basic_block_in_context (artifact.context, nul_helper, "entry");
		var bound = CApi.append_basic_block_in_context (artifact.context, nul_helper, "bound");
		var loop = CApi.append_basic_block_in_context (artifact.context, nul_helper, "next");
		var read = CApi.append_basic_block_in_context (artifact.context, nul_helper, "byte");
		var advance = CApi.append_basic_block_in_context (artifact.context, nul_helper, "advance");
		var found = CApi.append_basic_block_in_context (artifact.context, nul_helper, "found");
		var absent = CApi.append_basic_block_in_context (artifact.context, nul_helper, "absent");
		var b = CApi.create_builder_in_context (artifact.context);
		var base_value = CApi.get_param (nul_helper, 0);
		var limit = CApi.get_param (nul_helper, 1);
		var zero = CApi.const_null (count);
		CApi.position_builder_at_end (b, entry);
		CApi.build_cond_br (b, utf8_compare (b, CApi.IntPredicate.EQ, base_value, CApi.const_null (pointer), "null"), absent, bound);
		CApi.position_builder_at_end (b, bound);
		CApi.build_cond_br (b, utf8_compare (b, CApi.IntPredicate.SLT, limit, zero, "negative.limit"), absent, loop);
		CApi.position_builder_at_end (b, loop);
		var index = CApi.build_phi (b, count, "index");
		CApi.add_incoming (index, &zero, &bound, 1);
		CApi.build_cond_br (b, utf8_compare (b, CApi.IntPredicate.EQ, index, limit, "complete"), absent, read);
		CApi.position_builder_at_end (b, read);
		var value = utf8_byte (b, base_value, index, "nul.byte");
		CApi.build_cond_br (b, utf8_compare (b, CApi.IntPredicate.EQ, value, CApi.const_null (types.scalar (NativeScalarType.U8)), "nul"), found, advance);
		CApi.position_builder_at_end (b, advance);
		var next = CApi.build_add (b, index, CApi.const_int (count, 1, 0), "next");
		CApi.build_br (b, loop);
		CApi.add_incoming (index, &next, &advance, 1);
		CApi.position_builder_at_end (b, found);
		CApi.build_ret (b, index);
		CApi.position_builder_at_end (b, absent);
		CApi.build_ret (b, CApi.const_int (count, uint32.MAX, 0));
		artifact.class_functions.add (new LlvmClassFunctionBinding (nul_helper, nul_type));
		CApi.dispose_builder (b);
	}

	internal CApi.ValueRef find_nul(CApi.BuilderRef builder, CApi.ValueRef pointer, CApi.ValueRef limit) throws LlvmError {
		build_nul_helper ();
		CApi.ValueRef[] arguments = {
			pointer, limit
		};
		var call = CApi.build_call (builder, nul_type, nul_helper, arguments, arguments.length, "nul.position");
		CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
		artifact.class_calls.add (new LlvmClassCallBinding (call, nul_helper, nul_type, arguments, LlvmLowering.CALL_CONVENTION, "exact bounded NUL conversion"));
		return call;
	}

	internal CApi.ValueRef literal(TextBytes payload) throws LlvmError {
		if (!payload.valid ()) {
			throw new LlvmError.INVALID_INPUT ("invalid immutable UTF-8 literal payload");
		}
		if (payload.byte_length == 0) {
			return CApi.const_null (types.buffer_carrier ());
		}
		string key = payload.byte_length.to_string () + ":" + payload.hex ();
		var pointer = (CApi.ValueRef) literals.lookup (key);
		if ((void*) pointer == null) {
			// Exact bytes, without a sentinel. This is never a C string.
			var bytes = new CApi.ValueRef[(int) payload.byte_length];
			var byte_type = types.scalar (NativeScalarType.U8);
			for (int i = 0; i < bytes.length; i++) {
				bytes[i] = CApi.const_int (byte_type, payload.byte_at (i), 0);
			}
			var data = CApi.const_array (byte_type, bytes, bytes.length);
			string symbol = "astra.text.%u".printf (literals.size ());
			if ((void*) CApi.named_function (artifact.module, symbol) != null || (void*) CApi.named_global (artifact.module, symbol) != null) {
				throw new LlvmError.INVALID_INPUT ("text literal symbol conflicts with an external declaration");
			}
			pointer = CApi.add_global (artifact.module, CApi.type_of (data), symbol);
			CApi.set_linkage (pointer, CApi.Linkage.PRIVATE);
			CApi.set_global_constant (pointer, 1);
			CApi.set_initializer (pointer, data);
			literals.insert (key, (void*) pointer);
		}
		CApi.ValueRef[] fields = {
			pointer, CApi.const_int (types.scalar (NativeScalarType.I32), payload.byte_length, 0)
		};
		return CApi.const_struct (artifact.context, fields, fields.length, 0);
	}

	private void build_helper() throws LlvmError {
		if ((void*) helper != null) {
			return;
		}
		var pointer = types.scalar (NativeScalarType.PTR);
		var count = types.scalar (NativeScalarType.I32);
		var boolean = types.scalar (NativeScalarType.B1);
		var byte = types.scalar (NativeScalarType.U8);
		CApi.TypeRef[] parameters = {
			pointer, count, pointer, count
		};
		helper_type = CApi.function_type (boolean, parameters, parameters.length, 0);
		if ((void*) CApi.named_function (artifact.module, "astra.text.equal") != null || (void*) CApi.named_global (artifact.module, "astra.text.equal") != null) {
			throw new LlvmError.INVALID_INPUT ("text equality symbol conflicts with an external declaration");
		}
		helper = CApi.add_function (artifact.module, "astra.text.equal", helper_type);
		CApi.set_linkage (helper, CApi.Linkage.INTERNAL);
		CApi.set_function_call_conv (helper, LlvmLowering.CALL_CONVENTION);
		// Qualified LLVM's per-function TargetLibraryInfo disables libc
		// idioms here. Keep that policy on this helper through inlining.
		CApi.add_attribute (helper, uint.MAX, CApi.create_string_attribute (artifact.context, "no-builtins", 11, "", 0));
		CApi.add_attribute (helper, uint.MAX, CApi.create_enum_attribute (artifact.context, CApi.enum_attribute_kind ("noinline", 8), 0));
		var entry = CApi.append_basic_block_in_context (artifact.context, helper, "entry");
		var empty = CApi.append_basic_block_in_context (artifact.context, helper, "empty");
		var loop = CApi.append_basic_block_in_context (artifact.context, helper, "bytes");
		var advance = CApi.append_basic_block_in_context (artifact.context, helper, "advance");
		var yes = CApi.append_basic_block_in_context (artifact.context, helper, "equal");
		var no = CApi.append_basic_block_in_context (artifact.context, helper, "different");
		var builder = CApi.create_builder_in_context (artifact.context);
		CApi.position_builder_at_end (builder, entry);
		var length = CApi.get_param (helper, 1);
		CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, length, CApi.get_param (helper, 3), "same.length"), empty, no);
		CApi.position_builder_at_end (builder, empty);
		CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, length, CApi.const_int (count, 0, 0), "zero"), yes, loop);
		CApi.position_builder_at_end (builder, loop);
		var index = CApi.build_phi (builder, count, "index");
		CApi.ValueRef[] indices = {
			index
		};
		var left = CApi.build_load (builder, byte, CApi.build_gep (builder, byte, CApi.get_param (helper, 0), indices, 1, "left.address"), "left.byte");
		var right = CApi.build_load (builder, byte, CApi.build_gep (builder, byte, CApi.get_param (helper, 2), indices, 1, "right.address"), "right.byte");
		CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, left, right, "same.byte"), advance, no);
		CApi.position_builder_at_end (builder, advance);
		var next = CApi.build_add (builder, index, CApi.const_int (count, 1, 0), "next");
		CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, next, length, "finished"), yes, loop);
		CApi.ValueRef[] inputs = {
			CApi.const_int (count, 0, 0), next
		};
		CApi.BasicBlockRef[] predecessors = {
			empty, advance
		};
		CApi.add_incoming (index, inputs, predecessors, inputs.length);
		CApi.position_builder_at_end (builder, yes);
		CApi.build_ret (builder, CApi.const_int (boolean, 1, 0));
		CApi.position_builder_at_end (builder, no);
		CApi.build_ret (builder, CApi.const_int (boolean, 0, 0));
		CApi.dispose_builder (builder);
	}

	internal CApi.ValueRef equality(CApi.BuilderRef builder, CApi.ValueRef left, CApi.ValueRef right, bool negate, string name) throws LlvmError {
		build_helper ();
		CApi.ValueRef[] arguments = {
			CApi.build_extract_value (builder, left, 0, name + ".left.base"), CApi.build_extract_value (builder, left, 1, name + ".left.length"), CApi.build_extract_value (builder, right, 0, name + ".right.base"), CApi.build_extract_value (builder, right, 1, name + ".right.length")
		};
		var result = CApi.build_call (builder, helper_type, helper, arguments, arguments.length, negate ? name + ".equal" : name);
		CApi.set_instruction_call_conv (result, LlvmLowering.CALL_CONVENTION);
		return negate ? CApi.build_icmp (builder, CApi.IntPredicate.EQ, result, CApi.const_int (types.scalar (NativeScalarType.B1), 0, 0), name) : result;
	}

}
}
