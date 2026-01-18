// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployMultiStrategyVault} from "../script/DeployMultiStrategyVault.s.sol";
import {MultiStrategyVault} from "../src/MultiStrategyVault.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {MockInstantStrategy} from "../src/MockInstantStrategy.sol";
import {MockLockedStrategy} from "../src/MockLockedStrategy.sol";
import {IStrategy} from "../src/interfaces/IStrategy.sol";

contract TestMultiStrategyVault is Test {
    DeployMultiStrategyVault deployer;
    MultiStrategyVault multiStrategyVault;
    // HelperConfig helperConfig;
    address mUSDC;
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");
    address yieldProvider1 = makeAddr("yieldProvider1");

    uint256 constant FEE_BASIS_POINTS = 100; // 1% fee
    uint256 constant seedAmount = 2000 ether;
    uint256 constant MAX_BPS = 10_000; // 100%

    address strategy1;
    address strategy2;
    address strategy3;
    uint256 targetBps1;
    uint256 targetBps2;
    uint256 targetBps3;

    function setUp() external {
        deployer = new DeployMultiStrategyVault();
        (multiStrategyVault,) = deployer.deployContract();
        mUSDC = address(multiStrategyVault.asset());

        (strategy1, targetBps1) = multiStrategyVault.allocations(0);
        (strategy2, targetBps2) = multiStrategyVault.allocations(1);
        (strategy3, targetBps3) = multiStrategyVault.allocations(2);

        MockERC20(mUSDC).mint(user1, seedAmount);
        MockERC20(mUSDC).mint(user2, seedAmount);
        MockERC20(mUSDC).mint(user3, seedAmount);
        MockERC20(mUSDC).mint(yieldProvider1, seedAmount);

        // Approve the vault to transfer USDC on behalf of user1, user2 and user3
        vm.startPrank(user1);
        MockERC20(mUSDC).approve(address(multiStrategyVault), seedAmount);
        vm.stopPrank();

        vm.startPrank(user2);
        MockERC20(mUSDC).approve(address(multiStrategyVault), seedAmount);
        vm.stopPrank();

        vm.startPrank(user3);
        MockERC20(mUSDC).approve(address(multiStrategyVault), seedAmount);
        vm.stopPrank();
    }

    function testAllocationsAreProperlySet() public view {
        console.log("Logging 1st strategy----------------------------");
        console.log(strategy1);
        console.log(targetBps1);
    }

    function depositToVault(address user, uint256 amount) private {
        vm.startPrank(user);
        multiStrategyVault.deposit(amount, user);
        vm.stopPrank();
    }

    function testDeposit() public {
        uint256 depositAmount = 1000 ether;
        vm.startPrank(user1);
        multiStrategyVault.deposit(depositAmount, user1);
        vm.stopPrank();
        assertEq(MockERC20(mUSDC).balanceOf(user1), seedAmount - depositAmount);
        assertEq(MockERC20(mUSDC).balanceOf(address(strategy1)), depositAmount * targetBps1 / MAX_BPS);
        assertEq(MockERC20(mUSDC).balanceOf(address(strategy2)), depositAmount * targetBps2 / MAX_BPS);
        assertEq(MockERC20(mUSDC).balanceOf(address(strategy3)), depositAmount * targetBps3 / MAX_BPS);
    }

    function testEntireFlow() public {
        uint256 depositAmount = 1000 ether;

        vm.startPrank(DEFAULT_SENDER);
        MockInstantStrategy protocolA = new MockInstantStrategy(ERC20(mUSDC));
        uint256 protocolATargetBps = 6000; // 60%
        MockLockedStrategy protocolB = new MockLockedStrategy(ERC20(mUSDC));
        uint256 protocolBTargetBps = 4000; // 40%
        MultiStrategyVault.Allocation[] memory newAllocations = new MultiStrategyVault.Allocation[](2);
        newAllocations[0] = MultiStrategyVault.Allocation({strategy: address(protocolA), targetBps: protocolATargetBps});
        newAllocations[1] = MultiStrategyVault.Allocation({strategy: address(protocolB), targetBps: protocolBTargetBps});
        multiStrategyVault.setAllocations(newAllocations);
        vm.stopPrank();

        depositToVault(user1, depositAmount);

        // Simulate 10% yield on protocol A
        vm.startPrank(yieldProvider1);
        uint256 yieldBps = 1000; // 10% yield
        uint256 yieldAmount = (protocolA.totalAssets() * yieldBps) / MAX_BPS;
        MockERC20(mUSDC).approve(address(protocolA), yieldAmount);
        protocolA.simulateYield(yieldAmount);
        vm.stopPrank();

        uint256 user1Shares = multiStrategyVault.balanceOf(user1);
        console.log("user1 shares::", user1Shares);

        uint256 user1AssetsNow = multiStrategyVault.convertToAssets(user1Shares);
        assertEq(user1AssetsNow, 1060 ether);

        console.log("Protocol B has lockup:", IStrategy(address(protocolB)).hasLockup());

        // User1 wants to withdraw entire amount. Only funds from protocol A are withdrawn immediately.
        //  Protocol B has lockup, so withdrawal from protocol B will be queued.
        uint256 tokenBalanceBeforeClaim = MockERC20(mUSDC).balanceOf(user1);
        vm.startPrank(user1);
        uint256 requestId = multiStrategyVault.requestWithdraw(user1Shares);
        // Before lockup period is over check if user1 can claim the withdrawal; should return false
        assertEq(multiStrategyVault.canClaim(requestId), false);
        vm.stopPrank();
        uint256 tokenBalanceAfterClaim = MockERC20(mUSDC).balanceOf(user1);
        uint256 expectedWithdrawalFromProtocolA = (depositAmount * protocolATargetBps) / MAX_BPS + yieldAmount;
        assertEq(tokenBalanceAfterClaim - tokenBalanceBeforeClaim, expectedWithdrawalFromProtocolA);

        // Some time has passed and protocol B's lockup period is over
        vm.warp(block.timestamp + 7 days);
        vm.prank(DEFAULT_SENDER);
        protocolB.unlock();
        vm.stopPrank();

        // Check if user1 can claim the withdrawal; should return true
        assertEq(multiStrategyVault.canClaim(requestId), true);

        // User1 claims the withdrawal
        vm.startPrank(user1);
        multiStrategyVault.claimWithdraw(requestId);
        vm.stopPrank();
        assertEq(MockERC20(mUSDC).balanceOf(user1), seedAmount + yieldAmount);
        (,, bool claimed) = multiStrategyVault.withdrawalRequests(0);
        assertEq(claimed, true);
    }

    // Test suite that shows concentration risk is prevented while setting allocations
    function testSetAllocationRevertsOnConcentrationRisk() public {
        vm.startPrank(DEFAULT_SENDER);
        MockInstantStrategy protocolA = new MockInstantStrategy(ERC20(mUSDC));
        uint256 protocolATargetBps = 8000; // 80%
        MockInstantStrategy protocolB = new MockInstantStrategy(ERC20(mUSDC));
        uint256 protocolBTargetBps = 2000; // 30% (this will cause concentration risk)
        MultiStrategyVault.Allocation[] memory newAllocations = new MultiStrategyVault.Allocation[](2);
        newAllocations[0] = MultiStrategyVault.Allocation({strategy: address(protocolA), targetBps: protocolATargetBps});
        newAllocations[1] = MultiStrategyVault.Allocation({strategy: address(protocolB), targetBps: protocolBTargetBps});
        vm.expectRevert(MultiStrategyVault.MultiStrategyVault__AllocationExceedsMaxBpsPerStrategy.selector);
        multiStrategyVault.setAllocations(newAllocations);
        vm.stopPrank();
    }

    function testConcentrationRiskOnNewDeposit() public {
        uint256 depositAmount = 1000 ether;
        depositToVault(user1, depositAmount);

        // Currently, strategy 1 has 10% deposit i.e 100 ether
        //  Strategy 2 has 20% deposit i.e 200 ether
        //  Strategy 3 has 30% deposit i.e 300 ether

        // Simulate 50% yield on protocol A
        vm.startPrank(yieldProvider1);
        uint256 yieldBps = 5000; // 50% yield
        uint256 yieldAmount = (MockInstantStrategy(strategy1).totalAssets() * yieldBps) / MAX_BPS;
        MockERC20(mUSDC).approve(strategy1, yieldAmount);
        MockInstantStrategy(strategy1).simulateYield(yieldAmount);
        vm.stopPrank();

        // Now strategy 1 has 150 ether because of yield

        depositToVault(user2, depositAmount);
        // On new deposit, if checks were not in place, strategy 1 would receive 100 ether
        // However, it should receive only 55 ether to prevent concentration risk. (10% of total 2050 ether = 205 ether)
        assertEq(MockInstantStrategy(strategy1).totalAssets(), 205 ether);
    }
}
