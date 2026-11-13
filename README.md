# IMDwindowshopper (WWW)

A plain, fixed-supply ERC-20 token for an IMD custom-token launch on Ethereum (chain id 1).

| Setting          | Value                                                 |
| ---------------- | ----------------------------------------------------- |
| Solidity contract | `WindowShopperToken` (`src/WindowShopperToken.sol`)  |
| Token name       | `IMDwindowshopper`                                    |
| Token symbol     | `WWW`                                                 |
| Decimals         | 18                                                    |
| Total supply     | 1,000,000,000 WWW = `1000000000000000000000000000` minor units |
| Minting          | Once, in the constructor, whole supply to `msg.sender` (the deployer) |
| Constructor args | none                                                  |
| Owner / admin    | none                                                  |

## What the contract does

`WindowShopperToken` inherits OpenZeppelin v5.4.0 `ERC20` and adds nothing but constants and a
constructor that mints `TOTAL_SUPPLY` to `msg.sender`. After deployment the contract has:

- no `mint`, so the supply can never grow;
- no `burn`, so the supply never shrinks through the contract either (holders may still send tokens
  to an address nobody controls, which is their business);
- no owner, pause, blacklist, freeze, fee, tax or reflection; every `transfer` and `transferFrom`
  moves exactly the amount requested;
- `transferFrom` moves tokens only under an allowance the holder granted, so no privileged caller,
  the deployer included, can pull or freeze a holder's balance;
- no upgradeability, no `delegatecall`, no `selfdestruct`, no `receive`/`fallback` (plain ETH sent
  to it reverts).

The token's constructor makes no external calls and needs no other contract to exist, so it deploys
on an empty chain exactly as the launch checks require.

## Deployment parameters

The launch deploys the contract from its built bytecode through the IMD factory. The factory is
`msg.sender` of the constructor, so the factory receives the whole supply and pays it out as the
launch manifest says (swarm share to the MerkleDistributor, pool seed, remainder to the requester).
Nothing in this repository mints, reserves or holds any of the supply.

Build configuration (`foundry.toml`): `solc = "0.8.26"`, `evm_version = "cancun"`, optimizer on with
200 runs, `via_ir = false`, `bytecode_hash = "none"` and `cbor_metadata = false` so the deployed bytes
reproduce without a metadata hash, `ffi = false`, no filesystem permissions.

Values the manifest step needs, all fixed by this source:

- `token.contract`: `WindowShopperToken`
- `token.name`: `IMDwindowshopper`
- `token.symbol`: `WWW`
- `token.decimals`: `18`
- `token.totalSupply`: `1000000000000000000000000000`
- `token.constructorArgs`: `[]`
- `contracts`: `[]` (no application contracts)

The launch's pool, fee, tick spacing, economics and remainder recipient are decided by the launch
and written by the manifest step; nothing here depends on them.

`script/DeployWindowShopperToken.s.sol` is a reference deployment for local and review use only.
Its `deploy()` function is what the tests call; `run()` wraps it in a broadcast. It is never used
for the launch itself and this repository holds no keys and broadcasts nothing.

## After launch

There is nothing to configure. The contract has no owner and no setters.

## Assumptions

- The requester wants a plain token: the brief asks only for name, symbol and a fixed supply minted
  once to the deployer, so no burn, tax, vesting, governance or admin feature was added.
- "Deployer" means `msg.sender` of the constructor. At launch that is the IMD factory; in the
  reference script it is the broadcasting account.
- 18 decimals and the supply of 1,000,000,000 are taken from the brief verbatim; nothing is left
  open for the requester to choose.
- The `TOKEN_*` and `TOTAL_SUPPLY` constants are public so integrators can read the fixed values
  on chain without parsing the bytecode.

## Operational responsibilities

- **Supply distribution** is entirely the factory's and the launch policy's: the contract cannot
  influence or recover any of it. Whoever holds tokens is responsible for them; there is no admin
  recovery path by design.
- **No upgrade path.** A change in behaviour needs a new token; this one cannot be modified.
- **Explorer verification** of the deployed contract is the launch deployer's step, using the same
  compiler settings as `foundry.toml`.
- **Allowances** follow standard ERC-20 semantics. Holders should prefer exact approvals; an
  allowance of `type(uint256).max` is treated as infinite and never decreases.
- **Security review.** Tests passing are not an audit. The only logic is OpenZeppelin's audited
  `ERC20` plus a constructor mint, but an independent adversarial review before release remains the
  release policy's responsibility. Slither was not run here (not available on this worker); the
  source avoids every pattern the verifier's Slither detectors reject (no `selfdestruct`, no
  `delegatecall`, no `abi.encodePacked` of dynamic values, no initializers, no library linking).

## Repository layout

```
foundry.toml                         compiler pins and build settings
remappings.txt                       forge-std and @openzeppelin/contracts remappings
src/WindowShopperToken.sol           the token
script/DeployWindowShopperToken.s.sol reference deploy script
test/WindowShopperToken.t.sol        behaviour tests (success, failure and fuzz)
test/DeployWindowShopperToken.t.sol  deploy script test
lib/forge-std                        vendored forge-std 1.17.0 (src only, MIT/Apache-2.0)
lib/openzeppelin-contracts           vendored OpenZeppelin Contracts 5.4.0 (contracts only, MIT)
```

Dependencies are vendored as ordinary files, not git submodules, so the project builds offline.

## Running the checks

```
forge build
forge test
forge fmt --check
```

The fuzz tests were also run with the verifier's seed:

```
FOUNDRY_FUZZ_SEED=0x86ae9957cc95ac90e27598b23bd65a13024d6ca21599e436600080a2dc7dd5f6 forge test
```

### Test coverage summary

- metadata (`name`, `symbol`, `decimals`) and the exact supply constant;
- the whole supply is minted to the deployer, both a contract deployer and an EOA, with exactly one
  `Transfer` event from the zero address in the constructor;
- `transfer`: exact amounts, multi-hop conservation, zero amount, self-transfer, insufficient
  balance revert, zero-address receiver revert;
- `approve` / `transferFrom`: allowance accounting, infinite allowance, missing allowance, allowance
  exceeded, balance exceeded, and that the deployer cannot pull a holder's balance;
- no mint, burn, owner, pause, blacklist, upgrade or initialize selector is callable by anyone;
- plain ETH is rejected;
- runtime bytecode contains no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT` and fits EIP-170;
- fuzz: transfers conserve supply, over-balance transfers revert with the exact error, and
  `transferFrom` respects allowance and balance for arbitrary inputs.
