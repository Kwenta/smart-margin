// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {Test} from "lib/forge-std/src/Test.sol";
import {Account} from "../../src/Account.sol";
import {ConsolidatedEvents} from "../utils/ConsolidatedEvents.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {Factory} from "../../src/Factory.sol";
import {IAccount} from "../../src/interfaces/IAccount.sol";
import {IAddressResolver} from "../utils/interfaces/IAddressResolver.sol";
import {ISynth} from "../utils/interfaces/ISynth.sol";
import {Settings} from "../../src/Settings.sol";
import {Setup} from "../../script/Deploy.s.sol";
import {
    ADDRESS_RESOLVER,
    BLOCK_NUMBER,
    PROXY_SUSD,
    FUTURES_MARKET_MANAGER,
    SYSTEM_STATUS,
    PERPS_V2_EXCHANGE_RATE,
    UNISWAP_UNIVERSAL_ROUTER,
    UNISWAP_PERMIT2,
    GELATO,
    OPS,
    MARGIN_ASSET,
    DAI,
    WETH,
    SWAP_AMOUNT,
    EOA_WITH_DAI
} from "../utils/Constants.sol";

contract SwapBehaviorTest is Test, ConsolidatedEvents {
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    // main contracts
    Factory private factory;
    Account private account;
    Settings private settings;

    // helper contracts for testing
    IERC20 private sUSD;
    IERC20 private dai;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.rollFork(BLOCK_NUMBER);

        // define Setup contract used for deployments
        Setup setup = new Setup();

        // deploy system contracts
        (factory,, settings,) = setup.deploySystem({
            _deployer: address(0),
            _owner: address(this),
            _addressResolver: ADDRESS_RESOLVER,
            _gelato: GELATO,
            _ops: OPS,
            _universalRouter: UNISWAP_UNIVERSAL_ROUTER,
            _permit2: UNISWAP_PERMIT2
        });

        // deploy an Account contract
        account = Account(payable(factory.newAccount()));

        // define sUSD token
        sUSD = IERC20(IAddressResolver(ADDRESS_RESOLVER).getAddress(PROXY_SUSD));

        // define DAI token
        dai = IERC20(DAI);

        // whitelist DAI token
        settings.setTokenWhitelistStatus(DAI, true);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                              VALID SWAPS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    // /*//////////////////////////////////////////////////////////////
    //                             HELPERS
    // //////////////////////////////////////////////////////////////*/

    /// @custom:todo add function that approves Permit2

    /// @custom:todo add function that creates signatures

    /// @custom:todo add function that creates paths for pool swaps

    // function mintSUSD(address to, uint256 amount) private {
    //     address issuer = IAddressResolver(ADDRESS_RESOLVER).getAddress("Issuer");
    //     ISynth synthsUSD =
    //         ISynth(IAddressResolver(ADDRESS_RESOLVER).getAddress("SynthsUSD"));
    //     vm.prank(issuer);
    //     synthsUSD.issue(to, amount);
    // }

    // function modifyAccountMargin(int256 amount) private {
    //     IAccount.Command[] memory commands = new IAccount.Command[](1);
    //     commands[0] = IAccount.Command.ACCOUNT_MODIFY_MARGIN;
    //     bytes[] memory inputs = new bytes[](1);
    //     inputs[0] = abi.encode(amount);
    //     account.execute(commands, inputs);
    // }

    // function fundAccount(uint256 amount) private {
    //     vm.deal(address(account), 1 ether);
    //     mintSUSD(address(this), amount);
    //     sUSD.approve(address(account), amount);
    //     modifyAccountMargin({amount: int256(amount)});
    // }
}
