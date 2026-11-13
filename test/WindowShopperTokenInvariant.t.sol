// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {WindowShopperToken} from "src/WindowShopperToken.sol";
import {WindowShopperTokenHandler} from "./handlers/WindowShopperTokenHandler.sol";

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
contract WindowShopperTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    uint256 private constant ACTORS = 5;
    WindowShopperTokenHandler private handler;
    WindowShopperToken private token;

    function setUp() public {
        handler = new WindowShopperTokenHandler();
        token = handler.token();

        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = handler.move.selector;
        selectors[1] = handler.moveAll.selector;
        selectors[2] = handler.approve.selector;
        selectors[3] = handler.revoke.selector;
        selectors[4] = handler.spend.selector;
        selectors[5] = handler.spendAll.selector;
        selectors[6] = handler.transferTooMuch.selector;
        selectors[7] = handler.spendTooMuch.selector;
        selectors[8] = handler.invalidAddress.selector;
        selectors[9] = handler.donateToToken.selector;
        selectors[10] = handler.forbiddenCall.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyAndMetadataAreFixed() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.name(), "IMDwindowshopper");
        assertEq(token.symbol(), "WWW");
        assertEq(token.decimals(), 18);
        assertEq(token.TOKEN_NAME(), "IMDwindowshopper");
        assertEq(token.TOKEN_SYMBOL(), "WWW");
        assertEq(token.TOKEN_DECIMALS(), 18);
    }

    function invariant_balancesFollowAuthorizedFlowsAndConserveSupply() public view {
        uint256 sum;
        for (uint256 i; i < ACTORS + 1; ++i) {
            address account = _account(i);
            uint256 actual = token.balanceOf(account);
            assertEq(actual, handler.ghostBalance(account), "balance disagrees with authorized transfers");
            sum += actual;
        }
        assertEq(sum, SUPPLY, "tokens created, destroyed, or sent to an untracked recipient");
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function invariant_allowancesFollowApprovalsAndSuccessfulSpending() public view {
        // Include zero and the token: neither may acquire an approval through another actor's call.
        for (uint256 i; i < ACTORS + 2; ++i) {
            address owner = _account(i);
            for (uint256 j; j < ACTORS + 2; ++j) {
                address spender = _account(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.ghostAllowance(owner, spender),
                    "approval changed without permission, spent incorrectly, or consumed on failure"
                );
            }
        }
    }

    function invariant_validCallsSucceedAndInvalidCallsRevert() public view {
        assertFalse(handler.unexpectedCallResult(), "unexpected token return value, revert, or error data");
    }

    /// @notice Every active holder can still transfer its entire balance after any random sequence.
    function afterInvariant() public {
        for (uint256 i = 1; i < ACTORS; ++i) {
            handler.moveAll(i, 0);
            assertEq(token.balanceOf(handler.actors(i)), 0, "holder cannot empty its balance");
        }
        assertEq(
            token.balanceOf(handler.actors(0)) + token.balanceOf(address(token)),
            SUPPLY,
            "circulating tokens could not be collected"
        );
        invariant_supplyAndMetadataAreFixed();
        invariant_balancesFollowAuthorizedFlowsAndConserveSupply();
        invariant_allowancesFollowApprovalsAndSuccessfulSpending();
        invariant_validCallsSucceedAndInvalidCallsRevert();
    }

    /// @dev Deterministically exercises the handler's successful and rejected paths so that an
    /// accidentally inert handler cannot be mistaken for a passing randomized campaign.
    function test_handlerExercisesTransfersApprovalsRevocationsAndRejections() public {
        handler.move(0, 1, 1);
        handler.moveAll(4, 1);
        handler.approve(1, 2, 9, 3); // finite allowance
        handler.spend(1, 2, 3, 4);
        assertEq(token.allowance(handler.actors(1), handler.actors(2)), 5);
        handler.spendAll(1, 2, 1); // delegated self-transfer consumes the remaining allowance
        assertEq(token.allowance(handler.actors(1), handler.actors(2)), 0);
        handler.approve(1, 2, 0, 1); // unlimited allowance
        handler.spend(1, 2, 3, 1);
        assertEq(token.allowance(handler.actors(1), handler.actors(2)), type(uint256).max);
        handler.revoke(1, 2);
        assertEq(token.allowance(handler.actors(1), handler.actors(2)), 0);

        handler.transferTooMuch(1, 3, type(uint256).max);
        handler.spendTooMuch(1, 2, 3, 7, false, false);
        handler.spendTooMuch(1, 2, 3, type(uint256).max, true, false);
        handler.spendTooMuch(1, 2, 3, type(uint256).max, true, true);
        handler.invalidAddress(1, 2, 1, 0);
        handler.invalidAddress(1, 2, 0, 1);
        handler.invalidAddress(1, 2, 1, 2);
        handler.donateToToken(1, 1);
        for (uint8 mode; mode < 6; ++mode) {
            handler.forbiddenCall(0, 1, 1, mode);
        }

        assertGt(handler.nonzeroTransfers(), 0);
        assertEq(handler.nonzeroDelegatedTransfers(), 3);
        assertEq(handler.checkedRejections(), 13);
        assertEq(token.balanceOf(address(token)), 1);
        invariant_supplyAndMetadataAreFixed();
        invariant_balancesFollowAuthorizedFlowsAndConserveSupply();
        invariant_allowancesFollowApprovalsAndSuccessfulSpending();
        invariant_validCallsSucceedAndInvalidCallsRevert();
        afterInvariant();
    }

    function _account(uint256 index) private view returns (address) {
        if (index < ACTORS) return handler.actors(index);
        if (index == ACTORS) return address(token);
        return address(0);
    }
}
