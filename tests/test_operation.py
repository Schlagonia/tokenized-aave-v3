import ape
from ape import Contract, accounts
from utils.constants import MAX_BPS
from utils.utils import days_to_secs, increase_time
import pytest


def test__operation(
    chain,
    asset,
    strategy,
    user,
    deposit,
    amount,
    RELATIVE_APPROX,
):
    user_balance_before = asset.balanceOf(user)

    # Deposit to the strategy
    deposit()

    assert strategy.totalAssets() == amount

    chain.mine(10)

    # withdrawal
    strategy.withdraw(amount, user, user, sender=user)

    assert strategy.totalAssets() == 0

    assert asset.balanceOf(user) == user_balance_before


def test_profitable_report(
    chain,
    asset,
    strategy,
    deposit,
    user,
    amount,
    whale,
    RELATIVE_APPROX,
    keeper,
):
    # Deposit to the strategy
    user_balance_before = asset.balanceOf(user)

    # Deposit to the strategy
    deposit()

    assert strategy.totalAssets() == amount

    increase_time(chain, days_to_secs(2))

    before_pps = strategy.pricePerShare()

    tx = strategy.report(sender=keeper)

    profit, loss = tx.return_value

    assert profit >= 0

    performance_fees = profit * strategy.performanceFee() // MAX_BPS

    assert strategy.totalAssets() == amount + profit

    # needed for profits to unlock
    increase_time(chain, strategy.profitMaxUnlockTime() - 1)

    assert strategy.totalAssets() == amount + profit

    assert strategy.pricePerShare() > before_pps

    # withdrawal
    strategy.redeem(amount, user, user, sender=user)

    assert asset.balanceOf(user) > user_balance_before


def test__profitable_report__with_fee(
    chain,
    asset,
    strategy,
    deposit,
    user,
    management,
    rewards,
    amount,
    whale,
    RELATIVE_APPROX,
    keeper,
):
    # Set performance fee to 10%
    performance_fee = int(1_000)
    strategy.setPerformanceFee(performance_fee, sender=management)

    # Deposit to the strategy
    user_balance_before = asset.balanceOf(user)

    # Deposit to the strategy
    deposit()

    assert strategy.totalAssets() == amount

    increase_time(chain, days_to_secs(2))

    before_pps = strategy.pricePerShare()

    tx = strategy.report(sender=keeper)

    profit, loss = tx.return_value

    assert profit > 0

    assert strategy.totalAssets() == amount + profit

    # needed for profits to unlock
    increase_time(chain, strategy.profitMaxUnlockTime() - 1)

    assert strategy.totalAssets() == amount + profit

    assert strategy.pricePerShare() > before_pps

    tx = strategy.redeem(amount, user, user, sender=user)

    assert asset.balanceOf(user) > user_balance_before

    rewards_balance = strategy.balanceOf(rewards)

    strategy.redeem(rewards_balance, rewards, rewards, sender=rewards)


def test__withdraw_limit_airdrop(
    chain,
    asset,
    strategy,
    user,
    deposit,
    amount,
    whale,
):
    user_balance_before = asset.balanceOf(user)

    # Deposit to the strategy
    deposit()

    assert strategy.totalAssets() == amount

    aToken = strategy.aToken()

    limit = strategy.availableWithdrawLimit(user)

    assert limit <= asset.balanceOf(aToken)
    assert limit > amount

    asset.transfer(aToken, amount, sender=whale)

    new_limit = strategy.availableWithdrawLimit(user)

    # Should not be effected
    assert new_limit == limit
    assert limit < asset.balanceOf(aToken)
    assert limit > amount

    chain.mine(10)

    # withdrawal
    strategy.withdraw(amount, user, user, sender=user)

    assert strategy.totalAssets() == 0

    assert asset.balanceOf(user) == user_balance_before


def test__withdraw_limit_illiquid(
    chain,
    asset,
    strategy,
    user,
    deposit,
    amount,
    whale,
):
    user_balance_before = asset.balanceOf(user)

    # Deposit to the strategy
    deposit()

    assert strategy.totalAssets() == amount

    aToken = Contract(strategy.aToken())

    aToken_whale = accounts["0xb21DeB6D23D6Bd067D50c7e3EA6bc8874061342b"]

    limit = strategy.availableWithdrawLimit(user)

    balance = aToken.balanceOf(aToken_whale)

    assert balance > limit  # Cant make illiquid for test

    lendingPool = Contract(strategy.lendingPool())

    to_leave = amount // 10

    lendingPool.withdraw(asset, limit - to_leave, aToken_whale, sender=aToken_whale)

    assert strategy.availableWithdrawLimit(user) == to_leave
    assert strategy.maxWithdraw(user) == to_leave

    max_redeem = strategy.maxRedeem(user)

    strategy.redeem(max_redeem, user, user, sender=user)

    asset.transfer(aToken, amount, sender=whale)

    assert strategy.maxRedeem(user) == 0

    with ape.reverts("ERC4626: redeem more than max"):
        strategy.redeem(1, user, user, sender=user)


def test__tend_trigger(
    chain,
    strategy,
    asset,
    amount,
    deposit,
    keeper,
    user,
):
    # Check Trigger
    assert strategy.tendTrigger()[0] == False

    # Deposit to the strategy
    deposit()

    # Check Trigger
    assert strategy.tendTrigger()[0] == False

    chain.mine(days_to_secs(1))

    # Check Trigger
    assert strategy.tendTrigger()[0] == False

    strategy.report(sender=keeper)

    # Check Trigger
    assert strategy.tendTrigger()[0] == False

    # needed for profits to unlock
    increase_time(chain, strategy.profitMaxUnlockTime() - 1)

    # Check Trigger
    assert strategy.tendTrigger()[0] == False

    strategy.redeem(amount, user, user, sender=user)

    # Check Trigger
    assert strategy.tendTrigger()[0] == False
