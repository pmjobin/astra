// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Source;
using Astra.Ssa;

namespace Astra.Backend.LLVM {
internal class LlvmDebugFrameField : Object {
	private CApi.TypeRef frame;
	private CApi.TargetDataRef data;
	private uint index;
	private uint64 offset;
	private uint64 extent;
	private int packed;
	private GenericArray<void*> fields = new GenericArray<void*> ();
	internal LlvmDebugFrameField (CApi.TypeRef frame, CApi.TargetDataRef data, uint index) {
		this.frame = frame;
		this.data = data;
		this.index = index;
		packed = CApi.is_packed_struct (frame);
		for (uint i = 0; i < CApi.count_struct_element_types (frame); i++) {
			fields.add ((void*) CApi.struct_type_at_index (frame, i));
		}
		offset = CApi.offset_of_element (data, frame, index);
		extent = CApi.abi_size_of_type (data, CApi.struct_type_at_index (frame, index));
	}

	internal uint64 byte_offset { get { return offset; } }
	internal uint64 byte_size { get { return extent; } }
	internal void verify() throws LlvmError {
		if (CApi.is_packed_struct (frame) != packed || CApi.count_struct_element_types (frame) != fields.length || index >= fields.length) {
			throw new LlvmError.VERIFICATION ("debug async parameter lost its persistent frame layout");
		}
		for (uint i = 0; i < fields.length; i++) {
			if ((void*) CApi.struct_type_at_index (frame, i) != fields[i]) {
				throw new LlvmError.VERIFICATION ("debug async parameter lost its exact physical frame fields");
			}
		}
		if (CApi.offset_of_element (data, frame, index) != offset) {
			throw new LlvmError.VERIFICATION ("debug async parameter lost its persistent field offset");
		}
	}

}
// Independent physical/debug correspondence; no Source/SSA object retained.
internal class LlvmDebugRecord : Object {
	private CApi.MetadataRef metadata;
	private CApi.TypeRef storage;
	private CApi.TargetDataRef data;
	private string name;
	private CApi.MetadataRef[] members;
	private string[] names;
	private GenericArray<void*> fields = new GenericArray<void*> ();
	private int packed;
	private uint[] indices;
	internal LlvmDebugRecord (CApi.MetadataRef metadata, CApi.TypeRef storage, CApi.TargetDataRef data, string name, CApi.MetadataRef[] members, string[] names, uint[] selected) {
		this.metadata = metadata;
		this.storage = storage;
		this.data = data;
		this.name = name;
		this.members = members;
		this.names = names;
		indices = new uint[selected.length];
		for (int i = 0; i < selected.length; i++) {
			indices[i] = selected[i];
		}
		packed = CApi.is_packed_struct (storage);
		for (uint i = 0; i < CApi.count_struct_element_types (storage); i++) {
			fields.add ((void*) CApi.struct_type_at_index (storage, i));
		}
	}

