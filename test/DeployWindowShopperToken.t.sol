// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeployWindowShopperToken} from "../script/DeployWindowShopperToken.s.sol";
import {WindowShopperToken} from "../src/WindowShopperToken.sol";

contract DeployWindowShopperTokenTest is Test {
    function test_deployMintsWholeSupplyToTheScriptCaller() public {
        DeployWindowShopperToken script = new DeployWindowShopperToken();
        WindowShopperToken token = script.deploy();
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        // `deploy()` is called by the script contract itself, so the script contract is the deployer.
        assertEq(token.balanceOf(address(script)), 1_000_000_000 ether);
        assertEq(token.name(), "IMDwindowshopper");
        assertEq(token.symbol(), "WWW");
        assertEq(token.decimals(), 18);
    }
}
