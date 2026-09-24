# Zapper deployment

WETHZapper, GasCompZapper, LeverageWETHZapper and LeverageLSTZapper retain the
Solidity constructor `(addressesRegistry, flashLoanProvider, exchange)` and the
original public selectors. Configure the branch registry before deployment.
GasCompZapper and LeverageLSTZapper require collateral distinct from WETH.

The leverage variants create a fixed companion during construction. Its address
is immutable, there is no upgrade setter, and callers cannot select a delegate
target. The companion receives the already-read branch addresses as immutable
constructor arguments; it performs no registry queries, token approvals or event
emissions. The parent retains the reference constructor's registry reads, event
and approvals.

The parent delegates leveraged opening, lever-up, lever-down and their three
flash-loan callbacks. Ordinary opening/adjustment/closing, flash-loan closing,
manager configuration and ratio calculations remain in the parent. Delegation
preserves the parent address, msg.sender, msg.value, revert/return bytes, events
and manager mappings at Solidity slots 0 and 1. Companions do not add mutable
storage. Parent fallback handling accepts only empty calldata as Solidity's
receive handler does.

The isolated build and deployment tests measured these byte sizes (the complete
root rebuild is also checked by `scripts/export_abi.py`):

| Contract | Runtime | Initcode before arguments |
| --- | ---: | ---: |
| LeverageWETHZapper | 21,156 | 34,674 |
| LeverageWETHZapperLeverage | 10,606 | 11,144 |
| LeverageLSTZapper | 20,882 | 36,124 |
| LeverageLSTZapperLeverage | 12,087 | 12,675 |

Each runtime is below EIP-170's 24,576 bytes. Each parent initcode, including
its three address arguments and embedded companion creation code, is below
EIP-3860's 49,152 bytes. No separately supplied module addresses are required.

`GasCompZapperParity.t.sol` and `LeverageZapperParity.t.sol` compare the Fe
contracts with the pinned Solidity reference, including batch/individual
opening, leverage changes, token surplus preservation, flash-loan fees, manager
checks, ABI validation and rollback. `BorrowerOperationsSystem.t.sol` also
connects each variant to actual Fe protocol contracts. Its exchange/flash-loan
providers and collateral/oracle sources are controlled test dependencies;
production exchange and flash-loan modules remain separate port work.
