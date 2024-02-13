import ape
from ape import Contract
from utils.constants import MAX_BPS
from utils.checks import check_strategy_totals
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

    check_strategy_totals(
        strategy, total_assets=amount, total_debt=amount, total_idle=0
    )

    chain.mine(10)

    # withdrawal
    strategy.withdraw(amount, user, user, sender=user)

    check_strategy_totals(strategy, total_assets=0, total_debt=0, total_idle=0)

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

    check_strategy_totals(
        strategy, total_assets=amount, total_debt=amount, total_idle=0
    )

    increase_time(chain, days_to_secs(2))

    before_pps = strategy.pricePerShare()

    tx = strategy.report(sender=keeper)

    profit, loss = tx.return_value

    assert profit >= 0

    performance_fees = profit * strategy.performanceFee() // MAX_BPS

    # TODO: Implement logic so totalDebt == amount + profit
    check_strategy_totals(
        strategy, total_assets=amount + profit, total_debt=amount + profit, total_idle=0
    )

    # needed for profits to unlock
    increase_time(chain, strategy.profitMaxUnlockTime() - 1)

    check_strategy_totals(
        strategy, total_assets=amount + profit, total_debt=amount + profit, total_idle=0
    )
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

    check_strategy_totals(
        strategy, total_assets=amount, total_debt=amount, total_idle=0
    )

    increase_time(chain, days_to_secs(2))

    before_pps = strategy.pricePerShare()

    tx = strategy.report(sender=keeper)

    profit, loss = tx.return_value

    assert profit > 0

    check_strategy_totals(
        strategy, total_assets=amount + profit, total_debt=amount + profit, total_idle=0
    )

    # needed for profits to unlock
    increase_time(chain, strategy.profitMaxUnlockTime() - 1)

    check_strategy_totals(
        strategy, total_assets=amount + profit, total_debt=amount + profit, total_idle=0
    )

    assert strategy.pricePerShare() > before_pps

    tx = strategy.redeem(amount, user, user, sender=user)

    assert asset.balanceOf(user) > user_balance_before

    rewards_balance = strategy.balanceOf(rewards)

    strategy.redeem(rewards_balance, rewards, rewards, sender=rewards)


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
