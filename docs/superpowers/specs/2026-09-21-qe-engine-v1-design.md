# QE Engine V1 — Non-Inflationary Mint / Burn Architecture

**Repository:** Shtenco/synergy_qe  
**Integration target:** Shtenco/synergy_2chain_qe  
**Status:** Design specification  
**Date:** 2026-09-21

## 1. Goal

Build a QE engine that may expand supply only when the expansion is either a temporary, fully-accounted liability that is later burned, or a permanent expansion already covered by newly received external hard value.

The system must not count internally-created token value, managed oracle marks, LP marks, virtual liquidity, expected future demand, or future yield as profit.

Primary economic metric:

~~~text
CycleProfit =
HardNAV_after
- HardNAV_before
- NetExternalCapitalInjection
~~~

A successful temporary QE cycle must finish with:

~~~text
QEOutstanding_after == 0
UnbackedSupply_after == 0
CycleProfit >= MinRealizedProfit
~~~

The design explicitly prevents Terra/LUNA/UST-style reflexive failure modes.

## 2. Mechanisms distilled from reference protocols

### Frax: AMO accounting and limits

Reference: https://github.com/FraxFinance/frax-solidity/blob/master/src/hardhat/contracts/Frax/FraxAMOMinter.sol

Use:
- per-AMO minted balances;
- aggregate minted balance;
- mint cap;
- collateral-ratio check before mint;
- explicit burn path;
- explicit return of borrowed collateral.

QE V1 adaptation:
- each facilitator has independent outstanding debt and capacity;
- temporary mint raises a liability;
- burn lowers the same liability;
- returned hard assets are accounted separately from burn.

### Aave GHO: facilitator buckets

Reference: https://github.com/aave-dao/gho-origin/blob/main/src/contracts/gho/GhoToken.sol

Use:
- bucketCapacity;
- bucketLevel;
- mint increases level;
- burn decreases level;
- no facilitator may exceed its bucket.

QE V1 adaptation:
- ARBITRAGE, BRIDGE, LP, MARKET_MAKER, CREDIT facilitators have isolated limits.

### Maker/Sky DSS: double-entry debt

Reference: https://github.com/sky-ecosystem/dss/blob/master/src/vat.sol

Use:
- per-collateral and global debt ceilings;
- even privileged issuance creates an opposite debt entry;
- heal-like settlement retires matched asset and liability.

QE V1 rule:
- there is no privileged mint without equal liability accounting.

### Liquity BOLD: Stability Pool and shutdown

References:
- https://github.com/liquity/bold/blob/main/contracts/src/StabilityPool.sol
- https://github.com/liquity/bold/blob/main/contracts/src/AddressesRegistry.sol

Use:
- burn stablecoin while offsetting bad debt;
- transfer recoverable collateral to pre-funded loss absorbers;
- critical and shutdown collateral-ratio states;
- borrowing disabled when system safety deteriorates.

### Olympus: bounded market operations

References:
- https://github.com/OlympusDAO/olympus-v3/blob/develop/src/policies/Operator.sol
- https://github.com/OlympusDAO/olympus-v3/blob/develop/src/modules/MINTR/OlympusMinter.sol

Use:
- separated mint and treasury permissions;
- bounded market-operation capacity;
- reserve-in/token-out and token-in/reserve-out operations.

QE V1 rule:
- permanent supply may be minted only after actual hard reserve received is measured.

### Reserve Protocol: hard backing and revenue separation

References:
- https://github.com/reserve-protocol/protocol/blob/master/contracts/p1/RToken.sol
- https://github.com/reserve-protocol/protocol/blob/master/contracts/p1/BackingManager.sol
- https://github.com/reserve-protocol/protocol/blob/master/contracts/p1/RevenueTrader.sol

Use:
- issuance/redeem against backing;
- separate backing management from revenue trading;
- issuance freeze;
- realized revenue is distinct from rebalance bookkeeping.

### Origin / Alchemix / mStable: earned value first

References:
- https://github.com/OriginProtocol/origin-dollar/blob/master/contracts/contracts/vault/VaultCore.sol
- https://github.com/alchemix-finance/v2-foundry/blob/master/src/AlchemistV2.sol
- https://github.com/mstable/mStable-contracts/blob/master/contracts/masset/Masset.sol

Use:
- external yield and fees are realized before distribution;
- realized yield may retire debt;
- future yield is not current capital.

### RAI / Reflexer: controller is policy, not value

