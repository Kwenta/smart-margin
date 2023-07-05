// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {Test} from "lib/forge-std/src/Test.sol";

import {Setup} from "script/Deploy.s.sol";

import {Account} from "src/Account.sol";
import {Factory} from "src/Factory.sol";
import {IAccount} from "src/interfaces/IAccount.sol";
import {IERC20} from "src/interfaces/token/IERC20.sol";
import {IPermit2} from "src/interfaces/uniswap/IPermit2.sol";
import {SafeCast160} from "src/utils/uniswap/SafeCast160.sol";
import {Settings} from "src/Settings.sol";

import {ConsolidatedEvents} from "test/utils/ConsolidatedEvents.sol";
import {IAddressResolver} from "test/utils/interfaces/IAddressResolver.sol";
import {ISynth} from "test/utils/interfaces/ISynth.sol";

import {
    ADDRESS_RESOLVER,
    AMOUNT,
    BLOCK_NUMBER,
    DAI,
    EOA_WITH_DAI,
    LOW_FEE_TIER,
    PROXY_SUSD,
    UNISWAP_PERMIT2,
    UNISWAP_UNIVERSAL_ROUTER,
    USDC,
    USER
} from "test/utils/Constants.sol";

contract SwapBehaviorTest is Test, ConsolidatedEvents {
    using SafeCast160 for uint256;

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    Factory private factory;
    Account private account;
    Settings private settings;

    IERC20 private sUSD;
    IERC20 private dai = IERC20(DAI);
    IERC20 private usdc = IERC20(USDC);

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
            _gelato: address(0),
            _ops: address(0),
            _universalRouter: UNISWAP_UNIVERSAL_ROUTER,
            _permit2: UNISWAP_PERMIT2
        });

        account = Account(payable(factory.newAccount()));

        sUSD = IERC20(IAddressResolver(ADDRESS_RESOLVER).getAddress(PROXY_SUSD));
        mintSUSD(address(this), AMOUNT);

        vm.prank(EOA_WITH_DAI);
        dai.transfer(address(this), AMOUNT);

        // call approve() on an ERC20 to grant an infinite allowance to the canonical Permit2 contract
        sUSD.approve(UNISWAP_PERMIT2, type(uint256).max);

        // call approve() on the canonical Permit2 contract to grant an infinite allowance to the SM Account
        /// @dev this can be done via PERMIT2_PERMIT in production
        PERMIT2.approve(
            address(sUSD), address(account), type(uint160).max, type(uint48).max
        );

        // call approve() on an ERC20 to grant an infinite allowance to the canonical Permit2 contract
        dai.approve(UNISWAP_PERMIT2, type(uint256).max);

        // call approve() on the canonical Permit2 contract to grant an infinite allowance to the SM Account
        /// @dev this can be done via PERMIT2_PERMIT in production
        PERMIT2.approve(
            address(dai), address(account), type(uint160).max, type(uint48).max
        );
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                            SINGLE POOL SWAP
    //////////////////////////////////////////////////////////////*/

    function test_UniswapV3Swap_DAI_SUSD() public {
        // whitelist DAI
        settings.setTokenWhitelistStatus(address(dai), true);

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

    /*//////////////////////////////////////////////////////////////
                            MULTI POOL SWAP
    //////////////////////////////////////////////////////////////*/

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

    function test_UniswapV3Swap_DAI_USDC_SUSD() public {
        // whitelist DAI
        settings.setTokenWhitelistStatus(address(dai), true);

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

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    function test_UniswapV3Swap_DAI_SUSD_Event() public {
        // whitelist DAI
        settings.setTokenWhitelistStatus(address(dai), true);

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

        vm.expectEmit(true, true, true, true);
        emit UniswapV3Swap(
            address(dai),
            address(sUSD),
            address(account),
            amountIn,
            amountOutMin
        );
        account.execute(commands, inputs);
    }

    function test_UniswapV3Swap_SUSD_DAI_Event() public {
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

        vm.expectEmit(true, true, true, true);
        emit UniswapV3Swap(
            address(sUSD), address(dai), address(this), amountIn, amountOutMin
        );
        account.execute(commands, inputs);
    }

    /*//////////////////////////////////////////////////////////////
                             INVALID SWAPS
    //////////////////////////////////////////////////////////////*/

    function test_UniswapV3Swap_Only_Whitelisted_TokenIn() public {
        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.UNISWAP_V3_SWAP;

        bytes[] memory inputs = new bytes[](1);
        uint256 amountIn = AMOUNT / 2;
        uint256 amountOutMin = 1;
        bytes memory path = bytes.concat(
            bytes20(address(dai)), LOW_FEE_TIER, bytes20(address(sUSD))
        );
        inputs[0] = abi.encode(amountIn, amountOutMin, path);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccount.TokenSwapNotAllowed.selector,
                address(dai),
                address(sUSD)
            )
        );
        account.execute(commands, inputs);
    }

    function test_UniswapV3Swap_Only_Whitelisted_TokenOut() public {
        fundAccount(AMOUNT);

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.UNISWAP_V3_SWAP;

        bytes[] memory inputs = new bytes[](1);
        uint256 amountIn = AMOUNT / 2;
        uint256 amountOutMin = 1;
        bytes memory path = bytes.concat(
            bytes20(address(sUSD)), LOW_FEE_TIER, bytes20(address(dai))
        );
        inputs[0] = abi.encode(amountIn, amountOutMin, path);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccount.TokenSwapNotAllowed.selector,
                address(sUSD),
                address(dai)
            )
        );
        account.execute(commands, inputs);
    }

    function test_UniswapV3Swap_Either_SUSD_In_Out() public {
        /// @notice sUSD must be either tokenIn or tokenOut

        settings.setTokenWhitelistStatus(address(dai), true);

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.UNISWAP_V3_SWAP;

        bytes[] memory inputs = new bytes[](1);
        uint256 amountIn = AMOUNT / 2;
        uint256 amountOutMin = 1;
        bytes memory path = bytes.concat(
            bytes20(address(dai)), LOW_FEE_TIER, bytes20(address(dai))
        );
        inputs[0] = abi.encode(amountIn, amountOutMin, path);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccount.TokenSwapNotAllowed.selector,
                address(dai),
                address(dai)
            )
        );
        account.execute(commands, inputs);
    }

    function test_UniswapV3Swap_Invalid_AmountIn() public {
        /// @notice amountIn must be > 0

        settings.setTokenWhitelistStatus(address(dai), true);

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.UNISWAP_V3_SWAP;

        bytes[] memory inputs = new bytes[](1);
        uint256 amountIn = 0;
        uint256 amountOutMin = 1;
        bytes memory path = bytes.concat(
            bytes20(address(dai)), LOW_FEE_TIER, bytes20(address(sUSD))
        );
        inputs[0] = abi.encode(amountIn, amountOutMin, path);

        /// 'AS' revert message from UniswapV3Pool.sol when amountIn is 0
        /// https://docs.uniswap.org/contracts/v3/reference/error-codes
        vm.expectRevert(abi.encodePacked("AS"));
        account.execute(commands, inputs);
    }

    function test_UniswapV3Swap_Invalid_AmountOutMin() public {
        /// @notice add test; if amountOutMin is greater than amountOut, swap should fail

        settings.setTokenWhitelistStatus(address(dai), true);

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.UNISWAP_V3_SWAP;

        bytes[] memory inputs = new bytes[](1);
        uint256 amountIn = AMOUNT / 2;
        uint256 amountOutMin = type(uint256).max;
        bytes memory path = bytes.concat(
            bytes20(address(dai)), LOW_FEE_TIER, bytes20(address(sUSD))
        );
        inputs[0] = abi.encode(amountIn, amountOutMin, path);

        /// Custom Error type `V3TooLittleReceived` with signature `V3TooLittleReceived()`
        /// https://github.com/Uniswap/universal-router/blob/471d99ba276c383d2353d065f7a682e710ca7bdc/contracts/modules/uniswap/v3/V3SwapRouter.sol#L114
        vm.expectRevert(abi.encodeWithSignature("V3TooLittleReceived()"));
        account.execute(commands, inputs);
    }

    function test_UniswapV3Swap_Invalid_Path() public {
        bytes memory invalidPath = bytes.concat(
            bytes20(address(sUSD)),
            LOW_FEE_TIER,
            bytes20(address(0xBEEF)), // invalid token; will cause swap to fail
            LOW_FEE_TIER,
            bytes20(address(dai))
        );

        settings.setTokenWhitelistStatus(address(dai), true);

        fundAccount(AMOUNT);

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.UNISWAP_V3_SWAP;

        bytes[] memory inputs = new bytes[](1);
        uint256 amountIn = AMOUNT / 2;
        uint256 amountOutMin = 1;
        inputs[0] = abi.encode(amountIn, amountOutMin, invalidPath);

        // Call reverts without data
        vm.expectRevert(abi.encodePacked(""));
        account.execute(commands, inputs);
    }

    function test_UniswapV3Swap_Insufficient_Margin() public {
        /// @notice if account has insufficient margin when swapping out of sUSD, swap should fail

        settings.setTokenWhitelistStatus(address(dai), true);

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.UNISWAP_V3_SWAP;

        bytes[] memory inputs = new bytes[](1);
        uint256 amountIn = AMOUNT / 2;
        uint256 amountOutMin = 1;
        bytes memory path = bytes.concat(
            bytes20(address(sUSD)), LOW_FEE_TIER, bytes20(address(dai))
        );
        inputs[0] = abi.encode(amountIn, amountOutMin, path);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccount.InsufficientFreeMargin.selector, 0, AMOUNT / 2
            )
        );
        account.execute(commands, inputs);
    }

    function test_UniswapV3Swap_Insufficient_TokenIn_Balance() public {
        /// @notice if EOA has insufficient tokenIn balance, swap should fail

        settings.setTokenWhitelistStatus(address(dai), true);

        account.transferOwnership(USER);

        vm.startPrank(USER); // USER does not have DAI

        dai.approve(UNISWAP_PERMIT2, type(uint256).max);

        PERMIT2.approve(
            address(dai), address(account), type(uint160).max, type(uint48).max
        );

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.UNISWAP_V3_SWAP;

        bytes[] memory inputs = new bytes[](1);
        uint256 amountIn = AMOUNT / 2;
        uint256 amountOutMin = 1;
        bytes memory path = bytes.concat(
            bytes20(address(dai)), LOW_FEE_TIER, bytes20(address(sUSD))
        );
        inputs[0] = abi.encode(amountIn, amountOutMin, path);

        vm.expectRevert("TRANSFER_FROM_FAILED");
        account.execute(commands, inputs);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

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
        modifyAccountMargin({amount: int256(amount)});
    }
}
