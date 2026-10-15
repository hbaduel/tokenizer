// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {Script, console} from "forge-std/Script.sol";
import {Hbaduel42Token} from "../code/Hbaduel42Token.sol";
import {MultiSig42} from "../code/MultiSig42.sol";

contract DeployHbaduel42Token is Script {
    function run(bool useMultiSig) external returns (Hbaduel42Token) {
        if (useMultiSig) {
            return deployWithMultiSig();
        } else {
            return deployWithoutMultiSig();
        }
    }

    function deployWithoutMultiSig() internal returns (Hbaduel42Token) {
        address owner = vm.envAddress("OWNER_ADDRESS");
        address receiver = vm.envAddress("RECEIVER_ADDRESS");

        vm.startBroadcast();
        Hbaduel42Token token = new Hbaduel42Token(owner, receiver);
        vm.stopBroadcast();

        console.log("Hbaduel42Token deployed at:", address(token));
        return token;
    }

    function deployWithMultiSig() internal returns (Hbaduel42Token) {
        address[] memory owners = vm.envAddress("OWNERS_ADDRESSES", ",");
        uint256 nbConfirmationsRequired = vm.envUint("NB_CONFIRMATIONS_REQUIRED");

        vm.startBroadcast();
        MultiSig42 multiSig = new MultiSig42(owners, nbConfirmationsRequired);
        Hbaduel42Token token = new Hbaduel42Token(address(multiSig), address(multiSig));
        vm.stopBroadcast();

        console.log("MultiSig42 deployed at:", address(multiSig));
        console.log("Hbaduel42Token deployed at:", address(token));
        return token;
    }
}
