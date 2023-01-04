pragma solidity ^0.8.4;
// SPDX-License-Identifier: GPL-3.0-or-later

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./EarthERC20Token.sol";
import "./ITreasuryAllocation.sol";
import "./MintAllowance.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// import "hardhat/console.sol";

contract EarthTreasury is Ownable {
    // Underlying Earth token
    EarthERC20Token private EARTH;

    // underlying stable token we are holding and valuing treasury with
    IERC20 private STABLEC;

    // Minted earth allocated to various investment contracts
    MintAllowance public MINT_ALLOWANCE;

    // Ratio of treasury value in stablec to open supply of earth.
    struct IntrinsicValueRatio {
        uint256 stablec;
        uint256 earth;
    }
    IntrinsicValueRatio public intrinsicValueRatio;

    // Earth rewards harvested, and (yet) to be allocated to a pool
    uint256 public harvestedRewardsEarth;

    // Has treasury been seeded with STABLEC yet (essentially, has seedMint been called)
    // this will bootstrap IV
    bool public seeded = false;

    // all active pools. A pool is anything
    // that gets allocated some portion of harvest
    address[] public pools;
    mapping(address => uint96) public poolHarvestShare;
    uint96 public totalHarvestShares;

    // Current treasury STABLEC allocations
    mapping(ITreasuryAllocation => uint256) public treasuryAllocationsStablec;
    uint256 public totalAllocationStablec;

    event RewardsHarvested(uint256 _amount);
    event HarvestDistributed(address _contract, uint256 _amount);

    constructor(EarthERC20Token _EARTH, IERC20 _STABLEC) {
        EARTH = _EARTH;
        STABLEC = _STABLEC;
        MINT_ALLOWANCE = new MintAllowance(_EARTH);
    }

    function numPools() external view returns (uint256) {
        return pools.length;
    }

    /**
     * Seed treasury with STABLEC and Earth to bootstrap
     */
    function seedMint(
        uint256 amountStablec,
        uint256 amountEarth
    ) external onlyOwner {
        require(!seeded, "Owner has already seeded treasury");
        seeded = true;

        // can this go in the constructor?
        intrinsicValueRatio.stablec = amountStablec;
        intrinsicValueRatio.earth = amountEarth;

        SafeERC20.safeTransferFrom(
            STABLEC,
            msg.sender,
            address(this),
            amountStablec
        );
        EARTH.mint(msg.sender, amountEarth);
    }

    /**
     * Harvest rewards.
     *
     * For auditing, we harvest and allocate in two steps
     */
    function harvest(uint256 distributionPercent) external onlyOwner {
        require(
            distributionPercent <= 100,
            "Scaling factor interpreted as a %, needs to be between 0 (no harvest) and 100 (max harvest)"
        );

        uint256 reserveStablec = STABLEC.balanceOf(address(this)) +
            totalAllocationStablec;

        // Burn any excess earth, that is Any earth over and beyond harvestedRewardsEarth.
        // NOTE: If we don't do this, IV could drop...
        if (EARTH.balanceOf(address(this)) > harvestedRewardsEarth) {
            // NOTE: there isn't a Reentrancy issue as we control the EARTH ERC20 contract, and configure
            //       treasury with an address on contract creation
            EARTH.burn(EARTH.balanceOf(address(this)) - harvestedRewardsEarth);
        }

        uint256 totalSupplyEarth = EARTH.totalSupply() -
            EARTH.balanceOf(address(MINT_ALLOWANCE));
        uint256 impliedSupplyAtCurrentIVEarth = (reserveStablec *
            intrinsicValueRatio.earth) / intrinsicValueRatio.stablec;

        require(
            impliedSupplyAtCurrentIVEarth >= totalSupplyEarth,
            "Cannot run harvest when IV drops"
        );

        uint256 newHarvestEarth = ((impliedSupplyAtCurrentIVEarth -
            totalSupplyEarth) * distributionPercent) / 100;
        harvestedRewardsEarth += newHarvestEarth;

        intrinsicValueRatio.stablec = reserveStablec;
        intrinsicValueRatio.earth = totalSupplyEarth + newHarvestEarth;

        EARTH.mint(address(this), newHarvestEarth);
        emit RewardsHarvested(newHarvestEarth);
    }

    /**
     * ResetIV
     *
     * Not expected to be used in day to day operations, as opposed to harvest which
     * will be called ~ once per epoch.
     *
     * Only to be called if we have to post a treasury loss, and restart IV growth from
     * a new baseline.
     */
    function resetIV() external onlyOwner {
        uint256 reserveStablec = STABLEC.balanceOf(address(this)) +
            totalAllocationStablec;
        uint256 totalSupplyEarth = EARTH.totalSupply() -
            EARTH.balanceOf(address(MINT_ALLOWANCE));
        intrinsicValueRatio.stablec = reserveStablec;
        intrinsicValueRatio.earth = totalSupplyEarth;
    }

    /**
     * Allocate rewards to each pool.
     */
    function distributeHarvest() external onlyOwner {
        // transfer rewards as per defined allocation
        uint256 totalAllocated = 0;
        for (uint256 i = 0; i < pools.length; i++) {
            uint256 allocatedRewards = (harvestedRewardsEarth *
                poolHarvestShare[pools[i]]) / totalHarvestShares;

            // integer rounding may cause the last allocation to exceed harvested
            // rewards. Handle gracefully
            if ((totalAllocated + allocatedRewards) > harvestedRewardsEarth) {
                allocatedRewards = harvestedRewardsEarth - totalAllocated;
            }
            totalAllocated += allocatedRewards;
            SafeERC20.safeTransfer(EARTH, pools[i], allocatedRewards);
            emit HarvestDistributed(pools[i], allocatedRewards);
        }
        harvestedRewardsEarth -= totalAllocated;
    }

    /**
     * Mint and Allocate treasury EARTH.
     */
    function mintAndAllocateEarth(
        address _contract,
        uint256 amountEarth
    ) external onlyOwner {
        require(amountEarth > 0, "EARTH to mint and allocate must be > 0");

        // Mint and Allocate EARTH via MINT_ALLOWANCE helper
        EARTH.mint(address(this), amountEarth);
        SafeERC20.safeIncreaseAllowance(
            EARTH,
            address(MINT_ALLOWANCE),
            amountEarth
        );
        MINT_ALLOWANCE.increaseMintAllowance(_contract, amountEarth);
    }

    /**
     * Burn minted earth associated with a specific contract
     */
    function unallocateAndBurnUnusedMintedEarth(
        address _contract
    ) external onlyOwner {
        MINT_ALLOWANCE.burnUnusedMintAllowance(_contract);
    }

    /**
     * Allocate treasury STABLEC.
     */
    function allocateTreasuryStablec(
        ITreasuryAllocation _contract,
        uint256 amountStablec
    ) external onlyOwner {
        require(amountStablec > 0, "STABLEC to allocate must be > 0");

        treasuryAllocationsStablec[_contract] += amountStablec;
        totalAllocationStablec += amountStablec;
        SafeERC20.safeTransfer(STABLEC, address(_contract), amountStablec);
    }

    /**
     * Update treasury with latest mark to market for a given treasury allocation
     */
    function updateMarkToMarket(
        ITreasuryAllocation _contract
    ) external onlyOwner {
        uint256 oldReval = treasuryAllocationsStablec[_contract];
        uint256 newReval = _contract.reval();
        totalAllocationStablec = totalAllocationStablec + newReval - oldReval;
        treasuryAllocationsStablec[_contract] = newReval;
    }

    /**
     * Withdraw from a contract.
     *
     * Expects that pre-withdrawal reval() includes the unwithdrawn allowance, and post withdrawal reval()
     * drops by exactly this amount.
     */
    function withdraw(ITreasuryAllocation _contract) external onlyOwner {
        uint256 preWithdrawlReval = _contract.reval();
        uint256 pendingWithdrawal = STABLEC.allowance(
            address(_contract),
            address(this)
        );

        // NOTE: Reentrancy considered and it's safe STABLEC is a well known unchanging contract
        SafeERC20.safeTransferFrom(
            STABLEC,
            address(_contract),
            address(this),
            pendingWithdrawal
        );
        uint256 postWithdrawlReval = _contract.reval();

        totalAllocationStablec = totalAllocationStablec - pendingWithdrawal;
        treasuryAllocationsStablec[_contract] -= pendingWithdrawal;

        require(postWithdrawlReval + pendingWithdrawal == preWithdrawlReval);
    }

    /**
     * Withdraw from a contract which has some treasury allocation
     *
     * Ejects a contract out of treasury, pulling in any allowance of STABLEC
     * We only expect to use this if (for whatever reason). The booking in
     * The given TreasuryAllocation results in withdraw not working.
     *
     * Precondition, contract given has allocated all of it's Stablec assets
     * to be transfered into treasury as an allowance.
     *
     * This will only ever reduce treasury IV.
     */
    function ejectTreasuryAllocation(
        ITreasuryAllocation _contract
    ) external onlyOwner {
        uint256 pendingWithdrawal = STABLEC.allowance(
            address(_contract),
            address(this)
        );
        totalAllocationStablec -= treasuryAllocationsStablec[_contract];
        treasuryAllocationsStablec[_contract] = 0;
        SafeERC20.safeTransferFrom(
            STABLEC,
            address(_contract),
            address(this),
            pendingWithdrawal
        );
    }

    /**
     * Add or update a pool, and transfer in treasury assets
     */
    function upsertPool(
        address _contract,
        uint96 _poolHarvestShare
    ) external onlyOwner {
        require(_poolHarvestShare > 0, "Harvest share must be > 0");

        totalHarvestShares =
            totalHarvestShares +
            _poolHarvestShare -
            poolHarvestShare[_contract];

        // first time, add contract to array as well
        if (poolHarvestShare[_contract] == 0) {
            pools.push(_contract);
        }

        poolHarvestShare[_contract] = _poolHarvestShare;
    }

    /**
     * Remove a given investment pool.
     */
    function removePool(uint256 idx, address _contract) external onlyOwner {
        require(idx < pools.length, "No pool at the specified index");
        require(
            pools[idx] == _contract,
            "Pool at index and passed in address don't match"
        );

        pools[idx] = pools[pools.length - 1];
        pools.pop();
        totalHarvestShares -= poolHarvestShare[_contract];
        delete poolHarvestShare[_contract];
    }
}
