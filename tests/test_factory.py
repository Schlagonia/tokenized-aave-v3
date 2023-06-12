import ape
from ape import Contract, reverts, project
from utils.checks import check_strategy_totals, check_strategy_mins
from utils.utils import days_to_secs
from utils.constants import MAX_BPS
import pytest


def test__factory_deployed__operation(
    chain,
    asset,
    tokens,
    factory,
    user,
    management,
    rewards,
    whale,
    weth,
    weth_amount,
    amount,
    RELATIVE_APPROX,
    keeper,
):
    if asset == weth:
        asset = Contract(tokens["usdc"])
        amount = int(100_000e6)
    else:
        asset = Contract(tokens["weth"])
        amount = weth_amount

    tx = factory.newAaveV3Lender(asset, "yTest Factory", sender=management)

    event = list(tx.decode_logs(factory.NewAaveV3Lender))

    assert len(event) == 1
    assert event[0].asset == asset.address

    strategy = project.IStrategyInterface.at(event[0].strategy)

    asset.transfer(user, amount, sender=whale)

    user_balance_before = asset.balanceOf(user)

    # Deposit to the strategy
    asset.approve(strategy, amount, sender=user)
    strategy.deposit(amount, user, sender=user)

    check_strategy_totals(
        strategy,
        total_assets=amount,
        total_debt=amount,
        total_idle=0,
        total_supply=amount,
    )

    chain.mine(10)

    # withdrawal
    strategy.withdraw(amount, user, user, sender=user)

    check_strategy_totals(
        strategy, total_assets=0, total_debt=0, total_idle=0, total_supply=0
    )

    assert (
        pytest.approx(asset.balanceOf(user), rel=RELATIVE_APPROX) == user_balance_before
    )


def test__factory_deployed__profitable_report(
    chain,
    asset,
    tokens,
    factory,
    user,
    management,
    rewards,
    whale,
    weth,
    wavax,
    weth_amount,
    amount,
    RELATIVE_APPROX,
    keeper,
):
    if asset == weth:
        asset = Contract(tokens["usdc"])
        amount = int(100_000e6)

    else:
        asset = Contract(tokens["weth"])
        amount = weth_amount

    tx = factory.newAaveV3Lender(
        asset, "yTest Factory", rewards, keeper, management, sender=management
    )

    event = list(tx.decode_logs(factory.NewAaveV3Lender))

    assert len(event) == 1
    assert event[0].asset == asset.address

    strategy = project.IStrategyInterface.at(event[0].strategy)

    # allow any amount of swaps
    strategy.setMinAmountToSell(0, sender=management)

    asset.transfer(user, amount, sender=whale)

    # Deposit to the strategy
    user_balance_before = asset.balanceOf(user)

    # Deposit to the strategy
    asset.approve(strategy, amount, sender=user)
    strategy.deposit(amount, user, sender=user)

    check_strategy_totals(
        strategy,
        total_assets=amount,
        total_debt=amount,
        total_idle=0,
        total_supply=amount,
    )

    # Earn some profit
    chain.mine(days_to_secs(5))

    before_pps = strategy.pricePerShare()

    tx = strategy.report(sender=keeper)

    profit, loss = tx.return_value
    assert profit > 0

    performance_fees = profit * strategy.performanceFee() // MAX_BPS

    check_strategy_totals(
        strategy,
        total_assets=amount + profit,
        total_debt=amount + profit,
        total_idle=0,
        total_supply=amount + profit,
    )

    # needed for profits to unlock
    chain.pending_timestamp = (
        chain.pending_timestamp + strategy.profitMaxUnlockTime() - 1
    )
    chain.mine(timestamp=chain.pending_timestamp)

    check_strategy_totals(
        strategy,
        total_assets=amount + profit,
        total_debt=amount + profit,
        total_idle=0,
        total_supply=amount + performance_fees,
    )

    assert strategy.pricePerShare() > before_pps

    strategy.redeem(amount, user, user, sender=user)

    assert asset.balanceOf(user) > user_balance_before


