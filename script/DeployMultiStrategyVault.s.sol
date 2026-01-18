// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {HelperConfig} from "./HelperConfig.s.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {Script} from "forge-std/Script.sol";
import {MultiStrategyVault} from "../src/MultiStrategyVault.sol";
import {MockInstantStrategy} from "../src/MockInstantStrategy.sol";
import {MockLockedStrategy} from "../src/MockLockedStrategy.sol";

contract DeployMultiStrategyVault is Script {
    function run() external {
        deployContract();
    }

    function deployContract() public returns (MultiStrategyVault, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        address account = helperConfig.activeNetworkConfig();

        vm.startBroadcast(account);
        MockERC20 mockedUSDC = new MockERC20("Mock USDC", "mUSDC", 18);
        MultiStrategyVault multiStrategyVault = new MultiStrategyVault(mockedUSDC);

        MockInstantStrategy instantStrategy = new MockInstantStrategy(mockedUSDC);
        MockLockedStrategy lockedStrategy1 = new MockLockedStrategy(mockedUSDC);
        MockLockedStrategy lockedStrategy2 = new MockLockedStrategy(mockedUSDC);

        MultiStrategyVault.Allocation[] memory allocations = new MultiStrategyVault.Allocation[](3);
        allocations[0] = MultiStrategyVault.Allocation({strategy: address(instantStrategy), targetBps: 1000});
        allocations[1] = MultiStrategyVault.Allocation({strategy: address(lockedStrategy1), targetBps: 2000});
        allocations[2] = MultiStrategyVault.Allocation({strategy: address(lockedStrategy2), targetBps: 3000});
        multiStrategyVault.setAllocations(allocations);
        vm.stopBroadcast();
        return (multiStrategyVault, helperConfig);
    }
}