References:
- https://github.com/reflexer-labs/geb/blob/master/src/single/SAFEEngine.sol
- https://github.com/reflexer-labs/geb/blob/master/src/single/OracleRelayer.sol
- https://github.com/reflexer-labs/geb-simulations

Use:
- global debt ceilings;
- feedback controller;
- redemption-rate / risk-policy adjustment.

QE V1 rule:
- controller may alter capacity, spread and required profit, but cannot alter HardNAV by changing an internal reference price.

### Basis Cash / Ampleforth: failure-mode laboratory

References:
- https://github.com/Basis-Cash/basiscash-protocol/blob/master/contracts/treasury/Treasury.sol
- https://github.com/fragmentsorg/ampleforth-contracts/blob/master/contracts/UFragmentsPolicy.sol

Use them to stress contraction, bond queues and supply expansion.

Do not treat:
- future demand as collateral;
- rebase as profit;
- internally-issued claims as hard reserves.

### Terra / LUNA / UST: explicit anti-pattern

Reference:
https://github.com/terra-money/classic-core/blob/main/x/market/spec/01_concepts.md

Historical Terra market mechanics burned the offered asset, updated virtual TerraPoolDelta, minted the requested asset, and used virtual pools to express liquidity.

QE V1 prohibits:
- redeeming endogenous token A by minting endogenous token B and treating B as hard backing;
- counting virtual liquidity as reserve;
- increasing QE capacity when redemption pressure rises.

## 3. Core accounting definitions

All normalized values use 18-decimal USD-equivalent accounting.

### 3.1 Hard Asset

An asset is hard only when it:
1. is external to the protocol token system;
2. can be transferred or sold without minting another protocol liability;
3. has an independent live price source;
4. has an executable unwind route;
5. is not already counted through another claim.

Examples:
- USDC;
- ETH/WETH with haircut;
- separately approved external RWA token with haircut.

Always zero HardNAV:
- RUBX;
- RUBZ;
- USDS;
- ETHS;
- governance token;
- protocol-issued bonds;
- own-token side of protocol LP;
- any claim backed only by another endogenous asset.

### 3.2 Haircutted executable value

~~~text
ExecutablePrice(asset) =
min(
  IndependentOraclePrice,
  ConservativeTWAP,
  ExecutableUnwindPriceAtConfiguredSize
)

HardValue(asset) =
Balance(asset)
× ExecutablePrice(asset)
× Haircut(asset)
~~~

### 3.3 HardNAV

~~~text
HardNAV =
Σ HardValue(external assets)
- ExternalLiabilities
- ReservedSettlementClaims
- ExpectedExitCosts
~~~

ExpectedExitCosts includes executable gas and route costs for the size being valued.

### 3.4 Hard backing per permanent token

~~~text
HardBackingPerToken =
HardNAV / PermanentRedeemableSupply
~~~

Temporary QE supply is excluded only when the same amount is recorded as QEOutstanding liability. Otherwise it is unbacked supply.

### 3.5 Hard coverage ratio

~~~text
HardCR =
HardNAV / RedeemableHardLiabilities
~~~

### 3.6 Realized cycle profit

~~~text
NetExternalCapitalInjection =
ExternalDepositsDuringCycle
- ExternalWithdrawalsDuringCycle

CycleProfit =
HardNAV_after
- HardNAV_before
- NetExternalCapitalInjection
~~~

Internal token marks never enter this formula.

## 4. Non-negotiable invariants

### I-1 Endogenous assets are zero HardNAV

~~~text
HardValue(RUBX) = 0
HardValue(RUBZ) = 0
HardValue(USDS) = 0
HardValue(ETHS) = 0
~~~

### I-2 Every temporary mint creates equal QE liability

~~~text
ΔTemporarySupply == ΔQEOutstanding
~~~

No role, including governance, may bypass this.

### I-3 Permanent mint cannot dilute backing

For pre-mint HardNAV H, permanent supply S, new mint M and hard value V already received:

~~~text
(H + V) / (S + M) >= H / S
~~~

Equivalent:

~~~text
V >= M × (H / S)
~~~

### I-4 Profit only after principal retirement

Before profit distribution:

~~~text
cycle.qeOutstanding == 0
cycle.principalBurned == cycle.principalMinted
~~~

### I-5 No bridge double counting

One economic hard-asset unit may contribute to HardNAV in only one state:
- source settled;
- in flight with haircut;
- destination settled.

### I-6 Yield distribution is externally earned

~~~text
DistributedYield
<= RealizedExternalYield
 + RealizedExternalFees
 + RealizedTradingPnL
