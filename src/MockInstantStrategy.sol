// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626, ERC20} from "@solmate/tokens/ERC4626.sol";

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
