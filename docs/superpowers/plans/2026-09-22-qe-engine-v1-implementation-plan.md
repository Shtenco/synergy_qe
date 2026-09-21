# QE Engine V1 — Implementation Plan

**Design source:** docs/superpowers/specs/2026-09-21-qe-engine-v1-design.md  
**Target repository:** Shtenco/synergy_qe  
**Legacy integration source:** Shtenco/synergy_2chain_qe  
**Implementation style:** test-first, invariant-first, Base fork before mainnet  
**Solidity baseline:** 0.8.20  
**Framework:** Foundry

## 0. Definition of Done

QE Engine V1 is not done when contracts compile. It is done only when:

1. every temporary mint creates equal QE liability;
2. every successful cycle burns its full temporary principal before profit distribution;
3. permanent mint cannot reduce hard backing per permanent token;
4. endogenous assets contribute zero HardNAV;
5. internal oracle/managed gradient changes cannot alter HardNAV;
6. bridge claims cannot be double-counted;
7. LP positions cannot create HardNAV by minting the protocol's own token;
8. worsening risk inputs cannot increase mint capacity;
9. a losing route cannot become profitable through revaluation;
10. the legacy real-Base Uniswap route can be expressed as a fully-settled QE cycle;
11. all unit, fuzz, invariant, adversarial and pinned-fork tests pass.

The implementation is split into small auditable slices. Each task must leave the repository green.

---

# Phase 1 — Repository bootstrap and shared types

## Task 1.1 — Bootstrap Foundry project

Create:

- foundry.toml
- remappings.txt
- contracts/
- contracts/interfaces/
- contracts/libraries/
- contracts/token/
- test/unit/
- test/fuzz/
- test/invariant/
- test/adversarial/
- test/fork/
- script/

Use Solidity 0.8.20 and OpenZeppelin contracts.

Initial foundry profile:

~~~toml
[profile.default]
src = "contracts"
out = "out"
libs = ["lib"]
test = "test"
script = "script"
solc_version = "0.8.20"
optimizer = true
optimizer_runs = 200
via_ir = false
ffi = false

[profile.default.fuzz]
runs = 1000

[profile.default.invariant]
runs = 256
depth = 64
fail_on_revert = false

[rpc_endpoints]
base = "${BASE_RPC_URL}"
~~~

Acceptance:

~~~bash
forge build
~~~

must pass before any core contract is added.

Commit:

~~~text
build: bootstrap QE Engine V1 foundry project
~~~

---

## Task 1.2 — Add shared system types

Create:

- contracts/types/QETypes.sol

Required enums:

~~~solidity
enum SystemMode {
    NORMAL,
    DEFENSIVE,
    CONTRACTION,
    GLOBAL_SETTLEMENT
}

enum CycleState {
    NONE,
    CREATED,
    MINTED,
    DEPLOYED,
    RETURNED,
    PRINCIPAL_BURNED,
    SETTLED,
    EXPIRED,
    DEFAULTED,
    EMERGENCY_SETTLED
}

enum BridgeState {
    NONE,
    SOURCE_SETTLED,
    IN_FLIGHT,
    DESTINATION_SETTLED,
    FAILED
}
~~~

Required structs:

- AssetConfig
- FacilitatorConfig
- Cycle
- BridgeClaim
- RiskSnapshot
- ProfitWaterfallResult

No contract-specific storage logic goes into QETypes.sol.

Test:

- test/unit/QETypes.t.sol

Test only enum ordering and struct ABI assumptions that integrations depend on.

Commit:

~~~text
feat: add shared QE system types
~~~

---

# Phase 2 — Token authority and accounting boundary

## Task 2.1 — Implement QEToken.sol

Create:

- contracts/token/QEToken.sol
- contracts/interfaces/IQEToken.sol
- test/unit/QEToken.t.sol

Purpose:
one monetary token whose raw mint/burn surface is not exposed to arbitrary EOAs.

Roles:

~~~text
DEFAULT_ADMIN_ROLE
QE_CONTROLLER_ROLE
COLLATERAL_ADAPTER_ROLE
~~~

Allowed issuance paths:

1. temporary QE mint from QEController;
2. fully-collateralized mint from a collateral adapter.

Raw public governance mint is forbidden.

Required functions:

