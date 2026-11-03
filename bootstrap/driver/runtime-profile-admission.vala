// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;
using Astra.Backend.LLVM;

namespace Astra.Driver {
// Checked admission belongs to the driver. The standalone LLVM backend
// rechecks its own SSA/physical authorities without depending on Checked.
internal class RuntimeProfileAdmission : Object {
	private static void reject_windows(string detail) throws LlvmError {
		throw new LlvmError.TARGET ("Windows interop object profile: unsupported %s", detail);
	}

	private static void reject_none(string detail) throws LlvmError {
		throw new LlvmError.INVALID_INPUT ("runtime none: unsupported source requirement: %s", detail);
	}

	public static void windows(CheckedProgram program, bool explicit_declarations = false) throws LlvmError {
		bool declared = false;
		foreach (var owner in program.classes) {
			declared |= owner.foreign_export != null && owner.foreign_export.declared_api != null;
		}
		foreach (var handle in program.handles) {
			declared |= handle.c_import != null;
		}
		if (declared || explicit_declarations) {
			windows_declarations (program);
			return;
		}
		if (program.structs.length != 0 || program.enums.length != 0 || program.generic_classes.length != 0 || program.generic_structs.length != 0 || program.generic_functions.length != 0) {
			reject_windows ("records, resources, enums or generic definitions");
		}
		foreach (var handle in program.handles) {
			LlvmWindowsInteropProfile.require_value (handle.semantic_type);
		}
		foreach (var constant in program.constants) {
			LlvmWindowsInteropProfile.require_value (constant.semantic_type);
		}
		foreach (var owner in program.classes) {
			LlvmWindowsInteropProfile.require_value (owner.semantic_type);
			if (owner.parent_class != null || owner.polymorphic || owner.exception_root || owner.allocation_policy != null) {
				reject_windows ("Class inheritance, exception or allocation policy");
			}
			foreach (var field in owner.fields) {
				if (field.is_owned_field) {
					reject_windows ("owning Class field");
				}
				LlvmWindowsInteropProfile.require_value (field.semantic_type);
			}
			foreach (var property in owner.properties) {
				if (property.is_lazy) {
					reject_windows ("lazy property");
				}
				LlvmWindowsInteropProfile.require_value (property.semantic_type);
			}
		}
		foreach (var imported in program.c_functions) {
			LlvmWindowsInteropProfile.require_metadata (imported.metadata);
			LlvmWindowsInteropProfile.require_value (imported.return_type);
			foreach (var parameter in imported.parameters) {
				LlvmWindowsInteropProfile.require_value (parameter.semantic_type);
			}
		}
		foreach (var function in program.functions) {
			if (function.symbol.async_body != null || function.symbol.throws_type != null) {
				reject_windows ("async or native throws");
			}
			LlvmWindowsInteropProfile.require_value (function.symbol.return_type);
			foreach (var parameter in function.symbol.parameters) {
				LlvmWindowsInteropProfile.require_value (parameter.semantic_type);
			}
			foreach (var local in function.locals) {
				LlvmWindowsInteropProfile.require_value (local.semantic_type);
			}
		}
	}