~~~

### I-7 No reflexive redemption

Redemption of token A cannot be satisfied by creating endogenous token B and calling B hard value.

### I-8 Risk-state monotonicity

Worsening safety may only:
- lower mint capacity;
- increase required profit;
- increase haircuts;
- reduce bridge exposure;
- reduce accepted oracle age.

### I-9 Facilitator isolation

~~~text
facilitator.outstanding <= facilitator.capacity
Σ facilitator.outstanding <= globalCapacity
~~~

### I-10 No LP phantom NAV

For endogenous/external LP:

~~~text
HardNAV(LP)
<= executable hard value of external component
~~~

The endogenous component contributes zero.

### I-11 No accounting-only recapitalization

Rebase, rebalance, internal oracle changes, virtual pool changes, or book entries cannot increase HardNAV unless an external hard asset rises or an external liability falls.

### I-12 Emergency cannot print solvency

CONTRACTION and GLOBAL_SETTLEMENT disable discretionary mint. They allow burn, repayment, liquidation, settlement, hard-reserve recovery and safe redemptions only.

## 5. System state machine

~~~text
NORMAL
  ↓
DEFENSIVE
  ↓
CONTRACTION
  ↓
GLOBAL_SETTLEMENT
~~~

Transitions are driven by HardCR, redemption pressure, oracle integrity, bridge health and executable depth.

### NORMAL
Allowed:
- temporary QE;
- reserve-accretive permanent mint;
- arbitrage;
- LP operations;
- approved bridge routes;
- settled profit distribution.

### DEFENSIVE
Effects:
- reduce all facilitator capacities;
- raise minimum required profit;
- shorten temporary QE TTL;
- increase haircuts;
- reduce long bridge exposure;
- retain more realized profit in HardTreasury.

### CONTRACTION
Allowed:
- burn;
- repay;
- liquidate;
- StabilityPool offset;
- buyback funded by external assets;
- settle bridge assets;
- replenish hard reserve.

Disabled:
- new temporary QE;
- discretionary permanent mint;
- unfunded LP compensation;
- new bridge credit.

### GLOBAL_SETTLEMENT
- freeze policy actions;
- snapshot hard assets and liabilities;
- ignore endogenous prices;
- settle claims against conservative hard reserves;
- close in-flight QE by burn or explicit loss recognition.

## 6. V1 deterministic simulation defaults

These defaults exist to make V1 reproducible, not to claim optimal production calibration.

~~~text
NORMAL_MIN_HARD_CR            = 1.25e18
DEFENSIVE_TRIGGER_HARD_CR     = 1.18e18
CONTRACTION_TRIGGER_HARD_CR   = 1.08e18
GLOBAL_SETTLEMENT_HARD_CR     = 1.00e18

MAX_ORACLE_AGE_NORMAL         = 120 seconds
MAX_ORACLE_AGE_DEFENSIVE      = 60 seconds

MAX_EXECUTION_SLIPPAGE_BPS    = 50
MAX_SINGLE_CYCLE_LOSS_BPS     = 25
MIN_REALIZED_PROFIT_BPS       = 10

TEMP_QE_TTL_NORMAL            = 15 minutes
TEMP_QE_TTL_DEFENSIVE         = 5 minutes

MAX_FACILITATOR_SHARE_HARDNAV = 10%
MAX_GLOBAL_QE_SHARE_HARDNAV   = 25%

BRIDGE_PENDING_HAIRCUT_BPS    = 8000
BRIDGE_STALE_HAIRCUT_BPS      = 0
~~~

Changing parameters must never violate the invariants above.

## 7. Contracts

### 7.1 HardTreasury.sol

Single source of truth for external hard assets.

Responsibilities:
- custody approved external assets;
- register realized inflows;
- compute HardNAV;
- reserve assets for settlement;
- prevent double counting;
- transfer assets only to approved settlement/rebalance destinations.

Core state:

~~~solidity
struct AssetConfig {
    bool enabled;
    uint16 haircutBps;
    uint16 maxExposureBps;
    uint48 maxOracleAge;
    address priceAdapter;
    address unwindAdapter;
}

mapping(address => AssetConfig) public assetConfig;
mapping(address => uint256) public reservedForSettlement;
uint256 public externalLiabilitiesUsd18;
~~~

Views:
- hardValue(address asset)
- hardNAV()
- hardBackingPerToken()
- availableHardValue(address asset)

HardTreasury never values endogenous assets through ManagedOracle.

