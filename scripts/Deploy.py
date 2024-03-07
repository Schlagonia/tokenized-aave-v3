import ape
from ape import accounts, project, networks


def deploy():
    signer = accounts.load("v3_deployer")

    signer.deploy(
        project.SparkLenderFactory,
        "",
        "",
        # publish=True,
    )


def publish():
    factory = project.SparkLenderFactory.at("")

    networks.provider.network.explorer.publish_contract(factory)


def main():
    # publish()
    deploy()
