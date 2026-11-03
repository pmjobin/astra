// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.CAbi;
using Astra.NativeAbi;

namespace Astra.Tests.CImports {
private const string MALFORMED_EXPORT = "extern(C) int imported(); export(C) int f() { return 0; } bool b() { return true; } int p(bool x) { return 0; }";

private void malformed_core_exports() throws GLib.Error {
	for (int mode = 0; mode < 9; mode++) {
		var program = CoreBuilder.build (check (MALFORMED_EXPORT));
		CoreProgram? other = CoreBuilder.build (check (MALFORMED_EXPORT));
		var old = program.c_exports[0];
		CoreFunction? target = mode < 2 ? other.functions[0] : mode == 6 ? program.functions[1] : mode == 7 ? program.functions[2] : program.functions[0];
		string symbol = mode == 2 ? "" : mode == 3 ? "imported" : "f";
		program.c_exports[0] = new CoreCExport (old.span, old.name_span, target, symbol, mode == 4 ? (ForeignAbi) 99 : ForeignAbi.C, mode == 5 ? -1 : 0);
		target = null;
		if (mode == 1) {
			other = null;
			assert (program.c_exports[0].target == null);
		}
		if (mode == 8) {
			program.c_exports.add (new CoreCExport (old.span, old.name_span, program.functions[0], "f", ForeignAbi.C, 1));
		}
		// Symbol collisions are physical CABI errors, not malformed upstream IR.
		if (mode == 3 || mode == 8) {
			reject_export_collision (SsaBuilder.build (CfgBuilder.build (program)));
			continue;
		}
		string? previous = null;
		for (int attempt = 0; attempt < 2; attempt++) {
			try {
				CoreVerifier.verify (program);
				assert_not_reached ();
			} catch (CoreError.INVALID_IR error) {
				assert (error.message.contains ("C export") && (previous == null || previous == error.message));
				previous = error.message;
			}
		}
	}
}

private void malformed_cfg_exports() throws GLib.Error {
	for (int mode = 0; mode < 9; mode++) {
		var program = CfgBuilder.build (CoreBuilder.build (check (MALFORMED_EXPORT)));
		CfgProgram? other = CfgBuilder.build (CoreBuilder.build (check (MALFORMED_EXPORT)));
		var old = program.c_exports[0];
		CfgFunction? target = mode < 2 ? other.functions[0] : mode == 6 ? program.functions[1] : mode == 7 ? program.functions[2] : program.functions[0];
		string symbol = mode == 2 ? "" : mode == 3 ? "imported" : "f";
		program.c_exports[0] = new CfgCExport (old.span, old.name_span, target, symbol, mode == 4 ? (ForeignAbi) 99 : ForeignAbi.C, mode == 5 ? -1 : 0);
		target = null;
		if (mode == 1) {
			other = null;
			assert (program.c_exports[0].target == null);
		}
		if (mode == 8) {
			program.c_exports.add (new CfgCExport (old.span, old.name_span, program.functions[0], "f", ForeignAbi.C, 1));
		}
		// Symbol collisions are physical CABI errors, not malformed upstream IR.
		if (mode == 3 || mode == 8) {
			reject_export_collision (SsaBuilder.build (program));
			continue;
		}
		string? previous = null;
		for (int attempt = 0; attempt < 2; attempt++) {
			try {
				CfgVerifier.verify (program);
				assert_not_reached ();
			} catch (CfgError.INVALID_CFG error) {
				assert (error.message.contains ("C export") && (previous == null || previous == error.message));
				previous = error.message;
			}
		}
	}
}

private void malformed_ssa_exports() throws GLib.Error {
	for (int mode = 0; mode < 9; mode++) {
		var program = build (MALFORMED_EXPORT);
		SsaProgram? other = build (MALFORMED_EXPORT);
		var old = program.c_exports[0];
		SsaFunction? target = mode < 2 ? other.functions[0] : mode == 6 ? program.functions[1] : mode == 7 ? program.functions[2] : program.functions[0];
		string symbol = mode == 2 ? "" : mode == 3 ? "imported" : "f";
		program.c_exports[0] = new SsaCExport (old.span, old.name_span, target, symbol, mode == 4 ? (ForeignAbi) 99 : ForeignAbi.C, mode == 5 ? -1 : 0);
		target = null;
		if (mode == 1) {
			other = null;
			assert (program.c_exports[0].target == null);
		}
		if (mode == 8) {
			program.c_exports.add (new SsaCExport (old.span, old.name_span, program.functions[0], "f", ForeignAbi.C, 1));
		}
		// Symbol collisions are physical CABI errors, not malformed upstream IR.
		if (mode == 3 || mode == 8) {
			reject_export_collision (program);
			continue;
		}
		string? previous = null;
		for (int attempt = 0; attempt < 2; attempt++) {
			try {
				SsaVerifier.verify (program);
				assert_not_reached ();
			} catch (SsaError.INVALID_SSA error) {
				assert (error.message.contains ("C export") && (previous == null || previous == error.message));
				previous = error.message;
			}
		}
		try {
			CAbiBuilder.build (program, NativeAbiBuilder.build (build (MALFORMED_EXPORT)));
			assert_not_reached ();
		} catch (CAbiError.INVALID_SSA error) {
			assert (error.message.contains ("C export"));
		}
	}
}

private void reject_export_collision(SsaProgram program) throws GLib.Error {
	SsaVerifier.verify (program);
	var nabi = NativeAbiBuilder.build (program);
	try {
		CAbiBuilder.build (program, nabi);
		assert_not_reached ();
	} catch (CAbiError.DUPLICATE_SYMBOL error) {
		assert (error.message.contains ("C external symbol") && error.message.contains ("is declared more than once"));
	}
}

private void register_export_malformed() {
	add ("/cexport/core-malformed", malformed_core_exports);
	add ("/cexport/cfg-malformed", malformed_cfg_exports);
	add ("/cexport/ssa-malformed", malformed_ssa_exports);
}

}