	internal void verify() throws LlvmError {
		// Reject type-body changes before consulting LLVM's cached layouts;
		// an invalid mutation must not poison a restored type's layout cache.
		if (CApi.is_packed_struct (storage) != packed || CApi.count_struct_element_types (storage) != fields.length) {
			throw new LlvmError.VERIFICATION ("debug record lost its exact physical field count or packing");
		}
		for (uint i = 0; i < fields.length; i++) {
			if ((void*) CApi.struct_type_at_index (storage, i) != fields[i]) {
				throw new LlvmError.VERIFICATION ("debug record lost its exact physical field types");
			}
		}
		size_t length;
		if (CApi.di_type_name (metadata, out length) != name || CApi.di_type_size (metadata) != CApi.abi_size_of_type (data, storage) * 8 || CApi.di_type_alignment (metadata) != CApi.abi_alignment_of_type (data, storage) * 8 || indices.length != members.length || names.length != members.length) {
			throw new LlvmError.VERIFICATION ("debug record lost exact source name or physical size/alignment/member count");
		}
		for (uint i = 0; i < members.length; i++) {
			if (indices[i] >= fields.length) {
				throw new LlvmError.VERIFICATION ("debug source member lost its physical index");
			}
			var field = CApi.struct_type_at_index (storage, indices[i]);
			if ((void*) field != fields[indices[i]] || CApi.di_type_name (members[i], out length) != names[i] || CApi.di_type_offset (members[i]) != CApi.offset_of_element (data, storage, indices[i]) * 8 || CApi.di_type_size (members[i]) != CApi.abi_size_of_type (data, field) * 8 || CApi.di_type_alignment (members[i]) != CApi.abi_alignment_of_type (data, field) * 8) {
				throw new LlvmError.VERIFICATION ("debug record member lost exact source identity or physical type/offset/size/alignment");
			}
		}
	}

}
// Copied source coordinates and borrowed LLVM identities; no upstream IR graph.
internal class LlvmDebugScope : Object {
	internal CApi.ValueRef function;
	internal CApi.MetadataRef scope;
	internal CApi.MetadataRef file;
	internal string filename;
	internal string directory;
	internal bool sealed;
	internal HashTable<void*, void*> coordinates = new HashTable<void*, void*> (direct_hash, direct_equal);
	internal LlvmDebugScope (CApi.ValueRef function, CApi.MetadataRef scope, CApi.MetadataRef file, string filename, string directory) {
		this.function = function;
		this.scope = scope;
		this.file = file;
		this.filename = filename;
		this.directory = directory;
	}

}

internal class LlvmDebugInfo : Object {
	private CApi.ContextRef context;
	private CApi.DIBuilderRef builder;
	private bool finalized;
	private bool optimized;
	private bool has_compile_unit;
	private LlvmDebugScope? launch_scope;
	private CApi.MetadataRef launch_location;
	private GenericArray<LlvmDebugScope> scopes = new GenericArray<LlvmDebugScope> ();
	private HashTable<string, void*> files = new HashTable<string, void*> (str_hash, str_equal);
	private HashTable<void*, string> locations = new HashTable<void*, string> (direct_hash, direct_equal);
	private HashTable<string, void*> record_types = new HashTable<string, void*> (str_hash, str_equal);
	private GenericArray<LlvmDebugRecord> records = new GenericArray<LlvmDebugRecord> ();
	private GenericArray<LlvmDebugFrameField> frame_fields = new GenericArray<LlvmDebugFrameField> ();

	internal LlvmDebugInfo (LlvmModuleArtifact artifact, bool optimized) {
		context = artifact.context;
		this.optimized = optimized;
		CApi.set_new_debug_format (artifact.module, 1);
		builder = CApi.create_di_builder (artifact.module);
		// LLVMModuleFlagBehaviorWarning. The version comes from the linked LLVM.
		var version = CApi.const_int (CApi.int_type_in_context (context, 32), CApi.debug_metadata_version (), 0);
		CApi.add_module_flag (artifact.module, CApi.ModuleFlagBehavior.WARNING, "Debug Info Version", 18, CApi.value_as_metadata (version));
		var dwarf_version = CApi.const_int (CApi.int_type_in_context (context, 32), 4, 0);
		CApi.add_module_flag (artifact.module, CApi.ModuleFlagBehavior.WARNING, "Dwarf Version", 13, CApi.value_as_metadata (dwarf_version));
	}

	~LlvmDebugInfo () {
		CApi.dispose_di_builder (builder);
	}

	private static string absolute_path(SourceFile source) {
		// Preserve symlink/.. traversal exactly as it was read by SourceFile.
		return Path.is_absolute (source.path) ? source.path : Path.build_filename (Environment.get_current_dir (), source.path);
	}

	private CApi.MetadataRef file_for(SourceFile source) {
		string path = absolute_path (source);
		if (files.contains (path)) {
			return (CApi.MetadataRef) files.lookup (path);
		}
		string filename = Path.get_basename (path);
		string directory = Path.get_dirname (path);
		var file = CApi.di_file (builder, filename, filename.length, directory, directory.length);
		// C11 is the debugger expression dialect for the finite scalar profile;
		// the producer and real .astra file identify the actual source language.
		if (!has_compile_unit) {
			CApi.di_compile_unit (builder, CApi.DebugLanguage.C11, file, "Astra Stage 0", 13, optimized ? 1 : 0, "", 0, 0, "", 0, CApi.DebugEmission.FULL, 0, 0, 0, "", 0, "", 0);
			has_compile_unit = true;
		}
		files.insert (path, (void*) file);
		return file;
	}

	private CApi.MetadataRef scalar_type(SemanticType type) {
		uint bits, encoding;
		if (type is IntegerType) {
			bits = ((IntegerType) type).bit_width;
			encoding = ((IntegerType) type).is_signed ? 5 : 7;
		} else if (type is FloatingType) {
			bits = type.kind == TypeKind.F32 ? 32 : 64;
			encoding = 4;
		} else if (type.kind == TypeKind.BOOL) {
			bits = 8;
			encoding = 2;
		} else {
			return (CApi.MetadataRef) null;
		}
		string name = type.display_name ();
		return CApi.di_basic_type (builder, name, name.length, bits, encoding, 0);
	}

