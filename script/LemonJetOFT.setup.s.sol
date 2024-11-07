// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {LemonJetOFT} from "../src/LemonJetOFT.sol";

contract SetupLemonJetOFT is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        LemonJetOFT oft = LemonJetOFT(vm.envAddress("OFT_ADDRESS_B"));
        address bOFT = vm.envAddress("OFT_ADDRESS_A");
        uint32 bEid = uint32(vm.envUint("LZ_EID_A"));
        vm.startBroadcast(deployerPrivateKey);
        oft.setPeer(bEid, addressToBytes32(address(bOFT)));
        vm.stopBroadcast();
    }

    function addressToBytes32(address _addr) public pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
