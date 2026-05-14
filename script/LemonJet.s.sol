// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {LemonJet} from "../src/LemonJet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LemonJetDeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address reserveFund = vm.envAddress("RESERVE_FUND_ADDRESS");
        address vrfWrapper = vm.envAddress("VRF_WRAPPER_ADDRESS");
        address vaultToken = vm.envAddress("VAULT_TOKEN_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        LemonJet lemonJet = new LemonJet(vrfWrapper, reserveFund, IERC20(vaultToken), "LemonJet Vault", "LJUSDC");

        console2.log("LemonJet deployed at:", address(lemonJet));

        vm.stopBroadcast();
    }
}
