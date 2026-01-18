// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626, ERC20} from "@solmate/tokens/ERC4626.sol";

/*
     * @title MockInstantStrategy
     * @author Nihar Dangi
     *
     * @notice This contract represents a mock strategy that provides instant liquidity for a MultiStrategyVault.
     * It allows users to deposit and withdraw assets without any lockup period.
     *               
     * Assumptions:     
     * 1. Strategies are assumed to be vault-specific, meaning they only manage funds from this specific vault.
     * 2. No fees or performance incentives are implemented in this mock strategy.
     * 3. Yield generation is simulated by directly transferring assets to the strategy contract.
     * 4. This mock strategy does not interact with any external protocols; it simply holds the assets.
     *
     * @dev Inherits from ERC4626 for vault functionality
*/
contract MockInstantStrategy is ERC4626 {
    constructor(ERC20 asset) ERC4626(asset, "Instant Strategy Token", "INST") {}

    function deposit(uint256 assets) external {
        asset.transferFrom(msg.sender, address(this), assets);
    }

    function withdraw(uint256 assets, address to) external returns (uint256 withdrawn) {
        asset.transfer(to, assets);
        return assets;
    }

    function hasLockup() external pure returns (bool) {
        return false;
    }

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function simulateYield(uint256 amount) external {
        asset.transferFrom(msg.sender, address(this), amount);
    }
}
