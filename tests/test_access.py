import ape
from ape import Contract, reverts
from utils.checks import check_strategy_totals
from utils.utils import days_to_secs
import pytest


def test__dont_sell(
    strategy,
    wavax,
    management,
):
    assert strategy.dontSell(wavax) == False

    strategy.setDontSell(wavax, True, sender=management)

    assert strategy.dontSell(wavax) == True

    strategy.setDontSell(wavax, False, sender=management)

    assert strategy.dontSell(wavax) == False


def test__set_min_amount_to_sell(
    strategy,
    management,
):
    assert strategy.minAmountToSell() == 1e10

    amount = 0

    strategy.setMinAmountToSell(amount, sender=management)

    assert strategy.minAmountToSell() == amount

    amount = int(100e18)

    strategy.setMinAmountToSell(amount, sender=management)

    assert strategy.minAmountToSell() == amount


def test__manual_sell(
    strategy,
    management,
    whale,
    asset,
    wavax,
):
    assert strategy.asset() != wavax.address

    amount = int(2e18)

    wavax.transfer(strategy.address, amount, sender=whale)

    assert asset.balanceOf(strategy.address) == 0
    assert wavax.balanceOf(strategy.address) == amount

    strategy.sellRewardManually(wavax.address, sender=management)

    assert asset.balanceOf(strategy.address) > 0
    assert wavax.balanceOf(strategy.address) == 0


def test__set_dont_sell__reverts(
    strategy,
    wavax,
    user,
):
    assert strategy.dontSell(wavax) == False

    with reverts("!Authorized"):
        strategy.setDontSell(wavax, True, sender=user)

    assert strategy.dontSell(wavax) == False


def test__set_min_amount_to_sell__reverts(
    strategy,
    user,
):
    assert strategy.minAmountToSell() == 1e10

    with reverts("!Authorized"):
        strategy.setMinAmountToSell(0, sender=user)

    assert strategy.minAmountToSell() == 1e10


def test__manual_sell__reverts(strategy, management, whale, asset, wavax, user):
    assert strategy.asset() != wavax.address

    amount = int(2e18)

    wavax.transfer(strategy.address, amount, sender=whale)

    assert asset.balanceOf(strategy.address) == 0
    assert wavax.balanceOf(strategy.address) == amount

    with reverts("!Authorized"):
        strategy.sellRewardManually(wavax.address, sender=user)

    assert asset.balanceOf(strategy.address) == 0
    assert wavax.balanceOf(strategy.address) == amount


def test__emergency_withdraw__reverts(strategy, user, deposit, amount):
    with reverts("!Authorized"):
        strategy.emergencyWithdraw(100, sender=user)

    deposit()

    check_strategy_totals(
        strategy,
        total_assets=amount,
        total_debt=amount,
        total_idle=0,
        total_supply=amount,
    )

    with reverts("!Authorized"):
        strategy.emergencyWithdraw(100, sender=user)
