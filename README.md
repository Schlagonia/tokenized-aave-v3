# Tokenized Strategy Mix for Yearn V3 strategies

This repo will allow you to write, test and deploy V3 "Tokenized Strategies".

You will only need to override the three functions in Strategy.sol of `_invest`, `freeFunds` and `_totalInvested`. With the option to also override `_tend`, `tendTrigger`, `availableDepositLimit` and `availableWithdrawLimit` if desired.

## How to start

### Requirements
    Python >=3.8.0, <=3.10
    Yarn
    Node.js >=14
    Hardhat

### Fork this repository

    git clone https://github.com/user/tokenized-strategy-ape-mix

    cd tokenized-strategy-ape-mix

### Set up your virtual environment

    python3 -m venv venv

    source venv/bin/activate

Tip: You can make them persistent by adding the variables in ~/.env (ENVVAR=... format), then adding the following in .bashrc: `set -a; source "$HOME/.env"; set +a`

### Install Ape and all dependencies

    pip install -r requirements.txt
    
    yarn
    
    ape plugins install .
    
    ape compile
    
    ape test
    
### Set your environment Variables

    export WEB3_INFURA_PROJECT_ID=your_infura_api_key

    export ETHERSCAN_API_KEY=your_api_key

## Strategy Writing

### Good to know

To create your tokenized Strategy, you must override at least 3 functions outlined in `Strategy.sol`. An in-depth description for each function is provided above each function in `Strategy.sol`.

It is important to remember the default behavior for any tokenized strategy is to be a permissionless vault, so functions such as _invest and _freeFunds can be called by anyone, and care should be taken when implementing manipulatable logic such as swaps/lp movements. Strategists can choose to limit deposit/withdraw by overriding the `availableWithdrawLimit` and `availableDepositLimit` function if it is needed for safety.

It is recommended to build strategies on the assumption that reports will happen based on the strategies specific `profitMaxUnlockTime`. Since this is the only time _totalInvested will be called any strategies that need more frequent checks, updates should override the _tend and tendTrigger functions for any needed mid-report maintenance.

The only global variable from the BaseTokenizedStrategy that can be accessed from storage is `asset`. If other global variables are needed for your specific implementation, you can use the default `TokenizedStrategy` variable to quickly retrieve any other needed variables withen the implementation, such as totalAssets, totalDebt, isShutdown etc.

Example:

    require(!TokenizedStrategy.isShutdown(), "strategy is shutdown");

NOTE: It is impossible to write to a strategy's global storage state internally post-deployment. You must make external calls from the `management` address to configure any of the desired variables.

To include permissioned functions such as extra setters, the two modifiers of `onlyManagement` and `onlyManagementAndKeepers` are available by default.

Cloning is available natively through the BaseTokenizedStrategy and can be easily done using `TokenizedStrategy.clone(...)`. The cloning function will initialize all default storage needed for the BaseTokenizedStrategy as specified in the parameters of the clone function, but an internal initialize function will need to be used for any implementation-specific initialization, such as approvals.

NOTE: When cloning while using Periphery Helpers, you should reset all variables from the helper contract that will be used. The periphery contracts leave all global variables as non-constants so they can be overridden by the implementations. This means when cloning, they will all default back to 0, address(0), etc.

The symbol used for each tokenized Strategy is set automatically with a standardized approach based on the `asset`'s symbol. Strategists should use the `name` parameter in the constructor for a unique and descriptive name that encapsulates their specific Strategy. Standard naming conventions will include the asset name, the protocol used to generate yield, and the method rewards are sold if applicable. I.e., "Weth-AaveV3Lender-UniV3Swapper".

All other functionality, such as reward selling, emergency functions, upgradability, etc., is up to the strategist to determine what best fits their vision. Due to the ability of strategies to stand alone from a Vault, it is expected and encouraged for strategists to experiment with more complex, risky, or previously unfeasible Strategies.

## Periphery

To make Strategy writing as simple as possible, a suite of optional 'Periphery Helper' contracts can be inherited by your Strategy to provide standardized and tested functionality for things like swaps. A complete list of the periphery contracts can be viewed here https://github.com/Schlagonia/tokenized-strategy-periphery.

All periphery contracts are optional, and strategists are free to use them.

### APR Oracles

In order for easy integration with Vaults, frontends, debt allocaters etc. There is the option also to create an apr oracle contract for your specific contract implementation that should return the expected apr of the Strategy based on some given debtChange. 

### HealthCheck

### Report Triggers


## Testing

Due to the nature of the BaseTokenizedStrategy utilizing an external contract for the majority of its logic, the default interface for any tokenized strategy will not allow proper testing of all functions. Testing of your Strategy should utilize the pre-built `IStrategyInterface` interface to cast any deployed strategy through for testing, as seen in the confest example. You can add any external functions that you add for your specific implementation to this interface to be able to test all functions with one variable. 

Example:

    strategy = management.deploy(project.Strategy, asset, name)
    strategy =  project.IStrategyInterface.at(strategy.address)

Due to the permissionless nature of the tokenized Strategies, all tests are written without integration with any meta vault funding it. While those tests can be added, all V3 vaults utilize the ERC-4626 standard for deposit/withdraw and accounting, so they can be plugged in easily to any number of different vaults with the same `asset.`

#### Errors:

"DecodingError: Output corrupted.": Probably due to not running on a forked chain or a chain where the TokenizedStrategy contract isn't deployed.
"No conversion registered to handle": Check the `IStrategyInterface` interface the tests are using is up to date.

### Deployment

#### Contract Verification

Once the Strategy is fully deployed and verified, you will need to verify the TokenizedStrategy functions. To do this, navigate to the /#code page on etherscan.

1. Click on the `More Options` drop-down menu. 
2. Click "is this a proxy?".
3. Click the "Verify" button.
4. Click "Save". 

This should add all of the external `TokenizedStrategy` functions to the contract interface on Etherscan.

See the ApeWorx [documentation](https://docs.apeworx.io/ape/stable/) and [github](https://github.com/ApeWorX/ape) for more information.
