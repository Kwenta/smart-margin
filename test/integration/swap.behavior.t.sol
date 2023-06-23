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
    UNISWAP_V3_SWAP_ROUTER,
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
            _uniswapV3SwapRouter: UNISWAP_V3_SWAP_ROUTER
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
                             INVALID SWAPS
    //////////////////////////////////////////////////////////////*/

    /*
    vm.expectRevert("Insufficient balance after any settlement owing");

    vm.expectRevert(
            abi.encodeWithSelector(IAccount.LengthMismatch.selector)
        );
    */

    // function test_Command_UNISWAP_V3_SWAP_INTO_SUSD_Not_Whitelisted() public {
    //     IAccount.Command[] memory commands = new IAccount.Command[](1);
    //     commands[0] = IAccount.Command.UNISWAP_V3_SWAP_INTO_SUSD;

    //     bytes[] memory inputs = new bytes[](1);
    //     inputs[0] = abi.encode(
    //         WETH, // tokenIn; not whitelisted
    //         3000, // fee: for this example, we will set the pool fee to 0.3%
    //         block.timestamp, // deadline
    //         SWAP_AMOUNT, // amountIn
    //         1, // amountOutMinimum
    //         0 // sqrtPriceLimitX96
    //     );

    //     vm.expectRevert(
    //         abi.encodeWithSelector(IAccount.TokenSwapNotAllowed.selector)
    //     );

    //     account.execute(commands, inputs);
    // }

    // function test_Command_UNISWAP_V3_SWAP_INTO_SUSD_Invalid_Token() public {
    //     IAccount.Command[] memory commands = new IAccount.Command[](1);
    //     commands[0] = IAccount.Command.UNISWAP_V3_SWAP_INTO_SUSD;

    //     bytes[] memory inputs = new bytes[](1);
    //     inputs[0] = abi.encode(
    //         address(bytes20("BAD TOKEN")), // tokenIn; whitelisted but invalid token
    //         3000, // fee: for this example, we will set the pool fee to 0.3%
    //         block.timestamp, // deadline
    //         SWAP_AMOUNT, // amountIn
    //         1, // amountOutMinimum
    //         0 // sqrtPriceLimitX96
    //     );

    //     // whitelist a bad token
    //     settings.setTokenWhitelistStatus(address(bytes20("BAD TOKEN")), true);

    //     // Call reverts without data
    //     vm.expectRevert();
    //     account.execute(commands, inputs);
    // }

    // function test_Command_UNISWAP_V3_SWAP_INTO_SUSD_Insufficient_TokenIn()
    //     public
    // {
    //     IAccount.Command[] memory commands = new IAccount.Command[](1);
    //     commands[0] = IAccount.Command.UNISWAP_V3_SWAP_INTO_SUSD;

    //     bytes[] memory inputs = new bytes[](1);
    //     inputs[0] = abi.encode(
    //         DAI, // tokenIn
    //         3000, // fee: for this example, we will set the pool fee to 0.3%
    //         block.timestamp, // deadline
    //         SWAP_AMOUNT, // amountIn
    //         1, // amountOutMinimum
    //         0 // sqrtPriceLimitX96
    //     );

    //     vm.expectRevert("Dai/insufficient-balance");
    //     account.execute(commands, inputs);
    // }

    // function test_Command_UNISWAP_V3_SWAP_INTO_SUSD_Invalid_Fee() public {
    //     IAccount.Command[] memory commands = new IAccount.Command[](1);
    //     commands[0] = IAccount.Command.UNISWAP_V3_SWAP_INTO_SUSD;

    //     // Uniswap v3 introduces multiple pools for each token pair,
    //     // each with a different swapping fee. Liquidity providers may
    //     // initially create pools at three fee levels: 0.05%, 0.30%, and 1%.
    //     //
    //     // for this test, we set fee to type(uint24).max which is invalid
    //     bytes[] memory inputs = new bytes[](1);
    //     inputs[0] = abi.encode(
    //         DAI, // tokenIn
    //         type(uint24).max, // fee: invalid fee
    //         block.timestamp, // deadline
    //         SWAP_AMOUNT, // amountIn
    //         1, // amountOutMinimum
    //         0 // sqrtPriceLimitX96
    //     );

    //     account.transferOwnership(EOA_WITH_DAI);

    //     vm.startPrank(EOA_WITH_DAI);

    //     dai.approve(address(account), SWAP_AMOUNT);

    //     // Call reverts without data
    //     vm.expectRevert();
    //     account.execute(commands, inputs);

    //     vm.stopPrank();
    // }

    // function test_Command_UNISWAP_V3_SWAP_INTO_SUSD_Invalid_Deadline() public {
    //     IAccount.Command[] memory commands = new IAccount.Command[](1);
    //     commands[0] = IAccount.Command.UNISWAP_V3_SWAP_INTO_SUSD;

    //     // for this test, we set deadline to a time before the current block (i.e. in the past)
    //     bytes[] memory inputs = new bytes[](1);
    //     inputs[0] = abi.encode(
    //         DAI, // tokenIn
    //         3000, // fee: for this example, we will set the pool fee to 0.3%
    //         block.timestamp - 1, // deadline: invalid because it is in the past
    //         SWAP_AMOUNT, // amountIn
    //         1, // amountOutMinimum
    //         0 // sqrtPriceLimitX96
    //     );

    //     account.transferOwnership(EOA_WITH_DAI);

    //     vm.startPrank(EOA_WITH_DAI);

    //     dai.approve(address(account), SWAP_AMOUNT);

    //     vm.expectRevert("Transaction too old");
    //     account.execute(commands, inputs);

    //     vm.stopPrank();
    // }

    // function test_Command_UNISWAP_V3_SWAP_INTO_SUSD_Invalid_AmountIn() public {
    //     IAccount.Command[] memory commands = new IAccount.Command[](1);
    //     commands[0] = IAccount.Command.UNISWAP_V3_SWAP_INTO_SUSD;

    //     bytes[] memory inputs = new bytes[](1);
    //     inputs[0] = abi.encode(
    //         DAI, // tokenIn
    //         3000, // fee: for this example, we will set the pool fee to 0.3%
    //         block.timestamp, // deadline
    //         dai.balanceOf(EOA_WITH_DAI) + 1, // amountIn: greater than EOA's balance
    //         1, // amountOutMinimum
    //         0 // sqrtPriceLimitX96
    //     );

    //     account.transferOwnership(EOA_WITH_DAI);

    //     vm.startPrank(EOA_WITH_DAI);

    //     dai.approve(address(account), SWAP_AMOUNT);

    //     vm.expectRevert("Dai/insufficient-balance");
    //     account.execute(commands, inputs);

    //     vm.stopPrank();
    // }

    // function test_Command_UNISWAP_V3_SWAP_INTO_SUSD_Invalid_AmountOutMinimum()
    //     public
    // {
    //     IAccount.Command[] memory commands = new IAccount.Command[](1);
    //     commands[0] = IAccount.Command.UNISWAP_V3_SWAP_INTO_SUSD;

    //     bytes[] memory inputs = new bytes[](1);
    //     inputs[0] = abi.encode(
    //         DAI, // tokenIn
    //         3000, // fee: for this example, we will set the pool fee to 0.3%
    //         block.timestamp, // deadline
    //         SWAP_AMOUNT, // amountIn
    //         type(uint256).max, // amountOutMinimum: invalid due to being greater than current exchange rate
    //         0 // sqrtPriceLimitX96
    //     );

    //     account.transferOwnership(EOA_WITH_DAI);

    //     vm.startPrank(EOA_WITH_DAI);

    //     dai.approve(address(account), SWAP_AMOUNT);

    //     vm.expectRevert("Too little received");
    //     account.execute(commands, inputs);

    //     vm.stopPrank();
    // }

    // function test_Command_UNISWAP_V3_SWAP_INTO_SUSD_Invalid_SqrtPriceLimitX96()
    //     public
    // {
    //     IAccount.Command[] memory commands = new IAccount.Command[](1);
    //     commands[0] = IAccount.Command.UNISWAP_V3_SWAP_INTO_SUSD;

    //     // for this test, we set sqrtPriceLimitX96 to 1
    //     // see: https://uniswapv3book.com/docs/milestone_3/slippage-protection/#slippage-protection-in-swaps
    //     bytes[] memory inputs = new bytes[](1);
    //     inputs[0] = abi.encode(
    //         DAI, // tokenIn
    //         3000, // fee: for this example, we will set the pool fee to 0.3%
    //         block.timestamp, // deadline
    //         SWAP_AMOUNT, // amountIn
    //         1, // amountOutMinimum
    //         1 // sqrtPriceLimitX96
    //     );

    //     account.transferOwnership(EOA_WITH_DAI);

    //     vm.startPrank(EOA_WITH_DAI);

    //     dai.approve(address(account), SWAP_AMOUNT);

    //     // Call reverts with: "SPL" -> sqrtPriceLimit
    //     // vm.expectRevert(abi.encodePacked("SPL"));
    //     account.execute(commands, inputs);

    //     vm.stopPrank();
    // }

    // function test_Command_UNISWAP_V3_SWAP_OUT_OF_SUSD_Not_Whitelisted()
    //     public
    // {
    //     /// @custom:todo implement test
    // }

    // function test_Command_UNISWAP_V3_SWAP_OUT_OF_SUSD_Invalid_Token() public {
    //     /// @custom:todo implement test
    // }

    // function test_Command_UNISWAP_V3_SWAP_OUT_OF_SUSD_Insufficient_TokenIn()
    //     public
    // {
    //     /// @custom:todo implement test
    // }

    // function test_Command_UNISWAP_V3_SWAP_OUT_OF_SUSD_Insufficient_Margin()
    //     public
    // {
    //     /// @custom:todo implement test
    // }

    // function test_Command_UNISWAP_V3_SWAP_OUT_OF_SUSD_Invalid_Fee() public {
    //     /// @custom:todo implement test
    // }

    // function test_Command_UNISWAP_V3_SWAP_OUT_OF_SUSD_Invalid_Deadline()
    //     public
    // {
    //     /// @custom:todo implement test
    // }

    // function test_Command_UNISWAP_V3_SWAP_OUT_OF_SUSD_Invalid_AmountIn()
    //     public
    // {
    //     /// @custom:todo implement test
    // }

    // function test_Command_UNISWAP_V3_SWAP_OUT_OF_SUSD_Invalid_AmountOutMinimum()
    //     public
    // {
    //     /// @custom:todo implement test
    // }

    // function test_Command_UNISWAP_V3_SWAP_OUT_OF_SUSD_Invalid_SqrtPriceLimitX96(
    // ) public {
    //     /// @custom:todo implement test
    // }

    // /*//////////////////////////////////////////////////////////////
    //                           VALID SWAPS
    // //////////////////////////////////////////////////////////////*/

    // function test_Command_UNISWAP_V3_SWAP_INTO_SUSD() public {
    //     IAccount.Command[] memory commands = new IAccount.Command[](1);
    //     commands[0] = IAccount.Command.UNISWAP_V3_SWAP_INTO_SUSD;

    //     // Naively set amountOutMinimum to 0. In production, use an oracle or
    //     // other data source to choose a safer value for amountOutMinimum.
    //     // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap
    //     // our exact input amount.
    //     bytes[] memory inputs = new bytes[](1);
    //     inputs[0] = abi.encode(
    //         DAI, // tokenIn
    //         3000, // fee: for this example, we will set the pool fee to 0.3%
    //         block.timestamp, // deadline
    //         SWAP_AMOUNT, // amountIn
    //         1, // amountOutMinimum
    //         0 // sqrtPriceLimitX96
    //     );

    //     account.transferOwnership(EOA_WITH_DAI);

    //     vm.startPrank(EOA_WITH_DAI);

    //     dai.approve(address(account), SWAP_AMOUNT);

    //     uint256 preSwapBalance = sUSD.balanceOf(address(account));
    //     account.execute(commands, inputs);
    //     uint256 postSwapBalance = sUSD.balanceOf(address(account));

    //     vm.stopPrank();

    //     assert(postSwapBalance > preSwapBalance);
    // }

    // function test_Command_UNISWAP_V3_SWAP_OUT_OF_SUSD() public {
    //     fundAccount(SWAP_AMOUNT);

    //     IAccount.Command[] memory commands = new IAccount.Command[](1);
    //     commands[0] = IAccount.Command.UNISWAP_V3_SWAP_OUT_OF_SUSD;

    //     // Naively set amountOutMinimum to 0. In production, use an oracle or
    //     // other data source to choose a safer value for amountOutMinimum.
    //     // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap
    //     // our exact input amount.
    //     bytes[] memory inputs = new bytes[](1);
    //     inputs[0] = abi.encode(
    //         DAI, // tokenOut
    //         3000, // fee: for this example, we will set the pool fee to 0.3%
    //         block.timestamp, // deadline
    //         SWAP_AMOUNT, // amountIn
    //         1, // amountOutMinimum
    //         0 // sqrtPriceLimitX96
    //     );

    //     uint256 preSwapBalance = dai.balanceOf(address(this));
    //     account.execute(commands, inputs);
    //     uint256 postSwapBalance = dai.balanceOf(address(this));

    //     assert(postSwapBalance > preSwapBalance);
    // }

    // /*//////////////////////////////////////////////////////////////
    //                              EVENTS
    // //////////////////////////////////////////////////////////////*/

    // function test_Command_UNISWAP_V3_SWAP_INTO_SUSD_Event() public {
    //     IAccount.Command[] memory commands = new IAccount.Command[](1);
    //     commands[0] = IAccount.Command.UNISWAP_V3_SWAP_INTO_SUSD;

    //     bytes[] memory inputs = new bytes[](1);
    //     inputs[0] = abi.encode(
    //         DAI, // tokenIn
    //         3000, // fee: for this example, we will set the pool fee to 0.3%
    //         block.timestamp, // deadline
    //         SWAP_AMOUNT, // amountIn
    //         1, // amountOutMinimum
    //         0 // sqrtPriceLimitX96
    //     );

    //     account.transferOwnership(EOA_WITH_DAI);

    //     vm.startPrank(EOA_WITH_DAI);

    //     dai.approve(address(account), SWAP_AMOUNT);

    //     vm.expectEmit(true, true, true, true);
    //     emit UniswapV3Swap({
    //         tokenIn: DAI,
    //         tokenOut: MARGIN_ASSET,
    //         fee: 3000,
    //         recipient: address(account),
    //         deadline: block.timestamp,
    //         amountIn: SWAP_AMOUNT,
    //         amountOutMinimum: 1,
    //         sqrtPriceLimitX96: 0,
    //         amountOut: 99465767598291627963 // specific to block number; just verify that it's not 0
    //     });
    //     account.execute(commands, inputs);

    //     vm.stopPrank();
    // }

    // function test_Command_UNISWAP_V3_SWAP_OUT_OF_SUSD_Event() public {
    //     fundAccount(SWAP_AMOUNT);

    //     IAccount.Command[] memory commands = new IAccount.Command[](1);
    //     commands[0] = IAccount.Command.UNISWAP_V3_SWAP_OUT_OF_SUSD;

    //     bytes[] memory inputs = new bytes[](1);
    //     inputs[0] = abi.encode(
    //         DAI, // tokenOut
    //         3000, // fee: for this example, we will set the pool fee to 0.3%
    //         block.timestamp, // deadline
    //         SWAP_AMOUNT, // amountIn
    //         1, // amountOutMinimum
    //         0 // sqrtPriceLimitX96
    //     );

    //     vm.expectEmit(true, true, true, true);
    //     emit UniswapV3Swap({
    //         tokenIn: MARGIN_ASSET,
    //         tokenOut: DAI,
    //         fee: 3000,
    //         recipient: address(this),
    //         deadline: block.timestamp,
    //         amountIn: SWAP_AMOUNT,
    //         amountOutMinimum: 1,
    //         sqrtPriceLimitX96: 0,
    //         amountOut: 99532707665810238670 // specific to block number; just verify that it's not 0
    //     });
    //     account.execute(commands, inputs);
    // }

    // /*//////////////////////////////////////////////////////////////
    //                             HELPERS
    // //////////////////////////////////////////////////////////////*/

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
