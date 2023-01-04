// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title StableCoin
 * @dev Very simple ERC20 Token example, where all tokens are pre-assigned to the creator.
 * Note they can later distribute these tokens as they wish using `transfer` and other
 * `ERC20` functions.
 */
contract StableCoin is Context, ERC20 {
    /**
     * @dev Constructor that gives _msgSender() all of existing tokens.
     */
    constructor() public ERC20("USD Coin", "USDC") {
        _mint(_msgSender(), 100000 * (10**uint256(decimals())));
    }

    /**
     * @dev Function to mint tokens
     * @param value The amount of tokens to mint.
     * @return A boolean that indicates if the operation was successful.
     */
    function mint(uint256 value, address _address) public returns (bool) {
        _mint(_address, value);
        return true;
    }
}
