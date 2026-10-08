# SIMDTEST launch

`src/SIMDTESTToken.sol` implements `SIMDTESTToken`, a plain ERC-20 named
**SIMDTEST** with symbol **SIMDTEST**, 18 decimals, and exactly **1,000,000,000**
tokens (`1000000000000000000000000000` minor units).

The argument-free constructor credits the entire supply to `msg.sender` and
emits the mint `Transfer` event. For this launch, the deploying caller must be
the network's launch factory. Deployment through CREATE2 also credits that
factory, not the transaction originator. The constructor performs no transfers
or external calls. `totalSupply`, name, symbol and decimals are constants.

## Token behavior

- `transfer` moves the exact requested amount. There is no fee, tax, wallet
  limit, trading gate, special-address exemption or callback.
- `approve` replaces the caller's allowance and emits `Approval`. Approving
  zero revokes an allowance. As with standard ERC-20 approvals, clients should
  account for pending spending when replacing an existing allowance.
- `transferFrom` requires the caller's allowance, including when the caller is
  the holder. Finite allowances decrease; `type(uint256).max` stays unlimited.
  Spending emits `Transfer`, without an additional `Approval` event.
- Zero-value transfers between nonzero addresses succeed and emit `Transfer`.
  Self-transfers preserve balances and still require sufficient funds.
- Insufficient balance or allowance, a zero sender/recipient, or approval to
  a zero spender reverts with an ERC-20 custom error. Failed transfers leave
  both balances and allowances unchanged.
- There is no owner, admin, mint-after-construction, burn, pause, blacklist,
  recovery, proxy or upgrade function. Supply cannot increase or decrease.
  Transfers to the specified remainder address retain their balance and do
  not reduce `totalSupply`.
- The contract has no payable entry point or fallback. It makes no external
  calls and contains no delegate execution or destruction mechanism.

Only balances and user-controlled allowances are mutable. Tokens sent to the
token contract itself cannot be recovered because it has no recovery function.

## Deployment parameters

`launch.json` is the `custom_token` manifest. Its `constructorArgs` and
application `contracts` lists are empty. The artifact is
`out/SIMDTESTToken.sol/SIMDTESTToken.json`; no initialization call is needed.

| Parameter | Fixed value |
| --- | --- |
| Deployment network | Ethereum mainnet, chain ID `1` |
| Token contract | `SIMDTESTToken` |
| Uniswap v4 PoolManager | `0x000000000004444c5dc75cB358380D2e3dE08A90` |
| Paired currency (IMD) | `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` |
| Pool fee | `3000` (0.3%) |
| Tick spacing | `60` |
| Provenance initialPrice | `"125270724187523965593206900"` |
| economics.poolBps | `9000` |
| economics.initialMarketCapWei | `"2500000000000000000000"` (2500 IMD) |
| economics.remainderTo | `0x000000000000000000000000000000000000dead` |

These addresses and economics are supplied by the assignment. The remainder
address is the explicit requested destination. The manifest has no root
`chainId` key: the launch schema does not accept one. The launch operator must
select and verify chain ID 1 separately. The token itself is chain-independent
and does not store or privilege a factory, distributor or PoolManager address.

## Launch operation

The network operator submits the compiled creation code and manifest through
the existing `ProjectFactory.launchCustom` infrastructure. This project does
not deploy replacement infrastructure or include a broadcasting script.

1. The factory deploys the token and receives its entire supply through the
   constructor. There is no separate mint call.
2. The factory transfers the swarm's 10%, **100,000,000 SIMDTEST**, to its
   Merkle distributor, which handles claims and recipient proofs externally.
   The token neither calculates nor sends this allocation automatically.
3. The factory budgets 90% of the whole supply, **900,000,000 SIMDTEST**, for
   single-sided liquidity through the specified Uniswap v4 PoolManager.
4. The factory forwards any balance remaining after distribution and seeding
   to `economics.remainderTo`. The nominal allocation leaves no remainder;
   any seeding or liquidity rounding residual still uses that destination.

`pool.initialPrice` records the supplied sqrtPriceX96 with SIMDTEST treated as
currency0. It is provenance only. The deployer derives the actual opening
price from the market cap and total supply, accounting for the deployed token
address order. In minor units, the paired-currency-per-SIMDTEST ratio is
`2500000000000000000000 / 1000000000000000000000000000`. If SIMDTEST sorts as
currency1, the reciprocal ratio is used for the pool's currency1/currency0
price. Tick selection, liquidity sizing, rounding and initialization belong
to the launch infrastructure. No price or pool calculation runs in the token.

The factory, distributor claims and traders all use ordinary ERC-20 transfers.
Pool settlement transfers to and from the PoolManager require no whitelist.
Before launch, the operator checks the network, infrastructure addresses,
compiled artifact, currency ordering and the launch's full seed/buy/sell flow.
After deployment, source verification and checking the resulting balances and
pool configuration belong to the operator. There are no token settings to
configure after launch and no privileged key to retain or renounce.

## Build and tests

Install Foundry and Solidity **0.8.26**, then run from the repository root:

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, Cancun, optimization with 200 runs, and
`bytecode_hash = "none"`. There are no package dependencies, remappings,
submodules, compiler binaries, environment-dependent tests, fork RPCs, FFI,
or filesystem cheatcode permissions. With the pinned compiler installed,
builds and tests need no network.

Tests cover constructor supply and mint events, CREATE2 factory ownership of
the initial balance, metadata, exact and full-supply transfers, events,
self/zero transfers, approval replacement/revocation, finite and unlimited
allowances, unauthorized spending, rollback on failure, absence of admin
selectors, forbidden runtime opcodes, and token accounting along distributor
and PoolManager transfer paths. Four fuzz tests exercise supply conservation,
allowance accounting, overdraw failures and sequences of transfers, with
512 cases each by default.

The local PoolManager tests exercise token-side transfers at the supplied
address; they do not execute Uniswap's pool math or a live swap. The independent
network launch harness supplies the actual v4 manager and launch machinery
for its protected integration checks. Local checks do not replace that review
or an independent adversarial review before release. Slither and Mythril have
not been run. No transactions have been broadcast.
