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
import {SigUtils} from "../utils/SigUtils.sol";
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

contract PermitBehaviorTest is Test, ConsolidatedEvents {
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

    // signature utils
    SigUtils private sigUtils;
    uint256 internal ownerPrivateKey;
    uint256 internal spenderPrivateKey;
    address internal owner;
    address internal spender;

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

        ownerPrivateKey = 0xA11CE;
        spenderPrivateKey = 0xB0B;

        owner = vm.addr(ownerPrivateKey);
        spender = vm.addr(spenderPrivateKey);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Permit() public {}

    function test_Permit_UniswapV3Swap() public {
        // whitelist DAI
        settings.setTokenWhitelistStatus(address(dai), true);

        // call approve() on an ERC20 to grant an infinite allowance to the canonical Permit2 contract
        dai.approve(UNISWAP_PERMIT2, type(uint256).max);

        // Calling permit() on the canonical Permit2 contract removes the need to call approve() on an ERC20
        // PERMIT2.approve(
        //     address(dai), address(account), type(uint160).max, type(uint48).max
        // );

        // define _permit() parameters
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

        bytes32 digest = sigUtils.getTypedPermit2DataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        bytes memory signature;

        // define command(s)
        IAccount.Command[] memory commands = new IAccount.Command[](2);

        commands[0] = IAccount.Command.PERMIT2_PERMIT;
        commands[1] = IAccount.Command.UNISWAP_V3_SWAP;

        // define input(s)
        bytes[] memory inputs = new bytes[](2);

        inputs[0] = abi.encode(permitSingle, signature);

        uint256 amountIn = AMOUNT / 2;
        uint256 amountOutMin = 1;
        bytes memory path = bytes.concat(
            bytes20(address(dai)), LOW_FEE_TIER, bytes20(address(sUSD))
        );
        inputs[1] = abi.encode(amountIn, amountOutMin, path);

        uint256 preBalance = sUSD.balanceOf(address(account));
        account.execute(commands, inputs);
        uint256 postBalance = sUSD.balanceOf(address(account));

        assertGt(postBalance, preBalance);
    }

    function test_Permit_UniswapV3Swap_Replay() public {
        /// @custom:todo test when same nonce is used twice
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
        sUSD.approve(address(account), amount);
        modifyAccountMargin({amount: int256(amount)});
    }

    function getTypedPermit2DataHash(IPermit2.PermitSingle memory permitSingle)
        private
        returns (bytes32)
    {
        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address token,uint160 amount,uint48 expiration,uint48 nonce,address spender,uint256 sigDeadline)"
        );

        // create the hash of a permit
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                permitSingle.details.token,
                permitSingle.details.amount,
                permitSingle.details.expiration,
                permitSingle.details.nonce,
                permitSingle.spender,
                permitSingle.sigDeadline
            )
        );

        // computes the hash of the fully encoded EIP-712 message for 
        // the domain, which can be used to recover the signer
        bytes32 typedDataHash = keccak256(
            abi.encodePacked("\x19\x01", PERMIT2.DOMAIN_SEPARATOR(), structHash)
        );

        return typedDataHash;
    }
}
