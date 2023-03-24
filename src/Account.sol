// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {Auth} from "./utils/Auth.sol";
import {
    IAccount,
    IAddressResolver,
    IExchanger,
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
        (canExec,) = _validConditionalOrder(_conditionalOrderId);

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
    function execute(Command[] memory _commands, bytes[] memory _inputs)
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
            Command command = _commands[commandIndex];

            bytes memory input = _inputs[commandIndex];

            _dispatch(command, input);

            unchecked {
                commandIndex++;
            }
        }
    }

    function _dispatch(Command _command, bytes memory _inputs) internal {
        uint256 commandIndex = uint256(_command);

        if (commandIndex < 2) {
            if (!isOwner()) revert Unauthorized();

            if (_command == Command.ACCOUNT_MODIFY_MARGIN) {
                (int256 amount) = abi.decode(_inputs, (int256));
                _modifyAccountMargin({_amount: amount});
            } else {
                // ACCOUNT_WITHDRAW_ETH
                (uint256 amount) = abi.decode(_inputs, (uint256));
                _withdrawEth({_amount: amount});
            }
        } else {
            if (!isAuth()) revert Unauthorized();

            if (commandIndex < 4) {
                if (_command == Command.PERPS_V2_MODIFY_MARGIN) {
                    (address market, int256 amount) =
                        abi.decode(_inputs, (address, int256));
                    _perpsV2ModifyMargin({_market: market, _amount: amount});
                } else {
                    // PERPS_V2_WITHDRAW_ALL_MARGIN
                    address market = abi.decode(_inputs, (address));
                    _perpsV2WithdrawAllMargin({_market: market});
                }
            } else if (commandIndex < 8) {
                /// @custom:todo optimize fee calculation and impose it here

                if (_command == Command.PERPS_V2_SUBMIT_ATOMIC_ORDER) {
                    (address market, int256 sizeDelta, uint256 desiredFillPrice)
                    = abi.decode(_inputs, (address, int256, uint256));
                    _perpsV2SubmitAtomicOrder({
                        _market: market,
                        _sizeDelta: sizeDelta,
                        _desiredFillPrice: desiredFillPrice
                    });
                } else if (_command == Command.PERPS_V2_SUBMIT_DELAYED_ORDER) {
                    (
                        address market,
                        int256 sizeDelta,
                        uint256 desiredTimeDelta,
                        uint256 desiredFillPrice
                    ) = abi.decode(_inputs, (address, int256, uint256, uint256));
                    _perpsV2SubmitDelayedOrder({
                        _market: market,
                        _sizeDelta: sizeDelta,
                        _desiredTimeDelta: desiredTimeDelta,
                        _desiredFillPrice: desiredFillPrice
                    });
                } else if (
                    _command == Command.PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER
                ) {
                    (address market, int256 sizeDelta, uint256 desiredFillPrice)
                    = abi.decode(_inputs, (address, int256, uint256));
                    _perpsV2SubmitOffchainDelayedOrder({
                        _market: market,
                        _sizeDelta: sizeDelta,
                        _desiredFillPrice: desiredFillPrice
                    });
                } else {
                    // PERPS_V2_CLOSE_POSITION
                    (address market, uint256 desiredFillPrice) =
                        abi.decode(_inputs, (address, uint256));
                    _perpsV2ClosePosition({
                        _market: market,
                        _desiredFillPrice: desiredFillPrice
                    });
                }
            } else {
                // commandIndex >= 8
                if (_command == Command.PERPS_V2_CANCEL_DELAYED_ORDER) {
                    address market = abi.decode(_inputs, (address));
                    _perpsV2CancelDelayedOrder({_market: market});
                } else if (
                    _command == Command.PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER
                ) {
                    address market = abi.decode(_inputs, (address));
                    _perpsV2CancelOffchainDelayedOrder({_market: market});
                } else if (_command == Command.GELATO_PLACE_CONDITIONAL_ORDER) {
                    (
                        bytes32 marketKey,
                        int256 marginDelta,
                        int256 sizeDelta,
                        uint256 targetPrice,
                        ConditionalOrderTypes conditionalOrderType,
                        uint256 desiredFillPrice,
                        bool reduceOnly
                    ) = abi.decode(
                        _inputs,
                        (
                            bytes32,
                            int256,
                            int256,
                            uint256,
                            ConditionalOrderTypes,
                            uint256,
                            bool
                        )
                    );
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
                    uint256 orderId = abi.decode(_inputs, (uint256));
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
            bool success =
                MARGIN_ASSET.transferFrom(owner, address(this), _abs(_amount));
            if (!success) revert FailedMarginTransfer();

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
                bool success = MARGIN_ASSET.transfer(owner, _abs(_amount));
                if (!success) revert FailedMarginTransfer();

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
        _imposeFee({
            _fee: _calculateFee({
                _sizeDelta: _sizeDelta,
                _market: IPerpsV2MarketConsolidated(_market),
                _conditionalOrderFee: 0
            }),
            _marketKey: IPerpsV2MarketConsolidated(_market).marketKey(),
            _reason: FeeReason.TRADE_FEE
        });

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
        // establish Synthetix PerpsV2 Market position
        bytes32 marketKey = IPerpsV2MarketConsolidated(_market).marketKey();

        // close position (i.e. reduce size to zero)
        /// @dev this does not remove margin from market
        IPerpsV2MarketConsolidated(_market).closePositionWithTracking({
            desiredFillPrice: _desiredFillPrice,
            trackingCode: TRACKING_CODE
        });

        _imposeFee({
            _fee: _calculateFee({
                _sizeDelta: getPosition(marketKey).size,
                _market: IPerpsV2MarketConsolidated(_market),
                _conditionalOrderFee: 0
            }),
            _marketKey: marketKey,
            _reason: FeeReason.TRADE_FEE
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
        _imposeFee({
            _fee: _calculateFee({
                _sizeDelta: _sizeDelta,
                _market: IPerpsV2MarketConsolidated(_market),
                _conditionalOrderFee: 0
            }),
            _marketKey: IPerpsV2MarketConsolidated(_market).marketKey(),
            _reason: FeeReason.TRADE_FEE
        });

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
        _imposeFee({
            _fee: _calculateFee({
                _sizeDelta: _sizeDelta,
                _market: IPerpsV2MarketConsolidated(_market),
                _conditionalOrderFee: 0
            }),
            _marketKey: IPerpsV2MarketConsolidated(_market).marketKey(),
            _reason: FeeReason.TRADE_FEE
        });

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
        moduleData.modules[1] = IOps.Module.SINGLE_EXEC;

        moduleData.args[0] = abi.encode(
            address(this), abi.encodeCall(this.checker, conditionalOrderId)
        );
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
        (bool isValidConditionalOrder, uint256 fillPrice) =
            _validConditionalOrder(_conditionalOrderId);

        // Account.checker() will prevent this from being called if the conditional order is not valid
        /// @dev this is a safety/sanity check; never intended to fail
        assert(isValidConditionalOrder);

        ConditionalOrder memory conditionalOrder =
            getConditionalOrder(_conditionalOrderId);
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
                // delete conditional order from conditional orders
                delete conditionalOrders[_conditionalOrderId];

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

        // delete conditional order from conditional orders
        delete conditionalOrders[_conditionalOrderId];

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
    /// @return price that the order will be filled at (only valid if prev is true)
    function _validConditionalOrder(uint256 _conditionalOrderId)
        internal
        view
        returns (bool, uint256)
    {
        ConditionalOrder memory conditionalOrder =
            getConditionalOrder(_conditionalOrderId);

        // check if markets satisfy specific order type
        if (
            conditionalOrder.conditionalOrderType == ConditionalOrderTypes.LIMIT
        ) {
            return _validLimitOrder(conditionalOrder);
        } else if (
            conditionalOrder.conditionalOrderType == ConditionalOrderTypes.STOP
        ) {
            return _validStopOrder(conditionalOrder);
        } else {
            // unknown order type
            return (false, 0);
        }
    }

    /// @notice limit order logic condition checker
    /// @dev sizeDelta will never be zero due to check when submitting conditional order
    /// @param _conditionalOrder: struct for an active conditional order
    /// @return true if conditional order is valid by execution rules
    /// @return price that the conditional order will be submitted
    function _validLimitOrder(ConditionalOrder memory _conditionalOrder)
        internal
        view
        returns (bool, uint256)
    {
        /// @dev is marketKey is invalid, this will revert
        uint256 price =
            _sUSDRate(_getPerpsV2Market(_conditionalOrder.marketKey));

        if (_conditionalOrder.sizeDelta > 0) {
            // Long: increase position size (buy) once *below* target price
            // ex: open long position once price is below target
            return (price <= _conditionalOrder.targetPrice, price);
        } else {
            // Short: decrease position size (sell) once *above* target price
            // ex: open short position once price is above target
            return (price >= _conditionalOrder.targetPrice, price);
        }
    }

    /// @notice stop order logic condition checker
    /// @dev sizeDelta will never be zero due to check when submitting order
    /// @param _conditionalOrder: struct for an active conditional order
    /// @return true if conditional order is valid by execution rules
    /// @return price that the conditional order will be submitted
    function _validStopOrder(ConditionalOrder memory _conditionalOrder)
        internal
        view
        returns (bool, uint256)
    {
        /// @dev is marketKey is invalid, this will revert
        uint256 price =
            _sUSDRate(_getPerpsV2Market(_conditionalOrder.marketKey));

        if (_conditionalOrder.sizeDelta > 0) {
            // Long: increase position size (buy) once *above* target price
            // ex: unwind short position once price is above target (prevent further loss)
            return (price >= _conditionalOrder.targetPrice, price);
        } else {
            // Short: decrease position size (sell) once *below* target price
            // ex: unwind long position once price is below target (prevent further loss)
            return (price <= _conditionalOrder.targetPrice, price);
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
            bool success = MARGIN_ASSET.transfer(settings.treasury(), _fee);
            if (!success) revert FailedMarginTransfer();

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
