// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {Test} from "lib/forge-std/src/Test.sol";

import {UpgradeAccountOptimism} from "script/upgrades/v2.1.2/Upgrade.s.sol";
import {
    OPTIMISM_FACTORY,
    OPTIMISM_PDAO,
    OPTIMISM_UNISWAP_PERMIT2
} from "script/utils/parameters/OptimismParameters.sol";

import {Factory} from "src/Factory.sol";
import {IAccount as OldAccount} from
    "test/upgrades/v2.1.1/interfaces/IAccount.sol";
import {IAccount as NewAccount} from
    "test/upgrades/v2.1.2/interfaces/IAccount.sol";
import {IERC20} from "src/interfaces/token/IERC20.sol";
import {ISynth} from "test/utils/interfaces/ISynth.sol";

import {IAddressResolver} from "test/utils/interfaces/IAddressResolver.sol";
import {ADDRESS_RESOLVER, PROXY_SUSD} from "test/utils/Constants.sol";

contract UpgradeTest is Test {
    // BLOCK_NUMBER_UPGRADE corresponds to Optimism network state @ Oct-24-2023 05:53:13 PM +UTC
    // hard coded addresses are only guaranteed for this block
    uint256 private constant BLOCK_NUMBER_UPGRADE = 111_285_608;

    address private constant DELEGATE = address(0xDE1A6A7E);

    /*//////////////////////////////////////////////////////////////
                         V2.1.1 IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/

    address private constant OLD_IMPLEMENTATION =
        0x6B86c1A6878940666489780871E1C98B366d0aFF;

    /*//////////////////////////////////////////////////////////////
                         V2.1.2 IMPLEMENTATION
    //////////////////////////////////////////////////////////////*/

    address private NEW_IMPLEMENTATION;

    /*//////////////////////////////////////////////////////////////
                         V2.1.1 ACTIVE ACCOUNT
    //////////////////////////////////////////////////////////////*/

    address private activeAccount;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.rollFork(BLOCK_NUMBER_UPGRADE);

        // create active v2.1.1 account
        activeAccount = initAccountForStateTesting();

        // define Setup contract used for upgrades
        UpgradeAccountOptimism upgradeAccountOptimism =
            new UpgradeAccountOptimism();

        // deploy v2.1.2 implementation
        address implementationAddr = upgradeAccountOptimism.upgrade();
        NEW_IMPLEMENTATION = payable(implementationAddr);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deployed_Account_Version() public {
        (, bytes memory response) =
            activeAccount.call(abi.encodeWithSignature("VERSION()"));
        (bytes32 version) = abi.decode(response, (bytes32));
        assertEq(version, "2.1.1", "wrong version");
    }

    function test_Upgrade() public {
        /**
         * RECORD ALL STATE PRIOR TO UPGRADE
         */

        // fetch commited margin from Active Account
        (, bytes memory response) =
            activeAccount.call(abi.encodeWithSignature("committedMargin()"));
        (uint256 commitedMargin) = abi.decode(response, (uint256));
        assertGt(commitedMargin, 0, "commitedMargin is zero");

        // fetch current conditional order id from Active Account
        (, response) =
            activeAccount.call(abi.encodeWithSignature("conditionalOrderId()"));
        (uint256 conditionalOrderId) = abi.decode(response, (uint256));
        assertGt(conditionalOrderId, 0, "conditionalOrderId is zero");

        // fetch current conditional orders from Active Account
        OldAccount.ConditionalOrder[] memory orders =
            new OldAccount.ConditionalOrder[](conditionalOrderId);
        for (uint256 index = 0; index < conditionalOrderId; index++) {
            (, response) = activeAccount.call(
                abi.encodeWithSignature("getConditionalOrder(uint256)", index)
            );
            (OldAccount.ConditionalOrder memory order) =
                abi.decode(response, (OldAccount.ConditionalOrder));
            orders[index] = order;
        }

        // fetch owner from Active Account
        (, response) = activeAccount.call(abi.encodeWithSignature("owner()"));
        (address owner) = abi.decode(response, (address));
        assert(owner != address(0));

        // fetch delegate from Active Account
        (, response) = activeAccount.call(
            abi.encodeWithSignature("delegates(address)", DELEGATE)
        );
        assertEq(true, abi.decode(response, (bool)), "delegate missmatch");

        /**
         * EXECUTE UPGRADE
         */

        // upgrade Active Account to v2.1.2
        vm.prank(OPTIMISM_PDAO);
        Factory(OPTIMISM_FACTORY).upgradeAccountImplementation(
            address(NEW_IMPLEMENTATION)
        );

        /**
         * VERIFY VERSION DID CHANGE
         */

        (, response) = activeAccount.call(abi.encodeWithSignature("VERSION()"));
        (bytes32 version) = abi.decode(response, (bytes32));
        assert(version != "2.1.1");

        /**
         * CHECK STATE DID NOT CHANGE
         */

        (, response) =
            activeAccount.call(abi.encodeWithSignature("committedMargin()"));
        assertEq(
            commitedMargin,
            abi.decode(response, (uint256)),
            "commitedMargin missmatch"
        );

        // fetch current conditional order id from Active Account
        (, response) =
            activeAccount.call(abi.encodeWithSignature("conditionalOrderId()"));
        assertEq(
            conditionalOrderId,
            abi.decode(response, (uint256)),
            "conditionalOrderId missmatch"
        );

        // fetch current conditional orders from Active Account
        for (uint256 index = 0; index < conditionalOrderId; index++) {
            (, response) = activeAccount.call(
                abi.encodeWithSignature("getConditionalOrder(uint256)", index)
            );
            assertEq(
                orders[index].marketKey,
                abi.decode(response, (NewAccount.ConditionalOrder)).marketKey,
                "conditionalOrder missmatch"
            );
        }

        // fetch owner from Active Account
        (, response) = activeAccount.call(abi.encodeWithSignature("owner()"));
        assertEq(owner, abi.decode(response, (address)), "owner missmatch");

        // fetch delegate from Active Account
        (, response) = activeAccount.call(
            abi.encodeWithSignature("delegates(address)", DELEGATE)
        );
        assertEq(true, abi.decode(response, (bool)), "delegate missmatch");
    }

    /*//////////////////////////////////////////////////////////////
                               UTILITIES
    //////////////////////////////////////////////////////////////*/

    function initAccountForStateTesting() internal returns (address) {
        uint256 amount = 10_000 ether;

        /// @notice create account
        address payable accountAddress = Factory(OPTIMISM_FACTORY).newAccount();

        /// @notice mint sUSD to this contract
        address issuer = IAddressResolver(ADDRESS_RESOLVER).getAddress("Issuer");
        ISynth synthsUSD =
            ISynth(IAddressResolver(ADDRESS_RESOLVER).getAddress("SynthsUSD"));
        vm.prank(issuer);
        synthsUSD.issue(address(this), amount);

        /// @notice fund SM account with eth and sUSD (i.e. margin)
        vm.deal(accountAddress, 1 ether);
        IERC20(IAddressResolver(ADDRESS_RESOLVER).getAddress(PROXY_SUSD))
            .approve(address(accountAddress), type(uint256).max);
        OldAccount.Command[] memory commands = new OldAccount.Command[](1);
        commands[0] = OldAccount.Command.ACCOUNT_MODIFY_MARGIN;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(amount);
        OldAccount(accountAddress).execute(commands, inputs);

        /// @notice create/submit conditional order which lock up margin
        commands[0] = OldAccount.Command.GELATO_PLACE_CONDITIONAL_ORDER;
        bytes32 marketKey = bytes32("sETHPERP");
        inputs[0] = abi.encode(
            marketKey,
            int256(amount / 2),
            int256(1 ether),
            10_000 ether,
            OldAccount.ConditionalOrderTypes.LIMIT,
            1000 ether,
            true
        );
        OldAccount(accountAddress).execute(commands, inputs);

        /// @notice add delegate
        (bool s,) = accountAddress.call(
            abi.encodeWithSignature("addDelegate(address)", DELEGATE)
        );
        assertEq(s, true, "addDelegate failed");

        return accountAddress;
    }
}
