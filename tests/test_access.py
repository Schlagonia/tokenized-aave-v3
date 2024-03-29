import ape
from ape import Contract, reverts
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

    with reverts("!management"):
        strategy.setUniFees(weth, aave, 500, sender=user)

    assert strategy.uniFees(aave, weth) == 0
    assert strategy.uniFees(weth, aave) == 0


def test__claim_rewards(
    strategy,
    management,
):
    assert strategy.claimRewards() == True

    strategy.setClaimRewards(False, sender=management)

    assert strategy.claimRewards() == False

    strategy.setClaimRewards(True, sender=management)

    assert strategy.claimRewards() == True


def test__set_min_amount_to_sell_mapping(strategy, management, aave):
    assert strategy.minAmountToSellMapping(aave) == 0

    amount = int(1e4)

    strategy.setMinAmountToSellMapping(aave, amount, sender=management)

    assert strategy.minAmountToSellMapping(aave) == amount

    amount = int(100e18)

    strategy.setMinAmountToSellMapping(aave, amount, sender=management)

    assert strategy.minAmountToSellMapping(aave) == amount


def test__set_dont_sell__reverts(
    strategy,
    user,
):
    assert strategy.claimRewards() == True

    with reverts("!management"):
        strategy.setClaimRewards(False, sender=user)

    assert strategy.claimRewards() == True


def test__set_min_amount_to_sell_mapping__reverts(strategy, user, aave):
    assert strategy.minAmountToSellMapping(aave) == 0

    with reverts("!management"):
        strategy.setMinAmountToSellMapping(aave, int(1e4), sender=user)

    assert strategy.minAmountToSellMapping(aave) == 0


def test__emergency_withdraw__reverts(strategy, user, deposit, amount):
    with reverts("!emergency authorized"):
        strategy.emergencyWithdraw(100, sender=user)

    deposit()

    assert strategy.totalAssets() == amount

    with reverts("!emergency authorized"):
        strategy.emergencyWithdraw(100, sender=user)
