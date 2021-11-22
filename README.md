# side-platform
Convex Smart Contract Platform for Non-Eth Chains


## todo Changes from Eth Convex version
- update to solidity 0.8.10
- reward pools are minimal proxy
- combine base and virtual into one multi reward contract
- reduce token transfers on operations. for example mint directly to the stake contract and manually increase balance.
- remove minting cvx flow
- remove cvx staking, funnel all cvx fees back to ethchain
- add more event logs
- more control/easier to add extra rewards to a pool
- remove harvesters.  always claim and pull rewards when depositing/withdrawing/claiming
- handling for crv/cvx to/from eth chain