### 7.2 QEController.sol

Global monetary authority.

Responsibilities:
- open temporary cycles;
- authorize temporary mint;
- authorize permanent mint only after reserve proof;
- enforce mode and capacity;
- record global QE debt;
- invoke settlement.

State:

~~~solidity
enum SystemMode {
    NORMAL,
    DEFENSIVE,
    CONTRACTION,
    GLOBAL_SETTLEMENT
}

uint256 public globalCapacity;
uint256 public totalOutstanding;
SystemMode public mode;
~~~

Core entry points:
- openTemporaryCycle(bytes32 facilitatorId, uint256 requestedAmount, bytes routeData)
- authorizePermanentMint(uint256 amount, uint256 hardValueAlreadyReceived)
- burnTemporaryPrincipal(uint256 cycleId, uint256 amount)

There is no arbitrary public mint(address,uint256).

### 7.3 FacilitatorRegistry.sol

Aave-style isolated buckets.

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

Classes:
- ARBITRAGE
- BRIDGE
- LP
- MARKET_MAKER
- CREDIT

V1 enables ARBITRAGE and fully collateral-backed BRIDGE by default.

### 7.4 CycleEscrow.sol

Every temporary expansion belongs to one cycle.

States:

~~~text
CREATED
→ MINTED
→ DEPLOYED
→ RETURNED
→ PRINCIPAL_BURNED
→ SETTLED
~~~

Failure states:
- EXPIRED
- DEFAULTED
- EMERGENCY_SETTLED

Record:

~~~solidity
struct Cycle {
    bytes32 facilitatorId;
    CycleState state;
    uint128 principalMinted;
    uint128 principalBurned;
    uint128 externalValueInUsd18;
    uint128 externalValueOutUsd18;
    int128 realizedPnlUsd18;
    uint48 openedAt;
    uint48 expiresAt;
    bytes32 routeHash;
}
~~~

A successful cycle cannot become SETTLED until principalMinted equals principalBurned.

### 7.5 SettlementEngine.sol

Maker-like liability retirement and profit waterfall.

Order:

~~~text
1. repay external execution debt
2. return bridge principal
3. burn temporary QE principal
4. restore required HardCR buffer
5. restore StabilityPool target
6. recognize remaining hard delta as realized profit
7. distribute only recognized profit
~~~

Core:
- settleCycle(uint256 cycleId) returns realizedPnlUsd18

No owner distribution before steps 1–5.

### 7.6 RiskEngine.sol

Dynamic mint capacity:

~~~text
MintCapacity =
min(
  CollateralCapacity,
  MarketDepthCapacity,
  BridgeCapacity,
  LossBudgetCapacity,
  OracleCapacity,
  GlobalCapacity
)
~~~

CollateralCapacity:
largest exposure that leaves stressed HardCR above required mode threshold.

MarketDepthCapacity:
largest externally executable trade with slippage at or below MAX_EXECUTION_SLIPPAGE_BPS.

BridgeCapacity:
limited by settled reserves, in-flight claims, finality, route haircut and per-bridge cap.

LossBudgetCapacity:

~~~text
AvailableStabilityBuffer / MaxLossFraction
~~~

OracleCapacity:
zero if required sources are stale, unavailable, or diverge beyond allowed tolerance.

Redemption pressure:

~~~text
RedemptionPressure =
NetRedemptionsWindow / ExecutableExternalDepth
~~~

Higher pressure lowers capacity and raises required profit. It never enables emergency mint.

### 7.7 StabilityPool.sol

Pre-funded first-loss capital.

Funding:
- retained realized external profit;
- explicit external deposits;
- hard reserves explicitly allocated to loss absorption.

Never funded by assigning value to newly minted endogenous tokens.

### 7.8 BridgeAccounting.sol

Separates bridge claims from minting.

~~~solidity
enum BridgeState {
    NONE,
    SOURCE_SETTLED,
    IN_FLIGHT,
    DESTINATION_SETTLED,
    FAILED
}
~~~

Valuation:
- SOURCE_SETTLED: normal hard-asset haircut;
- IN_FLIGHT: normal haircut multiplied by pending bridge haircut;
- DESTINATION_SETTLED: destination hard-asset haircut;
- FAILED: zero.

Beyond configured finality age, pending bridge value becomes zero until resolved.

### 7.9 EmergencyShutdown.sol

Guardian may immediately:
- disable new QE;
- disable a facilitator;
- disable a bridge route;
- disable an oracle adapter;
- move mode to DEFENSIVE or CONTRACTION.

