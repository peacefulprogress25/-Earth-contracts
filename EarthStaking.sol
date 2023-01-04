pragma solidity ^0.8.4;
// SPDX-License-Identifier: GPL-3.0-or-later

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./ABDKMath64x64.sol";
import "./EarthERC20Token.sol";
import "./Fruit.sol";
import "./ExitQueue.sol";

// import "hardhat/console.sol";

/**
 * Mechancics of how a user can stake earth.
 */
contract EarthStaking is Ownable {
    using ABDKMath64x64 for int128;
    EarthERC20Token public immutable EARTH; // The token being staked, for which EARTH rewards are generated
    Fruit public immutable FRUIT; // Token used to redeem staked EARTH

    // epoch percentage yield, as an ABDKMath64x64
    int128 public epy;

    // epoch size, in seconds
    uint256 public epochSizeSeconds;

    // The starting timestamp. from where staking starts
    uint256 public startTimestamp;

    // epy compounded over every epoch since the contract creation up
    // until lastUpdatedEpoch. Represented as an ABDKMath64x64
    int128 public accumulationFactor;

    // the epoch up to which we have calculated accumulationFactor.
    uint256 public lastUpdatedEpoch;

    event StakeCompleted(
        address _staker,
        uint256 _amount,
        uint256 _lockedUntil
    );
    event AccumulationFactorUpdated(
        uint256 _epochsProcessed,
        uint256 _currentEpoch,
        uint256 _accumulationFactor
    );
    event UnstakeCompleted(address _staker, uint256 _amount);

    constructor(
        EarthERC20Token _EARTH,
        uint256 _epochSizeSeconds,
        uint256 _startTimestamp
    ) {
        require(
            _startTimestamp < block.timestamp,
            "Start timestamp must be in the past"
        );
        require(
            _startTimestamp > (block.timestamp - (24 * 2 * 60 * 60)),
            "Start timestamp can't be more than 2 days in the past"
        );

        EARTH = _EARTH;

        // Each version of the staking contract needs it's own instance of Fruit users can use to
        // claim back rewards
        FRUIT = new Fruit();
        epochSizeSeconds = _epochSizeSeconds;
        startTimestamp = _startTimestamp;
        epy = ABDKMath64x64.fromUInt(1);
        accumulationFactor = ABDKMath64x64.fromUInt(1);
    }

    /** Sets epoch percentage yield */
    function setEpy(
        uint256 _numerator,
        uint256 _denominator
    ) external onlyOwner {
        _updateAccumulationFactor();
        epy = ABDKMath64x64.fromUInt(1).add(
            ABDKMath64x64.divu(_numerator, _denominator)
        );
    }

    /** Get EPY as uint, scaled up the given factor (for reporting) */
    // Remove payable and add view after removing emit
    function getEpy(uint256 _scale) external payable returns (uint256) {
        return
            epy
                .sub(ABDKMath64x64.fromUInt(1))
                .mul(ABDKMath64x64.fromUInt(_scale))
                .toUInt();
    }

    function currentEpoch() public view returns (uint256) {
        return (block.timestamp - startTimestamp) / epochSizeSeconds;
    }

    /** Return current accumulation factor, scaled up to account for fractional component */
    function getAccumulationFactor(
        uint256 _scale
    ) external view returns (uint256) {
        return
            _accumulationFactorAt(currentEpoch())
                .mul(ABDKMath64x64.fromUInt(_scale))
                .toUInt();
    }

    /** Calculate the updated accumulation factor, based on the current epoch */
    function _accumulationFactorAt(
        uint256 epoch
    ) private view returns (int128) {
        uint256 _nUnupdatedEpochs = epoch - lastUpdatedEpoch;
        return accumulationFactor.mul(epy.pow(_nUnupdatedEpochs));
    }

    /** Balance in EARTH for a given amount of FRUIT */
    function balance(uint256 amountFruit) public view returns (uint256) {
        return
            _overflowSafeMul1e18(
                ABDKMath64x64.divu(amountFruit, 1e18).mul(
                    _accumulationFactorAt(currentEpoch())
                )
            );
    }

    /** updates rewards in pool */
    function _updateAccumulationFactor() internal {
        uint256 _currentEpoch = currentEpoch();

        // still in previous epoch, no action.
        // NOTE: should be a pre-condition that _currentEpoch >= lastUpdatedEpoch
        //       It's possible to end up in this state if we shorten epoch size.
        //       As such, it's not baked as a precondition
        if (_currentEpoch <= lastUpdatedEpoch) {
            return;
        }

        accumulationFactor = _accumulationFactorAt(_currentEpoch);
        lastUpdatedEpoch = _currentEpoch;
        uint256 _nUnupdatedEpochs = _currentEpoch - lastUpdatedEpoch;
        emit AccumulationFactorUpdated(
            _nUnupdatedEpochs,
            _currentEpoch,
            accumulationFactor.mul(10000).toUInt()
        );
    }

    /** Stake on behalf of a given address. Used by other contracts (like Presale) */
    function stakeFor(
        address _staker,
        uint256 _amountEarth
    ) public returns (uint256 amountFruit) {
        require(_amountEarth > 0, "Cannot stake 0 tokens");

        _updateAccumulationFactor();

        // net past value/genesis value/Fruit Value for the earth you are putting in.
        amountFruit = _overflowSafeMul1e18(
            ABDKMath64x64.divu(_amountEarth, 1e18).div(accumulationFactor)
        ); // didn't understand

        SafeERC20.safeTransferFrom(
            EARTH,
            msg.sender,
            address(this),
            _amountEarth
        );
        FRUIT.mint(_staker, amountFruit);
        emit StakeCompleted(_staker, _amountEarth, 0);

        return amountFruit;
    }

    /** Stake earth */
    function stake(
        uint256 _amountEarth
    ) external returns (uint256 amountFruit) {
        return stakeFor(msg.sender, _amountEarth);
    }

    /** Unstake earth */
    function unstake(uint256 _amountFruit) external {
        require(
            FRUIT.allowance(msg.sender, address(this)) >= _amountFruit,
            "Insufficient fruit allowance. Cannot unstake"
        );

        _updateAccumulationFactor();
        uint256 unstakeBalanceEarth = balance(_amountFruit);

        FRUIT.burnFrom(msg.sender, _amountFruit);

        SafeERC20.safeTransfer(EARTH, msg.sender, unstakeBalanceEarth);

        emit UnstakeCompleted(msg.sender, _amountFruit);
    }

    function _overflowSafeMul1e18(
        int128 amountFixedPoint
    ) internal pure returns (uint256) {
        uint256 integralDigits = amountFixedPoint.toUInt();
        uint256 fractionalDigits = amountFixedPoint
            .sub(ABDKMath64x64.fromUInt(integralDigits))
            .mul(ABDKMath64x64.fromUInt(1e18))
            .toUInt();
        return (integralDigits * 1e18) + fractionalDigits;
    }
}
