pragma solidity ^0.8.4;
// SPDX-License-Identifier: GPL-3.0-or-later

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "./EarthERC20Token.sol";

/**
 * Newly minted earth allocated to various earth strategies
 *
 * Any earth held by this contract is assumed to be unused,
 * and hence doesn't effect the intrinsinc value calculation.
 *
 * It's only considered in circulation once a pool pulls
 * it's allowance.
 */
contract MintAllowance is Ownable {
    // Earth contract address
    EarthERC20Token EARTH;

    constructor(EarthERC20Token _EARTH) {
      EARTH = _EARTH;
    }

    /**
     * Increase mint allowance for the given pool
     *
     * Atomically pulls amount from treasury before increasing allownance
     * as an extra check and balance
     */
    function increaseMintAllowance(address _pool, uint256 _amount) external onlyOwner {
      SafeERC20.safeTransferFrom(EARTH, msg.sender, address(this), _amount);
      SafeERC20.safeIncreaseAllowance(EARTH, _pool, _amount);
    }

    /**
     * Burn any unused mint allowance for a given pool
     */
    function burnUnusedMintAllowance(address _pool) external onlyOwner {
      uint256 unusedMintAllowance = EARTH.allowance(address(this), _pool);
      SafeERC20.safeDecreaseAllowance(EARTH, _pool, unusedMintAllowance);
      EARTH.burn(unusedMintAllowance);
    }
}