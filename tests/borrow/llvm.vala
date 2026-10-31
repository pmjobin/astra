// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Backend.LLVM;

namespace Astra.Tests.Borrows {
private LlvmModuleArtifact lower(SsaProgram ssa) throws GLib.Error {
	var nabi = NativeAbiBuilder.build (ssa);
	return LlvmLowering.lower (ssa, nabi, CAbiBuilder.build (ssa, nabi));
}

private void materialization(string name) throws GLib.Error {
	var ssa = build (fixture (name));
	var artifact = lower (ssa);
	artifact.verify ();
	string dump = artifact.dump ();
	int storage = 0;
	foreach (var function in ssa.functions) {
		storage += (int) function.storage.length;
	}
	assert (storage > 0 && dump.split (" = alloca ").length - 1 == storage);
	assert (!dump.contains ("alloca ptr") && dump.contains ("getelementptr"));
	assert (dump.contains ("load i32") && dump.contains ("store i32"));
	foreach (string forbidden in new string[] {"ptrtoint", "inttoptr", "malloc", "free", "retain", "release", "region", "borrow", "noalias", "nonnull ptr", "memcpy", "memmove", "undef", "poison"}) {
		assert (!dump.contains (forbidden));
	}
}

private void pointer_phis() throws GLib.Error {
	foreach (string name in new string[] {"borrow-branch", "borrow-null", "borrow-loop"}) {
		string dump = lower (build (fixture (name))).dump ();
		assert (dump.contains ("phi ptr"));
		assert (!dump.contains ("alloca ptr") && !dump.contains ("load ptr") && !dump.contains ("store ptr"));
		if (name == "borrow-null") {
			bool merged_null = false;
			foreach (string line in dump.split ("\n")) {
				if (line.contains ("phi ptr") && line.contains ("null")) {
					merged_null = true;
				}
			}
			assert (merged_null && dump.contains ("call void @llvm.trap()"));
		}
	}
}

private void llvm_lifetime() throws GLib.Error {
	SsaProgram? ssa = build (fixture ("borrow-alias"));
	var program_ref = WeakRef (ssa);
	var storage_ref = WeakRef (ssa.functions[1].storage[0]);
	var source_ref = WeakRef (ssa.span.file);
	var artifact = lower (ssa);
	ssa = null;
	assert (program_ref.get () == null && storage_ref.get () == null && source_ref.get () == null);
	artifact.verify ();
	assert (artifact.dump ().contains ("alloca %astra.struct.0"));
}

private int main(string[] args) {
	Test.init (ref args);
	cases = new HashTable<string, Case> (str_hash, str_equal);
	foreach (string fixture in new string[] {"basic", "copy", "reassign", "late", "branch", "null", "loop", "scopes", "recursive", "transitive", "alias", "mixed"}) {
		string name = "borrow-" + fixture;
		add ("/borrow/llvm/" + name, () => materialization (name));
	}
	add ("/borrow/llvm/pointer-phis", pointer_phis);
	add ("/borrow/llvm/lifetime", llvm_lifetime);
	int result = Test.run ();
	cases.remove_all ();
	return result;
}
}
