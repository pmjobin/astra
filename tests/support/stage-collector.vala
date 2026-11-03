// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Test-only hosted pipeline observation. Each dump is materialized before the
// next builder can mutate its input. This is not a public compiler option.
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

private SourceFile read_source(string path) throws FileError {
	uint8[] bytes;
	FileUtils.get_data(path, out bytes);
	return new SourceFile(path, (owned) bytes);
}

private void save(string directory, string stage, string data) throws FileError {
	FileUtils.set_contents(Path.build_filename(directory, stage), data);
}

private int collect(string[] args) throws GLib.Error {
	assert(args.length >= 3);
	string directory = args[1];
	string[] paths = new string[0];
	var vapis = new GenericArray<string>();
	for (int i = 2; i < args.length; i++) {
		if (args[i] == "--vapi") {
			assert(i + 1 < args.length);
			vapis.add(args[++i]);
		} else {
			assert(!args[i].has_prefix("--"));
			paths += args[i];
		}
	}
	var sources = new GenericArray<SourceFile>();
	foreach (string path in SourceSet.canonical_paths(paths)) {
		sources.add(read_source(path));
	}
	var parsed = SyntaxProgram.parse(new SourceSet(sources));
	if (parsed.diagnostic != null) {
		stderr.printf("%s\n", parsed.diagnostic.format());
		return 1;
	}
	save(directory, "syntax", SyntaxDump.format_program(parsed.program));
	var foreign = new GenericArray<ForeignDeclarationInput>();
	var handles = new GenericArray<ForeignHandleInput>();
	foreach (string path in vapis) {
		var input = Astra.Vapi.VapiParser.parse(read_source(path));
		if (input.diagnostic != null) {
			stderr.printf("%s\n", input.diagnostic.format());
			return 1;
		}
		foreach (var item in Astra.Vapi.VapiNormalizer.normalize(input.file)) {
			foreign.add(item);
		}
		foreach (var item in Astra.Vapi.VapiNormalizer.normalize_handles(input.file)) {
			handles.add(item);
		}
	}
	var checked = SemanticAnalyzer.analyze_program(parsed.program, foreign, handles);
	parsed = null;
	sources = null;
	if (checked.diagnostic != null) {
		stderr.printf("%s\n", checked.diagnostic.format());
		return 1;
	}
	save(directory, "semantics", SemanticDump.format(checked.program));
	var core = CoreBuilder.build(checked.program);
	checked = null;
	save(directory, "core", CoreDump.format(core));
	core = CoreGenericMonomorphizer.build(core);
	save(directory, "instances", CoreDump.format(core));
	var cfg = CfgBuilder.build(core);
	var flow = CfgFlowChecker.check(cfg);
	if (flow.diagnostic != null) {
		stderr.printf("%s\n", flow.diagnostic.format());
		return 1;
	}
	save(directory, "cfg", CfgDump.format(cfg));
	var ssa = SsaBuilder.build(cfg);
	save(directory, "ssa", SsaDump.format(ssa, Environment.get_variable("ASTRA_EXPLAIN_OPTIMIZATIONS") == "1"));
	var nabi = NativeAbiBuilder.build(ssa);
	save(directory, "nabi", NativeAbiDump.format(nabi));
	var cabi = CAbiBuilder.build(ssa, nabi);
	save(directory, "cabi", CAbiDump.format(cabi));
	var llvm = LlvmLowering.lower(ssa, nabi, cabi);
	llvm.verify();
	save(directory, "llvm", llvm.dump());
	return 0;
}

int main(string[] args) {
	try {
		return collect(args);
	} catch (GLib.Error error) {
		stderr.printf("%s\n", error.message);
		return 1;
	}
}