~~~solidity
function qeMint(address to, uint256 amount) external;
function collateralMint(address to, uint256 amount) external;
function burnFromController(address from, uint256 amount) external;
~~~

Tests:

1. admin EOA cannot call qeMint unless it is explicitly QEController;
2. QEController role can mint;
3. collateral adapter can mint through separate path;
4. unauthorized burn reverts;
5. totalSupply changes exactly by mint/burn amount;
6. no hidden privileged mint exists.

Acceptance:

~~~bash
forge test --match-contract QETokenTest -vv
~~~

Commit:

~~~text
feat: add role-isolated QE token
~~~

---

# Phase 3 — External pricing and HardNAV

## Task 3.1 — Implement OracleRouter.sol

Create:

- contracts/OracleRouter.sol
- contracts/interfaces/IOracleRouter.sol
- contracts/interfaces/IPriceAdapter.sol
- contracts/mocks/MockPriceAdapter.sol
- contracts/mocks/MockUnwindAdapter.sol
- test/unit/OracleRouter.t.sol
- test/fuzz/OracleRouterFuzz.t.sol

For every approved hard asset collect:

- independent oracle price;
- external TWAP price;
- executable unwind price.

Return:

~~~text
min(oracle, twap, executable)
~~~

Required protections:

- max age;
- zero price rejection;
- configurable divergence threshold;
- adapter enable/disable;
- emergency guardian disable.

Critical test:

~~~text
change any protocol-managed internal price
→ OracleRouter hard price remains unchanged
~~~

Fuzz:
for any three positive prices, conservative price equals minimum accepted price after freshness/divergence checks.

Commit:

~~~text
feat: add conservative external oracle router
~~~

---

## Task 3.2 — Implement HardTreasury.sol

Create:

- contracts/HardTreasury.sol
- contracts/interfaces/IHardTreasury.sol
- test/unit/HardTreasury.t.sol
- test/fuzz/HardTreasuryFuzz.t.sol

State:

~~~solidity
mapping(address => AssetConfig) public assetConfig;
mapping(address => uint256) public reservedForSettlement;
uint256 public externalLiabilitiesUsd18;
~~~

Core functions:

- registerAsset
- disableAsset
- hardValue
- hardNAV
- reserveForSettlement
- releaseSettlementReserve
- increaseExternalLiability
- decreaseExternalLiability
- transferApprovedAsset

HardNAV formula:

~~~text
Σ haircutted executable hard assets
- external liabilities
- reserved settlement claims
- expected exit costs
~~~

Important:
endogenous token addresses must be permanently unregistrable as hard assets.

Tests:

1. USDC balance raises HardNAV;
2. protocol token balance does not;
3. haircut lowers HardNAV;
4. external liability lowers HardNAV;
5. settlement reservation lowers available HardNAV;
6. stale oracle makes affected hard value zero or reverts according to chosen safe mode;
7. duplicate registration is safe;
8. own-token LP token cannot be registered as hard asset;
9. internal ManagedOracle cannot modify HardNAV.

Commit:

~~~text
feat: add executable hard treasury accounting
~~~

---

# Phase 4 — Facilitator buckets and QE debt

## Task 4.1 — Implement FacilitatorRegistry.sol

Create:

- contracts/FacilitatorRegistry.sol
- contracts/interfaces/IFacilitatorRegistry.sol
- test/unit/FacilitatorRegistry.t.sol
- test/fuzz/FacilitatorRegistryFuzz.t.sol

State per facilitator:

~~~solidity
struct Facilitator {
    bool enabled;
    uint128 capacity;
    uint128 outstanding;
    uint16 maxLossBps;
    uint32 maxTtl;
    uint16 riskWeightBps;
}
~~~

Functions:

- addFacilitator
- disableFacilitator
- setCapacity
- increaseOutstanding
- decreaseOutstanding
- remainingCapacity

Rules:

~~~text
outstanding <= capacity
~~~

Capacity increases:
governance timelock only.

Capacity decreases:
guardian or governance.

Tests:
- no over-cap mint accounting;
- disabling blocks new exposure but permits repayment;
- one facilitator cannot alter another bucket;
- sum of external registry values is reproducible for reconciliation.

Commit:

~~~text
feat: add isolated facilitator capacity buckets
~~~

---

## Task 4.2 — Implement QEController.sol skeleton

Create:

