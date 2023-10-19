import ape
from ape import accounts, project, networks


def deploy():
    signer = accounts.load("v3_deployer")

    signer.deploy(
        project.AaveV3LenderFactory,
        "0xB865AAf1f9f60630934739595f183C4900f65ed9",
        "0xB865AAf1f9f60630934739595f183C4900f65ed9",
        "0xd9e53c8b326fddcdbcf225d1f7be487e1f01bd0b",
        publish=True,
    )


def publish():
    factory = project.AaveV3Lender.at("0xc5eB11591636ac0794C149CEd926846105f61b17")

    networks.provider.network.explorer.publish_contract(factory)


def main():
    publish()
    # deploy()
