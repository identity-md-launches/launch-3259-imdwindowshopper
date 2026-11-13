// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {WindowShopperToken} from "../src/WindowShopperToken.sol";

/// @title Deploy script for WindowShopperToken
/// @notice Reference deployment only. The IMD launch deploys the token from its built bytecode
/// through the factory, so this script is for local and review use, never for the launch itself.
/// @dev The token takes no constructor arguments, so there is nothing to configure. `deploy()` is
/// the function tests call directly; `run()` only wraps it in a broadcast.
contract DeployWindowShopperToken is Script {
    /// @notice Deploys the token. Whoever calls this (the broadcaster) receives the whole supply.
    function deploy() public returns (WindowShopperToken token) {
        token = new WindowShopperToken();
    }

    /// @notice Broadcast entry point for `forge script`.
    function run() external returns (WindowShopperToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