- contracts/QEController.sol
- contracts/interfaces/IQEController.sol
- test/unit/QEController.t.sol

Dependencies:

- QEToken
- FacilitatorRegistry
- HardTreasury
- RiskEngine interface
- CycleEscrow interface

State:

~~~solidity
uint256 public globalCapacity;
uint256 public totalOutstanding;
SystemMode public mode;
~~~

Initial functions:

- setGlobalCapacity
- setMode
- openTemporaryCycle
- mintTemporary
- burnTemporaryPrincipal
- authorizePermanentMint

Temporary mint atomic accounting order:

~~~text
1. validate system mode
2. validate facilitator
3. validate RiskEngine capacity
4. increment facilitator outstanding
5. increment global outstanding
6. record cycle liability
7. mint token
~~~

If mint reverts, all debt state reverts.

Burn order:

~~~text
1. burn token
2. decrement cycle principal
3. decrement facilitator outstanding
4. decrement global outstanding
~~~

Tests:

1. mint increases token supply and QE debt equally;
2. mint over facilitator capacity reverts;
3. mint over global capacity reverts;
4. CONTRACTION blocks new QE;
5. repayment is allowed in CONTRACTION;
6. global outstanding equals registry aggregate;
7. governance cannot bypass liability creation.

Commit:

~~~text
feat: add double-entry QE controller
~~~

---

# Phase 5 — Per-cycle escrow state machine

## Task 5.1 — Implement CycleEscrow.sol

Create:

- contracts/CycleEscrow.sol
- contracts/interfaces/ICycleEscrow.sol
- test/unit/CycleEscrow.t.sol
- test/fuzz/CycleEscrowFuzz.t.sol

Cycle state machine:

~~~text
CREATED
→ MINTED
→ DEPLOYED
→ RETURNED
→ PRINCIPAL_BURNED
→ SETTLED
~~~

Failure:
- EXPIRED
- DEFAULTED
- EMERGENCY_SETTLED

Store:

- facilitatorId;
- routeHash;
- principalMinted;
- principalBurned;
- externalValueIn;
- externalValueOut;
- realizedPnl;
- timestamps.

State transition functions must be permissioned to controller / settlement engine / facilitator.

Tests:

1. illegal state transitions revert;
2. SETTLED before full principal burn reverts;
3. expired cycle cannot deploy new capital;
4. routeHash cannot change after MINTED;
5. burned principal cannot exceed minted principal;
6. state sequence survives fuzzed valid actions.

Commit:

~~~text
feat: add temporary QE cycle escrow
~~~

---

# Phase 6 — Bridge accounting without double counting

## Task 6.1 — Implement BridgeAccounting.sol

Create:

- contracts/BridgeAccounting.sol
- contracts/interfaces/IBridgeAccounting.sol
- test/unit/BridgeAccounting.t.sol
- test/fuzz/BridgeAccountingFuzz.t.sol

Each bridge transfer receives a unique claimId.

State progression:

~~~text
SOURCE_SETTLED
→ IN_FLIGHT
→ DESTINATION_SETTLED
~~~

or:

~~~text
IN_FLIGHT
→ FAILED
~~~

Required values:

- source chain;
- destination chain;
- asset;
- nominal amount;
- source hard value;
- state;
- openedAt;
- expectedFinality;
- destination transaction hash or message id.

HardNAV contribution rules:

~~~text
SOURCE_SETTLED = source hard value
IN_FLIGHT = hard value × pending haircut
DESTINATION_SETTLED = destination hard value
FAILED = 0
~~~

Test the no-double-count invariant explicitly:

~~~text
sourceContribution
+ inFlightContribution
+ destinationContribution

must never include more than one full economic unit
~~~

Stale bridge:
after max finality age, contribution becomes zero until resolved.

Commit:

~~~text
feat: add single-count bridge claim accounting
~~~

---

# Phase 7 — Stability Pool and emergency control

## Task 7.1 — Implement StabilityPool.sol

Create:

- contracts/StabilityPool.sol
- contracts/interfaces/IStabilityPool.sol
- test/unit/StabilityPool.t.sol
- test/fuzz/StabilityPoolFuzz.t.sol

Pool assets:
external hard assets only.

Functions:

- deposit
- withdraw subject to free-liquidity rule
- reserveLossBudget
- releaseLossBudget
- absorbLoss
- availableLossBudget

