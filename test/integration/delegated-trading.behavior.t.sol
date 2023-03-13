// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {Account} from "../../src/Account.sol";
import {AccountExposed} from "../utils/AccountExposed.sol";
import {ConsolidatedEvents} from "../utils/ConsolidatedEvents.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {Events} from "../../src/Events.sol";
import {Factory} from "../../src/Factory.sol";
import {
    IAccount,
    IFuturesMarketManager,
    IPerpsV2MarketConsolidated
} from "../../src/interfaces/IAccount.sol";
import {IAddressResolver} from "@synthetix/IAddressResolver.sol";
import {IPerpsV2MarketSettings} from "@synthetix/IPerpsV2MarketSettings.sol";
import {ISynth} from "@synthetix/ISynth.sol";
import {OpsReady, IOps} from "../../src/utils/OpsReady.sol";
import {Settings} from "../../src/Settings.sol";
import {Setup} from "../../script/Deploy.s.sol";
import "../utils/Constants.sol";

// functions tagged with @HELPER are helper functions and not tests
// tests tagged with @AUDITOR are flags for desired increased scrutiny by the auditors
contract DelegatedTradingBehavior is Test, ConsolidatedEvents {
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    Settings private settings;
    Events private events;
    Factory private factory;
    ERC20 private sUSD;
    Account private account;
    AccountExposed private accountExposed;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.rollFork(BLOCK_NUMBER);

        sUSD = ERC20(
            (IAddressResolver(ADDRESS_RESOLVER)).getAddress("ProxyERC20sUSD")
        );

        Setup setup = new Setup();
        factory = setup.deploySmartMarginFactory({
            owner: address(this),
            treasury: KWENTA_TREASURY,
            tradeFee: TRADE_FEE,
            limitOrderFee: LIMIT_ORDER_FEE,
            stopOrderFee: STOP_ORDER_FEE,
            addressResolver: ADDRESS_RESOLVER,
            marginAsset: MARGIN_ASSET,
            gelato: GELATO,
            ops: OPS
        });

        settings = Settings(factory.settings());
        events = Events(factory.events());

        account = Account(payable(factory.newAccount()));

        accountExposed = new AccountExposed();
        accountExposed.setFuturesMarketManager(
            IFuturesMarketManager(FUTURES_MARKET_MANAGER)
        );
        accountExposed.setSettings(settings);
        accountExposed.setEvents(events);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                      ADD/REMOVE DELEGATED TRADERS
    //////////////////////////////////////////////////////////////*/

    function test_AddDelegatedTrader() public {}
    function test_AddDelegatedTrader_OnlyOwner() public {}
    function test_AddDelegatedTrader_ZeroAddress() public {}
    function test_AddDelegatedTrader_AlreadyDelegated() public {}

    function test_RemoveDelegatedTrader() public {}
    function test_RemoveDelegatedTrader_OnlyOwner() public {}
    function test_RemoveDelegatedTrader_ZeroAddress() public {}
    function test_RemoveDelegatedTrader_NotDelegated() public {}

    /*//////////////////////////////////////////////////////////////
                      DELEGATED TRADER PERMISSIONS
    //////////////////////////////////////////////////////////////*/

    function test_DelegatedTrader_TransferAccountOwnership() public {}

    function test_DelegatedTrader_Execute_ACCOUNT_MODIFY_MARGIN() public {}
    function test_DelegatedTrader_Execute_ACCOUNT_WITHDRAW_ETH() public {}
    function test_DelegatedTrader_Execute_PERPS_V2_MODIFY_MARGIN() public {}
    function test_DelegatedTrader_Execute_PERPS_V2_WITHDRAW_ALL_MARGIN() public {}
    function test_DelegatedTrader_Execute_PERPS_V2_SUBMIT_ATOMIC_ORDER() public {}
    function test_DelegatedTrader_Execute_PERPS_V2_SUBMIT_DELAYED_ORDER() public {}
    function test_DelegatedTrader_Execute_PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER() public {}
    function test_DelegatedTrader_Execute_PERPS_V2_CANCEL_DELAYED_ORDER() public {}
    function test_DelegatedTrader_Execute_PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER() public {}
    function test_DelegatedTrader_Execute_PERPS_V2_CLOSE_POSITION() public {}
    function test_DelegatedTrader_Execute_GELATO_PLACE_CONDITIONAL_ORDER() public {}
    function test_DelegatedTrader_Execute_GELATO_CANCEL_CONDITIONAL_ORDER() public {}
}
