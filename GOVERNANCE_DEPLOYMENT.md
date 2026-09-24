# Governance deployment

The Fe Governance implementation uses three fixed delegate modules to fit the
EVM runtime limit. Deploy these contracts without constructor arguments:

1. `GovernanceStakingModule`
2. `GovernanceVotingModule`
3. `GovernanceActionsModule`

Then deploy the parent with the original Solidity arguments followed by those
three addresses:

```
Governance(lqty, lusd, stakingV1, bold, configuration, initialOwner,
           initialInitiatives, stakingModule, votingModule, actionsModule)
```

`configuration` retains the ten original uint256 fields, in order:
registration fee, registration threshold factor, unregistration threshold
factor, unregistration delay in epochs, voting threshold factor, minimum claim,
minimum accrual, epoch start, epoch duration, and voting cutoff. The exported
protocol ABI includes this actual constructor and the original runtime API.

The parent creates its own UserProxy implementation. Module addresses are
immutable, with no upgrade or replacement setter. Modules execute with the
parent's storage and original caller through delegatecall; they read the
parent's immutable configuration through its public getters. Protocol users
and initiatives call the parent. Events emitted by modules have the parent
address. All four contracts must be deployed from the matching build artifacts.

The constructor can register initial initiatives when initialOwner is the
constructor caller. Alternatively, that owner can call
`registerInitialInitiatives` after deployment, for example when initiatives
need the Governance address in their own constructors. Initial registration
renounces ownership, matching Solidity. The tests cover both orders.

The isolated validation recorded in `tests/results/governance-prepared.json`
passes all 25 connected differential tests and the ABI/size audit. Runtime
sizes are 15,847 bytes for the parent, 7,324 for staking, 21,116 for voting and
13,409 for actions. Parent initcode is 26,432 bytes before constructor arguments.
Deployment helpers check initcode including arguments and deployed runtime.
Root full-suite validation remains pending until separately recorded.

Tests cover complete stake/vote/claim/reset/withdraw flows, BribeInitiative,
Curve gauge payouts and nonfatal hook failures, Merkl threshold accumulation
and campaigns, multicall and atomic rollback. External tokens, V1 staking,
gauges and the Merkl creator are test doubles; the Governance, UserProxy and
initiative contracts in the all-Fe comparisons use their actual Fe bytecode.
