// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.5.0
pragma solidity ^0.8.28;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

contract LemonJetTokenUpgradeable is
    Initializable,
    ERC20Upgradeable,
    OwnableUpgradeable,
    ERC20PermitUpgradeable,
    UUPSUpgradeable
{
    error AlreadyMinted();

    uint256 public mintAmount;
    mapping(address => uint256) public minted;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address recipient, address initialOwner, uint256 _mintAmount) public initializer {
        __ERC20_init("LemonJetToken", "LJT");
        __Ownable_init(initialOwner);
        __ERC20Permit_init("LemonJetToken");

        _mint(recipient, 1_000_000_000 * 10 ** decimals());
        mintAmount = _mintAmount;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function mint() public {
        uint256 alreadyMinted = minted[msg.sender];
        require(alreadyMinted < mintAmount, AlreadyMinted());

        uint256 amountToMint = mintAmount - alreadyMinted;
        minted[msg.sender] = mintAmount;
        _mint(msg.sender, amountToMint);
    }

    function setMintAmount(uint256 _mintAmount) public onlyOwner {
        mintAmount = _mintAmount;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
