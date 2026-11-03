// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Semantic;

namespace Astra.Tests.LifecycleInitialization {
private void lattice() {
	var empty = new FieldInitializationState (2);
	assert (!empty.is_definite (0) && !empty.is_possible (0));
	var left = empty.copy ();
	left.initialize (0);
	var right = empty.copy ();
	right.initialize (1);
	var join = FieldInitializationState.join (left, right);
	assert (!join.is_definite (0) && !join.is_definite (1) && join.is_possible (0) && join.is_possible (1));
	right.initialize (0);
	join = FieldInitializationState.join (left, right);
	assert (join.is_definite (0) && !join.is_definite (1) && join.is_possible (1));
	left.reachable = false;
	assert (FieldInitializationState.join (left, right).same_as (right));
	right.reachable = false;
	join = FieldInitializationState.join (left, right);
	assert (!join.reachable && join.is_definite (0) && join.is_definite (1));
}

int main(string[] args) {
	Test.init (ref args);
	Test.add_func ("/obj-life/init-analysis/definite-possible-join-and-unreachable", lattice);
	return Test.run ();
}

}