Loss absorption:
must reduce real external pool assets.

It may not mint a protocol token to report a successful loss absorption.

Tests:

1. absorbed loss lowers pool balance;
2. impossible loss amount reverts;
3. reserved loss capacity cannot be withdrawn;
4. own token cannot fund StabilityPool capital.

Commit:

~~~text
feat: add pre-funded stability loss buffer
~~~

---

## Task 7.2 — Implement EmergencyShutdown.sol

Create:

- contracts/EmergencyShutdown.sol
- contracts/interfaces/IEmergencyShutdown.sol
- test/unit/EmergencyShutdown.t.sol

Guardian can:
- NORMAL → DEFENSIVE;
- NORMAL/DEFENSIVE → CONTRACTION;
- disable facilitator;
- disable bridge route;
- disable oracle adapter.

Guardian cannot:
- CONTRACTION → NORMAL;
- GLOBAL_SETTLEMENT → NORMAL;
- raise capacity;
- lower haircut.

Governance timelock can recover only after RiskEngine safety checks pass.

Commit:

~~~text
feat: add monotonic emergency shutdown controls
~~~

---

# Phase 8 — Dynamic RiskEngine

## Task 8.1 — Implement risk capacity modules

Create:

- contracts/RiskEngine.sol
- contracts/interfaces/IRiskEngine.sol
- contracts/libraries/RiskMath.sol
- test/unit/RiskEngine.t.sol
- test/fuzz/RiskEngineFuzz.t.sol

Inputs:

- HardTreasury HardNAV;
- current hard liabilities;
- current system mode;
- facilitator config;
- executable route quote;
- bridge exposure;
- StabilityPool available buffer;
- oracle health;
- redemption pressure.

Capacity:

~~~text
min(
  CollateralCapacity,
  MarketDepthCapacity,
  BridgeCapacity,
  LossBudgetCapacity,
  OracleCapacity,
  GlobalCapacity
)
~~~

RedemptionPressure:

~~~text
NetRedemptionsWindow / ExecutableExternalDepth
~~~

Monotonic fuzz properties:

- lower HardNAV cannot increase capacity;
- lower external depth cannot increase capacity;
- higher redemption pressure cannot increase capacity;
- higher bridge risk cannot increase capacity;
- stale oracle sets capacity to zero;
- mode NORMAL → DEFENSIVE cannot increase capacity.

Commit:

~~~text
feat: add monotonic dynamic QE risk engine
~~~

---

# Phase 9 — Settlement and real profit recognition

## Task 9.1 — Implement SettlementEngine.sol

Create:

- contracts/SettlementEngine.sol
- contracts/interfaces/ISettlementEngine.sol
- test/unit/SettlementEngine.t.sol
- test/fuzz/SettlementEngineFuzz.t.sol

Dependencies:
- HardTreasury;
- QEController;
- CycleEscrow;
- StabilityPool;
- BridgeAccounting.

Settlement waterfall:

~~~text
1. repay external execution liabilities
2. return bridge principal
3. reacquire temporary principal if needed
4. burn QE principal
5. restore HardCR target
6. restore StabilityPool target
7. restore bridge reserve target
8. pay approved operating cost
9. recognize remaining delta as distributable profit
~~~

Critical accounting:

~~~text
CycleProfit =
HardNAVAfter
- HardNAVBefore
- NetExternalCapitalInjection
~~~

The engine should store HardNAVBefore when cycle opens, not accept it from caller.

Tests:

1. successful profit cycle;
2. break-even cycle;
3. losing cycle;
4. principal not fully burnable;
5. external debt outstanding;
6. fake internal token appreciation;
7. owner distribution attempted before settlement;
8. realized profit cannot exceed actual external hard delta.

Commit:

~~~text
feat: add hard-nav settlement and profit recognition
~~~

---

# Phase 10 — Profit distribution after solvency

## Task 10.1 — Implement ProfitDistributor.sol

Create:

- contracts/ProfitDistributor.sol
- contracts/interfaces/IProfitDistributor.sol
- test/unit/ProfitDistributor.t.sol

Replace legacy fixed 40/30/20/10-first logic.

Order:

~~~text
RealizedProfit
→ HardCR reserve
→ StabilityPool reserve
→ bridge reserve
→ operating costs
→ distributable surplus
~~~

