// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Hbaduel42Token is ERC20, Ownable {
    uint256 public constant UNIT = 10 ** 18;
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * UNIT;
    uint256 public constant MAX_SUPPLY = 10_000_000 * UNIT;

    error ExceedsMaximumSupply(uint256 exceededAmount, uint256 maxSupply);

    constructor(address initialOwner, address receiver) ERC20("Hbaduel42Token", "HFT") Ownable(initialOwner) {
        _mint(receiver, INITIAL_SUPPLY);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        uint256 newTotalSupply = totalSupply() + amount;
        if (newTotalSupply > MAX_SUPPLY) {
            revert ExceedsMaximumSupply(newTotalSupply - MAX_SUPPLY, MAX_SUPPLY);
        }
        _mint(to, amount);
    }
}
