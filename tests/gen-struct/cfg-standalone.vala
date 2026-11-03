// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Core;
using Astra.Cfg;
using Astra.Semantic;
namespace Astra.Tests.GenStructCore {
private void boundary() {
	try {
		var unresolved = sample ();
		bool rejected = false;
		try {
			CfgBuilder.build (unresolved);
		} catch (CfgError error) {
			rejected = error.message.contains ("before CFG");
		}
		assert (rejected);
		CoreProgram? core = CoreGenericMonomorphizer.build (sample (true));
		var witness = WeakRef (core.structs[0]);
		var field_witness = WeakRef (core.structs[0].fields[0]);
		var cfg = CfgBuilder.build (core);
		core = null;
		assert (witness.get () == null && field_witness.get () == null);
		CfgVerifier.verify (cfg);
		foreach (var structure in cfg.structs) {
			assert (structure.semantic_type is StructType);
			foreach (var field in structure.fields) {
				assert (field.semantic_type.kind != TypeKind.GENERIC_STRUCT_APPLICATION && !(field.semantic_type is TypeParameterType));
			}
		}
		var forged = CoreGenericMonomorphizer.build (sample ());
		forged.functions[0].locals[0].semantic_type = unresolved.functions[0].locals[0].semantic_type;
		rejected = false;
		try {
			CfgBuilder.build (forged);
		} catch (CfgError error) {
			rejected = error.message.contains ("unresolved generic aggregate");
		}
		assert (rejected);
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/gen-struct/cfg/materialized-only-malformed-model-firewall-lifetime", boundary);
	return Test.run ();
}

}
