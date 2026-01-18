// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626, ERC20} from "@solmate/tokens/ERC4626.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";

/*
     * @title MockLockedStrategy
     * @author Nihar Dangi
     *
     * @notice This contract represents a mock strategy that provides locked liquidity for a MultiStrategyVault.
     * It allows users to deposit and withdraw assets with a lockup period.
     * Owner can unlock the strategy to allow withdrawals.     
     *               
     * Assumptions:     
     * 1. Strategies are assumed to be vault-specific, meaning they only manage funds from this specific vault.
     * 2. No fees or performance incentives are implemented in this mock strategy.
     * 3. Yield generation is simulated by directly transferring assets to the strategy contract.
     * 4. This mock strategy does not interact with any external protocols; it simply holds the assets.
     *
     * @dev Inherits from ERC4626 for vault functionality
*/
contract MockLockedStrategy is ERC4626, Ownable {
    bool public unlocked;

    constructor(ERC20 asset) ERC4626(asset, "Locked Strategy Token", "LST") Ownable(msg.sender) {}

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function deposit(uint256 assets) external {
        asset.transferFrom(msg.sender, address(this), assets);
    }

    function withdraw(uint256 assets, address to) external returns (uint256 withdrawn) {
        if (!unlocked) return 0;

        asset.transfer(to, assets);
        return assets;
    }

    function hasLockup() external view returns (bool) {
        return !unlocked;
    }

    function unlock() external onlyOwner {
        unlocked = true;
    }

    function simulateYield(uint256 amount) external {
        asset.transferFrom(msg.sender, address(this), amount);
    }
}
