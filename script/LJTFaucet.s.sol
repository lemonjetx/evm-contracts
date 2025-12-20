// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {LJTFaucet} from "../src/LJTFaucet.sol";

contract DeployLJTFaucet is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address tokenAddress = vm.envAddress("LJT_TOKEN_ADDRESS");
        address owner = vm.envOr("FAUCET_OWNER", deployer);

        vm.startBroadcast(deployerPrivateKey);

        LJTFaucet faucet = new LJTFaucet(tokenAddress, owner);

        console2.log("LJTFaucet deployed at:", address(faucet));
        console2.log("Token:", tokenAddress);
        console2.log("Owner:", owner);

        vm.stopBroadcast();
    }
}

