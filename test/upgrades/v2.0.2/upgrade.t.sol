// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

/*//////////////////////////////////////////////////////////////
                           FOR REFERENCE ONLY
    //////////////////////////////////////////////////////////////*/

// import "lib/forge-std/src/Test.sol";
// import "../../utils/Constants.sol";
// import "../../../script/utils/parameters/OptimismGoerliParameters.sol";
// import {UpgradeAccountOptimismGoerli} from
//     "../../../script/upgrades/v2.0.2/Upgrade.s.sol";
// import {Account} from "../../../src/Account.sol";
// import {Factory} from "../../../src/Factory.sol";
// import {IAccount} from "../../../src/interfaces/IAccount.sol";

// contract UpgradeTest is Test {
//     // BLOCK_NUMBER corresponds to Optimism Goerli network state @ Jun-01-2023 08:24:34 PM +UTC
//     // hard coded addresses are only guaranteed for this block
//     uint256 constant BLOCK_NUMBER_UPGRADE = 10_111_503;

//     /*//////////////////////////////////////////////////////////////
//                          V2.0.1 IMPLEMENTATION
//     //////////////////////////////////////////////////////////////*/

//     address private constant OLD_IMPLEMENTATION =
//         0x76210dbA7b06bC40ec4E152D2Dcfd6bFa8102a8a;

//     /*//////////////////////////////////////////////////////////////
//                          V2.0.2 IMPLEMENTATION
//     //////////////////////////////////////////////////////////////*/

//     Account private NEW_IMPLEMENTATION;

//     /*//////////////////////////////////////////////////////////////
//                                  STATE
//     //////////////////////////////////////////////////////////////*/

//     /// @dev account only active at the specified block number
//     address ACTIVE_ACCOUNT = 0x4585158D9F2EE5Dca9BDbCf8453e9c9D04B4340E;

//     /*//////////////////////////////////////////////////////////////
//                                  SETUP
//     //////////////////////////////////////////////////////////////*/

//     function setUp() public {
//         vm.rollFork(BLOCK_NUMBER_UPGRADE);

//         // define Setup contract used for upgrades
//         UpgradeAccountOptimismGoerli upgradeAccountOptimismGoerli =
//             new UpgradeAccountOptimismGoerli();

//         // deploy v2.0.2 implementation
//         address implementationAddr = upgradeAccountOptimismGoerli.upgrade();
//         NEW_IMPLEMENTATION = Account(payable(implementationAddr));
//     }

//     /*//////////////////////////////////////////////////////////////
//                                  TESTS
//     //////////////////////////////////////////////////////////////*/

//     function test_Deployed_Account_Version() public {
//         (, bytes memory response) =
//             OLD_IMPLEMENTATION.call(abi.encodeWithSignature("VERSION()"));
//         (bytes32 version) = abi.decode(response, (bytes32));
//         assertEq(version, "2.0.1", "wrong version");
//     }

//     function test_Upgrade() public {
//         /**
//          * RECORD ALL STATE PRIOR TO UPGRADE
//          */

//         // fetch commited margin from Active Account
//         (, bytes memory response) =
//             ACTIVE_ACCOUNT.call(abi.encodeWithSignature("committedMargin()"));
//         (uint256 commitedMargin) = abi.decode(response, (uint256));
//         assert(commitedMargin != 0);

//         // fetch current conditional order id from Active Account
//         (, response) =
//             ACTIVE_ACCOUNT.call(abi.encodeWithSignature("conditionalOrderId()"));
//         (uint256 conditionalOrderId) = abi.decode(response, (uint256));
//         assert(conditionalOrderId != 0);

//         // fetch current conditional orders from Active Account
//         IAccount.ConditionalOrder[] memory orders =
//             new IAccount.ConditionalOrder[](conditionalOrderId);
//         for (uint256 index = 0; index < conditionalOrderId; index++) {
//             (, response) = ACTIVE_ACCOUNT.call(
//                 abi.encodeWithSignature("getConditionalOrder(uint256)", index)
//             );
//             (IAccount.ConditionalOrder memory order) =
//                 abi.decode(response, (IAccount.ConditionalOrder));
//             orders[index] = order;
//         }

//         // fetch owner from Active Account
//         (, response) = ACTIVE_ACCOUNT.call(abi.encodeWithSignature("owner()"));
//         (address owner) = abi.decode(response, (address));
//         assert(owner != address(0));

//         // create delegate for Active Account
//         vm.prank(owner);
//         (bool s,) = ACTIVE_ACCOUNT.call(
//             abi.encodeWithSignature("addDelegate(address)", address(this))
//         );
//         assertEq(s, true, "addDelegate failed");

//         /**
//          * EXECUTE UPGRADE
//          */

//         // upgrade Active Account to v2.0.2
//         vm.prank(OPTIMISM_GOERLI_KWENTA_ADMIN_DAO_MULTI_SIG);
//         Factory(OPTIMISM_GOERLI_FACTORY).upgradeAccountImplementation(
//             address(NEW_IMPLEMENTATION)
//         );

//         /**
//          * CHECK STATE DID NOT CHANGE
//          */

//         (, response) =
//             ACTIVE_ACCOUNT.call(abi.encodeWithSignature("committedMargin()"));
//         assertEq(
//             commitedMargin,
//             abi.decode(response, (uint256)),
//             "commitedMargin missmatch"
//         );

//         // fetch current conditional order id from Active Account
//         (, response) =
//             ACTIVE_ACCOUNT.call(abi.encodeWithSignature("conditionalOrderId()"));
//         assertEq(
//             conditionalOrderId,
//             abi.decode(response, (uint256)),
//             "conditionalOrderId missmatch"
//         );

//         // fetch current conditional orders from Active Account
//         for (uint256 index = 0; index < conditionalOrderId; index++) {
//             (, response) = ACTIVE_ACCOUNT.call(
//                 abi.encodeWithSignature("getConditionalOrder(uint256)", index)
//             );
//             assertEq(
//                 orders[index].marketKey,
//                 abi.decode(response, (IAccount.ConditionalOrder)).marketKey,
//                 "conditionalOrder missmatch"
//             );
//         }

//         // fetch owner from Active Account
//         (, response) = ACTIVE_ACCOUNT.call(abi.encodeWithSignature("owner()"));
//         assertEq(owner, abi.decode(response, (address)), "owner missmatch");

//         // fetch delegate from Active Account
//         (, response) = ACTIVE_ACCOUNT.call(
//             abi.encodeWithSignature("delegates(address)", address(this))
//         );
//         assertEq(true, abi.decode(response, (bool)), "delegate missmatch");
//     }
// }
