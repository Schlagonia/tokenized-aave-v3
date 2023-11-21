import ape
from ape import accounts, project, networks


def deploy():
    signer = accounts.load("")

    signer.deploy(
        project.AaveV3LenderFactory,
        "",
        "",
        "",
        publish=True,
    )


def publish():
    factory = project.AaveV3Lender.at("")

    networks.provider.network.explorer.publish_contract(factory)


def main():
    #publish()
    deploy()