	private static void windows_declarations(CheckedProgram program) throws LlvmError {
		if (program.enums.length != 0) {
			reject_windows ("declarations-v1 enum storage");
		}
		foreach (var handle in program.handles) {
			LlvmWindowsInteropProfile.require_declared_value (handle.semantic_type);
		}
		foreach (var constant in program.constants) {
			LlvmWindowsInteropProfile.require_declared_value (constant.semantic_type);
		}
		foreach (var structure in program.structs) {
			foreach (var field in structure.fields) {
				LlvmWindowsInteropProfile.require_declared_value (field.semantic_type);
			}
		}
		foreach (var owner in program.classes) {
			LlvmWindowsInteropProfile.require_declared_value (owner.semantic_type);
			if (owner.allocation_policy != null) {
				reject_windows ("declarations-v1 allocation policy");
			}
			foreach (var field in owner.fields) {
				LlvmWindowsInteropProfile.require_declared_value (field.semantic_type);
			}
			foreach (var property in owner.properties) {
				LlvmWindowsInteropProfile.require_declared_value (property.semantic_type);
			}
		}
		foreach (var imported in program.c_functions) {
			LlvmWindowsInteropProfile.require_metadata (imported.metadata);
			LlvmWindowsInteropProfile.require_declared_value (imported.return_type);
			foreach (var parameter in imported.parameters) {
				LlvmWindowsInteropProfile.require_declared_value (parameter.semantic_type);
			}
		}
		foreach (var function in program.functions) {
			if (function.symbol.async_body != null) {
				reject_windows ("declarations-v1 async");
			}
			LlvmWindowsInteropProfile.require_declared_value (function.symbol.return_type);
			foreach (var parameter in function.symbol.parameters) {
				LlvmWindowsInteropProfile.require_declared_value (parameter.semantic_type);
			}
			foreach (var local in function.locals) {
				LlvmWindowsInteropProfile.require_declared_value (local.semantic_type);
			}
		}
	}

	public static void none(LlvmRuntimeProfile profile, CheckedProgram program) throws LlvmError {
		if (profile.target == LlvmTargetMachineArtifact.PC_BARE_METAL) {
			foreach (var exported in program.c_exports) {
				if (exported.external_symbol != "astra_trap_handler") {
					continue;
				}
				var handler = exported.target;
				if (handler == null || handler.return_type.kind != TypeKind.INT || handler.parameters.length != 2 || handler.parameters[0].semantic_type.kind != TypeKind.INT || handler.parameters[1].semantic_type.kind != TypeKind.INT || handler.throws_type != null || handler.async_body != null) {
					reject_none ("PC trap handler requires exact nonthrowing int(int,int) C export");
				}
			}
		}
		profile.local_classes.remove_all ();
		foreach (var owner in program.classes) {
			if (profile.target != LlvmTargetMachineArtifact.PC_BARE_METAL || owner.polymorphic || owner.parent_class != null || owner.exception_root || ((ClassType) owner.semantic_type).is_interface || owner.generic_instance != null) {
				reject_none ("unqualified Class layout or lifecycle");
			}
			profile.local_classes.insert (owner.semantic_type, true);
		}
		foreach (var owner in program.classes) {
			foreach (var field in owner.fields) {
				if (!profile.value_type (field.semantic_type)) {
					reject_none ("Class field " + field.name);
				}
			}
		}
		foreach (var imported in program.c_functions) {
			if (profile.target != LlvmTargetMachineArtifact.PC_BARE_METAL || imported.metadata.device == null || !imported.metadata.device.valid ()) {
				reject_none ("unqualified external provider");
			}
		}
		if (program.handles.length != 0 || program.enums.length != 0 || program.generic_classes.length != 0 || program.generic_structs.length != 0 || program.generic_functions.length != 0) {
			reject_none ("classes, resources, providers, enums and generic definitions require hosted runtime");
		}
		foreach (var structure in program.structs) {
			foreach (var field in structure.fields) {
				if (!profile.value_type (field.semantic_type)) {
					reject_none ("record field " + field.name);
				}
			}
		}
		foreach (var constant in program.constants) {
			if (!profile.value_type (constant.semantic_type)) {
				reject_none ("constant " + constant.name);
			}
		}
		foreach (var function in program.functions) {
			if (!profile.value_type (function.symbol.return_type)) {
				reject_none ("function " + function.symbol.name);
			}
			foreach (var parameter in function.symbol.parameters) {
				if (!profile.value_type (parameter.semantic_type)) {
					reject_none ("parameter " + parameter.name);
				}
			}
			foreach (var local in function.locals) {
				if (!profile.value_type (local.semantic_type, true)) {
					reject_none ("local " + local.name);
				}
			}
		}
	}

}
}
