import ape
from ape import Contract, reverts
from utils.utils import days_to_secs, increase_time
from utils.constants import MAX_BPS
import pytest


def test__emergency_withdraw(
    chain,
    asset,
    strategy,
    user,
    deposit,
    amount,
    management,
    RELATIVE_APPROX,
    keeper,
):
    user_balance_before = asset.balanceOf(user)

    # Deposit to the strategy
    deposit()

    assert strategy.totalAssets() == amount

    chain.mine(10)

    assert asset.balanceOf(strategy) == 0

    # Need to shutdown the strategy, and withdraw
    strategy.shutdownStrategy(sender=management)
    strategy.emergencyWithdraw(amount, sender=management)

    assert asset.balanceOf(strategy) >= amount

    assert strategy.totalAssets() == amount

    increase_time(chain, strategy.profitMaxUnlockTime() - 1)

    # withdrawal
    tx = strategy.redeem(amount, user, user, sender=user)

    assert strategy.totalAssets() == 0

    assert (
        pytest.approx(asset.balanceOf(user), rel=RELATIVE_APPROX) == user_balance_before
    )


def test__shutdown__report_doesnt_reinvest(
    chain,
    asset,
    strategy,
    user,
    deposit,
    amount,
    management,
    RELATIVE_APPROX,
    keeper,
):
    user_balance_before = asset.balanceOf(user)

    # Deposit to the strategy
    deposit()

    assert strategy.totalAssets() == amount

    chain.mine(days_to_secs(1))

    # Shutdown the strategy
    strategy.shutdownStrategy(sender=management)

    to_withdraw = amount // 2

    strategy.emergencyWithdraw(to_withdraw, sender=management)

    assert asset.balanceOf(strategy.address) == to_withdraw

    # Report should still work correctly
    tx = strategy.report(sender=management)

    profit, loss = tx.return_value
    assert profit > 0

    performance_fees = profit * strategy.performanceFee() // MAX_BPS

    assert strategy.totalAssets() == amount + profit

    # needed for profits to unlock
    chain.pending_timestamp = (
        chain.pending_timestamp + strategy.profitMaxUnlockTime() - 1
    )
    chain.mine(timestamp=chain.pending_timestamp)

    # withdrawal
    strategy.redeem(amount, user, user, sender=user)

    assert asset.balanceOf(user) > user_balance_before
