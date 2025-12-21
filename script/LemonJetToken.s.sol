// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {LemonJetToken} from "../src/LemonJetToken.sol";

contract DeployLemonJetToken is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address recipient = vm.envOr("TOKEN_RECIPIENT", deployer);
        address initialOwner = vm.envOr("TOKEN_OWNER", deployer);

        vm.startBroadcast(deployerPrivateKey);

        LemonJetToken token = new LemonJetToken(recipient, initialOwner);

        console2.log("LemonJetToken deployed at:", address(token));
        console2.log("Recipient:", recipient);
        console2.log("Owner:", initialOwner);

        vm.stopBroadcast();
    }
}