	private CApi.MetadataRef signature_type(SemanticType type, LlvmStructRegistry registry, LlvmModuleArtifact artifact) throws LlvmError {
		var scalar = value_type (type, registry, artifact);
		if ((void*) scalar != null || type.kind == TypeKind.VOID) {
			return scalar;
		}
		string name = type.display_name ();
		return CApi.di_unspecified_type (builder, name, name.length);
	}

	internal CApi.MetadataRef value_type(SemanticType type, LlvmStructRegistry registry, LlvmModuleArtifact artifact) throws LlvmError {
		var scalar = scalar_type (type);
		if ((void*) scalar != null) {
			return scalar;
		}
		var owner = registry.debug_class (type);
		if (owner == null) {
			return (CApi.MetadataRef) null;
		}
		var record = record_type (owner, registry, artifact);
		if ((void*) record == null) {
			return record;
		}
		var pointer = CApi.pointer_type_in_context (context, 0);
		var data = artifact.class_target.enum_target_data (artifact);
		return CApi.di_pointer_type (builder, record, CApi.abi_size_of_type (data, pointer) * 8, CApi.abi_alignment_of_type (data, pointer) * 8, 0, "", 0);
	}

	internal static bool scalar_parameter(SsaFunction source, int physical, out uint original) {
		int index = physical;
		foreach (var group in source.struct_parameters) {
			int end = group.first_leaf + (int) group.shape.leaves.length;
			if (physical >= group.first_leaf && physical < end) {
				original = 0;
				return false;
			}
			if (physical >= end) {
				index -= (int) group.shape.leaves.length - 1;
			}
		}
		foreach (var group in source.buffer_parameters) {
			if (physical >= group.first_leaf && physical < group.first_leaf + 2) {
				original = 0;
				return false;
			}
			if (physical >= group.first_leaf + 2) {
				index--;
			}
		}
		original = (uint) index;
		return true;
	}

	internal LlvmDebugScope function_scope(SsaFunction source, CApi.ValueRef function, LlvmStructRegistry registry, LlvmModuleArtifact artifact) throws LlvmError {
		var file = file_for (source.name_span.file);
		int line, column;
		source.name_span.file.locate (source.name_span.start, out line, out column);
		int count = (int) source.parameters.length;
		foreach (var group in source.struct_parameters) {
			count += 1 - (int) group.shape.leaves.length;
		}
		count -= (int) source.buffer_parameters.length;
		var parameters = new CApi.MetadataRef[count + 1];
		parameters[0] = signature_type (source.return_type, registry, artifact);
		for (int p = 0; p < source.parameters.length; p++) {
			uint ordinal;
			if (scalar_parameter (source, p, out ordinal)) {
				parameters[ordinal + 1] = signature_type (source.parameters[p].semantic_type, registry, artifact);
			}
		}
		foreach (var group in source.struct_parameters) {
			parameters[group.source_ordinal + 1] = signature_type (group.shape.semantic_type, registry, artifact);
		}
		foreach (var group in source.buffer_parameters) {
			parameters[group.source_ordinal + 1] = signature_type (group.cleanup.buffer_shape.slice_type, registry, artifact);
		}
		var type = CApi.di_subroutine_type (builder, file, parameters, parameters.length, 0);
		size_t length;
		string linkage = CApi.value_name (function, out length);
		var scope = CApi.di_function (builder, file, source.name, source.name.length, linkage, length, file, line, type, 1, 1, line, 0, optimized ? 1 : 0);
		CApi.set_subprogram (function, scope);
		string path = absolute_path (source.name_span.file);
		var binding = new LlvmDebugScope (function, scope, file, Path.get_basename (path), Path.get_dirname (path));
		scopes.add (binding);
		return binding;
	}

	internal void prepare_launch(SsaFunction source) throws LlvmError {
		var file = file_for (source.name_span.file);
		int line, column;
		source.name_span.file.locate (source.name_span.start, out line, out column);
		var parameters = new CApi.MetadataRef[1];
		parameters[0] = scalar_type (source.return_type);
		var type = CApi.di_subroutine_type (builder, file, parameters, 1, 0);
		var scope = CApi.di_function (builder, file, "main", 4, "main", 4, file, line, type, 0, 1, line, 0, optimized ? 1 : 0);
		string path = absolute_path (source.name_span.file);
		launch_scope = new LlvmDebugScope ((CApi.ValueRef) null, scope, file, Path.get_basename (path), Path.get_dirname (path));
		launch_location = location (launch_scope, source.name_span);
	}

