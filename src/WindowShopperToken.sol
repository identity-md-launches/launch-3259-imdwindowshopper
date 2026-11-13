// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title IMDwindowshopper (WWW)
/// @notice A plain, fixed-supply ERC-20. The whole supply of 1,000,000,000 WWW (18 decimals) is
/// minted once, in the constructor, to the deployer. Nothing can mint afterwards.
/// @dev Deliberately minimal:
///  - no owner, no admin role, no pause, no blacklist, no fee or burn on transfer;
///  - no upgradeability, no delegatecall, no selfdestruct;
///  - the only supply change possible after deployment is none: this contract exposes no burn.
/// The deployer (`msg.sender` of the constructor) is the launch factory, which distributes the
/// supply according to the launch manifest. The contract itself keeps no reserve.
contract WindowShopperToken is ERC20 {
    /// @notice ERC-20 name.
    string public constant TOKEN_NAME = "IMDwindowshopper";

    /// @notice ERC-20 symbol.
    string public constant TOKEN_SYMBOL = "WWW";

    /// @notice Decimals, as the ERC-20 standard default.
    uint8 public constant TOKEN_DECIMALS = 18;

    /// @notice Whole supply in minor units: 1,000,000,000 * 10 ** 18.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(TOKEN_DECIMALS);

    /// @notice Mints the entire fixed supply to the deployer.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return TOKEN_DECIMALS;
    }
}
