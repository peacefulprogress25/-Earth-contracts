pragma solidity ^0.8.4;
// SPDX-License-Identifier: GPL-3.0-or-later

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./EarthERC20Token.sol";
import "./EarthTreasury.sol";
import "./EarthStaking.sol";
import "./PresaleAllocation.sol";
import "./LockedFruit.sol";
import "hardhat/console.sol";

/**
 * Presale campaign, which lets users to mint and stake based on current IV and a whitelist
 */
contract Presale is Ownable, Pausable {
    IERC20 public STABLEC; // STABLEC contract address
    EarthERC20Token public EARTH; // EARTH ERC20 contract
    EarthTreasury public TREASURY;
    EarthStaking public STAKING; // Staking contract

    // Unlock timestamp. This will change during the presale period, but will always be in a 2 week range.

    uint256 public mintMultiple;

    uint256 public decamicalplacemintMultiple = 10;
    // How much allocation has each user used.

    event MintComplete(
        address minter,
        uint256 acceptedStablec,
        uint256 mintedTemple,
        uint256 mintedFruit
    );

    constructor(
        IERC20 _STABLEC,
        EarthERC20Token _EARTH,
        EarthStaking _STAKING,
        EarthTreasury _TREASURY,
        uint256 _mintMultiple // uint256 _unlockTimestamp
    ) {
        STABLEC = _STABLEC;
        EARTH = _EARTH;
        STAKING = _STAKING;
        TREASURY = _TREASURY;

        mintMultiple = _mintMultiple;
    }

    /**
     * Pause contract. Either emergency or at the end of presale
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * Revert pause
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // added mint v1
    function mint(uint256 _amountPaidStablec) external whenNotPaused {
        require(_amountPaidStablec > 0, "amount must be greater then zero");
        require(
            STABLEC.allowance(msg.sender, address(this)) >= _amountPaidStablec,
            "Insufficient stablecoin allowance. Cannot unstake"
        );

        (uint256 _stablec, uint256 _earth) = TREASURY.intrinsicValueRatio();

        console.log("_amountPaidStablec", _amountPaidStablec);

        uint256 _earthMinted = (10 * _amountPaidStablec * _earth) /
            _stablec /
            mintMultiple;

        // pull stablec from staker and immediately transfer back to treasury

        SafeERC20.safeTransferFrom(
            STABLEC,
            msg.sender,
            address(TREASURY),
            _amountPaidStablec
        );

        EARTH.mint(msg.sender, _earthMinted); //user getting earth tokens
    }
}
