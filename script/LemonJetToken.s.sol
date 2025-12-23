// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {LemonJetTokenUpgradeable} from "../src/LemonJetTokenUpgradeable.sol";

contract DeployLemonJetToken is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address recipient = vm.envOr("TOKEN_RECIPIENT", deployer);
        address initialOwner = vm.envOr("TOKEN_OWNER", deployer);
        uint256 mintAmount = vm.envOr("TOKEN_MINT_AMOUNT", uint256(0));

        vm.startBroadcast(deployerPrivateKey);

        address proxy = Upgrades.deployUUPSProxy(
            "LemonJetTokenUpgradeable.sol:LemonJetTokenUpgradeable",
            abi.encodeCall(LemonJetTokenUpgradeable.initialize, (recipient, initialOwner, mintAmount))
        );

        console2.log("LemonJetTokenUpgradeable UUPS proxy deployed at:", proxy);
        console2.log("Recipient:", recipient);
        console2.log("Owner:", initialOwner);
        console2.log("Mint amount:", mintAmount);

        vm.stopBroadcast();
    }
}
