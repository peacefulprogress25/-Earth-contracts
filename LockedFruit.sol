pragma solidity ^0.8.4;
// SPDX-License-Identifier: GPL-3.0-or-later

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Fruit.sol";

/**
 * Bookkeeping for Fruit that's locked
 */
contract LockedFruit {
    struct LockedEntry {
        // How many tokens are locked
        uint256 BalanceFruit;

        // WHen can the user unlock these tokens
        uint256 LockedUntilTimestamp;
    }

    // All temple locked for any given user
    mapping(address => LockedEntry[]) public locked;

    Fruit public FRUIT; // The token being staked, for which TEMPLE rewards are generated

    event FruitLocked(address _staker, uint256 _amount, uint256 _lockedUntil);
    event FruitWithdraw(address _staker, uint256 _amount);

    constructor(Fruit _FRUIT) {
        FRUIT = _FRUIT;
    }

    function numLocks(address _staker) external view returns(uint256) {
        return locked[_staker].length;
    }

    /** lock up Fruit */
    function lockFor(address _staker, uint256 _amountFruit, uint256 _lockedUntilTimestamp) public {
        LockedEntry memory lockEntry = LockedEntry({BalanceFruit: _amountFruit, LockedUntilTimestamp: _lockedUntilTimestamp});
        locked[_staker].push(lockEntry);

        SafeERC20.safeTransferFrom(FRUIT, msg.sender, address(this), _amountFruit);
        emit FruitLocked(_staker, _amountFruit, _lockedUntilTimestamp);
    }

    function lock(uint256 _amountFruit, uint256 _lockedUntilTimestamp) external {
        lockFor(msg.sender, _amountFruit, _lockedUntilTimestamp);
    }

    /** Withdraw a specific locked entry */
    function withdrawFor(address _staker, uint256 _idx) public {
        LockedEntry[] storage lockedEntries = locked[_staker];

        require(_idx < lockedEntries.length, "No lock entry at the specified index");
        require(lockedEntries[_idx].LockedUntilTimestamp < block.timestamp, "Specified entry is still locked");

        LockedEntry memory entry = lockedEntries[_idx];

        lockedEntries[_idx] = lockedEntries[lockedEntries.length-1];
        lockedEntries.pop();

        SafeERC20.safeTransfer(FRUIT, _staker, entry.BalanceFruit);
        emit FruitWithdraw(_staker, entry.BalanceFruit);
    }

    function withdraw(uint256 _idx) external {
        withdrawFor(msg.sender, _idx);
    }
}