// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {Auth} from "./utils/Auth.sol";
import {
    IAccount,
    IAddressResolver,
    IFactory,
    IFuturesMarketManager,
    IPerpsV2MarketConsolidated,
    ISettings,
    IEvents
} from "./interfaces/IAccount.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from
    "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {OpsReady, IOps} from "./utils/OpsReady.sol";

/// @title Kwenta Smart Margin Account Implementation
/// @author JaredBorders (jaredborders@pm.me), JChiaramonte7 (jeremy@bytecode.llc)
/// @notice flexible smart margin account enabling users to trade on-chain derivatives
contract Account is IAccount, OpsReady, Auth, Initializable {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAccount
    bytes32 public constant VERSION = "2.0.0";

    /// @notice tracking code used when modifying positions
    bytes32 private constant TRACKING_CODE = "KWENTA";

    /// @notice name for futures market manager
    bytes32 private constant FUTURES_MARKET_MANAGER = "FuturesMarketManager";

    /// @notice constant for sUSD currency key
    bytes32 private constant SUSD = "sUSD";

    /// @notice minimum ETH balance required to place a conditional order
    uint256 private constant MIN_ETH = 1 ether / 100;

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice address of the Synthetix ReadProxyAddressResolver
    IAddressResolver private immutable ADDRESS_RESOLVER;

    /// @notice address of the Synthetix ProxyERC20sUSD
    /// address used as the margin asset
    IERC20 private immutable MARGIN_ASSET;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAccount
    IFactory public factory;

    //// @inheritdoc IAccount
    IFuturesMarketManager public futuresMarketManager;

    /// @inheritdoc IAccount
    ISettings public settings;

    /// @inheritdoc IAccount
    IEvents public events;

    /// @inheritdoc IAccount
    uint256 public committedMargin;

    /// @inheritdoc IAccount
    uint256 public conditionalOrderId;

    /// @notice track conditional orders by id
    mapping(uint256 id => ConditionalOrder order) private conditionalOrders;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice helpful modifier to check non-zero values
    /// @param value: value to check if zero
    modifier notZero(uint256 value, bytes32 valueName) {
        if (value == 0) revert ValueCannotBeZero(valueName);

        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice disable initializers on initial contract deployment
    /// @dev set owner of implementation to zero address
    /// @param addressResolver: address of Synthetix ReadProxyAddressResolver
    /// @param marginAsset: address of Synthetix ProxyERC20sUSD
    /// @param gelato: address of Gelato
    /// @param ops: address of Ops
    constructor(
        address addressResolver,
        address marginAsset,
        address gelato,
        address ops
    ) Auth(address(0)) OpsReady(gelato, ops) {
        // recommended to use this to lock implementation contracts
        // that are designed to be called through proxies
        _disableInitializers();

        ADDRESS_RESOLVER = IAddressResolver(addressResolver);
        MARGIN_ASSET = IERC20(marginAsset);
    }

    /// @notice initialize contract (only once) and transfer ownership to specified address
    /// @dev ensure resolver and sUSD addresses are set to their proxies and not implementations
    /// @param _owner: account owner
    /// @param _settings: contract address for account settings
    /// @param _events: address of events contract for accounts
    /// @param _factory: contract address for account factory
    function initialize(
        address _owner,
        address _settings,
        address _events,
        address _factory
    ) external initializer {
        owner = _owner;
        emit OwnershipTransferred(address(0), _owner);

        settings = ISettings(_settings);
        events = IEvents(_events);
        factory = IFactory(_factory);

        // get address for futures market manager
        futuresMarketManager = IFuturesMarketManager(
            ADDRESS_RESOLVER.requireAndGetAddress(
                FUTURES_MARKET_MANAGER,
                "Account: Could not get Futures Market Manager"
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAccount
    function getDelayedOrder(bytes32 _marketKey)
        external
        view
        override
        returns (IPerpsV2MarketConsolidated.DelayedOrder memory order)
    {
        // fetch delayed order data from Synthetix
        order = _getPerpsV2Market(_marketKey).delayedOrders(address(this));
    }

    /// @inheritdoc IAccount
    function checker(uint256 _conditionalOrderId)
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        canExec = _validConditionalOrder(_conditionalOrderId);

        // calldata for execute func
        execPayload =
            abi.encodeCall(this.executeConditionalOrder, _conditionalOrderId);
    }

    /// @inheritdoc IAccount
    function freeMargin() public view override returns (uint256) {
        return MARGIN_ASSET.balanceOf(address(this)) - committedMargin;
    }

    /// @inheritdoc IAccount
    function getPosition(bytes32 _marketKey)
        public
        view
        override
        returns (IPerpsV2MarketConsolidated.Position memory position)
    {
        // fetch position data from Synthetix
        position = _getPerpsV2Market(_marketKey).positions(address(this));
    }

    /// @inheritdoc IAccount
    function getConditionalOrder(uint256 _conditionalOrderId)
        public
        view
        override
        returns (ConditionalOrder memory)
    {
        return conditionalOrders[_conditionalOrderId];
    }

    /*//////////////////////////////////////////////////////////////
                               OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    /// @notice transfer ownership of account to new address
    /// @dev update factory's record of account ownership
    /// @param _newOwner: new account owner
    function transferOwnership(address _newOwner) public override {
        // will revert if msg.sender is *NOT* owner
        super.transferOwnership(_newOwner);

        // update the factory's record of owners and account addresses
        factory.updateAccountOwnership({
            _account: address(this),
            _newOwner: _newOwner,
            _oldOwner: msg.sender // verified to be old owner
        });
    }

    /*//////////////////////////////////////////////////////////////
                               EXECUTION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAccount
    function execute(Command[] calldata _commands, bytes[] calldata _inputs)
        external
        payable
        override
    {
        uint256 numCommands = _commands.length;
        if (_inputs.length != numCommands) {
            revert LengthMismatch();
        }

        // loop through all given commands and execute them
        for (uint256 commandIndex = 0; commandIndex < numCommands;) {
            _dispatch(_commands[commandIndex], _inputs[commandIndex]);
            unchecked {
                commandIndex++;
            }
        }
    }

    /// @notice Decodes and executes the given command with the given inputs
    /// @param _command: The command type to execute
    /// @param _inputs: The inputs to execute the command with
    function _dispatch(Command _command, bytes calldata _inputs) internal {
        uint256 commandIndex = uint256(_command);

        if (commandIndex < 2) {
            /// @dev only owner can execute the following commands
            if (!isOwner()) revert Unauthorized();

            if (_command == Command.ACCOUNT_MODIFY_MARGIN) {
                int256 amount;
                assembly {
                    amount := calldataload(_inputs.offset)
                }
                _modifyAccountMargin({_amount: amount});
            } else {
                uint256 amount;
                assembly {
                    amount := calldataload(_inputs.offset)
                }
                _withdrawEth({_amount: amount});
            }
        } else {
            /// @dev both owner and delegates can execute the following commands
            if (!isAuth()) revert Unauthorized();

            if (commandIndex < 4) {
                address market;

                if (_command == Command.PERPS_V2_MODIFY_MARGIN) {
                    int256 amount;
                    assembly {
                        market := calldataload(_inputs.offset)
                        amount := calldataload(add(_inputs.offset, 0x20))
                    }
                    _perpsV2ModifyMargin({_market: market, _amount: amount});
                } else {
                    assembly {
                        market := calldataload(_inputs.offset)
                    }
                    _perpsV2WithdrawAllMargin({_market: market});
                }
            } else if (commandIndex < 10) {
                address market;
                int256 sizeDelta;
                uint256 desiredFillPrice;
                bytes32 marketKey;

                if (_command == Command.PERPS_V2_SUBMIT_ATOMIC_ORDER) {
                    assembly {
                        market := calldataload(_inputs.offset)
                        sizeDelta := calldataload(add(_inputs.offset, 0x20))
                        desiredFillPrice :=
                            calldataload(add(_inputs.offset, 0x40))
                    }
                    _perpsV2SubmitAtomicOrder({
                        _market: market,
                        _sizeDelta: sizeDelta,
                        _desiredFillPrice: desiredFillPrice
                    });
                } else if (_command == Command.PERPS_V2_SUBMIT_DELAYED_ORDER) {
                    uint256 desiredTimeDelta;
                    assembly {
                        market := calldataload(_inputs.offset)
                        sizeDelta := calldataload(add(_inputs.offset, 0x20))
                        desiredTimeDelta :=
                            calldataload(add(_inputs.offset, 0x40))
                        desiredFillPrice :=
                            calldataload(add(_inputs.offset, 0x60))
                    }
                    _perpsV2SubmitDelayedOrder({
                        _market: market,
                        _sizeDelta: sizeDelta,
                        _desiredTimeDelta: desiredTimeDelta,
                        _desiredFillPrice: desiredFillPrice
                    });
                } else if (
                    _command == Command.PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER
                ) {
                    assembly {
                        market := calldataload(_inputs.offset)
                        sizeDelta := calldataload(add(_inputs.offset, 0x20))
                        desiredFillPrice :=
                            calldataload(add(_inputs.offset, 0x40))
                    }
                    _perpsV2SubmitOffchainDelayedOrder({
                        _market: market,
                        _sizeDelta: sizeDelta,
                        _desiredFillPrice: desiredFillPrice
                    });
                } else if (_command == Command.PERPS_V2_CLOSE_POSITION) {
                    assembly {
                        market := calldataload(_inputs.offset)
                        desiredFillPrice :=
                            calldataload(add(_inputs.offset, 0x20))
                    }
                    /// @dev define current position size before closing so fee can be imposed later
                    marketKey = IPerpsV2MarketConsolidated(market).marketKey();
                    sizeDelta = getPosition(marketKey).size;
                    _perpsV2ClosePosition({
                        _market: market,
                        _desiredFillPrice: desiredFillPrice
                    });
                } else if (
                    _command == Command.PERPS_V2_SUBMIT_CLOSE_DELAYED_ORDER
                ) {
                    uint256 desiredTimeDelta;
                    assembly {
                        market := calldataload(_inputs.offset)
                        desiredTimeDelta :=
                            calldataload(add(_inputs.offset, 0x20))
                        desiredFillPrice :=
                            calldataload(add(_inputs.offset, 0x40))
                    }
                    /// @dev define current position size before closing so fee can be imposed later
                    marketKey = IPerpsV2MarketConsolidated(market).marketKey();
                    sizeDelta = getPosition(marketKey).size;
                    _perpsV2SubmitCloseDelayedOrder({
                        _market: market,
                        _desiredTimeDelta: desiredTimeDelta,
                        _desiredFillPrice: desiredFillPrice
                    });
                } else {
                    assembly {
                        market := calldataload(_inputs.offset)
                        desiredFillPrice :=
                            calldataload(add(_inputs.offset, 0x20))
                    }
                    /// @dev define current position size before closing so fee can be imposed later
                    marketKey = IPerpsV2MarketConsolidated(market).marketKey();
                    sizeDelta = getPosition(marketKey).size;
                    _perpsV2SubmitCloseOffchainDelayedOrder({
                        _market: market,
                        _desiredFillPrice: desiredFillPrice
                    });
                }

                /// @dev has marketKey already been defined? if so, no need to fetch it again
                marketKey = marketKey == bytes32(0)
                    ? IPerpsV2MarketConsolidated(market).marketKey()
                    : marketKey;

                // the above commands are all subject to a trade fee if delta size is non-zero
                if (sizeDelta != 0) {
                    _imposeFee({
                        _fee: _calculateFee({
                            _sizeDelta: sizeDelta,
                            _market: IPerpsV2MarketConsolidated(market),
                            _conditionalOrderFee: 0
                        }),
                        _marketKey: marketKey,
                        _reason: FeeReason.TRADE_FEE
                    });
                }
            } else {
                // commandIndex >= 10
                if (_command == Command.PERPS_V2_CANCEL_DELAYED_ORDER) {
                    address market;
                    assembly {
                        market := calldataload(_inputs.offset)
                    }
                    _perpsV2CancelDelayedOrder({_market: market});
                } else if (
                    _command == Command.PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER
                ) {
                    address market;
                    assembly {
                        market := calldataload(_inputs.offset)
                    }
                    _perpsV2CancelOffchainDelayedOrder({_market: market});
                } else if (_command == Command.GELATO_PLACE_CONDITIONAL_ORDER) {
                    bytes32 marketKey;
                    int256 marginDelta;
                    int256 sizeDelta;
                    uint256 targetPrice;
                    ConditionalOrderTypes conditionalOrderType;
                    uint256 desiredFillPrice;
                    bool reduceOnly;
                    assembly {
                        marketKey := calldataload(_inputs.offset)
                        marginDelta := calldataload(add(_inputs.offset, 0x20))
                        sizeDelta := calldataload(add(_inputs.offset, 0x40))
                        targetPrice := calldataload(add(_inputs.offset, 0x60))
                        conditionalOrderType :=
                            calldataload(add(_inputs.offset, 0x80))
                        desiredFillPrice :=
                            calldataload(add(_inputs.offset, 0xa0))
                        reduceOnly := calldataload(add(_inputs.offset, 0xc0))
                    }
                    _placeConditionalOrder({
                        _marketKey: marketKey,
                        _marginDelta: marginDelta,
                        _sizeDelta: sizeDelta,
                        _targetPrice: targetPrice,
                        _conditionalOrderType: conditionalOrderType,
                        _desiredFillPrice: desiredFillPrice,
                        _reduceOnly: reduceOnly
                    });
                } else if (_command == Command.GELATO_CANCEL_CONDITIONAL_ORDER)
                {
                    uint256 orderId;
                    assembly {
                        orderId := calldataload(_inputs.offset)
                    }
                    _cancelConditionalOrder({_conditionalOrderId: orderId});
                } else {
                    revert InvalidCommandType(commandIndex);
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        ACCOUNT DEPOSIT/WITHDRAW
    //////////////////////////////////////////////////////////////*/

    /// @notice allows ETH to be deposited directly into a margin account
    /// @notice ETH can be withdrawn
    receive() external payable {}

    /// @notice allow users to withdraw ETH deposited for keeper fees
    /// @param _amount: amount to withdraw
    function _withdrawEth(uint256 _amount) internal {
        if (_amount > 0) {
            (bool success,) = payable(owner).call{value: _amount}("");
            if (!success) revert EthWithdrawalFailed();

            events.emitEthWithdraw({
                user: msg.sender,
                account: address(this),
                amount: _amount
            });
        }
    }

    /// @notice deposit/withdraw margin to/from this smart margin account
    /// @param _amount: amount of margin to deposit/withdraw
    function _modifyAccountMargin(int256 _amount) internal {
        // if amount is positive, deposit
        if (_amount > 0) {
            /// @dev failed Synthetix asset transfer will revert and not return false if unsuccessful
            MARGIN_ASSET.transferFrom(owner, address(this), _abs(_amount));

            events.emitDeposit({
                user: msg.sender,
                account: address(this),
                amount: _abs(_amount)
            });
        } else if (_amount < 0) {
            // if amount is negative, withdraw
            if (_abs(_amount) > freeMargin()) {
                /// @dev make sure committed margin isn't withdrawn
                revert InsufficientFreeMargin(freeMargin(), _abs(_amount));
            } else {
                /// @dev failed Synthetix asset transfer will revert and not return false if unsuccessful
                MARGIN_ASSET.transfer(owner, _abs(_amount));

                events.emitWithdraw({
                    user: msg.sender,
                    account: address(this),
                    amount: _abs(_amount)
                });
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                          MODIFY MARKET MARGIN
    //////////////////////////////////////////////////////////////*/

    /// @notice deposit/withdraw margin to/from a Synthetix PerpsV2 Market
    /// @param _market: address of market
    /// @param _amount: amount of margin to deposit/withdraw
    function _perpsV2ModifyMargin(address _market, int256 _amount) internal {
        if (_amount > 0) {
            if (uint256(_amount) > freeMargin()) {
                revert InsufficientFreeMargin(freeMargin(), uint256(_amount));
            } else {
                IPerpsV2MarketConsolidated(_market).transferMargin(_amount);
            }
        } else {
            IPerpsV2MarketConsolidated(_market).transferMargin(_amount);
        }
    }

    /// @notice withdraw margin from market back to this account
    /// @dev this will *not* fail if market has zero margin
    function _perpsV2WithdrawAllMargin(address _market) internal {
        IPerpsV2MarketConsolidated(_market).withdrawAllMargin();
    }

    /*//////////////////////////////////////////////////////////////
                             ATOMIC ORDERS
    //////////////////////////////////////////////////////////////*/

    /// @notice submit an atomic order to a Synthetix PerpsV2 Market
    /// @dev trade fee may be imposed on smart margin account
    /// @param _market: address of market
    /// @param _sizeDelta: size delta of order
    /// @param _desiredFillPrice: desired fill price of order
    function _perpsV2SubmitAtomicOrder(
        address _market,
        int256 _sizeDelta,
        uint256 _desiredFillPrice
    ) internal {
        IPerpsV2MarketConsolidated(_market).modifyPositionWithTracking({
            sizeDelta: _sizeDelta,
            desiredFillPrice: _desiredFillPrice,
            trackingCode: TRACKING_CODE
        });
    }

    /// @notice close Synthetix PerpsV2 Market position via an atomic order
    /// @dev trade fee may be imposed on smart margin account
    /// @param _market: address of market
    /// @param _desiredFillPrice: desired fill price of order
    function _perpsV2ClosePosition(address _market, uint256 _desiredFillPrice)
        internal
    {
        // close position (i.e. reduce size to zero)
        /// @dev this does not remove margin from market
        IPerpsV2MarketConsolidated(_market).closePositionWithTracking({
            desiredFillPrice: _desiredFillPrice,
            trackingCode: TRACKING_CODE
        });
    }

    /*//////////////////////////////////////////////////////////////
                             DELAYED ORDERS
    //////////////////////////////////////////////////////////////*/

    /// @notice submit a delayed order to a Synthetix PerpsV2 Market
    /// @dev trade fee may be imposed on smart margin account
    /// @param _market: address of market
    /// @param _sizeDelta: size delta of order
    /// @param _desiredTimeDelta: desired time delta of order
    /// @param _desiredFillPrice: desired fill price of order
    function _perpsV2SubmitDelayedOrder(
        address _market,
        int256 _sizeDelta,
        uint256 _desiredTimeDelta,
        uint256 _desiredFillPrice
    ) internal {
        IPerpsV2MarketConsolidated(_market).submitDelayedOrderWithTracking({
            sizeDelta: _sizeDelta,
            desiredTimeDelta: _desiredTimeDelta,
            desiredFillPrice: _desiredFillPrice,
            trackingCode: TRACKING_CODE
        });
    }

    /// @notice cancel a *pending* delayed order from a Synthetix PerpsV2 Market
    /// @dev will revert if no previous delayed order
    function _perpsV2CancelDelayedOrder(address _market) internal {
        IPerpsV2MarketConsolidated(_market).cancelDelayedOrder(address(this));
    }

    /// @notice close Synthetix PerpsV2 Market position via a delayed order
    /// @dev trade fee may be imposed on smart margin account
    /// @param _market: address of market
    /// @param _desiredTimeDelta: desired time delta of order
    /// @param _desiredFillPrice: desired fill price of order
    function _perpsV2SubmitCloseDelayedOrder(
        address _market,
        uint256 _desiredTimeDelta,
        uint256 _desiredFillPrice
    ) internal {
        // close position (i.e. reduce size to zero)
        /// @dev this does not remove margin from market
        IPerpsV2MarketConsolidated(_market).submitCloseDelayedOrderWithTracking({
            desiredTimeDelta: _desiredTimeDelta,
            desiredFillPrice: _desiredFillPrice,
            trackingCode: TRACKING_CODE
        });
    }

    /*//////////////////////////////////////////////////////////////
                        DELAYED OFF-CHAIN ORDERS
    //////////////////////////////////////////////////////////////*/

    /// @notice submit an off-chain delayed order to a Synthetix PerpsV2 Market
    /// @dev trade fee may be imposed on smart margin account
    /// @param _market: address of market
    /// @param _sizeDelta: size delta of order
    /// @param _desiredFillPrice: desired fill price of order
    function _perpsV2SubmitOffchainDelayedOrder(
        address _market,
        int256 _sizeDelta,
        uint256 _desiredFillPrice
    ) internal {
        IPerpsV2MarketConsolidated(_market)
            .submitOffchainDelayedOrderWithTracking({
            sizeDelta: _sizeDelta,
            desiredFillPrice: _desiredFillPrice,
            trackingCode: TRACKING_CODE
        });
    }

    /// @notice cancel a *pending* off-chain delayed order from a Synthetix PerpsV2 Market
    /// @dev will revert if no previous offchain delayed order
    function _perpsV2CancelOffchainDelayedOrder(address _market) internal {
        IPerpsV2MarketConsolidated(_market).cancelOffchainDelayedOrder(
            address(this)
        );
    }

    /// @notice close Synthetix PerpsV2 Market position via an offchain delayed order
    /// @dev trade fee may be imposed on smart margin account
    /// @param _market: address of market
    /// @param _desiredFillPrice: desired fill price of order
    function _perpsV2SubmitCloseOffchainDelayedOrder(
        address _market,
        uint256 _desiredFillPrice
    ) internal {
        // close position (i.e. reduce size to zero)
        /// @dev this does not remove margin from market
        IPerpsV2MarketConsolidated(_market)
            .submitCloseOffchainDelayedOrderWithTracking({
            desiredFillPrice: _desiredFillPrice,
            trackingCode: TRACKING_CODE
        });
    }

    /*//////////////////////////////////////////////////////////////
                           CONDITIONAL ORDERS
    //////////////////////////////////////////////////////////////*/

    /// @notice register a conditional order internally and with gelato
    /// @dev restricts _sizeDelta to be non-zero otherwise no need for conditional order
    /// @param _marketKey: Synthetix futures market id/key
    /// @param _marginDelta: amount of margin (in sUSD) to deposit or withdraw
    /// @param _sizeDelta: denominated in market currency (i.e. ETH, BTC, etc), size of position
    /// @param _targetPrice: expected conditional order price
    /// @param _conditionalOrderType: expected conditional order type enum where 0 = LIMIT, 1 = STOP, etc..
    /// @param _desiredFillPrice: desired price to fill Synthetix PerpsV2 order at execution time
    /// @param _reduceOnly: if true, only allows position's absolute size to decrease
    function _placeConditionalOrder(
        bytes32 _marketKey,
        int256 _marginDelta,
        int256 _sizeDelta,
        uint256 _targetPrice,
        ConditionalOrderTypes _conditionalOrderType,
        uint256 _desiredFillPrice,
        bool _reduceOnly
    ) internal notZero(_abs(_sizeDelta), "_sizeDelta") {
        // if more margin is desired on the position we must commit the margin
        if (_marginDelta > 0) {
            // ensure margin doesn't exceed max
            if (uint256(_marginDelta) > freeMargin()) {
                revert InsufficientFreeMargin(
                    freeMargin(), uint256(_marginDelta)
                );
            }
            committedMargin += _abs(_marginDelta);
        }

        // create and submit Gelato task for this conditional order
        bytes32 taskId = _createGelatoTask();

        // internally store the conditional order
        conditionalOrders[conditionalOrderId] = ConditionalOrder({
            marketKey: _marketKey,
            marginDelta: _marginDelta,
            sizeDelta: _sizeDelta,
            targetPrice: _targetPrice,
            gelatoTaskId: taskId,
            conditionalOrderType: _conditionalOrderType,
            desiredFillPrice: _desiredFillPrice,
            reduceOnly: _reduceOnly
        });

        events.emitConditionalOrderPlaced({
            account: address(this),
            conditionalOrderId: conditionalOrderId,
            marketKey: _marketKey,
            marginDelta: _marginDelta,
            sizeDelta: _sizeDelta,
            targetPrice: _targetPrice,
            conditionalOrderType: _conditionalOrderType,
            desiredFillPrice: _desiredFillPrice,
            reduceOnly: _reduceOnly
        });

        conditionalOrderId++;
    }

    /// @notice create a new Gelato task for a conditional order
    /// @return taskId of the new Gelato task
    function _createGelatoTask() internal returns (bytes32 taskId) {
        IOps.ModuleData memory moduleData = _createGelatoModuleData();

        taskId = IOps(OPS).createTask({
            execAddress: address(this),
            execData: abi.encodeCall(
                this.executeConditionalOrder, conditionalOrderId
                ),
            moduleData: moduleData,
            feeToken: ETH
        });
    }

    /// @notice create the Gelato ModuleData for a conditional order
    /// @dev see IOps for details on the task creation and the ModuleData struct
    function _createGelatoModuleData()
        internal
        view
        returns (IOps.ModuleData memory moduleData)
    {
        moduleData = IOps.ModuleData({
            modules: new IOps.Module[](2),
            args: new bytes[](2)
        });

        moduleData.modules[0] = IOps.Module.RESOLVER;
        moduleData.args[0] = abi.encode(
            address(this), abi.encodeCall(this.checker, conditionalOrderId)
        );

        moduleData.modules[1] = IOps.Module.SINGLE_EXEC;
        // moduleData.args[1] is empty for single exec thus no need to encode
    }

    /// @notice cancel a gelato queued conditional order
    /// @param _conditionalOrderId: key for an active conditional order
    function _cancelConditionalOrder(uint256 _conditionalOrderId) internal {
        ConditionalOrder memory conditionalOrder =
            getConditionalOrder(_conditionalOrderId);

        // if margin was committed, free it
        if (conditionalOrder.marginDelta > 0) {
            committedMargin -= _abs(conditionalOrder.marginDelta);
        }

        // cancel gelato task
        /// @dev will revert if task id does not exist {Automate.cancelTask: Task not found}
        IOps(OPS).cancelTask({taskId: conditionalOrder.gelatoTaskId});

        // delete order from conditional orders
        delete conditionalOrders[_conditionalOrderId];

        events.emitConditionalOrderCancelled({
            account: address(this),
            conditionalOrderId: _conditionalOrderId,
            reason: ConditionalOrderCancelledReason
                .CONDITIONAL_ORDER_CANCELLED_BY_USER
        });
    }

    /*//////////////////////////////////////////////////////////////
                   GELATO CONDITIONAL ORDER HANDLING
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAccount
    function executeConditionalOrder(uint256 _conditionalOrderId)
        external
        override
        onlyOps
    {
        ConditionalOrder memory conditionalOrder =
            getConditionalOrder(_conditionalOrderId);

        // delete conditional order from conditional orders
        delete conditionalOrders[_conditionalOrderId];

        /// @dev conditional order is valid given checker() returns true; define fill price
        uint256 fillPrice =
            _sUSDRate(_getPerpsV2Market(conditionalOrder.marketKey));

        // define market address
        address market = address(_getPerpsV2Market(conditionalOrder.marketKey));

        // if conditional order is reduce only, ensure position size is only reduced
        if (conditionalOrder.reduceOnly) {
            int256 currentSize = _getPerpsV2Market(conditionalOrder.marketKey)
                .positions({account: address(this)}).size;

            // ensure position exists and incoming size delta is NOT the same sign
            /// @dev if incoming size delta is the same sign, then the conditional order is not reduce only
            if (
                currentSize == 0
                    || _isSameSign(currentSize, conditionalOrder.sizeDelta)
            ) {
                events.emitConditionalOrderCancelled({
                    account: address(this),
                    conditionalOrderId: _conditionalOrderId,
                    reason: ConditionalOrderCancelledReason
                        .CONDITIONAL_ORDER_CANCELLED_NOT_REDUCE_ONLY
                });

                return;
            }

            // ensure incoming size delta is not larger than current position size
            /// @dev reduce only conditional orders can only reduce position size (i.e. approach size of zero) and
            /// cannot cross that boundary (i.e. short -> long or long -> short)
            if (_abs(conditionalOrder.sizeDelta) > _abs(currentSize)) {
                // bound conditional order size delta to current position size
                conditionalOrder.sizeDelta = -currentSize;
            }
        }

        // if margin was committed, free it
        if (conditionalOrder.marginDelta > 0) {
            committedMargin -= _abs(conditionalOrder.marginDelta);
        }

        // calculate conditional order fee imposed by Kwenta
        uint256 conditionalOrderFee = conditionalOrder.conditionalOrderType
            == ConditionalOrderTypes.LIMIT
            ? settings.limitOrderFee()
            : settings.stopOrderFee();

        // execute trade
        _perpsV2ModifyMargin({
            _market: market,
            _amount: conditionalOrder.marginDelta
        });
        _perpsV2SubmitOffchainDelayedOrder({
            _market: market,
            _sizeDelta: conditionalOrder.sizeDelta,
            _desiredFillPrice: conditionalOrder.desiredFillPrice
        });

        // pay Gelato imposed fee for conditional order execution
        (uint256 fee, address feeToken) = IOps(OPS).getFeeDetails();
        _transfer({_amount: fee, _paymentToken: feeToken});

        // pay Kwenta imposed fee for both the trade and the conditional order execution
        uint256 kwentaImposedFee = _calculateFee({
            _sizeDelta: conditionalOrder.sizeDelta,
            _market: IPerpsV2MarketConsolidated(market),
            _conditionalOrderFee: conditionalOrderFee
        });
        _imposeFee({
            _fee: kwentaImposedFee,
            _marketKey: conditionalOrder.marketKey,
            _reason: FeeReason.TRADE_AND_CONDITIONAL_ORDER_FEE
        });

        events.emitConditionalOrderFilled({
            account: address(this),
            conditionalOrderId: _conditionalOrderId,
            fillPrice: fillPrice,
            keeperFee: fee,
            kwentaFee: kwentaImposedFee
        });
    }

    /// @notice order logic condition checker
    /// @dev this is where order type logic checks are handled
    /// @param _conditionalOrderId: key for an active order
    /// @return true if conditional order is valid by execution rules
    function _validConditionalOrder(uint256 _conditionalOrderId)
        internal
        view
        returns (bool)
    {
        ConditionalOrder memory conditionalOrder =
            getConditionalOrder(_conditionalOrderId);

        /// @dev is marketKey is invalid, this will revert
        uint256 price = _sUSDRate(_getPerpsV2Market(conditionalOrder.marketKey));

        // check if markets satisfy specific order type
        if (
            conditionalOrder.conditionalOrderType == ConditionalOrderTypes.LIMIT
        ) {
            return _validLimitOrder(conditionalOrder, price);
        } else if (
            conditionalOrder.conditionalOrderType == ConditionalOrderTypes.STOP
        ) {
            return _validStopOrder(conditionalOrder, price);
        }

        // unknown order type
        return false;
    }

    /// @notice limit order logic condition checker
    /// @dev sizeDelta will never be zero due to check when submitting conditional order
    /// @param _conditionalOrder: struct for an active conditional order
    /// @param _price: current price of market asset
    /// @return true if conditional order is valid by execution rules
    function _validLimitOrder(
        ConditionalOrder memory _conditionalOrder,
        uint256 _price
    ) internal pure returns (bool) {
        if (_conditionalOrder.sizeDelta > 0) {
            // Long: increase position size (buy) once *below* target price
            // ex: open long position once price is below target
            return _price <= _conditionalOrder.targetPrice;
        } else {
            // Short: decrease position size (sell) once *above* target price
            // ex: open short position once price is above target
            return _price >= _conditionalOrder.targetPrice;
        }
    }

    /// @notice stop order logic condition checker
    /// @dev sizeDelta will never be zero due to check when submitting order
    /// @param _conditionalOrder: struct for an active conditional order
    /// @param _price: current price of market asset
    /// @return true if conditional order is valid by execution rules
    function _validStopOrder(
        ConditionalOrder memory _conditionalOrder,
        uint256 _price
    ) internal pure returns (bool) {
        if (_conditionalOrder.sizeDelta > 0) {
            // Long: increase position size (buy) once *above* target price
            // ex: unwind short position once price is above target (prevent further loss)
            return _price >= _conditionalOrder.targetPrice;
        } else {
            // Short: decrease position size (sell) once *below* target price
            // ex: unwind long position once price is below target (prevent further loss)
            return _price <= _conditionalOrder.targetPrice;
        }
    }

    /*//////////////////////////////////////////////////////////////
                             FEE UTILITIES
    //////////////////////////////////////////////////////////////*/

    /// @notice calculate fee based on both size and given market
    /// @param _sizeDelta: size delta of given trade
    /// @param _market: Synthetix PerpsV2 Market
    /// @param _conditionalOrderFee: additional fee charged for conditional orders
    /// @return fee to be imposed based on size delta
    function _calculateFee(
        int256 _sizeDelta,
        IPerpsV2MarketConsolidated _market,
        uint256 _conditionalOrderFee
    ) internal view returns (uint256 fee) {
        fee = (_abs(_sizeDelta) * (settings.tradeFee() + _conditionalOrderFee))
            / settings.MAX_BPS();

        /// @notice fee is currently measured in the underlying base asset of the market
        /// @dev fee will be measured in sUSD, thus exchange rate is needed
        fee = (_sUSDRate(_market) * fee) / 1e18;
    }

    /// @notice impose fee on account
    /// @param _fee: fee to impose
    /// @param _marketKey: key for Synthetix PerpsV2 market
    /// @param _reason: reason for fee
    function _imposeFee(uint256 _fee, bytes32 _marketKey, FeeReason _reason)
        internal
    {
        /// @dev send fee to Kwenta's treasury
        if (_fee > freeMargin()) {
            // fee canot be greater than available margin
            revert CannotPayFee();
        } else {
            // attempt to transfer margin asset from user to Kwenta's treasury
            /// @dev failed Synthetix asset transfer will revert and not return false if unsuccessful
            MARGIN_ASSET.transfer(settings.treasury(), _fee);

            events.emitFeeImposed({
                account: address(this),
                amount: _fee,
                marketKey: _marketKey,
                reason: bytes32(uint256(_reason))
            });
        }
    }

    /*//////////////////////////////////////////////////////////////
                            GETTER UTILITIES
    //////////////////////////////////////////////////////////////*/

    /// @notice fetch PerpsV2Market market defined by market key
    /// @param _marketKey: key for Synthetix PerpsV2 market
    /// @return IPerpsV2Market contract interface
    function _getPerpsV2Market(bytes32 _marketKey)
        internal
        view
        returns (IPerpsV2MarketConsolidated)
    {
        return IPerpsV2MarketConsolidated(
            futuresMarketManager.marketForKey(_marketKey)
        );
    }

    /// @notice get exchange rate of underlying market asset in terms of sUSD
    /// @param _market: Synthetix PerpsV2 Market
    /// @return price in sUSD
    function _sUSDRate(IPerpsV2MarketConsolidated _market)
        internal
        view
        returns (uint256)
    {
        (uint256 price, bool invalid) = _market.assetPrice();
        if (invalid) {
            revert InvalidPrice();
        }
        return price;
    }

    /*//////////////////////////////////////////////////////////////
                             MATH UTILITIES
    //////////////////////////////////////////////////////////////*/

    /// @notice get absolute value of the input, returned as an unsigned number.
    /// @param x: signed number
    /// @return z uint256 absolute value of x
    function _abs(int256 x) internal pure returns (uint256 z) {
        assembly {
            let mask := sub(0, shr(255, x))
            z := xor(mask, add(mask, x))
        }
    }

    /// @notice determines if input numbers have the same sign
    /// @dev asserts that both numbers are not zero
    /// @param x: signed number
    /// @param y: signed number
    /// @return true if same sign, false otherwise
    function _isSameSign(int256 x, int256 y) internal pure returns (bool) {
        assert(x != 0 && y != 0);
        return (x ^ y) >= 0;
    }
}
