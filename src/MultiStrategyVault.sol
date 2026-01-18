// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC4626, ERC20} from "@solmate/tokens/ERC4626.sol";
import {AccessControl} from "@openzeppelin/access/AccessControl.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";

/*
     * @title MultiStrategyVault
     * @author Nihar Dangi
     *
     * @notice The system is designed to be as minimal as possible. It consists of a single MultiStrategyVault contract that
     * manages multiple strategies for yield generation. Users can deposit and withdraw assets from the vault,
     * and the vault will allocate funds across the different strategies based on predefined target allocations.     
     *     
     * Typical flow:
     * 1. Users deposit USDC into the MultiStrategyVault and receive vault shares in return.
     * 2. The vault allocates the deposited USDC across multiple strategies based on predefined target basis points (bps).
     * 3. Users can request withdrawals by burning their vault shares
     * 4. If sufficient liquidity is available in the vault, the withdrawal is processed immediately. If not, the request is queued.
     * 5. Users can claim their queued withdrawals once sufficient liquidity is available.
     * 6. The vault can be rebalanced by a manager to ensure that the allocations across strategies remain aligned with the target bps.
     * 7. The vault includes pause functionality to halt deposits, mints, and withdrawals in case of emergencies.
     * 8. Access control is implemented to restrict certain functions to authorized roles only.
     * 
     * Assumptions:     
     * 1. Strategies are assumed to be vault-specific, meaning they only manage funds from this specific vault.
     * 2. Cap Enforcement: Each strategy has a maximum allocation limit to prevent over-concentration of funds.
     * 3. Various checks are in place to prevent concentration risk, ensuring no single strategy can dominate the vault's allocations.        
     *
     * @dev Inherits from ERC4626 for vault functionality and AccessControl for role-based access management.     
*/
contract MultiStrategyVault is ERC4626, AccessControl {
    ////////////////
    ///  Events  ///
    ////////////////
    event AllocationsUpdated(address indexed manager);
    event Rebalanced(address indexed manager, uint256 totalAssets);
    event WithdrawalRequested(uint256 indexed requestId, address indexed user, uint256 assets);
    event WithdrawalClaimed(uint256 indexed requestId, address indexed user, uint256 assets);
    event Paused(address indexed admin);
    event Unpaused(address indexed admin);

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

    ////////////////////
    ///  Modifiers  ///
    ///////////////////
    modifier whenNotPaused() {
        if (paused) revert MultiStrategyVault__ContractPaused();
        _;
    }

    ////////////////////
    ///  Functions  ///
    ///////////////////
    constructor(ERC20 asset) ERC4626(asset, "Token Metrics Vault Token", "TMVT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
    }

    /////////////////////////////////////
    ///  External & Public Functions  ///
    /////////////////////////////////////
    /*
     * @param _allocations: The allocations to set
     * @notice This function will set the allocations array for the vault. Only callable by MANAGER_ROLE.
     */
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
        emit AllocationsUpdated(msg.sender);
    }

    /*
     * @param assets: The amount of the underlying asset to deposit
     * @param receiver: The address that will receive the minted shares
     * @notice This function will deposit user's assets and mint shares in the vault.
     */
    function deposit(uint256 assets, address receiver) public override whenNotPaused returns (uint256) {
        return super.deposit(assets, receiver);
    }

    /*
     * @param shares: The amount of shares to mint
     * @param receiver: The address that will receive the minted shares
     * @notice This function will mint shares in the vault.
     */
    function mint(uint256 shares, address receiver) public override whenNotPaused returns (uint256) {
        return super.mint(shares, receiver);
    }

    /*    
     * @notice This function will rebalance the vault's allocations according to the target bps set for each strategy.
     * Only callable by MANAGER_ROLE.
     */
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
        emit Rebalanced(msg.sender, total);
    }

    /*    
     * @notice This function will return the total assets managed by the vault across all strategies.
     */
    function totalAssets() public view virtual override returns (uint256) {
        uint256 total = asset.balanceOf(address(this));
        for (uint256 i = 0; i < allocations.length; i++) {
            total += IStrategy(allocations[i].strategy).totalAssets();
        }
        return total;
    }

    /*
     * @param shares: The amount of shares to withdraw     
     * @notice This function will request a withdrawal from the vault. It will attempt to fulfill the withdrawal
     * immediately from available liquidity. If insufficient liquidity is available, the remaining amount will be queued.
     */
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
            emit WithdrawalRequested(requestId, msg.sender, pending);
        }
    }

    /*
     * @param requestId: The ID of the withdrawal request to claim     
     * @notice This function will allow users to claim their queued withdrawals once sufficient liquidity is available.
     */
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
        emit WithdrawalClaimed(requestId, msg.sender, req.assets);
    }

    /*
     * @param requestId: The ID of the withdrawal request to check
     * @notice This function will return true if the withdrawal request can be claimed (i.e., sufficient liquidity is available).
     */
    function canClaim(uint256 requestId) public view returns (bool) {
        WithdrawRequest memory req = withdrawalRequests[requestId];
        if (req.claimed) {
            return false;
        }
        return _availableLiquidity() >= req.assets;
    }

    /*
     * @param user: The address of the user to get withdrawal requests for
     * @notice This function will return an array of pending withdrawal request IDs for the specified user.
     */
    function getUserWithdrawalRequests(address user) external view returns (uint256[] memory) {
        uint256[] memory requestIDs = userToWithdrawalRequests[user];
        uint256[] memory pendingRequestIDs = new uint256[](requestIDs.length);
        uint256 pendingCount = 0;
        for (uint256 i = 0; i < requestIDs.length; i++) {
            if (!withdrawalRequests[requestIDs[i]].claimed) {
                pendingRequestIDs[pendingCount] = requestIDs[i];
                pendingCount++;
            }
        }
        assembly {
            mstore(pendingRequestIDs, pendingCount)
        }
        return pendingRequestIDs;
    }

    /*
     * @notice This function will pause the contract, preventing deposits, mints, and withdrawals. 
     * Only callable by DEFAULT_ADMIN_ROLE.
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        paused = true;
        emit Paused(msg.sender);
    }

    /*
     * @notice This function will unpause the contract, allowing deposits, mints, and withdrawals. 
     * Only callable by DEFAULT_ADMIN_ROLE.
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        paused = false;
        emit Unpaused(msg.sender);
    }

    //////////////////////////////////////
    ///  Internal & Private Functions  ///
    //////////////////////////////////////
    /*
     * @param assets: The amount of the underlying asset deposited
     * @param shares: The amount of shares minted
     * @notice This function is called after a deposit is made (hook) to allocate funds to strategies based on target bps.
     */
    function afterDeposit(uint256 assets, uint256 shares) internal virtual override {
        uint256 total = totalAssets();
        for (uint256 i = 0; i < allocations.length; i++) {
            Allocation memory allocation = allocations[i];
            uint256 maxAllowed = (total * allocation.targetBps) / MAX_BPS;
            uint256 currentAmount = IStrategy(allocation.strategy).totalAssets();
            if (maxAllowed <= currentAmount) {
                continue;
            }

            uint256 allocationAmount = (assets * allocation.targetBps) / MAX_BPS;
            uint256 toDeposit = maxAllowed - currentAmount;
            if (allocationAmount < toDeposit) {
                toDeposit = allocationAmount;
            }

            asset.approve(allocation.strategy, toDeposit);
            IStrategy(allocation.strategy).deposit(toDeposit);
        }
    }

    /*     
     * @notice This function will return the total available liquidity in the vault, including funds in strategies without lockup.
     */
    function _availableLiquidity() internal view returns (uint256) {
        uint256 available = asset.balanceOf(address(this));
        for (uint256 i = 0; i < allocations.length; i++) {
            Allocation memory allocation = allocations[i];
            // Only fetch from strategies with instant liquidity (no lockup)
            if (!IStrategy(allocation.strategy).hasLockup()) {
                available += IStrategy(allocation.strategy).totalAssets();
            }
        }
        return available;
    }

    /*     
     * @notice This function will pull liquid funds from strategies without lockup to fulfill withdrawal requests.
     */
    function _pullLiquidFunds(uint256 assets) internal {
        uint256 remaining = assets;
        for (uint256 i = 0; i < allocations.length; i++) {
            Allocation memory allocation = allocations[i];
            // Pull funds from strategies with instant liquidity (no lockup)
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
}