Only timelocked governance may increase capacity or exit severe shutdown states.

### 7.10 OracleRouter.sol

Hard-asset price:

~~~text
ConservativePrice =
min(
  independent oracle,
  external DEX TWAP,
  executable quote
)
~~~

Managed internal price is a strategy/simulation signal only and cannot value reserves.

## 8. Temporary QE flow

~~~text
1. RiskEngine quotes maximum executable capacity.
2. QEController creates cycleId.
3. CycleEscrow records principal liability.
4. Temporary supply is minted.
5. Facilitator executes approved route.
6. External hard asset is returned.
7. SettlementEngine repays external liabilities.
8. Temporary principal is reacquired if required.
9. Temporary principal is burned.
10. HardNAV is recomputed.
11. Only remaining hard delta is profit.
12. Solvency-first profit waterfall executes.
~~~

If burn cannot complete before TTL:
- cycle becomes EXPIRED;
- facilitator mint is disabled;
- StabilityPool loss path begins;
- system mode may only become more restrictive.

## 9. Permanent mint flow

Sequence:

~~~text
1. external hard asset arrives;
2. HardTreasury values it conservatively;
3. QEController computes maximum non-dilutive mint;
4. actual mint is capped;
5. backing-per-token is checked again after mint.
~~~

For H = pre-mint HardNAV, S = pre-mint permanent supply, V = hard value received:

~~~text
M_max = (V × S) / H
~~~

when H is nonzero.

Future revenue cannot substitute for V.

## 10. Profit waterfall

Legacy fixed 40/30/20/10 distribution is replaced by:

~~~text
RealizedProfit
  ↓
restore HardCR target
  ↓
restore StabilityPool target
  ↓
restore bridge reserve target
  ↓
pay accrued operating costs
  ↓
remaining distributable surplus
~~~

Only the remaining surplus can go to owner, governance, buyback or other recipients.

## 11. Explicit anti-Terra rules

Forbidden:
- redeem RUBX by minting RUBZ;
- rescue hard claims through unlimited endogenous issuance;
- count virtual pools as reserve;
- count collapsing governance equity as reserve;
- pay yield from token creation;
- count expected future demand as collateral.

Redemption stress must cause:

~~~text
QE capacity ↓
required spread ↑
required profit ↑
haircuts ↑
new long exposure ↓
~~~

## 12. Migration from synergy_2chain_qe

Legacy repository:
https://github.com/Shtenco/synergy_2chain_qe

### BridgeCore

Keep:
- genuine collateral-backed 1:1 lock/mint wrapping.

Change:
- separate collateral-backed synth mint from QE mint;
- all QE inventory must use QEController + CycleEscrow;
- BridgeCore cannot create discretionary monetary inventory.

### InternalAMM

Keep:
- x*y=k swap mechanics and explicit slippage.

Change:
- own-token marks do not count as HardNAV;
- rebaseLP, batchRebase and rebalancePool may distribute value only when funded by already-realized hard surplus;
- book-only changes cannot create treasury claims.

### ManagedOracle

Current managed gradient is retained only for strategy simulation and routing.

HardTreasury and RiskEngine must use OracleRouter external conservative pricing instead.

### ArbitrageExecutor

Convert into facilitator adapter.

Every route:
- carries cycleId;
- obtains executable pre-trade quote;
- enforces slippage;
- measures actual external balance deltas;
- settles and burns principal before distribution.

The existing simplified Cycle B accounting is not an accepted V1 profit proof.

### TreasuryDistributor

Fixed ratios become a final distribution adapter after SettlementEngine confirms:
- external debt paid;
- QE principal burned;
- HardCR target restored;
- StabilityPool target restored.

## 13. Required events

Minimum:
- CycleOpened
- TemporaryMinted
- TemporaryBurned
- ExternalValueReceived
- CycleSettled
- CycleDefaulted
- SystemModeChanged
- FacilitatorCapacityChanged

Every economic state transition must be externally auditable.

## 14. Access control

Roles:
- GOVERNANCE_TIMELOCK
- GUARDIAN
- QE_CONTROLLER
- SETTLEMENT_KEEPER
- FACILITATOR
- ORACLE_ADMIN
- TREASURY_MANAGER

Rules:
- guardian may only reduce risk;
- capacity increases require timelock;
- no EOA receives raw minter role;
- token minter role belongs only to QEController or collateral-backed bridge adapter;
- deployer mint privileges are revoked after setup.

