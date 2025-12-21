// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {LemonJetToken} from "../src/LemonJetToken.sol";

contract UpgradeLemonJetToken is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        LemonJetToken newImplementation = new LemonJetToken();

        // Upgrade proxy to new implementation
        LemonJetToken proxy = LemonJetToken(proxyAddress);
        proxy.upgradeToAndCall(address(newImplementation), "");

        console2.log("New implementation deployed at:", address(newImplementation));
        console2.log("Proxy upgraded:", proxyAddress);

        vm.stopBroadcast();
    }
}