Only final surplus can be split.

Configurable final split may initially be:
- owner;
- treasury;
- buyback.

Test:
if HardCR target is not restored, owner receives zero.

Commit:

~~~text
feat: add solvency-first realized profit waterfall
~~~

---

# Phase 11 — External route / AMO facilitator

## Task 11.1 — Define route adapter interface

Create:

- contracts/interfaces/IRouteAdapter.sol
- contracts/routes/BaseUniswapV3Adapter.sol
- contracts/mocks/MockRouteAdapter.sol
- test/unit/BaseUniswapV3Adapter.t.sol

Adapter interface:

~~~solidity
function quote(bytes calldata routeData)
    external
    view
    returns (
        uint256 amountIn,
        uint256 expectedAmountOut,
        uint256 worstCaseAmountOut,
        uint256 estimatedGasUsd18
    );

function execute(bytes calldata routeData)
    external
    returns (
        address hardAssetReturned,
        uint256 hardAssetAmount
    );
~~~

The adapter must never report protocol-token mark-to-market profit.

Commit:

~~~text
feat: add executable route adapter boundary
~~~

---

## Task 11.2 — Implement ArbitrageFacilitator.sol

Create:

- contracts/facilitators/ArbitrageFacilitator.sol
- contracts/interfaces/IArbitrageFacilitator.sol
- test/unit/ArbitrageFacilitator.t.sol

Responsibilities:

1. receive cycleId and temporary QE inventory;
2. execute only pre-approved routeHash;
3. measure external asset balance delta;
4. return external asset to HardTreasury / settlement custody;
5. mark CycleEscrow RETURNED;
6. never call ProfitDistributor directly.

Tests:
- route mismatch reverts;
- realized hard return uses balance delta;
- quoted profit without real balance gain is zero;
- facilitator cannot open its own mint outside controller.

Commit:

~~~text
feat: add cycle-bound arbitrage facilitator
~~~

---

# Phase 12 — Migrate proven legacy Base route

## Task 12.1 — Extract legacy route facts

Read from synergy_2chain_qe:

- contracts/BridgeCore.sol
- contracts/InternalAMM.sol
- contracts/ArbitrageExecutor.sol
- test/DirectUniswapV3Harvest.t.sol
- PROFIT_MECHANICS_ATOMIC.md
- PROFIT_TEST_REPORT_2026-09-21.md

Do not copy production ArbitrageExecutor wholesale.

Produce:

- docs/migration/legacy-route-map.md

Map every legacy action to V1 component:

~~~text
legacy real USDC/WETH external leg
→ BaseUniswapV3Adapter

legacy temporary synthetic inventory
→ QEController + CycleEscrow

legacy internal swap
→ route adapter / AMM adapter

legacy bridge claims
→ BridgeAccounting

legacy treasury split
→ SettlementEngine + ProfitDistributor

legacy managed price
→ strategy signal only
~~~

Commit:

~~~text
docs: map legacy 2chain route into QE V1
~~~

---

## Task 12.2 — Port the real Base Uniswap fork test

Create:

- test/fork/BaseUniswapQEFlow.t.sol

Pinned block:
use the exact legacy known-good block first for regression reproducibility.

Initial external assets:
- Base USDC
- Base WETH

Test flow:

~~~text
hardNAVBefore
→ QE cycle open
→ temporary liability minted
→ approved external route
→ actual USDC/WETH balance delta
→ return hard asset
→ principal burn
→ settlement
→ hardNAVAfter
~~~

Required assertions:

~~~text
QEOutstandingAfter == 0
Cycle principalMinted == principalBurned
UnbackedSupplyAfter == 0
HardNAVAfter >= HardNAVBefore
reportedProfit == HardNAVAfter - HardNAVBefore - netExternalInjection
~~~

A profitable historical fork state may assert reportedProfit > 0.

A no-edge fork state must assert cycle rejection or zero/non-positive realized profit, not fabricated profit.

Commit:

~~~text
test: port real Base route into settled QE cycle
~~~

---

# Phase 13 — Legacy anti-pattern regression tests

## Task 13.1 — Managed oracle phantom-profit regression

Create:

- test/adversarial/ManagedOraclePhantomNAV.t.sol

Reproduce:
change internal managed price / gradient while external balances remain unchanged.

