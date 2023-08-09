import ape 
from ape import accounts, project

def deploy():
    signer = accounts.load("")

    signer.deploy(
        project.AaveV3LenderFactory,
        "",
        "",
        "",
        publish=True
    )

def main():
    deploy()