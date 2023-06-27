// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {Test} from "lib/forge-std/src/Test.sol";
import {Account} from "../../src/Account.sol";
import {ConsolidatedEvents} from "../utils/ConsolidatedEvents.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {Factory} from "../../src/Factory.sol";
import {IAccount} from "../../src/interfaces/IAccount.sol";
import {IAddressResolver} from "../utils/interfaces/IAddressResolver.sol";
import {IPermit2} from "../../src/interfaces/uniswap/IPermit2.sol";
import {ISynth} from "../utils/interfaces/ISynth.sol";
import {SafeCast160} from "../../src/utils/uniswap/SafeCast160.sol";
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
    DAI,
    USDC,
    SWAP_AMOUNT,
    EOA_WITH_DAI,
    AMOUNT,
    LOW_FEE_TIER
} from "../utils/Constants.sol";

contract SwapBehaviorTest is Test, ConsolidatedEvents {
    using SafeCast160 for uint256;

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
    IERC20 private dai = IERC20(DAI);
    IERC20 private usdc = IERC20(USDC);

    // uniswap
    IPermit2 private PERMIT2;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.rollFork(BLOCK_NUMBER);

        PERMIT2 = IPermit2(UNISWAP_PERMIT2);

        Setup setup = new Setup();

        (factory,, settings,) = setup.deploySystem({
            _deployer: address(0),
            _owner: address(this),
            _addressResolver: ADDRESS_RESOLVER,
            _gelato: GELATO,
            _ops: OPS,
            _universalRouter: UNISWAP_UNIVERSAL_ROUTER,
            _permit2: UNISWAP_PERMIT2
        });

        account = Account(payable(factory.newAccount()));

        sUSD = IERC20(IAddressResolver(ADDRESS_RESOLVER).getAddress(PROXY_SUSD));
        mintSUSD(address(this), AMOUNT);

        vm.prank(EOA_WITH_DAI);
        dai.transfer(address(this), AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                              VALID SWAPS
    //////////////////////////////////////////////////////////////*/

    function test_UniswapV3Swap_DAI_SUSD() public {
        // whitelist DAI
        settings.setTokenWhitelistStatus(address(dai), true);

        // call approve() on an ERC20 to grant an infinite allowance to the canonical Permit2 contract
        dai.approve(UNISWAP_PERMIT2, type(uint256).max);

        // call approve() on the canonical Permit2 contract to grant an infinite allowance to the SM Account
        /// @dev this can be done via signature in production
        PERMIT2.approve(
            address(dai), address(account), type(uint160).max, type(uint48).max
        );

        // define command(s)
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.UNISWAP_V3_SWAP;

        // define input(s)
        bytes[] memory inputs = new bytes[](1);
        uint256 amountIn = AMOUNT / 2;
        uint256 amountOutMin = 1;
        bytes memory path = bytes.concat(
            bytes20(address(dai)), LOW_FEE_TIER, bytes20(address(sUSD))
        );
        inputs[0] = abi.encode(amountIn, amountOutMin, path);

        uint256 preBalance = sUSD.balanceOf(address(account));
        account.execute(commands, inputs);
        uint256 postBalance = sUSD.balanceOf(address(account));

        assertGt(postBalance, preBalance);
    }

    function test_UniswapV3Swap_DAI_USDC_SUSD() public {
        // whitelist DAI
        settings.setTokenWhitelistStatus(address(dai), true);

        // call approve() on an ERC20 to grant an infinite allowance to the canonical Permit2 contract
        dai.approve(UNISWAP_PERMIT2, type(uint256).max);

        // call approve() on the canonical Permit2 contract to grant an infinite allowance to the SM Account
        /// @dev this can be done via signature in production
        PERMIT2.approve(
            address(dai), address(account), type(uint160).max, type(uint48).max
        );

        // define command(s)
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.UNISWAP_V3_SWAP;

        // define input(s)
        bytes[] memory inputs = new bytes[](1);
        uint256 amountIn = AMOUNT / 2;
        uint256 amountOutMin = 1;
        bytes memory path = bytes.concat(
            bytes20(address(dai)),
            LOW_FEE_TIER,
            bytes20(address(usdc)),
            LOW_FEE_TIER,
            bytes20(address(sUSD))
        );
        inputs[0] = abi.encode(amountIn, amountOutMin, path);

        uint256 preBalance = sUSD.balanceOf(address(account));
        account.execute(commands, inputs);
        uint256 postBalance = sUSD.balanceOf(address(account));

        assertGt(postBalance, preBalance);
    }

    function test_UniswapV3Swap_SUSD_DAI() public {
        // whitelist DAI
        settings.setTokenWhitelistStatus(address(dai), true);

        // fund account with sUSD
        fundAccount(AMOUNT);

        // define command(s)
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.UNISWAP_V3_SWAP;

        // define input(s)
        bytes[] memory inputs = new bytes[](1);
        uint256 amountIn = AMOUNT / 2;
        uint256 amountOutMin = 1;
        bytes memory path = bytes.concat(
            bytes20(address(sUSD)), LOW_FEE_TIER, bytes20(address(dai))
        );
        inputs[0] = abi.encode(amountIn, amountOutMin, path);

        uint256 preBalance = dai.balanceOf(address(this));
        account.execute(commands, inputs);
        uint256 postBalance = dai.balanceOf(address(this));

        assertGt(postBalance, preBalance);
    }

    function test_UniswapV3Swap_SUSD_DAI_USDC() public {
        // whitelist DAI
        settings.setTokenWhitelistStatus(address(usdc), true);

        // fund account with sUSD
        fundAccount(AMOUNT);

        // define command(s)
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.UNISWAP_V3_SWAP;

        // define input(s)
        bytes[] memory inputs = new bytes[](1);
        uint256 amountIn = AMOUNT / 2;
        uint256 amountOutMin = 1;
        bytes memory path = bytes.concat(
            bytes20(address(sUSD)),
            LOW_FEE_TIER,
            bytes20(address(dai)),
            LOW_FEE_TIER,
            bytes20(address(usdc))
        );
        inputs[0] = abi.encode(amountIn, amountOutMin, path);

        uint256 preBalance = usdc.balanceOf(address(this));
        account.execute(commands, inputs);
        uint256 postBalance = usdc.balanceOf(address(this));

        assertGt(postBalance, preBalance);
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    // function test_UniswapV3Swap_DAI_SUSD_Event() public {
    //     // call approve() on an ERC20 to grant an infinite allowance to the canonical Permit2 contract
    //     dai.approve(UNISWAP_PERMIT2, type(uint256).max);

    //     // call approve() on the canonical Permit2 contract to grant an infinite allowance to the SM Account
    //     /// @dev this can be done via signature in production
    //     PERMIT2.approve(
    //         address(dai), address(account), type(uint160).max, type(uint48).max
    //     );

    //     // define command(s)
    //     IAccount.Command[] memory commands = new IAccount.Command[](1);
    //     commands[0] = IAccount.Command.UNISWAP_V3_SWAP;

    //     // define input(s)
    //     bytes[] memory inputs = new bytes[](1);
    //     uint256 amountIn = AMOUNT / 2;
    //     uint256 amountOutMin = 1;
    //     bytes memory path = bytes.concat(
    //         bytes20(address(dai)), LOW_FEE_TIER, bytes20(address(sUSD))
    //     );
    //     inputs[0] = abi.encode(amountIn, amountOutMin, path);

    //     vm.expectEmit(true, true, true, true);
    //     emit UniswapV3Swap(
    //         address(dai),
    //         address(sUSD),
    //         address(account),
    //         amountIn,
    //         amountOutMin
    //     );
    //     account.execute(commands, inputs);
    // }

    // function test_UniswapV3Swap_SUSD_DAI_Event() public {
    //     // fund account with sUSD
    //     fundAccount(AMOUNT);

    //     // define command(s)
    //     IAccount.Command[] memory commands = new IAccount.Command[](1);
    //     commands[0] = IAccount.Command.UNISWAP_V3_SWAP;

    //     // define input(s)
    //     bytes[] memory inputs = new bytes[](1);
    //     uint256 amountIn = AMOUNT / 2;
    //     uint256 amountOutMin = 1;
    //     bytes memory path = bytes.concat(
    //         bytes20(address(sUSD)), LOW_FEE_TIER, bytes20(address(dai))
    //     );
    //     inputs[0] = abi.encode(amountIn, amountOutMin, path);

    //     vm.expectEmit(true, true, true, true);
    //     emit UniswapV3Swap(
    //         address(sUSD), address(dai), address(this), amountIn, amountOutMin
    //     );
    //     account.execute(commands, inputs);
    // }

    // /*//////////////////////////////////////////////////////////////
    //                             HELPERS
    // //////////////////////////////////////////////////////////////*/

    function mintSUSD(address to, uint256 amount) private {
        address issuer = IAddressResolver(ADDRESS_RESOLVER).getAddress("Issuer");
        ISynth synthsUSD =
            ISynth(IAddressResolver(ADDRESS_RESOLVER).getAddress("SynthsUSD"));
        vm.prank(issuer);
        synthsUSD.issue(to, amount);
    }

    function modifyAccountMargin(int256 amount) private {
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.ACCOUNT_MODIFY_MARGIN;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(amount);
        account.execute(commands, inputs);
    }

    function fundAccount(uint256 amount) private {
        vm.deal(address(account), 1 ether);
        mintSUSD(address(this), amount);
        sUSD.approve(address(account), amount);
        modifyAccountMargin({amount: int256(amount)});
    }
}