Assert:

~~~text
HardNAVAfter == HardNAVBefore
~~~

Commit:

~~~text
test: forbid managed-oracle hard nav creation
~~~

---

## Task 13.2 — LP rebase phantom-profit regression

Create:

- test/adversarial/LPPhantomNAV.t.sol

Scenario:
- mint protocol token;
- add to own-token/external-token LP;
- change internal LP accounting;
- call rebase/rebalance equivalent.

Assert:
no hard reserve gain unless actual external asset is received.

Commit:

~~~text
test: forbid own-token lp phantom nav
~~~

---

## Task 13.3 — Simplified Cycle B regression

Create:

- test/adversarial/SimplifiedCycleB.t.sol

Reproduce the legacy idea:
split a notional external receipt in half and call half "profit" without complete executable settlement.

Assert:
SettlementEngine reports no profit unless HardNAV actually increases after all liabilities and burn.

Commit:

~~~text
test: reject accounting-only cycle B profit
~~~

---

# Phase 14 — Terra failure laboratory

## Task 14.1 — Reflexive redemption death spiral model

Create:

- test/adversarial/TerraReflexiveRedemption.t.sol
- test/helpers/TerraFailureModel.sol

Model only enough of the historical failure structure to test V1 safeguards:

~~~text
stable redemption pressure
→ attempted endogenous rescue mint
→ rescue token price decline
→ larger required rescue mint
~~~

Do not integrate Terra mechanics into production contracts.

Tests at:
- 30% redemption;
- 50%;
- 70%.

Required V1 behavior:
- endogenous rescue mint is impossible;
- capacity falls;
- mode becomes DEFENSIVE / CONTRACTION;
- HardNAV ignores rescue token price.

Commit:

~~~text
test: add Terra reflexive redemption failure laboratory
~~~

---

## Task 14.2 — Endogenous equity collapse

Create:

- test/adversarial/EndogenousEquityCollapse.t.sol

Shock internal governance/equity token:
- -50%;
- -90%;
- -100%.

Assert HardNAV does not directly fall because it was never counted as hard backing.

Any real external side effect is accounted separately.

Commit:

~~~text
test: prove endogenous equity is excluded from hard backing
~~~

---

# Phase 15 — Bridge and oracle adversarial suite

## Task 15.1 — Bridge default tests

Create:

- test/adversarial/BridgeDefault.t.sol

Scenarios:
- source settled;
- in-flight;
- delayed;
- failed;
- destination settled.

Invariant:
one economic asset cannot count twice.

Commit:

~~~text
test: add bridge finality and default stress cases
~~~

---

## Task 15.2 — Oracle divergence tests

Create:

- test/adversarial/OracleDivergence.t.sol

Scenarios:
- stale source;
- 5% divergence;
- 10%;
- 30%;
- managed internal price manipulation.

Required:
unsafe inputs drive mint capacity to zero before reserve valuation becomes optimistic.

Commit:

~~~text
test: add multi-source oracle failure cases
~~~

---

# Phase 16 — Market-depth, gas and MEV stress

## Task 16.1 — Depth collapse

Create:

- test/adversarial/DepthCollapse.t.sol

Reduce executable depth by:
- 50%;
- 75%;
- 90%;
- 95%.

Assert:
MarketDepthCapacity is monotonic non-increasing.

Commit:

~~~text
test: add executable depth collapse stress
~~~

---

## Task 16.2 — Gas/slippage/MEV shock

Create:

- test/adversarial/ExecutionCostShock.t.sol

Model:
- base gas increase;
- priority fee;
- worse slippage;
- MEV penalty;
- bridge fee.

Execution decision:

~~~text
ExpectedHardReturn
- PrincipalCost
- Gas
- Slippage
- BridgeFees
- RiskBuffer
>= MinimumRequiredProfit
~~~

Gross spread alone cannot authorize mint.

Commit:

~~~text
test: enforce net executable profit gate
~~~

---

# Phase 17 — Stateful invariant harness

## Task 17.1 — Build invariant handler

Create:

- test/invariant/QEInvariantHandler.t.sol
- test/invariant/QECoreInvariants.t.sol

Random actions:
- deposit hard asset;
- open cycle;
- mint;
- deploy;
- return hard asset;
- burn;
- settle;
- alter external depth;
- alter oracle freshness;
- change bridge state;
- move system mode;
- absorb loss.

