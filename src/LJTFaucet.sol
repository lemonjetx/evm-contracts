// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract LJTFaucet is Ownable {

    IERC20 public immutable token;
    uint256 public claimAmount = 1000 * 10 ** 18;

    mapping(address => uint256) public claimed;

    event Claimed(address indexed user, uint256 amount);
    event ClaimAmountUpdated(uint256 oldAmount, uint256 newAmount);

    error AlreadyClaimed();

    constructor(address _token, address _owner) Ownable(_owner) {
        token = IERC20(_token);
    }

    function setClaimAmount(uint256 _claimAmount) external onlyOwner {
        uint256 oldAmount = claimAmount;
        claimAmount = _claimAmount;
        emit ClaimAmountUpdated(oldAmount, _claimAmount);
    }

    function claim() external {
        if (claimed[msg.sender] != 0) revert AlreadyClaimed();

        claimed[msg.sender] += claimAmount;
        token.transfer(msg.sender, claimAmount);

        emit Claimed(msg.sender, claimAmount);
    }

    function withdraw(address to, uint256 amount) external onlyOwner {
        token.transfer(to, amount);
    }
}

