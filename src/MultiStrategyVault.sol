// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC4626, ERC20} from "@solmate/tokens/ERC4626.sol";
import {AccessControl} from "@openzeppelin/access/AccessControl.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";

contract MultiStrategyVault is ERC4626, AccessControl {
    ////////////////
    ///  Errors  ///
    ////////////////
    error MultiStrategyVault__AllocationExceedsMaxBpsPerStrategy();
    error MultiStrategyVault__AllocationBpsShouldBeGreaterThanZero();
    error MultiStrategyVault__AllocationStrategyAddressCannotBeZero();
    error MultiStrategyVault__TotalAllocationExceedsMaxBps();

    ///////////////
    ///  Types  ///
    ///////////////
    struct Allocation {
        address strategy;
        uint256 targetBps;
    }

    /////////////////////////
    ///  State Variables  ///
    /////////////////////////
    // Create a new role identifier for the manager role
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    uint256 public constant MAX_BPS = 10_000; // 100%
    uint256 public constant MAX_BPS_PER_STRATEGY = 5_000; // 50%
    Allocation[] public allocations;

    constructor(ERC20 asset) ERC4626(asset, "TokenMetricsVaultToken", "TMVT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
    }

    function setAllocations(Allocation[] calldata _allocations) external onlyRole(MANAGER_ROLE) {
        // Implementation for setting allocations goes here
        uint256 totalBps = 0;
        for (uint256 i = 0; i < _allocations.length; i++) {
            if (_allocations[i].strategy == address(0)) {
                revert MultiStrategyVault__AllocationStrategyAddressCannotBeZero();
            }
            if (_allocations[i].targetBps == 0) {
                revert MultiStrategyVault__AllocationBpsShouldBeGreaterThanZero();
            }
            if (_allocations[i].targetBps > MAX_BPS_PER_STRATEGY) {
                revert MultiStrategyVault__AllocationExceedsMaxBpsPerStrategy();
            }
            totalBps += _allocations[i].targetBps;
        }
        if (totalBps > MAX_BPS) {
            revert MultiStrategyVault__TotalAllocationExceedsMaxBps();
        }
        // Delete existing allocations and set new ones
        delete allocations;

        for (uint256 i = 0; i < _allocations.length; i++) {
            // Set the allocation for each strategy
            allocations.push(_allocations[i]);
        }
    }

    function rebalance() external onlyRole(MANAGER_ROLE) {
        // Move funds to match target allocations
        uint256 total = totalAssets();

        // Withdraw from strategies that are over-allocated
        for (uint256 i = 0; i < allocations.length; i++) {
            Allocation memory allocation = allocations[i];
            // Skip strategies with lockup periods
            if (IStrategy(allocation.strategy).hasLockup()) {
                continue;
            }
            uint256 targetAmount = (total * allocation.targetBps) / MAX_BPS;
            uint256 currentAmount = IStrategy(allocation.strategy).totalAssets();

            if (currentAmount > targetAmount) {
                uint256 excess = currentAmount - targetAmount;
                IStrategy(allocation.strategy).withdraw(excess, address(this));
            }
        }

        // Deposit into strategies that are under-allocated
        for (uint256 i = 0; i < allocations.length; i++) {
            Allocation memory allocation = allocations[i];
            uint256 targetAmount = (total * allocation.targetBps) / MAX_BPS;
            uint256 currentAmount = IStrategy(allocation.strategy).totalAssets();

            if (currentAmount < targetAmount) {
                uint256 deficit = targetAmount - currentAmount;
                asset.approve(allocation.strategy, deficit);
                IStrategy(allocation.strategy).deposit(deficit);
            }
        }
    }

    function totalAssets() public view virtual override returns (uint256) {
        uint256 total = asset.balanceOf(address(this));
        for (uint256 i = 0; i < allocations.length; i++) {
            total += IStrategy(allocations[i].strategy).totalAssets();
        }
        return total;
    }

    function afterDeposit(uint256 assets, uint256 shares) internal virtual override {
        for (uint256 i = 0; i < allocations.length; i++) {
            Allocation memory allocation = allocations[i];
            uint256 allocationAmount = (assets * allocation.targetBps) / MAX_BPS;
            asset.approve(allocation.strategy, allocationAmount);
            IStrategy(allocation.strategy).deposit(allocationAmount);
        }
    }
}
