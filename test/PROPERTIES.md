# WWW test properties

The original deployment and ERC-20 tests remain intact. The additional tests use
the real `WindowShopperToken` and the repository's vendored dependencies. They
require no RPC, external packages, environment-dependent addresses, or fixtures
from `test/scratch/`.

## Discovery and scope

The five discovery passes below apply the supplied Pashov fizz guide. Input
generation, explicit boundary examples, and the review for vacuous properties
follow the supplied Trail of Bits property-based testing guide. These are manual
passes; no subagents or additional fuzzing frameworks are used.

| Pass | Contract evidence | Properties selected |
| --- | --- | --- |
| Conservation | `src/WindowShopperToken.sol:26-30`; inherited `ERC20.sol:176-208` | The supply remains exactly `1_000_000_000 * 10**18`; all balances sum to it; each holder has exactly its initial allocation plus authorized receipts minus authorized payments. |
| State transitions | Inherited `ERC20.sol:99-146,273-306` | Approvals overwrite only the caller/spender pair; finite approvals decrease only on successful delegated transfers; unlimited approvals remain unlimited until overwritten or revoked. Rejected calls preserve the entire observable ledger. |
| Round trips | Inherited `ERC20.sol:159-208`; token has no transfer overrides | A transfer through two other holders and back restores balances and allowances exactly. Self-transfers preserve balances while delegated self-transfers still consume finite allowance. No rounding tolerance is appropriate for this integer ledger. |
| Adversarial sequences | Token exposes no mint, burn, owner, pause, or freeze functions | Overspending, unauthorized spending, and zero recipients/spenders fail without mutation. An unlimited allowance does not bypass balance checks. Every active holder can transfer its full balance after a random sequence. |
| Token semantics | `src/WindowShopperToken.sol:15-35`; inherited ERC-20 public interface | Metadata remains fixed; zero transfers to valid recipients succeed and emit events; a zero owner cannot mint; the zero address never holds tokens. Tokens sent to the token contract remain part of the supply. |

Inherited line references refer to
`lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol`.
These properties follow the task's fixed-supply requirements, the accepted
contract's public behavior, and exact balance accounting. There is no vault,
exchange, fee calculation, governance, or separate application contract in this
implementation to which the other protocol templates would apply.

## Executable coverage

`WindowShopperTokenProperties.t.sol` adds deterministic boundaries and nine fuzz
properties, with 1,000 examples per property. The deterministic cases include
zero, one minor unit, the full supply, `uint256.max - 1`, and `uint256.max`.
Failure tests compare a digest of the total supply, all reachable balances, and
all allowance pairs before and after the rejected operation. They also check
the precise custom error where the invalid input has an unambiguous cause.

`WindowShopperTokenInvariant.t.sol` targets only the eleven action selectors of
`handlers/WindowShopperTokenHandler.sol`, with 256 runs at depth 64. Its four
always-on properties check:

1. The specified supply and metadata never change.
2. Actual balances match authorized flows and sum to the specified supply.
3. All allowances match approvals, revocations, and successful delegated spending.
4. Valid calls return true; invalid calls revert with the expected error.

The handler deploys the token itself and distributes the constructor mint among
five active holders, including that actual deployer. The token contract is an
additional recipient whose balance is included in conservation checks. It is
never impersonated as a sender. Donations in random sequences are limited to
one sixteenth of the sender's modeled balance to retain circulating tokens;
a unit test separately sends the entire supply to the token contract.

Ghost balances start from the specification, not from token getters. Ghost
allowances start at zero. Only successful authorized actions update them, and
rejected calls leave them untouched. Bounds use this independent expected
ledger. The invariant compares **every** tracked owner/spender pair, including
the zero address and the token, so unrelated-account changes are also detected.

Unexpected low-level call results latch a failure flag rather than reverting the
handler, preventing the default invariant runner from discarding the evidence.
The handler's deterministic sequence test proves that both positive transfers
and rejected operations execute. `afterInvariant` collects every active
holder's full balance through the handler and checks all properties again.

## Reproduction

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
FOUNDRY_FUZZ_SEED=0x86ae9957cc95ac90e27598b23bd65a13024d6ca21599e436600080a2dc7dd5f6 \
  forge test --offline --out test/scratch/out --cache-path test/scratch/cache -vv
```

Output and cache paths keep local generated files inside the disposable scratch
directory. The tests also run with ordinary `forge test`; no configuration
changes are required. The supplied protected launch checks describe factory and
pool integration but depend on an external launch harness absent from this
repository. This suite exercises the submitted token locally; it does not claim
to execute that external pool integration.

Local LCOV inspection covers all lines and functions of the custom token. The
uncovered inherited code is the overridden default `decimals`, internal burning
which the token never exposes, and zero-sender/zero-mint-recipient guards that
valid callers cannot reach. Tests do not add artificial mint or burn entry points
to the implementation merely to increase a coverage percentage.
