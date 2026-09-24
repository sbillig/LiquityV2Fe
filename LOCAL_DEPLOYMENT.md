# Run the Fe Liquity V2 system locally

Run these commands from the repository root. Install Python 3, Rust/Cargo, Node/npm
and Foundry (`forge`, `cast`, `anvil`); the build uses the pinned Solidity 0.8.24
compiler and the local Fe release compiler.

```sh
python3 scripts/bootstrap.py
./scripts/test.sh
python3 tools/local_demo/run.py
```

The last command starts its own Anvil at `http://127.0.0.1:18545`, chain ID 31337,
and deploys the Fe contracts. It prints the deployment manifest path under
`deployments/local-<timestamp>/deployment.json`. Leave the command running to use
the system; Ctrl-C stops its Anvil. No private key is required: this command only
uses the local Anvil's unlocked development accounts.

To run the complete transaction smoke check and stop Anvil automatically:

```sh
python3 tools/local_demo/run.py --smoke
```

Use `--port 18546` if another local service occupies the default port. The runner
fails on a port collision and does not reuse or stop that other service. Use
`--repo /path/to/repo` when running outside the repository root, `--artifacts` to
select a build directory, and `--output-dir` for a new, explicit result directory.

## Deployed system

- Shared BOLD and CollateralRegistry; three WETH/rETH/wstETH branches with actual
  Fe registries, borrowing operations, manager/modules, pools, sorted lists, NFTs,
  price feeds and gas compensation.
- Metadata renderer and FixedAssetReader with all five pinned original assets.
- Governance and its fixed modules, actual UserProxy implementation, and Bribe,
  Curve-gauge and Merkl initiatives.
- HintHelpers, MultiTroveGetter, DebtInFrontHelper, RedemptionHelper and Constants.
- WETHZapper, GasCompZapper, LeverageWETHZapper and LeverageLSTZapper, with Curve,
  Uniswap V3 and Hybrid exchange adapters and both hybrid quote helpers.
- Fe Balancer flash-loan adapter. The fixed delegate modules and constructor
  arguments are assembled automatically; see the individual deployment documents.

All Liquity contracts use Fe bytecode deployed by transactions with the normal
EVM runtime/initcode size limits. The local chain runs Cancun, matching the
Solidity differential test environment.

The Solidity contracts in `tools/local_demo/src/DevDependencies.sol` are explicitly
external fixtures: collateral/LQTY/LUSD/USDC/reward tokens, oracle data/rates, V1
staking, Curve/Uniswap markets, Balancer vault, Curve gauge and Merkl creator.
Market prices are deterministic and do not model real DEX price impact. USDC uses
six decimals. BOLD liquidity is borrowed from the real Fe protocol. The Balancer
vault and Merkl creator fixtures are installed at their canonical external
addresses using `anvil_setCode`, because those addresses are fixed in the pinned
upstream integrations. No Fe protocol contract is installed through this method.

Demo governance uses one-day epochs and a 90% voting cutoff. Collateral prices
start at 2,000 BOLD per token; oracle staleness windows are seven days. These are
local deployment parameters. The external fixtures are not production services.

## Smoke coverage and evidence

`--smoke` creates liquidity-provider troves and funds the external market fixtures
with borrowed BOLD. It opens and closes the basic zappers, then exercises leveraged
opening, leverage increases/decreases and flash-loan closes through every adapter
on all three branches. It checks batch membership, fee/rate updates, pending debt
and batch exit, and queries both quote-helper generations.

It then opens two more troves per branch, deposits into the StabilityPools and
renders the NFTs. LQTY is staked through a real UserProxy, votes are allocated to
all three initiatives, branch interest is minted and claimed, bribes are claimed,
Curve rewards reach the gauge, Merkl creates a campaign, and the voter exits.
Finally it redeems across branches, liquidates a trove, shuts down a branch, and
redeems through the remaining branches. Collateral/pool balances and shared BOLD
supply are checked against recorded branch debt. The smoke deliberately changes
state and shuts down one branch; use a fresh default deployment for exploration.

The output directory contains:

- `deployment.json`: addresses, branch wiring, external fixture declarations and
  deployment transaction hashes/gas usage.
- `zapper-smoke-result.json`: zapper/exchange/batch transaction evidence.
- `smoke-result.json`: core/NFT/governance/reward transaction evidence.
- `anvil.log`: the runner's own node log.

The runner stops its node on completion or failure in smoke mode. The files
remain available for inspection.
