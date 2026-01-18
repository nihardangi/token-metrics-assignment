// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626, ERC20} from "@solmate/tokens/ERC4626.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";

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
