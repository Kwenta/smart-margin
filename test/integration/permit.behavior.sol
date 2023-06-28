// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {Account} from "../../src/Account.sol";
import {Factory} from "../../src/Factory.sol";
import {IAccount} from "../../src/interfaces/IAccount.sol";
import {IAddressResolver} from "../utils/interfaces/IAddressResolver.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {IPermit2} from "../../src/interfaces/uniswap/IPermit2.sol";
import {PermitSignature} from "../utils/PermitSignature.sol";
import {SafeCast160} from "../../src/utils/uniswap/SafeCast160.sol";
import {Settings} from "../../src/Settings.sol";
import {Setup} from "../../script/Deploy.s.sol";
import {Test} from "lib/forge-std/src/Test.sol";
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
    USDC
} from "../utils/Constants.sol";

contract PermitBehaviorTest is Test, PermitSignature {
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

    address signer;
    uint256 signerPrivateKey;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.rollFork(BLOCK_NUMBER);

        Setup setup = new Setup();

        signerPrivateKey = 0x12341234;
        signer = vm.addr(signerPrivateKey);

        PERMIT2 = IPermit2(UNISWAP_PERMIT2);

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
        account.transferOwnership(signer);

        vm.prank(EOA_WITH_DAI);
        dai.transfer(signer, AMOUNT);

        sUSD = IERC20(IAddressResolver(ADDRESS_RESOLVER).getAddress(PROXY_SUSD));

        settings.setTokenWhitelistStatus(address(dai), true);

        vm.prank(signer);
        dai.approve(UNISWAP_PERMIT2, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Permit() public {
        IPermit2.PermitSingle memory permitSingle = IPermit2.PermitSingle({
            details: IPermit2.PermitDetails({
                token: address(dai),
                amount: type(uint160).max,
                expiration: type(uint48).max,
                nonce: 0
            }),
            spender: address(account),
            sigDeadline: block.timestamp + 1000
        });

        bytes memory signature = getPermitSignature({
            permit: permitSingle,
            privateKey: signerPrivateKey,
            domainSeparator: PERMIT2.DOMAIN_SEPARATOR()
        });

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERMIT2_PERMIT;

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(permitSingle, signature);

        vm.startPrank(signer);
        account.execute(commands, inputs);

        (uint160 amount, uint48 expiration, uint48 nonce) =
            PERMIT2.allowance(signer, address(dai), address(account));
        assertEq(amount, type(uint160).max);
        assertEq(expiration, type(uint48).max);
        assertEq(nonce, 1);
    }

    function test_Permit_UniswapV3Swap() public {
        IPermit2.PermitSingle memory permitSingle = IPermit2.PermitSingle({
            details: IPermit2.PermitDetails({
                token: address(dai),
                amount: type(uint160).max,
                expiration: type(uint48).max,
                nonce: 0
            }),
            spender: address(account),
            sigDeadline: block.timestamp + 1000
        });

        bytes memory signature = getPermitSignature({
            permit: permitSingle,
            privateKey: signerPrivateKey,
            domainSeparator: PERMIT2.DOMAIN_SEPARATOR()
        });

        uint256 amountIn = AMOUNT / 2;
        uint256 amountOutMin = 1;
        bytes memory path = bytes.concat(
            bytes20(address(dai)), LOW_FEE_TIER, bytes20(address(sUSD))
        );

        IAccount.Command[] memory commands = new IAccount.Command[](2);
        commands[0] = IAccount.Command.PERMIT2_PERMIT;
        commands[1] = IAccount.Command.UNISWAP_V3_SWAP;

        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(permitSingle, signature);
        inputs[1] = abi.encode(amountIn, amountOutMin, path);

        vm.prank(signer);
        account.execute(commands, inputs);

        assertGt(sUSD.balanceOf(address(account)), 0);
    }

    function test_Permit_UniswapV3Swap_Cant_Replay() public {
        IPermit2.PermitSingle memory permitSingle = IPermit2.PermitSingle({
            details: IPermit2.PermitDetails({
                token: address(dai),
                amount: type(uint160).max,
                expiration: type(uint48).max,
                nonce: 0
            }),
            spender: address(account),
            sigDeadline: block.timestamp + 1000
        });

        bytes memory signature = getPermitSignature({
            permit: permitSingle,
            privateKey: signerPrivateKey,
            domainSeparator: PERMIT2.DOMAIN_SEPARATOR()
        });

        IAccount.Command[] memory commands = new IAccount.Command[](1);
        commands[0] = IAccount.Command.PERMIT2_PERMIT;

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(permitSingle, signature);

        vm.startPrank(signer);
        account.execute(commands, inputs);
        vm.expectRevert();
        account.execute(commands, inputs);
    }
}
