// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Syntax;
using Astra.Semantic;
using Astra.Core;
using Astra.Cfg;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;
namespace Astra.Tests.ApplicationRuntime {
// Deliberately no Bag allocation in any user function: only formal receivers.
private SsaProgram program() throws GLib.Error {
	string template;
	FileUtils.get_contents ("lib/astra/collections/bag.astra", out template);
	var source = new SourceFile.from_text ("borrowed-only.astra", template + "\nclass Item{int n;init(int n){this.n=n;}}void add(Bag<Item> bag,owned Item value){bag.append(move value);}int count(Bag<Item> bag){return bag.count();}int main(){return 0;}");
	var files = new GenericArray<SourceFile> ();
	files.add (source);
	var syntax = SyntaxProgram.parse (new SourceSet (files));
	assert (syntax.diagnostic == null);
	var checked = SemanticAnalyzer.analyze_program (syntax.program);
	assert (checked.diagnostic == null);
	var core = CoreGenericMonomorphizer.build (CoreBuilder.build (checked.program));
	CoreVerifier.verify_concrete (core);
	var cfg = CfgBuilder.build (core);
	CfgVerifier.verify (cfg);
	var ssa = SsaBuilder.build (cfg);
	SsaVerifier.verify (ssa);
	return ssa;
}
private void borrowed_layout() {
	try {
		var s = program ();
		var native = NativeAbiBuilder.build (s);
		NativeAbiVerifier.verify (native);
		var artifact = LlvmLowering.lower (s, native, CAbiBuilder.build (s, native));
		artifact.verify ();
		assert (artifact.class_layouts.length >= 1 && artifact.class_addresses.length >= 1);
		var address = artifact.class_addresses[0].instruction;
		assert (CApi.opcode (address) == CApi.Opcode.GEP);
		var index = CApi.operand (address, 2);
		CApi.set_operand (address, 2, CApi.const_int (CApi.type_of (index), 1, 0));
		bool rejected = false;
		try {
			artifact.verify ();
		} catch (LlvmError error) {
			Test.message ("%s", error.message);
			rejected = true;
		}
		assert (rejected);
		CApi.set_operand (address, 2, index);
		artifact.verify ();
	} catch (GLib.Error error) {
		GLib.error ("%s", error.message);
	}
}
int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/application-runtime/borrowed-only-slots-layout-index-restored", borrowed_layout);
	return Test.run ();
}
}
