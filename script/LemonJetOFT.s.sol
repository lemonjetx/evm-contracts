// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {LemonJetOFT} from "../src/LemonJetOFT.sol";

contract DeployLemonJetOFT is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address lzEndpoint = vm.envAddress("LZ_ENDPOINT_ADDRESS");
        vm.startBroadcast(deployerPrivateKey);
        LemonJetOFT oft = new LemonJetOFT("Lemon Jet", "LJT", lzEndpoint, vm.addr(deployerPrivateKey));
        vm.stopBroadcast();
    }
}
