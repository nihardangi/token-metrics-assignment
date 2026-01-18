// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {MultiStrategyVault} from "../src/MultiStrategyVault.sol";

contract HelperConfig is Script {
    address private constant PROD_DEPLOYER_ADDRESS = 0xED2C3b451e15f57bf847c60b65606eCFB73C85d9;
    address private constant ANVIL_DEPLOYER_ADDRESS = DEFAULT_SENDER;

    struct NetworkConfig {
        address account;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory networkConfig = NetworkConfig({account: PROD_DEPLOYER_ADDRESS});

        return networkConfig;
    }

    function getOrCreateAnvilEthConfig() public view returns (NetworkConfig memory) {
        if (activeNetworkConfig.account != address(0)) {
            return activeNetworkConfig;
        }
        return NetworkConfig({account: ANVIL_DEPLOYER_ADDRESS});
    }
}
