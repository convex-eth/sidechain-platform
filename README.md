
# Convex Curve Staking Platform
Convex Smart Contract Platform for staking on Curve on non-Ethereum mainnet chains.

This is a fork of the original version at https://github.com/convex-eth/platform


## Main Changes
- Update to Solidity 0.8.10
- Remove harvester requirements with new staking and reward contracts
- Remove unnecessary functionality that only pertains to Ethereum mainnet
- Fix/Improve various aspects of original platform

## Main Contract Usage

### VoterProxy
VoterProxy is an immutable contract that has access to use the platform's veCrv weight.  All staked positions will be consolidated to this contract.

The controller of this contract is called the operator. It is the only address that has access to staked positions.  In order for a new operator to be assigned, the previous operator must be put into a Shutdown state.  This shutdown state should remove all staking positions and tokens so that a new operator does not have access.

The owner of this contract only has the ability to replace the operator which, as mentioned above, must be in a shutdown state before replacement.


### Booster
Booster contract is the main contract in which users will interact and is also the operator of the VoterProxy.

#### Booster Tasks
- Deposits
- Withdraws
- Manage Pool Creation
- Set Fees
- Manage various roles(pool, rescue, reward)
- Manage Factories (reward, token)
- Handle Shutdown tasks

#### Booster Roles
- **Owner**
The Owner can:
	- Set a new owner
	- Set CRV address for a given curve pool factory
	- Set a Rescue Manager
	- Set a Reward manager
	- Set factories for reward and deposit token contracts
	- Set fees and where fees are accumulated
	- Shutdown the system
- **Pool Manager**
The Pool Manager can:
	- Set a new pool manager
	- Add a new pool
	- Shutdown a specific pool
The main objective of the pool manager is to be able to add conditions and/or improve easiness of creating a new pool. For example if the pool manager can prove a pool is an official Curve pool, then the add pool function could be unguarded and open for anyone to call.  This sort of check is better to perform on another contract/module than perform directly on the booster in case extra checks need to be added.
- **Rescue Manager**
The Rescue Manage can:
	- Pull non-lp and non-gauge tokens off the VoterProxy.  This is to address the need that some airdrops or 3rd party rewards may be placed on the VoterProxy address.  It will only have access to pull tokens that are not part of a protected token list, which will hold LP and Gauge tokens.  Extra rewards that pools receive should also be claimed directly to reward contracts, thus there should only be tokens that are outside the scope of the Convex system that are recoverable.
- **Reward Manager**
The Reward Manager can:
	- Define what address is used for the CVX token on the local chain
	- Add extra/outside rewards to a staking contract that are not on the curve gauge directly (ex. adding CVX rewards to a pool)
	- Can define a "hook" used by the staking contract to claim outside rewards.
	- Can define weights on ExtraRewrdPool to set which pools get how much of a specific reward (ex. A single CVX reward contract that splits its weight between multiple curve pools )

### ConvexRewardPool


### ExtraRewardPool


