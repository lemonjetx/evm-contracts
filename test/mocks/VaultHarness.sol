// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Vault} from "../../src/Vault.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @dev Test harness for Vault that provides an initializer entry point
contract VaultHarness is Vault {
    function initialize(
        IERC20 _asset,
        address _reserveFund,
        string memory _name,
        string memory _symbol
    ) public override initializer {
        super.initialize(_asset, _reserveFund, _name, _symbol);
    }
}
