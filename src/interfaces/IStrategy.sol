// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

interface IStrategy {
    function deposit(uint256 assets) external;
    function withdraw(uint256 assets, address to) external returns (uint256 withdrawn);
    function totalAssets() external view returns (uint256);
    function hasLockup() external view returns (bool);
}
