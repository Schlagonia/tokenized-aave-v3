import ape
from ape import Contract, reverts, project
from utils.utils import days_to_secs
import pytest


def check_oracle(oracle, strategy, user, management):

    current_apr = oracle.aprAfterDebtChange(strategy.address, 0)

    assert current_apr > 0
    # If APR is expected to be under 100%
    assert current_apr < int(1e18)

    new_apr = oracle.aprAfterDebtChange(strategy, 10000000000000000000)

    assert new_apr < current_apr

    higher_apr = oracle.aprAfterDebtChange(strategy, -10000000000000000)

    assert higher_apr > current_apr

    print(f"Current apr {oracle.aprAfterDebtChange(strategy, 0)}")


def test__oracle(create_oracle, strategy, user, management):

    oracle = create_oracle()

    check_oracle(
        oracle,
        strategy,
        user,
        management,
    )
