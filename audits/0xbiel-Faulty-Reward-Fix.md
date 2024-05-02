# <h1 align="center"> Fix faulty reward token can lock LP tokens </h1>

**Fixed Convex Sidechain platform ConvexRewardPool and RewardManager**

🟨 Possible 🟥 High Severity

### Issue:

The bug affects the deposit, withdrawal, and reward claiming functionalities, causing transactions to
revert consistently. This presents a significant risk to the stability and usability of the contract.
Specifically, the problem arises from the implementation of the try-catch block at line 156 of
ConvexRewardPool.sol. Despite attempts to handle exceptions using try-catch, transactions continue
to revert.

### Incident History:

This issue has already manifested in the fxETH Reward Pool (contract address:
[0xaCb744c7e7C95586DB83Eda3209e6483Fb1FCbA4](https://arbiscan.io/address/0xaCb744c7e7C95586DB83Eda3209e6483Fb1FCbA4)) on Arbitrum Mainnet. Users are currently
unable to deposit, withdraw funds, or claim rewards due to this bug. This error happened because the
Curve fxETH Gauge [0x5839337bf070Fea56595A5027e83Cd7126b23884](https://arbiscan.io/address/0x5839337bf070Fea56595A5027e83Cd7126b23884) has an array with the
reward tokens, and the reward_tokens[0] is [0x365AccFCa291e7D3914637ABf1F7635dB165Bb09](https://arbiscan.io/address/0x365AccFCa291e7D3914637ABf1F7635dB165Bb09)
which is in fact a normal address, so when you call updateRewardList it reads this address and then
tries to insert it with \_insertRewardToken, and then is when the problem happens, because it tries to
transfer like if was an ERC20 token, and the transaction reverts because Try Catch doesn’t do its job,
and basically locks all the Reward Pool for the users. But this doesn’t revert with my implementation.
But this has happened on the fxETH pool for now but could affect all other pools.

### Fix

To fix this, I've changed on line [156 of ConvexRewardPool.sol](https://github.com/convex-eth/sidechain-platform/blob/main/contracts/contracts/ConvexRewardPool.sol#L156) from

```solidity
try IERC20(_token).transfer(address(this), 0){}catch{}
```

to

```solidity
(bool _success, bytes memory _data) = _token.call(
    abi.encodeWithSelector(
        IERC20(_token).transfer.selector,
        address(this),
        0
    )
);
if (!_success || (_data.length > 0 && !abi.decode(_data, (bool)))) {
    // Token transfer failed or did not return true, treat as non-compliant or non-existent token
    return;
}
```

So if it fails it doesn't revert the transaction. Also on [_\_insertRewardToken_](./src/ConvexRewardPool.sol) checks if the given address is a contract or not, and if it's not address it invalidates the address and returns, so that when claiming skips this address.

```solidity
uint32 size;

assembly {
    size := extcodesize(_token)
}

if (size > 0) {
    (bool success, ) = _token.call(
        abi.encodeWithSelector(
            IERC20(_token).balanceOf.selector,
            address(this)
        )
    );
    if (!success) {
        // Token balance check failed, treat as non-compliant or non-existent token
        _invalidateReward(_token);
        return;
    }
} else {
    // Address is not a contract, treat as non-compliant or non-existent token
    _invalidateReward(_token);
    return;
}
```

I've also updated the [PoolRewardHook.sol](./src/PoolRewardHook.sol) when transferring the tokens to

```solidity
(bool success, bytes memory data) = address(
    poolRewardList[msg.sender][i]
).call(
        abi.encodeWithSelector(
            IRewards(poolRewardList[msg.sender][i])
                .getReward
                .selector,
            msg.sender
        )
    );
if (!success || (data.length > 0 && !abi.decode(data, (bool)))) {
    return;
}
```

Just to make sure it doesn't break.

### Testing ([My repo](https://github.com/0xbiel/ConvexFix))

I've also added a [test](./test/Contract.t.sol) which tests the deposit, withdrawal and the claim of the rewards with a wrong address as a deposit in the Curve.fi Gauge.

This [test](./test/Contract.t.sol) file first forks Arbitrum, creates a new [RewardFactory](./src/RewardFactory.sol), and deploys an empty [ConvexRewardPool](./src/ConvexRewardPool.sol) as a template for the factory, it then sets this factory to the [Booster](./src/Booster.sol), then changes the [RewardHook](./src/PoolRewardHook.sol) to the updated one. And then updates the Implementation at the factory to the template, it shuts down the broken ConvexRewardPool (15), and adds the new Pool.

Once then new Pool is added it then checks that has been correctly added. The first test is the deposit, which deposits all the balance of the LP tokens, then also tries claiming the rewards. And finally Withdrawing with claiming true, and Withdrawing without claiming.

```shell
forge test -vv

[⠔] Compiling...
No files changed, compilation skipped

Running 5 tests for test/Contract.t.sol:TestContract
[PASS] testClaimRewards() (gas: 392342)
[PASS] testDeposit() (gas: 872168)
[PASS] testSetPool() (gas: 10371)
[PASS] testWithdrawWithClaim() (gas: 709924)
[PASS] testWithdrawWithoutClaim() (gas: 1146055)
Test result: ok. 5 passed; 0 failed; 0 skipped; finished in 56.94s

Ran 1 test suites: 5 tests passed, 0 failed, 0 skipped (5 total tests)
```

### Contact

Should you require further clarification or assistance, please do not hesitate to reach out to me via this
email, Twitter (@0xbiel), or Discord (0xbiel).
