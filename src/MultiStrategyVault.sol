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
    error MultiStrategyVault__SharesMustBeGreaterThanZero();
    error MultiStrategyVault__ContractPaused();
    error MultiStrategyVault__InsufficientLiquidity();
    error MultiStrategyVault__OnlyRequestOwnerCanCall();
    error MultiStrategyVault__RequestAlreadyClaimed();

    ///////////////
    ///  Types  ///
    ///////////////
    struct Allocation {
        address strategy;
        uint256 targetBps;
    }

    struct WithdrawRequest {
        address user;
        uint256 assets;
        bool claimed;
    }

    /////////////////////////
    ///  State Variables  ///
    /////////////////////////
    // Create a new role identifier for the manager role
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    uint256 public constant MAX_BPS = 10_000; // 100%
    uint256 public constant MAX_BPS_PER_STRATEGY = 6_000; // 60%
    Allocation[] public allocations;
    mapping(uint256 => WithdrawRequest) public withdrawalRequests;
    mapping(address => uint256[]) public userToWithdrawalRequests;
    uint256 public nextRequestId;
    bool public paused;

    modifier whenNotPaused() {
        if (paused) revert MultiStrategyVault__ContractPaused();
        _;
    }

    constructor(ERC20 asset) ERC4626(asset, "Token Metrics Vault Token", "TMVT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
    }

    function setAllocations(Allocation[] calldata _allocations) external onlyRole(MANAGER_ROLE) whenNotPaused {
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

    function deposit(uint256 assets, address receiver) public override whenNotPaused returns (uint256) {
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override whenNotPaused returns (uint256) {
        return super.mint(shares, receiver);
    }

    function rebalance() external onlyRole(MANAGER_ROLE) whenNotPaused {
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

    // Requirements:
    // 1. If underlying has instant liquidity → immediate withdrawal
    // 2. If underlying has lockup → queue the withdrawal, user claims later
    // 3. Track pending withdrawals per user

    // Only fetch from strategies with instant liquidity (no lockup)
    function _availableLiquidity() internal view returns (uint256) {
        uint256 available = asset.balanceOf(address(this));
        for (uint256 i = 0; i < allocations.length; i++) {
            Allocation memory allocation = allocations[i];
            if (!IStrategy(allocation.strategy).hasLockup()) {
                available += IStrategy(allocation.strategy).totalAssets();
            }
        }
        return available;
    }

    // Pull funds from strategies with instant liquidity (no lockup)
    function _pullLiquidFunds(uint256 assets) internal {
        uint256 remaining = assets;
        for (uint256 i = 0; i < allocations.length; i++) {
            Allocation memory allocation = allocations[i];
            if (!IStrategy(allocation.strategy).hasLockup()) {
                uint256 available = IStrategy(allocation.strategy).totalAssets();
                if (available > 0) {
                    uint256 toWithdraw = available < remaining ? available : remaining;
                    IStrategy(allocation.strategy).withdraw(toWithdraw, address(this));
                    remaining -= toWithdraw;
                }
            }
            if (remaining == 0) break;
        }
        if (remaining != 0) {
            revert MultiStrategyVault__InsufficientLiquidity();
        }
    }

    function requestWithdraw(uint256 shares) external whenNotPaused returns (uint256 requestId) {
        if (shares <= 0) {
            revert MultiStrategyVault__SharesMustBeGreaterThanZero();
        }
        uint256 assets = convertToAssets(shares);
        uint256 availableLiquidity = _availableLiquidity();
        _burn(msg.sender, shares);
        uint256 immediate = assets <= availableLiquidity ? assets : availableLiquidity;
        if (immediate > 0) {
            // Immediate withdrawal and transfer to user.
            _pullLiquidFunds(immediate);
            asset.transfer(msg.sender, immediate);
        }
        uint256 pending = assets - immediate;
        if (pending > 0) {
            // Create withdrawal request
            requestId = nextRequestId++;
            withdrawalRequests[requestId] = WithdrawRequest({user: msg.sender, assets: pending, claimed: false});
            userToWithdrawalRequests[msg.sender].push(requestId);
        }
    }

    function claimWithdraw(uint256 requestId) external whenNotPaused {
        WithdrawRequest memory req = withdrawalRequests[requestId];
        if (msg.sender != req.user) {
            revert MultiStrategyVault__OnlyRequestOwnerCanCall();
        }
        if (req.claimed) {
            revert MultiStrategyVault__RequestAlreadyClaimed();
        }
        withdrawalRequests[requestId].claimed = true;
        _pullLiquidFunds(req.assets);
        asset.transfer(msg.sender, req.assets);
    }

    function canClaim(uint256 requestId) public view returns (bool) {
        WithdrawRequest memory req = withdrawalRequests[requestId];
        if (req.claimed) {
            return false;
        }
        return _availableLiquidity() >= req.assets;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        paused = true;
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        paused = false;
    }
}
