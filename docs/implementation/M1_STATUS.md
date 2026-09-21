# QE Engine V1 — M1 Implementation Status

Branch: `impl/qe-engine-v1-m1`

## Implemented

Core M1 contracts:

- `contracts/types/QETypes.sol`
- `contracts/token/QEToken.sol`
- `contracts/OracleRouter.sol`
- `contracts/HardTreasury.sol`
- `contracts/FacilitatorRegistry.sol`
- `contracts/CycleEscrow.sol`
- `contracts/BridgeAccounting.sol`
- `contracts/StabilityPool.sol`
- `contracts/RiskEngine.sol`
- `contracts/QEController.sol`

Interfaces and test mocks are included.

## Accounting invariant

The controller enforces after every temporary mint and burn:

```text
QEToken.temporarySupply
=
QEController.totalOutstanding
=
FacilitatorRegistry.totalOutstanding
=
CycleEscrow.totalPrincipalOutstanding
```

A stateful Foundry invariant harness exists at:

`test/invariant/QECoreInvariants.t.sol`

It randomly opens cycles and burns partial/full principal across cycle IDs.

## Security corrections made during implementation

1. Added a separate `temporarySupply` so collateral-backed/permanent supply is not confused with QE debt.
2. Bound every `facilitatorId` to an authorized operator; arbitrary callers cannot consume a QE bucket.
3. Prevented disable/re-enable of a HardTreasury asset from duplicating it in `registeredAssets` and double-counting HardNAV.
4. HardNAV excludes configured endogenous assets.
5. OracleRouter uses the minimum of independent oracle value, external TWAP value, and executable unwind value.
6. Stale/divergent oracle data returns zero conservative value.
7. RiskEngine capacity is monotonic with worsening redemption pressure/mode and can source its loss budget from the prefunded StabilityPool.
8. BridgeAccounting gives one claim exactly one accounting state and applies a pending haircut; stale/failed claims are zero.
9. StabilityPool can absorb losses only by spending prefunded external assets; it cannot count endogenous mint as capital.
10. Explicit Solidity interface `override` mismatches found in static review were corrected.

## Tests authored

Unit tests:

- `test/unit/QETypes.t.sol`
- `test/unit/QEToken.t.sol`
- `test/unit/OracleRouter.t.sol`
- `test/unit/HardTreasury.t.sol`
- `test/unit/FacilitatorRegistry.t.sol`
- `test/unit/CycleEscrow.t.sol`
- `test/unit/BridgeAccounting.t.sol`
- `test/unit/StabilityPool.t.sol`
- `test/unit/RiskEngine.t.sol`
- `test/unit/QEController.t.sol`

Stateful invariants:

- `test/invariant/QECoreInvariants.t.sol`

## Verification blocker

A Foundry GitHub Actions workflow was added, but the repository currently receives no hosted runner.

Observed on latest run:

```text
status: completed
conclusion: failure
runner_id: 0
runner_name: ""
steps: []
```

Therefore the workflow is failing before checkout/install/build/test begins.

The current branch is **implemented but not yet compiler/test verified**. No claim is made that `forge build` or `forge test` passes until a runner or local Foundry environment executes them.

## Required verification once runner is available

```bash
forge fmt --check
forge build
forge test -vv
forge test --match-contract QECoreInvariants -vv
```

M1 may be declared green only after those commands pass.

## Next gate

Do not connect arbitrage/Base execution until M1 compiles and the four-way debt invariant passes stateful testing.
