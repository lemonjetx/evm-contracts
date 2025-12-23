// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {LemonJetUpgradeable} from "../src/LemonJetUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LemonJetDeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address reserveFund = vm.envAddress("RESERVE_FUND_ADDRESS");
        address vrfWrapper = vm.envAddress("VRF_WRAPPER_ADDRESS");
        address vaultToken = vm.envAddress("VAULT_TOKEN_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy a UUPS proxy with the LemonJetUpgradeable implementation
        address proxy = Upgrades.deployUUPSProxy(
            "LemonJetUpgradeable.sol:LemonJetUpgradeable",
            abi.encodeCall(
                LemonJetUpgradeable.initialize,
                (vrfWrapper, reserveFund, IERC20(vaultToken), "LemonJet Vault", "LJUSDC")
            )
        );

        console2.log("LemonJetUpgradeable UUPS proxy deployed at:", proxy);

        vm.stopBroadcast();
    }
}