def test__factory_deployed__reward_selling(
    chain,
    asset,
    tokens,
    factory,
    user,
    management,
    rewards,
    whale,
    weth,
    weth_amount,
    amount,
    wavax,
    RELATIVE_APPROX,
    keeper,
):
    if asset == weth:
        asset = Contract(tokens["usdc"])
        amount = int(100_000e6)
    else:
        asset = Contract(tokens["weth"])
        amount = weth_amount

    tx = factory.newAaveV3Lender(
        asset, "yTest Factory", rewards, keeper, management, sender=management
    )

    event = list(tx.decode_logs(factory.NewAaveV3Lender))

    assert len(event) == 1
    assert event[0].asset == asset.address

    strategy = project.IStrategyInterface.at(event[0].strategy)

    asset.transfer(user, amount, sender=whale)

    # allow any amount of swaps
    strategy.setMinAmountToSell(0, sender=management)

    # Deposit to the strategy
    user_balance_before = asset.balanceOf(user)

    # Deposit to the strategy
    asset.approve(strategy, amount, sender=user)
    strategy.deposit(amount, user, sender=user)

    check_strategy_totals(
        strategy,
        total_assets=amount,
        total_debt=amount,
        total_idle=0,
        total_supply=amount,
    )

    # Earn some profit
    chain.mine(days_to_secs(5))

    # Send aave to strategy
    avax_amount = int(1e18)
    wavax.transfer(strategy, avax_amount, sender=whale)
    assert wavax.balanceOf(strategy) == avax_amount

    before_pps = strategy.pricePerShare()

    tx = strategy.report(sender=keeper)

    profit, loss = tx.return_value

    assert profit > 0

    performance_fees = profit * strategy.performanceFee() // MAX_BPS

    check_strategy_totals(
        strategy,
        total_assets=amount + profit,
        total_debt=amount + profit,
        total_idle=0,
        total_supply=amount + profit,
    )

    assert wavax.balanceOf(strategy.address) == 0

    # needed for profits to unlock
    chain.pending_timestamp = (
        chain.pending_timestamp + strategy.profitMaxUnlockTime() - 1
    )
    chain.mine(timestamp=chain.pending_timestamp)

    check_strategy_totals(
        strategy,
        total_assets=amount + profit,
        total_debt=amount + profit,
        total_idle=0,
        total_supply=amount + performance_fees,
    )

    assert strategy.pricePerShare() > before_pps

    strategy.redeem(amount, user, user, sender=user)

    assert asset.balanceOf(user) > user_balance_before


def test__factory_deployed__shutdown(
    chain,
    asset,
    tokens,
    factory,
    user,
    management,
    rewards,
    whale,
    weth,
    weth_amount,
    amount,
    RELATIVE_APPROX,
    keeper,
):
    if asset == weth:
        asset = Contract(tokens["usdc"])
        amount = int(100_000e6)
    else:
        asset = Contract(tokens["weth"])
        amount = weth_amount

    tx = factory.newAaveV3Lender(asset, "yTest Factory", sender=management)

    event = list(tx.decode_logs(factory.NewAaveV3Lender))

    assert len(event) == 1
    assert event[0].asset == asset.address

    strategy = project.IStrategyInterface.at(event[0].strategy)

    asset.transfer(user, amount, sender=whale)

    user_balance_before = asset.balanceOf(user)

    # Deposit to the strategy
    asset.approve(strategy, amount, sender=user)
    strategy.deposit(amount, user, sender=user)

    check_strategy_totals(
        strategy,
        total_assets=amount,
        total_debt=amount,
        total_idle=0,
        total_supply=amount,
    )

    chain.mine(14)

    assert asset.balanceOf(strategy) == 0

    # Need to shutdown the strategy and withdraw
    strategy.shutdownStrategy(sender=management)
    strategy.emergencyWithdraw(amount, sender=management)

    assert asset.balanceOf(strategy) >= amount
    check_strategy_mins(
        strategy,
        min_total_assets=amount,
        min_total_debt=0,
        min_total_idle=amount,
        min_total_supply=amount,
    )

    # withdrawal
    strategy.withdraw(amount, user, user, sender=user)

    assert (
        pytest.approx(asset.balanceOf(user), rel=RELATIVE_APPROX) == user_balance_before
    )


def test__factroy_deployed__access(
    chain,
    asset,
    tokens,
    factory,
    user,
    management,
    rewards,
    whale,
    wavax,
    weth_amount,
    amount,
    RELATIVE_APPROX,
    keeper,
):
    if asset == wavax:
        asset = Contract(tokens["usdc"])
        amount = int(100_000e6)
    else:
        asset = Contract(tokens["dai"])
        amount = weth_amount

    tx = factory.newAaveV3Lender(asset, "yTest Factory", sender=management)

    event = list(tx.decode_logs(factory.NewAaveV3Lender))

    assert len(event) == 1
    assert event[0].asset == asset.address

    strategy = project.IStrategyInterface.at(event[0].strategy)

    asset.transfer(user, amount, sender=whale)

    assert strategy.minAmountToSell() == 1e10

    amount = 0

    strategy.setMinAmountToSell(amount, sender=management)

    assert strategy.minAmountToSell() == amount

    with reverts("!Authorized"):
        strategy.setMinAmountToSell(int(1e12), sender=user)

    assert strategy.minAmountToSell() == 0

    with reverts("!Authorized"):
        strategy.emergencyWithdraw(100, sender=user)
