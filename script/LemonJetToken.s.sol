// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {LemonJetToken} from "../src/LemonJetToken.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployLemonJetToken is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address recipient = vm.envOr("TOKEN_RECIPIENT", deployer);
        address initialOwner = vm.envOr("TOKEN_OWNER", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        LemonJetToken implementation = new LemonJetToken();

        // Deploy proxy with initialization
        bytes memory initData = abi.encodeCall(
            LemonJetToken.initialize,
            (recipient, initialOwner)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        console2.log("LemonJetToken implementation deployed at:", address(implementation));
        console2.log("LemonJetToken proxy deployed at:", address(proxy));
        console2.log("Recipient:", recipient);
        console2.log("Owner:", initialOwner);

        vm.stopBroadcast();
    }
}
