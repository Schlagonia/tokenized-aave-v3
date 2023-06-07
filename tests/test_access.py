import ape
from ape import Contract, reverts
from utils.checks import check_strategy_totals
from utils.utils import days_to_secs
import pytest


def test__set_uni_fees(
    asset,
    strategy,
    management,
    wavax,
):
    # Everything should start as 0
    assert strategy.uniFees(wavax, asset) == 0
    assert strategy.uniFees(asset, wavax) == 0

    strategy.setUniFees(wavax, asset, 500, sender=management)

    assert strategy.uniFees(wavax, asset) == 500
    assert strategy.uniFees(asset, wavax) == 500

    strategy.setUniFees(asset, wavax, 5, sender=management)

    assert strategy.uniFees(wavax, asset) == 5
    assert strategy.uniFees(asset, wavax) == 5

    strategy.setUniFees(asset, wavax, 0, sender=management)

    assert strategy.uniFees(wavax, asset) == 0
    assert strategy.uniFees(asset, wavax) == 0


def test__set_uni_fees__reverts(
    strategy,
    user,
    wavax,
    asset,
):
    # Everything should start as 0
    assert strategy.uniFees(wavax, asset) == 0
    assert strategy.uniFees(asset, wavax) == 0

    with reverts("!Authorized"):
        strategy.setUniFees(asset, wavax, 500, sender=user)

    assert strategy.uniFees(wavax, asset) == 0
    assert strategy.uniFees(asset, wavax) == 0


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
    assert strategy.minAmountToSell() == 1e4

    amount = 0

    strategy.setMinAmountToSell(amount, sender=management)

    assert strategy.minAmountToSell() == amount

    amount = int(100e18)

    strategy.setMinAmountToSell(amount, sender=management)

    assert strategy.minAmountToSell() == amount


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
    assert strategy.minAmountToSell() == 1e4

    with reverts("!Authorized"):
        strategy.setMinAmountToSell(0, sender=user)

    assert strategy.minAmountToSell() == 1e4


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
