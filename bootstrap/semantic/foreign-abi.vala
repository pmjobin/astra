// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Semantic {
public class ComImportTypes : Object {
	public static bool valid(Astra.Foreign.CForeignMetadata metadata, SemanticType result, SemanticType[] arguments, PointerParameterContract[] contracts, string cleanup) {
		if (!metadata.valid_com ()) {
			return false;
		}
		var com = metadata.com_import;
		if (com == null) {
			if (metadata.gobject_carrier != "") {
				var carrier = arguments.length == 1 ? arguments[0] as HandleType : null;
				var resource = result as HandleType;
				return metadata.import_policy_valid () && carrier != null && carrier.name == metadata.gobject_carrier && carrier.foreign_policy_identity.has_prefix ("GObjectImport;declarations-v1;") && contracts.length == 1 && contracts[0] == PointerParameterContract.BORROWED_NOESCAPE && resource != null && resource.foreign_policy_identity == "" && cleanup != "";
			}
			if (result is HandleType && ((HandleType) result).foreign_policy_identity != "") {
				return false;
			}
			foreach (var type in arguments) {
				if (type is HandleType && ((HandleType) type).foreign_policy_identity != "") {
					return false;
				}
			}
			return true;
		}
		var role = metadata.com_role;
		if (arguments.length != (role == Astra.Source.ComImportRole.SCALE ? 3 : 2) || contracts.length != arguments.length || contracts[0] != PointerParameterContract.BORROWED_NOESCAPE) {
			return false;
		}
		if (metadata.com_owner_result) {
			if (!(result is HandleType) || ((HandleType) result).foreign_policy_identity != com.identity () || cleanup != com.prefix + "_release") {
				return false;
			}
		} else if (result.kind != TypeKind.INT || cleanup != "") {
			return false;
		}
		if (role == Astra.Source.ComImportRole.ACQUIRE) {
			if (!(arguments[0] is RawPointerType)) {
				return false;
			}
		} else if (!(arguments[0] is HandleType) || ((HandleType) arguments[0]).foreign_policy_identity != com.identity ()) {
			return false;
		}
		if (role == Astra.Source.ComImportRole.SET || role == Astra.Source.ComImportRole.SCALE) {
			if (arguments[1].kind != TypeKind.INT || contracts[1] != PointerParameterContract.UNMANAGED) {
				return false;
			}
		}
		if (role != Astra.Source.ComImportRole.SET && (!CPlainRecordTypes.i32_pointer (arguments[arguments.length - 1]) || contracts[contracts.length - 1] != PointerParameterContract.BORROWED_NOESCAPE)) {
			return false;
		}
		return true;
	}

}
// Foreign declaration contract; never native semantic type authority.
public enum ForeignAbi {
	C
}

}
