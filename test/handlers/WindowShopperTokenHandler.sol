// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WindowShopperToken} from "src/WindowShopperToken.sol";

/// @notice Drives the real token through its public interface; no storage edits or token deals.
/// @dev All successful recipients are enumerated: five actors plus the token itself. The model
/// starts from the specified constructor mint and changes only from requested, authorized actions.
/// Bounds come from that model, never from a potentially incorrect balance/allowance getter.
contract WindowShopperTokenHandler is Test {
    uint256 public constant SUPPLY = 1_000_000_000 ether;
    uint256 public constant ACTOR_COUNT = 5;

    WindowShopperToken public immutable token;
    address[5] public actors;
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    // Latch failures instead of reverting the handler: Forge's default invariant settings may
    // discard reverted handler calls. Every unexpected result must remain visible to an invariant.
    bool public unexpectedCallResult;
    uint256 public nonzeroTransfers;
    uint256 public nonzeroDelegatedTransfers;
    uint256 public checkedRejections;

    constructor() {
        token = new WindowShopperToken();
        actors[0] = address(this); // The actual deploying contract participates as an ordinary holder.
        actors[1] = makeAddr("invariant-alice");
        actors[2] = makeAddr("invariant-bob");
        actors[3] = makeAddr("invariant-carol");
        actors[4] = makeAddr("invariant-dana");
        ghostBalance[address(this)] = SUPPLY;
        for (uint256 i = 1; i < ACTOR_COUNT; ++i) {
            _transfer(address(this), actors[i], SUPPLY / ACTOR_COUNT);
        }
        // The counters describe randomized actions, not fixture funding.
        nonzeroTransfers = 0;
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _actor(toSeed), bound(amountSeed, 0, ghostBalance[from]));
    }

    function moveAll(uint256 fromSeed, uint256 toSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _actor(toSeed), ghostBalance[from]);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 mode) external {
        uint256 choice = uint256(mode) % 6;
        uint256 amount;
        if (choice == 0) amount = 0;
        else if (choice == 1) amount = type(uint256).max;
        else if (choice == 2) amount = type(uint256).max - 1;
        else if (choice == 3) amount = bound(amountSeed, 0, SUPPLY);
        else if (choice == 4) amount = 1;
        else amount = amountSeed; // Every uint256 is a valid approval, even with no balance.
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        _approve(_actor(ownerSeed), _actor(spenderSeed), 0);
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 available = _spendable(owner, spender);
        _spend(owner, spender, _actor(toSeed), bound(amountSeed, 0, available));
    }

    function spendAll(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        _spend(owner, spender, _actor(toSeed), _spendable(owner, spender));
    }

    function transferTooMuch(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        uint256 held = ghostBalance[from];
        uint256 amount = bound(amountSeed, held + 1, type(uint256).max);
        _reject(
            from,
            abi.encodeCall(IERC20.transfer, (_actor(toSeed), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount)
        );
    }

    function spendTooMuch(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed,
        bool exceedBalance,
        bool infinite
    ) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount;
        bytes memory error;
        if (exceedBalance) {
            uint256 held = ghostBalance[owner];
            amount = bound(amountSeed, held + 1, type(uint256).max - 1);
            if (!_approve(owner, spender, infinite ? type(uint256).max : amount)) return;
            error = abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount);
        } else {
            uint256 allowed = bound(amountSeed, 0, SUPPLY);
            if (!_approve(owner, spender, allowed)) return;
            amount = allowed + 1;
            error = abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount);
        }
        _reject(spender, abi.encodeCall(IERC20.transferFrom, (owner, _actor(toSeed), amount)), error);
    }

    function invalidAddress(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 mode) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 choice = uint256(mode) % 3;
        if (choice == 0) {
            _reject(
                owner,
                abi.encodeCall(IERC20.transfer, (address(0), bound(amountSeed, 0, ghostBalance[owner]))),
                abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
            );
        } else if (choice == 1) {
            _reject(
                owner,
                abi.encodeCall(IERC20.approve, (address(0), amountSeed)),
                abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
            );
        } else {
            uint256 amount = bound(amountSeed, 0, _spendable(owner, spender));
            _reject(
                spender,
                abi.encodeCall(IERC20.transferFrom, (owner, address(0), amount)),
                abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
            );
        }
    }

    function donateToToken(uint256 fromSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        // Keep circulating balances useful for long sequences. Full-supply donations have a
        // separate unit test. The token is tracked as a recipient, never impersonated as a sender.
        _transfer(from, address(token), bound(amountSeed, 0, ghostBalance[from] / 16));
    }

    function forbiddenCall(uint256 callerSeed, uint256 holderSeed, uint256 amountSeed, uint8 mode) external {
        address holder = _actor(holderSeed);
        bytes memory data;
        uint256 choice = uint256(mode) % 6;
        if (choice == 0) data = abi.encodeWithSignature("mint(address,uint256)", holder, amountSeed);
        else if (choice == 1) data = abi.encodeWithSignature("burn(uint256)", amountSeed);
        else if (choice == 2) data = abi.encodeWithSignature("burnFrom(address,uint256)", holder, amountSeed);
        else if (choice == 3) data = abi.encodeWithSignature("pause()");
        else if (choice == 4) data = abi.encodeWithSignature("freeze(address)", holder);
        else data = abi.encodeWithSignature("initialize(address)", holder);
        _reject(_actor(callerSeed), data, "");
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[bound(seed, 0, ACTOR_COUNT - 1)];
    }

    function _spendable(address owner, address spender) private view returns (uint256) {
        uint256 allowed = ghostAllowance[owner][spender];
        uint256 held = ghostBalance[owner];
        return allowed < held ? allowed : held;
    }

    function _transfer(address from, address to, uint256 amount) private {
        if (!_succeed(from, abi.encodeCall(IERC20.transfer, (to, amount)))) return;
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        if (amount > 0) ++nonzeroTransfers;
    }

    function _approve(address owner, address spender, uint256 amount) private returns (bool) {
        if (!_succeed(owner, abi.encodeCall(IERC20.approve, (spender, amount)))) return false;
        ghostAllowance[owner][spender] = amount;
        return true;
    }

    function _spend(address owner, address spender, address to, uint256 amount) private {
        if (!_succeed(spender, abi.encodeCall(IERC20.transferFrom, (owner, to, amount)))) return;
        ghostBalance[owner] -= amount;
        ghostBalance[to] += amount;
        if (ghostAllowance[owner][spender] != type(uint256).max) {
            ghostAllowance[owner][spender] -= amount;
        }
        if (amount > 0) ++nonzeroDelegatedTransfers;
    }

    function _succeed(address caller, bytes memory data) private returns (bool) {
        vm.prank(caller);
        (bool ok, bytes memory result) = address(token).call(data);
        // Compare ABI-encoded true without abi.decode, which could itself revert on bad data.
        if (!ok || keccak256(result) != keccak256(abi.encode(true))) {
            unexpectedCallResult = true;
            return false;
        }
        return true;
    }

    function _reject(address caller, bytes memory data, bytes memory expectedError) private {
        vm.prank(caller);
        (bool ok, bytes memory result) = address(token).call(data);
        if (ok || (expectedError.length != 0 && keccak256(result) != keccak256(expectedError))) {
            unexpectedCallResult = true;
        }
        ++checkedRejections;
        // No ghost update: the next invariant also checks that a rejected call was atomic.
    }
}
