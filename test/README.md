# Token test coverage

Run `forge build` and `forge test` from the repository root. The tests use the
existing local `TestSupport.sol` and require no packages, RPC, environment
variables, filesystem cheatcodes or changes to Foundry configuration.

- `SIMDTESTToken.t.sol` retains the original constructor, ERC-20, launch transfer,
  admin rejection, event and runtime opcode tests. Its four fuzz properties now
  each run 1,000 cases through inline configuration.
- `SIMDTESTToken.adversarial.t.sol` adds allowance replay and replacement,
  self-spending authorization, maximum finite versus infinite approval,
  insufficient-balance rollback followed by a valid spend, truncated calldata,
  nonpayable entry points, contract recipients, and full-supply round trips
  before and after advancing time. Each new fuzz property runs 1,000 cases.
- `SIMDTESTToken.invariant.t.sol` runs 256 sequences of 128 calls. A handler mixes
  direct transfers, approvals, delegated transfers and rejected admin calls.
  Inputs include zero, full balances, excess balances/allowances, maximum uint,
  self-transfers, revocations and invalid zero addresses. The independent model
  checks every tracked balance and allowance after each call, including failed
  calls, and verifies that balances sum to the original fixed supply. Initial
  balances come from constructor minting and real transfers; token storage is
  never overwritten. Receive-only destinations include the token contract and
  the assignment's remainder address. Unexpected handler reverts fail the run.
  A deterministic sequence also checks that the handler exercises nonzero
  direct/delegated spending and rejected operations.

The actor addresses are local fixtures, except the PoolManager and remainder
addresses explicitly provided by the assignment. The PoolManager actor tests
token accounting only. This suite does not deploy Uniswap v4 or the launch
factory, validate Merkle proofs, or execute pool initialization or swaps. The
pinned protected harness separately exercises factory-style deployment, pool
initialization, seeding and swaps with a real local v4 manager; it is not part
of this repository's runnable suite. End-to-end validation against the deployed
mainnet launch infrastructure remains owed.

Review of the supplied implementation and manifest found no confirmed defect
requiring a finding. These tests do not establish correctness of external launch
infrastructure or future deployments.