	internal void attach_launch(CApi.ValueRef wrapper, CApi.BuilderRef instructions) {
		if (launch_scope == null) {
			return;
		}
		launch_scope.function = wrapper;
		CApi.set_subprogram (wrapper, launch_scope.scope);
		CApi.set_debug_location (instructions, launch_location);
		scopes.add (launch_scope);
	}

	private CApi.MetadataRef location(LlvmDebugScope scope, SourceSpan span) throws LlvmError {
		string path = absolute_path (span.file);
		if (Path.get_basename (path) != scope.filename || Path.get_dirname (path) != scope.directory) {
			throw new LlvmError.INVALID_INPUT ("debug location %s:%d differs from function source %s/%s".printf (path, span.start, scope.directory, scope.filename));
		}
		int line, column;
		span.file.locate (span.start, out line, out column);
		var result = CApi.di_location (context, line, column, scope.scope, (CApi.MetadataRef) null);
		locations.insert ((void*) result, "%u:%u".printf (line, column));
		return result;
	}

	internal void position(LlvmDebugScope scope, CApi.BuilderRef instructions, SourceSpan span) throws LlvmError {
		CApi.set_debug_location (instructions, location (scope, span));
	}

	internal void parameter(LlvmDebugScope scope, SsaFunctionParameter source, uint ordinal, CApi.ValueRef value, CApi.BuilderRef instructions, CApi.MetadataRef type) throws LlvmError {
		if ((void*) type == null) {
			return;
		}
		int line, column;
		source.name_span.file.locate (source.name_span.start, out line, out column);
		var variable = CApi.di_parameter (builder, scope.scope, source.name, source.name.length, ordinal + 1, scope.file, line, type, 1, 0);
		var expression = CApi.di_expression (builder, null, 0);
		var loc = location (scope, source.name_span);
		if (optimized) {
			CApi.di_value (builder, value, variable, expression, loc, CApi.insert_block (instructions));
		} else {
			var storage = CApi.build_alloca (instructions, CApi.type_of (value), "debug.parameter." + source.name);
			CApi.build_store (instructions, value, storage);
			CApi.di_declare (builder, storage, variable, expression, loc, CApi.insert_block (instructions));
		}
	}

	internal void frame_parameter(LlvmDebugScope scope, SsaFunctionParameter source, uint ordinal, CApi.ValueRef backing, CApi.TypeRef frame, uint index, CApi.BasicBlockRef block, CApi.MetadataRef type, LlvmModuleArtifact artifact) throws LlvmError {
		if ((void*) type == null || index == uint.MAX) {
			return;
		}
		if (artifact.class_target == null) {
			artifact.class_target = new LlvmTargetMachineArtifact (0, artifact.selected_target);
		}
		var binding = new LlvmDebugFrameField (frame, artifact.class_target.enum_target_data (artifact), index);
		frame_fields.add (binding);
		int line, column;
		source.name_span.file.locate (source.name_span.start, out line, out column);
		var variable = CApi.di_parameter (builder, scope.scope, source.name, source.name.length, ordinal + 1, scope.file, line, type, 1, 0);
		// DWARF plus_uconst, offset, deref_size, extent, stack_value. The tracked
		// value is the frame base; the Source parameter value lives in it.
		uint64[] operations = {
			0x23, binding.byte_offset, 0x94, binding.byte_size, 0x9f
		};
		CApi.di_value_before (builder, backing, variable, CApi.di_expression (builder, operations, operations.length), location (scope, source.name_span), CApi.block_terminator (block));
	}