Required invariants:

~~~text
INV_01 HardNAV cannot rise solely from native token mint.
INV_02 temporary supply equals QE outstanding.
INV_03 facilitator outstanding <= capacity.
INV_04 global outstanding equals sum of facilitator debt.
INV_05 settled success has full principal burn.
INV_06 unsettled cycle cannot distribute profit.
INV_07 bridge claim single-count.
INV_08 GLOBAL_SETTLEMENT cannot jump directly to NORMAL.
INV_09 worsening risk cannot raise capacity.
INV_10 permanent mint cannot dilute hard backing.
INV_11 managed internal price cannot change HardNAV.
INV_12 accounting-only rebase cannot increase HardNAV.
~~~

Command:

~~~bash
forge test --match-contract QECoreInvariants -vv
~~~

Commit:

~~~text
test: add stateful QE accounting invariants
~~~

---

# Phase 18 — Permanent mint path

## Task 18.1 — Add non-dilutive permanent mint tests first

Create:

- test/unit/PermanentMint.t.sol
- test/fuzz/PermanentMintFuzz.t.sol

Before implementing final permanent mint path, tests must encode:

~~~text
M_max = V × S / H
~~~

where:
- H = pre-mint HardNAV;
- S = pre-mint permanent redeemable supply;
- V = already-received hard value.

Assertions:
- mint at or below M_max preserves backing;
- mint above M_max reverts;
- future revenue cannot be supplied as V;
- endogenous asset deposit counts as V = 0.

Then finish QEController.authorizePermanentMint.

Commit:

~~~text
feat: enforce non-dilutive permanent mint
~~~

---

# Phase 19 — Full-system acceptance scenario

## Task 19.1 — Add QEEngineV1Acceptance.t.sol

Create:

- test/QEEngineV1Acceptance.t.sol

Test sequence:

1. deploy all contracts;
2. register Base USDC/WETH;
3. fund initial external HardTreasury;
4. configure ARBITRAGE facilitator;
5. open profitable temporary cycle;
6. execute route;
7. return hard value;
8. burn full QE principal;
9. settle;
10. distribute only surplus;
11. trigger adverse market state;
12. verify capacity contracts;
13. attempt Terra-style endogenous rescue;
14. verify rejection;
15. recover through hard-value restoration;
16. verify safe mode transition rules.

Final assertions:

~~~text
totalOutstanding == 0
facilitator.outstanding == 0
successful cycle principalMinted == principalBurned
HardNAV_after > HardNAV_before for profitable route
no phantom NAV
no bridge double count
no distribution before settlement
~~~

Commit:

~~~text
test: add QE Engine V1 end-to-end acceptance scenario
~~~

---

# Phase 20 — Deployment and permission hardening

## Task 20.1 — Deployment script

Create:

- script/DeployQEEngineV1.s.sol
- script/ConfigureQEEngineV1.s.sol
- test/unit/DeploymentPermissions.t.sol

Deployment sequence:

1. deploy QEToken;
2. deploy OracleRouter;
3. deploy HardTreasury;
4. deploy FacilitatorRegistry;
5. deploy CycleEscrow;
6. deploy BridgeAccounting;
7. deploy StabilityPool;
8. deploy RiskEngine;
9. deploy QEController;
10. deploy SettlementEngine;
11. deploy ProfitDistributor;
12. deploy EmergencyShutdown;
13. deploy route adapters;
14. wire roles;
15. revoke deployer mint privileges;
16. transfer admin rights to timelock/guardian addresses.

Required permission assertion:

~~~text
No EOA can directly create monetary supply after deployment finalization.
~~~

Commit:

~~~text
feat: add hardened QE Engine V1 deployment
~~~

---

# Phase 21 — Documentation and audit package

## Task 21.1 — Produce accounting map

Create:

- docs/accounting/HARDNAV.md
- docs/accounting/QE_DEBT.md
- docs/accounting/PROFIT_RECOGNITION.md
- docs/accounting/BRIDGE_SINGLE_COUNT.md
- docs/security/ANTI_TERRA.md

Each document must point to exact contract functions and matching tests.

Commit:

~~~text
docs: document QE accounting and anti-Terra invariants
~~~

---

## Task 21.2 — Generate audit checklist