## 15. Mandatory failure-mode simulations

### Terra-style bank run
30%, 50%, 70% redemption attempts.

Required:
- capacity falls;
- no endogenous rescue mint;
- HardNAV ignores rescue-token value;
- mode becomes more restrictive.

### Endogenous-token collapse
50%, 90%, 100% price collapse.

Required:
- direct HardNAV calculation remains unaffected except actual external consequences.

### Oracle failure
Stale feed and 5%, 10%, 30% cross-source disagreement.

Required:
- mint capacity goes to zero before unsafe price is accepted.

### Bridge delay/default
Required:
- in-flight haircut rises to 100%;
- no source/destination double counting.

### External-depth collapse
50–95% depth loss.

Required:
- MarketDepthCapacity falls immediately;
- stale quote cannot authorize new cycle.

### Full allowed strategy loss
Required:
- only pre-funded StabilityPool absorbs configured amount;
- exhausted facilitator is disabled;
- owner distribution is zero below solvency target.

### Gas/MEV shock
Required:
- quoted gross spread is insufficient;
- execution requires positive net executable return after gas, slippage and fees.

### LP phantom-value attack
Mint endogenous token and add it to protocol LP.

Required:
- HardNAV does not rise from the endogenous side.

## 16. Formal invariant suite

~~~text
INV_01 HardNAV cannot rise solely because protocol-native supply rises.

INV_02 totalTemporarySupply == totalQEOutstanding,
except transiently within one atomic settlement call.

INV_03 facilitator.outstanding <= facilitator.capacity.

INV_04 sum(facilitator.outstanding) == QEController.totalOutstanding.

INV_05 successful SETTLED cycle:
principalMinted == principalBurned.

INV_06 unsettled cycle cannot distribute profit.

INV_07 a bridge claim contributes to HardNAV in at most one state.

INV_08 GLOBAL_SETTLEMENT cannot transition directly to NORMAL.

INV_09 worsening risk inputs cannot increase MintCapacity.

INV_10 permanent mint cannot reduce HardBackingPerToken
beyond integer rounding tolerance.

INV_11 changing ManagedOracle gradient alone cannot change HardNAV.

INV_12 rebase/rebalance without external asset movement
cannot increase HardNAV.
~~~

## 17. Technology baseline

To remain compatible with synergy_2chain_qe:

~~~text
Solidity: 0.8.20
Framework: Foundry
Target: Base mainnet fork first
Libraries: OpenZeppelin
Primary hard assets in V1 fork tests: Base USDC + WETH
Testing: unit + fuzz + invariant + pinned-fork integration
~~~

Mainnet deployment is not a V1 acceptance condition. Reproducible fork proofs come first.

## 18. Acceptance criteria

Implementation is accepted only when:

1. Temporary QE cannot exist without equal recorded QE liability.
2. Temporary principal is burned before profit distribution.
3. Permanent mint cannot reduce hard backing per token.
4. Own tokens have zero HardNAV.
5. LP positions cannot manufacture HardNAV from own-token marks.
6. Bridge assets cannot be double counted.
7. Managed internal gradient cannot change HardNAV.
8. Terra-style redemption cannot mint endogenous rescue equity.
9. Higher redemption pressure lowers QE capacity.
10. Fixed 40/30/20/10 distribution is replaced with solvency-first waterfall.
11. Every facilitator has an isolated capacity bucket.
12. Global debt equals reconciled facilitator debt.
13. HardNAV includes executable exit costs.
14. A profitable temporary cycle ends with QEOutstanding == 0, UnbackedSupply == 0 and CycleProfit > 0.
15. A losing route cannot hide loss through revaluation.
16. Terra, bridge-default, stale-oracle, depth-collapse, gas/MEV and LP-phantom tests pass.
17. The real Base Uniswap fork route can be expressed as a cycle without test-only accounting exemptions.

## 19. Architectural decision

QE Engine V1 is:

~~~text
Aave facilitator buckets
+ Frax AMO debt/accounting
+ Maker double-entry liabilities
+ Liquity shutdown + Stability Pool
+ Olympus bounded market operations
+ Reserve hard-backing discipline
+ Origin/Alchemix/mStable realized-yield accounting
+ RAI feedback controller
~~~

Terra, Basis Cash and Ampleforth remain adversarial models.

Core principle:

~~~text
Mint is financing, not profit.

Profit exists only after external value is realized,
temporary mint principal is retired,
external liabilities are paid,
and HardNAV has genuinely increased.
~~~
