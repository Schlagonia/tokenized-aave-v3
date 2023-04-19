import ape
from ape import Contract, reverts
from utils.checks import check_strategy_totals, check_strategy_mins
from utils.utils import days_to_secs, increase_time
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

    check_strategy_totals(
        strategy,
        total_assets=amount,
        total_debt=amount,
        total_idle=0,
        total_supply=amount,
    )

    chain.mine(10)

    assert asset.balanceOf(strategy) == 0

    # Need to shutdown the strategy, withdraw and then report the updated balances
    strategy.shutdownStrategy(sender=management)
    strategy.emergencyWithdraw(amount, sender=management)
    strategy.report(sender=management)

    assert asset.balanceOf(strategy) >= amount

    check_strategy_mins(
        strategy,
        min_total_assets=amount,
        min_total_debt=0,
        min_total_idle=amount,
        min_total_supply=amount,
    )

    increase_time(chain, strategy.profitMaxUnlockTime() - 1)

    # withdrawal
    tx = strategy.redeem(amount, user, user, sender=user)

    print(f"Shares redeemed {tx.return_value}")
    print(f"Debt is  {strategy.totalDebt()}")
    print(f"Assets is {strategy.totalAssets()}")

    check_strategy_totals(
        strategy, total_assets=0, total_debt=0, total_idle=0, total_supply=0
    )

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

    check_strategy_totals(
        strategy,
        total_assets=amount,
        total_debt=amount,
        total_idle=0,
        total_supply=amount,
    )

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

    check_strategy_totals(
        strategy,
        total_assets=amount + profit,
        total_debt=amount + profit - to_withdraw,
        total_idle=to_withdraw,
        total_supply=amount + profit,
    )

    # needed for profits to unlock
    chain.pending_timestamp = (
        chain.pending_timestamp + strategy.profitMaxUnlockTime() - 1
    )
    chain.mine(timestamp=chain.pending_timestamp)

    # withdrawal
    strategy.redeem(amount, user, user, sender=user)

    check_strategy_totals(
        strategy, total_assets=0, total_debt=0, total_idle=0, total_supply=0
    )

    assert asset.balanceOf(user) > user_balance_before
