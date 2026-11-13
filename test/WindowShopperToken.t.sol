// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WindowShopperToken} from "../src/WindowShopperToken.sol";

/// @notice Stands in for the launch factory: deploys the token so that `msg.sender` of the
/// constructor is a contract, exactly as it will be at launch.
contract DeployerProbe {
    function deploy() external returns (WindowShopperToken) {
        return new WindowShopperToken();
    }

    function send(WindowShopperToken token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract WindowShopperTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    DeployerProbe internal deployer;
    WindowShopperToken internal token;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public {
        deployer = new DeployerProbe();
        token = deployer.deploy();
    }

    // ---------------------------------------------------------------- metadata and supply

    function test_metadata() public view {
        assertEq(token.name(), "IMDwindowshopper");
        assertEq(token.symbol(), "WWW");
        assertEq(token.decimals(), 18);
        assertEq(token.TOKEN_NAME(), "IMDwindowshopper");
        assertEq(token.TOKEN_SYMBOL(), "WWW");
        assertEq(token.TOKEN_DECIMALS(), 18);
    }

    function test_supplyIsOneBillionWithEighteenDecimals() public view {
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), 1_000_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_wholeSupplyMintedToDeployerInConstructor() public view {
        assertEq(token.balanceOf(address(deployer)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_constructorEmitsSingleMintTransfer() public {
        DeployerProbe other = new DeployerProbe();
        vm.recordLogs();
        WindowShopperToken fresh = other.deploy();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "exactly one event in the constructor");
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics[0], IERC20.Transfer.selector);
        assertEq(address(uint160(uint256(logs[0].topics[1]))), address(0));
        assertEq(address(uint160(uint256(logs[0].topics[2]))), address(other));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_eoaDeployerAlsoReceivesWholeSupply() public {
        vm.prank(alice);
        WindowShopperToken fresh = new WindowShopperToken();
        assertEq(fresh.balanceOf(alice), SUPPLY);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    // ---------------------------------------------------------------- transfer

    function test_transferMovesExactAmount() public {
        uint256 amount = 1_234 ether;
        vm.expectEmit(address(token));
        emit IERC20.Transfer(address(deployer), alice, amount);
        assertTrue(deployer.send(token, alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(deployer)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferChainArrivesWholeAtEveryHop() public {
        uint256 amount = 10_000 ether;
        deployer.send(token, alice, amount);
        vm.prank(alice);
        token.transfer(bob, amount);
        vm.prank(bob);
        token.transfer(carol, amount);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(carol), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferOfZeroSucceeds() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        deployer.send(token, alice, 5 ether);
        vm.prank(alice);
        token.transfer(alice, 5 ether);
        assertEq(token.balanceOf(alice), 5 ether);
    }

    function test_transferRevertsOnInsufficientBalance() public {
        deployer.send(token, alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1 ether, 1 ether + 1)
        );
        token.transfer(bob, 1 ether + 1);
    }

    function test_transferRevertsToZeroAddress() public {
        deployer.send(token, alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
    }

    // ---------------------------------------------------------------- approve / transferFrom

    function test_approveSetsAllowanceAndEmits() public {
        vm.prank(alice);
        vm.expectEmit(address(token));
        emit IERC20.Approval(alice, bob, 7 ether);
        assertTrue(token.approve(bob, 7 ether));
        assertEq(token.allowance(alice, bob), 7 ether);
    }

    function test_approveRevertsForZeroSpender() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_transferFromSpendsAllowance() public {
        deployer.send(token, alice, 100 ether);
        vm.prank(alice);
        token.approve(bob, 60 ether);

        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, 40 ether));

        assertEq(token.balanceOf(alice), 60 ether);
        assertEq(token.balanceOf(carol), 40 ether);
        assertEq(token.allowance(alice, bob), 20 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromWithInfiniteAllowanceDoesNotDecrease() public {
        deployer.send(token, alice, 100 ether);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        token.transferFrom(alice, carol, 100 ether);
        assertEq(token.allowance(alice, bob), type(uint256).max);
        assertEq(token.balanceOf(carol), 100 ether);
    }

    function test_transferFromRevertsWithoutAllowance() public {
        deployer.send(token, alice, 100 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1 ether));
        token.transferFrom(alice, carol, 1 ether);
    }

    function test_transferFromRevertsAboveAllowance() public {
        deployer.send(token, alice, 100 ether);
        vm.prank(alice);
        token.approve(bob, 10 ether);
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 10 ether, 11 ether)
        );
        token.transferFrom(alice, carol, 11 ether);
    }

    function test_transferFromRevertsAboveBalanceEvenWithAllowance() public {
        deployer.send(token, alice, 5 ether);
        vm.prank(alice);
        token.approve(bob, 100 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5 ether, 6 ether));
        token.transferFrom(alice, carol, 6 ether);
    }

    /// @dev `transferFrom` moves tokens only under an allowance the holder granted; a would-be
    /// privileged caller, the deployer included, cannot pull a holder's balance.
    function test_deployerCannotPullHolderBalance() public {
        deployer.send(token, alice, 10 ether);
        vm.prank(address(deployer));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(deployer), 0, 1)
        );
        token.transferFrom(alice, address(deployer), 1);
        assertEq(token.balanceOf(alice), 10 ether);
    }

    // ---------------------------------------------------------------- no admin surface

    function test_noMintOrAdminSelectorIsCallable() public {
        string[14] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "owner()",
            "transferOwnership(address)",
            "renounceOwnership()",
            "pause()",
            "unpause()",
            "blacklist(address)",
            "setBlacklist(address,bool)",
            "upgradeTo(address)",
            "initialize(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, type(uint128).max);
            vm.prank(address(deployer));
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            vm.prank(alice);
            (ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_rejectsPlainEther() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
    }

    function test_runtimeCodeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "runtime exceeds EIP-170");
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xF4, "DELEGATECALL");
            assertTrue(op != 0xF2, "CALLCODE");
            assertTrue(op != 0xFF, "SELFDESTRUCT");
        }
    }

    // ---------------------------------------------------------------- fuzz

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != address(deployer));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(deployer.send(token, to, amount));
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(address(deployer)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY - 1);
        amount = bound(amount, held + 1, SUPPLY);
        deployer.send(token, alice, held);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount));
        token.transfer(bob, amount);
    }

    function testFuzz_transferFromRespectsAllowance(uint256 held, uint256 allowed, uint256 amount) public {
        held = bound(held, 0, SUPPLY);
        allowed = bound(allowed, 0, type(uint256).max - 1);
        amount = bound(amount, 0, SUPPLY);
        deployer.send(token, alice, held);
        vm.prank(alice);
        token.approve(bob, allowed);

        vm.prank(bob);
        if (amount > allowed) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, allowed, amount)
            );
            token.transferFrom(alice, carol, amount);
        } else if (amount > held) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount));
            token.transferFrom(alice, carol, amount);
        } else {
            assertTrue(token.transferFrom(alice, carol, amount));
            assertEq(token.balanceOf(carol), amount);
            assertEq(token.balanceOf(alice), held - amount);
            assertEq(token.allowance(alice, bob), allowed - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }
}
