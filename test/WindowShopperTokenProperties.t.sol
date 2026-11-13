// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WindowShopperToken} from "src/WindowShopperToken.sol";

/// @notice Boundary and sequence properties supplementing the original deployment/ERC-20 tests.
/// forge-config: default.fuzz.runs = 1000
contract WindowShopperTokenPropertiesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    WindowShopperToken private token;
    address private alice = makeAddr("property-alice");
    address private bob = makeAddr("property-bob");
    address private carol = makeAddr("property-carol");

    function setUp() public {
        token = new WindowShopperToken();
    }

    function test_oneWeiRoundTripIsExact() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_fullSupplyCanMoveAndReturn() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_fullSupplySelfTransferEmitsAndPreservesState() public {
        bytes32 beforeState = _stateDigest();
        vm.expectEmit(address(token));
        emit IERC20.Transfer(address(this), address(this), SUPPLY);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(_stateDigest(), beforeState);
    }

    function test_selfTransferStillRequiresSufficientBalance() public {
        token.transfer(alice, 1);
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(alice);
        token.transfer(alice, 2);
        assertEq(_stateDigest(), beforeState);
    }

    function test_maximumTransferRevertsWithoutOverflowOrMutation() public {
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(bob, type(uint256).max);
        assertEq(_stateDigest(), beforeState);
    }

    function test_zeroTransferToZeroAddressStillReverts() public {
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(_stateDigest(), beforeState);
    }

    function test_zeroApprovalToZeroSpenderStillReverts() public {
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(_stateDigest(), beforeState);
    }

    function test_zeroTransferFromWithoutBalanceOrApprovalEmitsAndPreservesState() public {
        bytes32 beforeState = _stateDigest();
        vm.expectEmit(address(token));
        emit IERC20.Transfer(alice, carol, 0);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, 0));
        assertEq(_stateDigest(), beforeState);
    }

    function test_transferFromZeroOwnerCannotMintEvenWithZeroAmount() public {
        bytes32 beforeState = _stateDigest();
        // A zero owner is invalid regardless of amount. Do not require a particular error
        // precedence between the allowance check and the sender check for this invalid input.
        vm.expectRevert();
        vm.prank(bob);
        token.transferFrom(address(0), carol, 0);
        assertEq(_stateDigest(), beforeState);
        vm.expectRevert();
        vm.prank(bob);
        token.transferFrom(address(0), carol, 1);
        assertEq(_stateDigest(), beforeState);
    }

    function test_zeroTransferFromToZeroReceiverStillReverts() public {
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(bob);
        token.transferFrom(alice, address(0), 0);
        assertEq(_stateDigest(), beforeState);
    }

    function test_fullSupplyDelegatedTransferExhaustsFiniteAllowance() public {
        _approve(address(this), bob, SUPPLY);
        vm.expectEmit(address(token));
        emit IERC20.Transfer(address(this), alice, SUPPLY);
        vm.prank(bob);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(address(this), bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_holderUsingTransferFromNeedsItsOwnAllowance() public {
        token.transfer(alice, 2);
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(alice, bob, 1);
        assertEq(_stateDigest(), beforeState);

        _approve(alice, alice, 2);
        vm.prank(alice);
        assertTrue(token.transferFrom(alice, alice, 2));
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.allowance(alice, alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromToSpenderCreditsSpender() public {
        token.transfer(alice, 2);
        _approve(alice, bob, 2);
        vm.expectEmit(address(token));
        emit IERC20.Transfer(alice, bob, 2);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, bob, 2));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 2);
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromToOwnerSpendsFiniteAllowanceWithoutMovingBalance() public {
        token.transfer(alice, 2);
        _approve(alice, bob, 2);
        vm.expectEmit(address(token));
        emit IERC20.Transfer(alice, alice, 2);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, alice, 2));
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteAllowanceSelfTransferPreservesState() public {
        token.transfer(alice, SUPPLY);
        _approve(alice, bob, type(uint256).max);
        bytes32 beforeState = _stateDigest();
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, alice, SUPPLY));
        assertEq(_stateDigest(), beforeState);
    }

    function test_maximumMinusOneAllowanceIsFinite() public {
        token.transfer(alice, 1);
        _approve(alice, bob, type(uint256).max - 1);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, 1));
        assertEq(token.allowance(alice, bob), type(uint256).max - 2);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(carol), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteAllowanceDoesNotPermitMaximumTransferFrom() public {
        token.transfer(alice, SUPPLY);
        _approve(alice, bob, type(uint256).max);
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, SUPPLY, type(uint256).max)
        );
        vm.prank(bob);
        token.transferFrom(alice, carol, type(uint256).max);
        assertEq(_stateDigest(), beforeState);
    }

    function test_approvalBelongsToCallerAndCannotAuthorizeAnotherHolder() public {
        token.transfer(alice, 1);
        _approve(bob, carol, type(uint256).max);
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, carol, 0, 1));
        vm.prank(carol);
        token.transferFrom(alice, bob, 1);
        assertEq(_stateDigest(), beforeState);
    }

    function test_revokedInfiniteApprovalCannotBeUsedAgain() public {
        token.transfer(alice, 3);
        _approve(alice, bob, type(uint256).max);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, 1));
        assertEq(token.allowance(alice, bob), type(uint256).max);
        _approve(alice, bob, 0);
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(alice, carol, 1);
        assertEq(_stateDigest(), beforeState);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(carol), 1);
    }

    function test_replacingInfiniteApprovalWithFiniteApprovalSetsNewLimit() public {
        token.transfer(alice, 3);
        _approve(alice, bob, type(uint256).max);
        _approve(alice, bob, 1);
        assertEq(token.allowance(alice, bob), 1);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, 1));
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(carol), 1);
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(alice, carol, 1);
        assertEq(_stateDigest(), beforeState);
    }

    function test_failedBalanceCheckDoesNotConsumeApprovalAndCanBeRetried() public {
        _approve(alice, bob, 1);
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(bob);
        token.transferFrom(alice, carol, 1);
        assertEq(_stateDigest(), beforeState);

        token.transfer(alice, 1);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, 1));
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(carol), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToTokenContractIsAccountedWithoutBurning() public {
        assertTrue(token.transfer(address(token), SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_nonpayableERC20CallRejectsValueWithoutApproving() public {
        vm.deal(alice, 1);
        bytes32 beforeState = _stateDigest();
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1}(abi.encodeCall(IERC20.approve, (bob, 1)));
        assertFalse(ok);
        assertEq(_stateDigest(), beforeState);
        assertEq(alice.balance, 1);
        assertEq(address(token).balance, 0);
    }

    function testFuzz_roundTripPreservesBalancesAndUnrelatedApprovals(uint256 amount, uint256 approval) public {
        amount = bound(amount, 0, SUPPLY);
        _approve(alice, bob, approval);
        bytes32 beforeState = _stateDigest();
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        vm.prank(bob);
        assertTrue(token.transfer(address(this), amount));
        assertEq(_stateDigest(), beforeState);
    }

    function testFuzz_approveOverwritesAndIsIdempotent(uint256 previous, uint256 replacement) public {
        _approve(alice, carol, 7);
        _approve(bob, alice, 11);
        _approve(alice, bob, previous);
        vm.expectEmit(address(token));
        emit IERC20.Approval(alice, bob, replacement);
        _approve(alice, bob, replacement);
        assertEq(token.allowance(alice, bob), replacement);
        assertEq(token.allowance(alice, carol), 7);
        assertEq(token.allowance(bob, alice), 11);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
        bytes32 beforeState = _stateDigest();
        _approve(alice, bob, replacement);
        assertEq(_stateDigest(), beforeState);
    }

    function testFuzz_finiteApprovalCannotBeSpentTwice(uint256 approved, uint256 first) public {
        approved = bound(approved, 1, SUPPLY - 1);
        first = bound(first, 0, approved);
        token.transfer(alice, SUPPLY);
        _approve(alice, bob, approved);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, first));
        assertEq(token.allowance(alice, bob), approved - first);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, approved - first));
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.balanceOf(alice), SUPPLY - approved);
        assertEq(token.balanceOf(carol), approved);
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(alice, carol, 1);
        assertEq(_stateDigest(), beforeState);
    }

    function testFuzz_infiniteApprovalSurvivesRepeatedSpending(uint256 first) public {
        first = bound(first, 0, SUPPLY);
        token.transfer(alice, SUPPLY);
        _approve(alice, bob, type(uint256).max);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, first));
        assertEq(token.allowance(alice, bob), type(uint256).max);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, SUPPLY - first));
        assertEq(token.allowance(alice, bob), type(uint256).max);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(carol), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceIsAtomic(uint256 held, uint256 requested) public {
        held = bound(held, 0, SUPPLY);
        requested = bound(requested, held + 1, type(uint256).max);
        token.transfer(alice, held);
        _approve(alice, bob, type(uint256).max);
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, requested));
        vm.prank(alice);
        token.transfer(carol, requested);
        assertEq(_stateDigest(), beforeState);
    }

    function testFuzz_transferFromAboveAllowanceIsAtomic(uint256 held, uint256 approved, uint256 requested) public {
        held = bound(held, 1, SUPPLY);
        approved = bound(approved, 0, held - 1);
        requested = bound(requested, approved + 1, held);
        token.transfer(alice, held);
        _approve(alice, bob, approved);
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, approved, requested)
        );
        vm.prank(bob);
        token.transferFrom(alice, carol, requested);
        assertEq(_stateDigest(), beforeState);
    }

    function testFuzz_transferFromAboveBalanceRestoresFiniteApproval(uint256 held, uint256 requested, uint256 approved)
        public
    {
        held = bound(held, 0, SUPPLY);
        requested = bound(requested, held + 1, type(uint256).max - 1);
        approved = bound(approved, requested, type(uint256).max - 1);
        token.transfer(alice, held);
        _approve(alice, bob, approved);
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, requested));
        vm.prank(bob);
        token.transferFrom(alice, carol, requested);
        assertEq(_stateDigest(), beforeState);
    }

    function testFuzz_transferFromToZeroRestoresAllowance(uint256 amount, uint256 approved, bool infinite) public {
        amount = bound(amount, 0, SUPPLY);
        approved = infinite ? type(uint256).max : bound(approved, amount, type(uint256).max - 1);
        token.transfer(alice, SUPPLY);
        _approve(alice, bob, approved);
        bytes32 beforeState = _stateDigest();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(bob);
        token.transferFrom(alice, address(0), amount);
        assertEq(_stateDigest(), beforeState);
    }

    function testFuzz_delegatedSelfTransferHasNoBalanceEffect(uint256 held, uint256 amount, uint256 approved) public {
        held = bound(held, 0, SUPPLY);
        amount = bound(amount, 0, held);
        approved = bound(approved, amount, type(uint256).max - 1);
        token.transfer(alice, held);
        _approve(alice, bob, approved);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, alice, amount));
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(address(this)), SUPPLY - held);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, bob), approved - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
    }

    /// @dev Compare the entire reachable balance/allowance ledger across a rejected operation.
    /// This catches collateral changes, including allowance consumption before a transfer reverts.
    function _stateDigest() private view returns (bytes32 digest) {
        address[6] memory accounts = [address(this), alice, bob, carol, address(token), address(0)];
        digest = keccak256(abi.encode(token.totalSupply()));
        for (uint256 i; i < accounts.length; ++i) {
            digest = keccak256(abi.encode(digest, token.balanceOf(accounts[i])));
            for (uint256 j; j < accounts.length; ++j) {
                digest = keccak256(abi.encode(digest, token.allowance(accounts[i], accounts[j])));
            }
        }
    }
}
