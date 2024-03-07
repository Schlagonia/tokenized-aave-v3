import ape
from ape import Contract, reverts, project, accounts
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

    tx = factory.newSparkLender(asset, "yTest Factory", sender=management)

    event = list(tx.decode_logs(factory.NewSparkLender))

    assert len(event) == 1
    assert event[0].asset == asset.address

    strategy = project.IStrategyInterface.at(event[0].strategy)

    strategy.acceptManagement(sender=management)

    asset.transfer(user, amount, sender=whale)

    user_balance_before = asset.balanceOf(user)

    # Deposit to the strategy
    asset.approve(strategy, amount, sender=user)
    strategy.deposit(amount, user, sender=user)

    assert strategy.totalAssets() == amount

    chain.mine(10)

    # withdrawal
    strategy.withdraw(amount, user, user, sender=user)

    assert strategy.totalAssets() == 0

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
    aave,
    weth_amount,
    amount,
    RELATIVE_APPROX,
    keeper,
):
    if asset == weth:
        asset = Contract(tokens["usdc"])
        amount = int(100_000e6)
        aave_fee = 3000
    else:
        asset = Contract(tokens["weth"])
        amount = weth_amount
        aave_fee = 3000

    tx = factory.newSparkLender(asset, "yTest Factory", sender=management)

    event = list(tx.decode_logs(factory.NewSparkLender))

    assert len(event) == 1
    assert event[0].asset == asset.address

    strategy = project.IStrategyInterface.at(event[0].strategy)

    strategy.acceptManagement(sender=management)

    # set uni fees for swap
    strategy.setUniFees(aave, asset, aave_fee, sender=management)

    asset.transfer(user, amount, sender=whale)

    # Deposit to the strategy
    user_balance_before = asset.balanceOf(user)

    # Deposit to the strategy
    asset.approve(strategy, amount, sender=user)
    strategy.deposit(amount, user, sender=user)

    assert strategy.totalAssets() == amount

    # Earn some profit
    chain.mine(days_to_secs(5))

    before_pps = strategy.pricePerShare()

    tx = strategy.report(sender=keeper)

    profit, loss = tx.return_value
    assert profit > 0

    performance_fees = profit * strategy.performanceFee() // MAX_BPS

    assert strategy.totalAssets() >= amount + profit

    # needed for profits to unlock
    chain.pending_timestamp = (
        chain.pending_timestamp + strategy.profitMaxUnlockTime() - 1
    )
    chain.mine(timestamp=chain.pending_timestamp)

    assert strategy.totalAssets() >= amount

    assert strategy.pricePerShare() > before_pps

    strategy.redeem(amount, user, user, sender=user)

    assert asset.balanceOf(user) > user_balance_before