	internal CApi.MetadataRef record_type(SsaNativeInstance source, LlvmStructRegistry registry, LlvmModuleArtifact artifact) throws LlvmError {
		var owner = source as SsaClass;
		if (owner != null && (owner.parent_class != null || owner.polymorphic)) {
			return (CApi.MetadataRef) null;
		}
		string key = absolute_path (source.name_span.file) + ":" + source.name;
		if (record_types.contains (key)) {
			return (CApi.MetadataRef) record_types.lookup (key);
		}
		if (source.fields.length <= 0 || source.fields.length > 128) {
			return (CApi.MetadataRef) null;
		}
		var fields = new CApi.MetadataRef[source.fields.length];
		for (int i = 0; i < fields.length; i++) {
			var field = source.fields[i];
			fields[i] = scalar_type (field.semantic_type);
			if ((void*) fields[i] == null) {
				var child = registry.debug_record (field.semantic_type);
				if (child != null) {
					fields[i] = record_type (child, registry, artifact);
				}
			}
			if ((void*) fields[i] == null || field.owned_cleanup != null) {
				return (CApi.MetadataRef) null;
			}
		}
		if (artifact.class_target == null) {
			artifact.class_target = new LlvmTargetMachineArtifact (0, artifact.selected_target);
		}
		var data = artifact.class_target.enum_target_data (artifact);
		var layout = registry.lookup (source);
		var file = file_for (source.name_span.file);
		var members = new CApi.MetadataRef[fields.length];
		string[] names = {};
		var indices = new uint[fields.length];
		for (uint i = 0; i < fields.length; i++) {
			var field = source.fields[i];
			int line, column;
			field.name_span.file.locate (field.name_span.start, out line, out column);
			uint index = registry.field_index (field);
			indices[i] = index;
			var physical = CApi.struct_type_at_index (layout, index);
			names += field.name;
			members[i] = CApi.di_member_type (builder, file, field.name, field.name.length, file_for (field.name_span.file), line, CApi.abi_size_of_type (data, physical) * 8, CApi.abi_alignment_of_type (data, physical) * 8, CApi.offset_of_element (data, layout, index) * 8, 0, fields[i]);
		}
		int line, column;
		source.name_span.file.locate (source.name_span.start, out line, out column);
		var metadata = CApi.di_struct_type (builder, file, source.name, source.name.length, file, line, CApi.abi_size_of_type (data, layout) * 8, CApi.abi_alignment_of_type (data, layout) * 8, 0, (CApi.MetadataRef) null, members, members.length, 0, (CApi.MetadataRef) null, key, key.length);
		record_types.insert (key, (void*) metadata);
		records.add (new LlvmDebugRecord (metadata, layout, data, source.name, members, names, indices));
		return metadata;
	}

	internal void local(LlvmDebugScope scope, SsaAddressableLocal source, CApi.ValueRef storage, CApi.BasicBlockRef block, CApi.MetadataRef aggregate = (CApi.MetadataRef) null) throws LlvmError {
		var type = (void*) aggregate == null ? scalar_type(source.semantic_type) : aggregate;
		if ((void*) type == null) {
			return;
		}
		int line, column;
		source.name_span.file.locate (source.name_span.start, out line, out column);
		var variable = CApi.di_local (builder, scope.scope, source.name, source.name.length, scope.file, line, type, 1, 0, 0);
		CApi.di_declare (builder, storage, variable, CApi.di_expression (builder, null, 0), location (scope, source.name_span), block);
	}

	internal void finish() {
		CApi.di_finalize (builder);
		finalized = true;
	}

	internal void verify() throws LlvmError {
		if (!finalized) {
			throw new LlvmError.VERIFICATION ("debug metadata must be finalized before verification");
		}
		foreach (var record in records) {
			record.verify ();
		}
		foreach (var field in frame_fields) {
			field.verify ();
		}
		foreach (var binding in scopes) {
			uint length;
			if ((void*) CApi.get_subprogram (binding.function) != (void*) binding.scope || (void*) CApi.di_scope_file (binding.scope) != (void*) binding.file || CApi.di_filename (binding.file, out length) != binding.filename || CApi.di_directory (binding.file, out length) != binding.directory) {
				throw new LlvmError.VERIFICATION ("debug subprogram lost exact source file identity");
			}
			for (var block = CApi.first_block (binding.function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					var loc = CApi.instruction_debug_location (instruction);
					if (binding.sealed && binding.coordinates.lookup ((void*) instruction) != (void*) loc) {
						throw new LlvmError.VERIFICATION ("debug instruction lost exact original source location");
					}
					if (!binding.sealed) {
						binding.coordinates.insert ((void*) instruction, (void*) loc);
					}
					if ((void*) loc == null) {
						continue;
					}
					string expected = "%u:%u".printf (CApi.di_location_line (loc), CApi.di_location_column (loc));
					if (locations.lookup ((void*) loc) != expected || (void*) CApi.di_location_scope (loc) != (void*) binding.scope) {
						throw new LlvmError.VERIFICATION ("debug instruction lost verified source coordinates/scope");
					}
				}
			}
			binding.sealed = true;
		}
	}

}
}