Create:

- docs/security/AUDIT_CHECKLIST.md

Checklist:

- access control;
- reentrancy;
- oracle freshness;
- price divergence;
- decimals;
- rounding;
- bridge replay/double count;
- route callback security;
- token approvals;
- permanent mint formula;
- liability reconciliation;
- state-machine transitions;
- emergency monotonicity;
- invariant coverage;
- upgrade/admin risk.

Commit:

~~~text
docs: add QE Engine V1 audit checklist
~~~

---

# Phase 22 — Execution order

Implementation must proceed in this exact dependency order:

~~~text
1. repository bootstrap
2. QETypes
3. QEToken
4. OracleRouter
5. HardTreasury
6. FacilitatorRegistry
7. CycleEscrow
8. BridgeAccounting
9. StabilityPool
10. RiskEngine
11. QEController
12. SettlementEngine
13. ProfitDistributor
14. RouteAdapter
15. ArbitrageFacilitator
16. legacy migration map
17. Base fork route
18. adversarial failure suites
19. invariant harness
20. permanent mint path
21. full acceptance scenario
22. deployment hardening
23. audit docs
~~~

The controller is intentionally implemented after most accounting components so it cannot accidentally become the source of truth for values that belong to Treasury, Escrow, BridgeAccounting, or RiskEngine.

---

# Phase 23 — Required CI command set

Before each implementation PR is considered green:

~~~bash
forge fmt --check
forge build
forge test
forge test --match-path "test/fuzz/*"
forge test --match-path "test/invariant/*"
forge test --match-path "test/adversarial/*"
~~~

Fork suite:

~~~bash
forge test   --fork-url "$BASE_RPC_URL"   --match-path "test/fork/*"   -vv
~~~

A fixed known-good Base block should remain in one regression test, while a separate optional latest-block suite can detect whether the economic edge still exists.

---

# Phase 24 — What must NOT be ported from synergy_2chain_qe

Do not copy as production truth:

1. managed internal price as hard fair value;
2. accounting-only rebaseLP / rebalancePool value creation;
3. simplified Cycle B profit assignment;
4. fixed profit distribution before solvency restoration;
5. any production route that quotes profit without executing the external leg;
6. any test funding mechanism as proof of organic strategy capital;
7. any synthetic asset valuation that counts its own issue price as external collateral.

What can be ported:

1. real Base USDC/WETH token integration;
2. real Uniswap V3 callback mechanics;
3. useful constant-product AMM math;
4. decimal-normalization fixes;
5. msg.value correctness checks;
6. slippage protections;
7. pinned fork regression infrastructure;
8. test evidence that system gain must correspond to an external counterparty/value-source delta.

---

# Phase 25 — First implementation milestone

Milestone M1 is reached only after Tasks 1–9 are complete:

~~~text
QEToken
OracleRouter
HardTreasury
FacilitatorRegistry
CycleEscrow
BridgeAccounting
StabilityPool
RiskEngine
QEController
~~~

M1 proof:

~~~text
temporary token mint == exact QE debt
own-token mint cannot increase HardNAV
managed internal price cannot increase HardNAV
facilitator cannot exceed capacity
risk deterioration cannot expand capacity
bridge claim cannot double count
~~~

No arbitrage strategy is added before M1 is green.

---

# Phase 26 — Second implementation milestone

M2 includes:

~~~text
SettlementEngine
ProfitDistributor
RouteAdapter
ArbitrageFacilitator
real Base fork migration
~~~

M2 proof:

~~~text
open QE liability
→ execute external route
→ return external hard value
→ burn full temporary principal
→ settle
→ distribute only real surplus
~~~

This is the first point where the system is allowed to claim a "profitable QE cycle."

---

# Phase 27 — Final implementation milestone

M3 requires:

- Terra failure laboratory;
- oracle/bridge/depth/gas adversarial tests;
- stateful invariant suite;
- permanent non-dilutive mint;
- deployment hardening;
- full acceptance scenario.

Final V1 economic assertion:

~~~text
Mint is temporary financing or reserve-backed issuance.

It is never itself revenue.

A QE cycle is profitable only when,
after all principal, liabilities, gas, slippage, bridge costs,
loss reserves and settlement obligations are accounted for,
external HardNAV is higher than it was before the cycle.
~~~
