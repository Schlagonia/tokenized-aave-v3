import ape
from ape import Contract, reverts
from utils.checks import check_strategy_totals
from utils.utils import days_to_secs
import pytest


def test__set_uni_fees(
    asset,
    strategy,
    management,
    aave,
    weth,
):
    # Everything should start as 0
    assert strategy.uniFees(aave, weth) == 0
    assert strategy.uniFees(weth, aave) == 0

    strategy.setUniFees(aave, weth, 500, sender=management)

    assert strategy.uniFees(aave, weth) == 500
    assert strategy.uniFees(weth, aave) == 500

    strategy.setUniFees(weth, aave, 5, sender=management)

    assert strategy.uniFees(aave, weth) == 5
    assert strategy.uniFees(weth, aave) == 5

    strategy.setUniFees(weth, aave, 0, sender=management)

    assert strategy.uniFees(aave, weth) == 0
    assert strategy.uniFees(weth, aave) == 0


def test__set_uni_fees__reverts(
    strategy,
    user,
    aave,
    weth,
):
    # Everything should start as 0
    assert strategy.uniFees(aave, weth) == 0
    assert strategy.uniFees(weth, aave) == 0

    with reverts("!Authorized"):
        strategy.setUniFees(weth, aave, 500, sender=user)

    assert strategy.uniFees(aave, weth) == 0
    assert strategy.uniFees(weth, aave) == 0


def test__dont_sell(
    strategy,
    aave,
    management,
):
    assert strategy.dontSell(aave) == False

    strategy.setDontSell(aave, True, sender=management)

    assert strategy.dontSell(aave) == True

    strategy.setDontSell(aave, False, sender=management)

    assert strategy.dontSell(aave) == False


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
    aave,
    user,
):
    assert strategy.dontSell(aave) == False

    with reverts("!Authorized"):
        strategy.setDontSell(aave, True, sender=user)

    assert strategy.dontSell(aave) == False


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