def test__factory_deployed__reward_selling_auction(
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
    aave,
    RELATIVE_APPROX,
    keeper,
    buyer,
):
    if asset == weth:
        asset = Contract(tokens["usdc"])
        amount = int(100_000e6)
        aave_fee = 3000

    else:
        asset = Contract(tokens["weth"])
        amount = weth_amount
        aave_fee = 3000

    tx = factory.newSparkLender(asset, "yTest Factory", sender=management)

    event = list(tx.decode_logs(factory.NewSparkLender))

    assert len(event) == 1
    assert event[0].asset == asset.address

    strategy = project.IStrategyInterface.at(event[0].strategy)

    strategy.acceptManagement(sender=management)

    asset.transfer(user, amount, sender=whale)

    assert strategy.useAuction()

    # Deploy and setup auction
    auction_factory = Contract(strategy.auctionFactory())

    tx = auction_factory.createNewAuction(
        asset, strategy, management, sender=management
    )

    auction = project.IAuction.at(tx.return_value)

    strategy.setAuction(auction, sender=management)

    auction.setHookFlags(True, True, False, False, sender=management)

    tx = auction.enable(aave, strategy, sender=management)
    id = tx.return_value

    # Deposit to the strategy
    user_balance_before = asset.balanceOf(user)

    # Deposit to the strategy
    asset.approve(strategy, amount, sender=user)
    strategy.deposit(amount, user, sender=user)

    assert strategy.totalAssets() == amount

    # Earn some profit
    chain.mine(days_to_secs(5))

    # Send aave to strategy
    aave_amount = int(1e18)
    aave.transfer(strategy, aave_amount, sender=whale)
    assert aave.balanceOf(strategy) == aave_amount

    assert auction.kickable(id) == aave_amount

    tx = auction.kick(id, sender=management)
    assert tx.return_value == aave_amount
    assert aave.balanceOf(auction) == aave_amount

    chain.mine(auction_factory.DEFAULT_AUCTION_LENGTH() // 2)

    needed = auction.getAmountNeeded(id, aave_amount)

    assert needed > 0

    asset.transfer(buyer, needed, sender=whale)

    asset.approve(auction, needed, sender=buyer)

    auction.take(id, sender=buyer)

    assert aave.balanceOf(auction) == 0
    assert aave.balanceOf(strategy) == 0
    assert asset.balanceOf(strategy) == needed

    before_pps = strategy.pricePerShare()

    tx = strategy.report(sender=keeper)

    profit, loss = tx.return_value

    assert profit > 0

    performance_fees = profit * strategy.performanceFee() // MAX_BPS

    assert strategy.totalAssets() == amount + profit

    assert aave.balanceOf(strategy.address) == 0
    # Sold tokens are left idle
    assert asset.balanceOf(strategy.address) > 0

    # needed for profits to unlock
    chain.pending_timestamp = (
        chain.pending_timestamp + strategy.profitMaxUnlockTime() - 1
    )
    chain.mine(timestamp=chain.pending_timestamp)

    assert strategy.totalAssets() == amount + profit

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

    tx = factory.newSparkLender(asset, "yTest Factory", sender=management)

    event = list(tx.decode_logs(factory.NewSparkLender))

    assert len(event) == 1
    assert event[0].asset == asset.address

    strategy = project.IStrategyInterface.at(event[0].strategy)

    strategy.acceptManagement(sender=management)

    asset.transfer(user, amount, sender=whale)

    user_balance_before = asset.balanceOf(user)

    # Deposit to the strategy
    asset.approve(strategy, amount, sender=user)
    strategy.deposit(amount, user, sender=user)

    assert strategy.totalAssets() == amount

    chain.mine(14)

    assert asset.balanceOf(strategy) == 0

    # Need to shutdown the strategy, withdraw and then report the updated balances
    strategy.shutdownStrategy(sender=management)
    strategy.emergencyWithdraw(amount, sender=management)
    strategy.report(sender=management)

    assert asset.balanceOf(strategy) >= amount

    assert strategy.totalAssets() >= amount

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
    weth,
    aave,
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

    tx = factory.newSparkLender(asset, "yTest Factory", sender=management)

    event = list(tx.decode_logs(factory.NewSparkLender))

    assert len(event) == 1
    assert event[0].asset == asset.address

    strategy = project.IStrategyInterface.at(event[0].strategy)

    strategy.acceptManagement(sender=management)

    asset.transfer(user, amount, sender=whale)

    # Everything should start as 0
    assert strategy.uniFees(aave, weth) == 0
    assert strategy.uniFees(weth, aave) == 0

    strategy.setUniFees(aave, weth, 300, sender=management)

    assert strategy.uniFees(aave, weth) == 300
    assert strategy.uniFees(weth, aave) == 300

    with reverts("!management"):
        strategy.setUniFees(weth, aave, 0, sender=user)

    assert strategy.uniFees(aave, weth) == 300
    assert strategy.uniFees(weth, aave) == 300

    with reverts("!emergency authorized"):
        strategy.emergencyWithdraw(100, sender=user)
