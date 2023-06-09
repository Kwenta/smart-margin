// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {Auth} from "./utils/Auth.sol";
import {
    IAccount,
    IEvents,
    IFactory,
    IFuturesMarketManager,
    IPerpsV2ExchangeRate,
    IPerpsV2MarketConsolidated,
    ISettings,
    ISystemStatus
} from "./interfaces/IAccount.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OpsReady, IOps} from "./utils/OpsReady.sol";

/// @title Kwenta Smart Margin Account Implementation
/// @author JaredBorders (jaredborders@pm.me), JChiaramonte7 (jeremy@bytecode.llc)
/// @notice flexible smart margin account enabling users to trade on-chain derivatives
contract Account is IAccount, Auth, OpsReady {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAccount
    bytes32 public constant VERSION = "2.0.2";

    /// @notice tracking code used when modifying positions
    bytes32 internal constant TRACKING_CODE = "KWENTA";

    /// @notice used to ensure the pyth provided price is sufficiently recent
    /// @dev price cannot be older than MAX_PRICE_LATENCY seconds
    uint256 internal constant MAX_PRICE_LATENCY = 120;

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice address of the Smart Margin Account Factory
    IFactory internal immutable FACTORY;

    /// @notice address of the contract used by all accounts for emitting events
    /// @dev can be immutable due to the fact the events contract is
    /// upgraded alongside the account implementation
    IEvents internal immutable EVENTS;

    /// @notice address of the Synthetix ProxyERC20sUSD contract used as the margin asset
    /// @dev can be immutable due to the fact the sUSD contract is a proxy address
    IERC20 internal immutable MARGIN_ASSET;

    /// @notice address of the Synthetix PerpsV2ExchangeRate
    /// @dev used internally by Synthetix Perps V2 contracts to retrieve asset exchange rates
    IPerpsV2ExchangeRate internal immutable PERPS_V2_EXCHANGE_RATE;

    /// @notice address of the Synthetix FuturesMarketManager
    /// @dev the manager keeps track of which markets exist, and is the main window between
    /// perpsV2 markets and the rest of the synthetix system. It accumulates the total debt
    /// over all markets, and issues and burns sUSD on each market's behalf
    IFuturesMarketManager internal immutable FUTURES_MARKET_MANAGER;

    /// @notice address of the Synthetix SystemStatus
    /// @dev the system status contract is used to check if the system is operational
    ISystemStatus internal immutable SYSTEM_STATUS;

    /// @notice address of contract used to store global settings
    ISettings internal immutable SETTINGS;

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAccount
    uint256 public committedMargin;

    /// @inheritdoc IAccount
    uint256 public conditionalOrderId;

    /// @notice track conditional orders by id
    mapping(uint256 id => ConditionalOrder order) internal conditionalOrders;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier isAccountExecutionEnabled() {
        _isAccountExecutionEnabled();

        _;
    }

    function _isAccountExecutionEnabled() internal view {
        if (!SETTINGS.accountExecutionEnabled()) {
            revert AccountExecutionDisabled();
        }
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice disable initializers on initial contract deployment
    /// @dev set owner of implementation to zero address
    /// @param _factory: address of the Smart Margin Account Factory
    /// @param _events: address of the contract used by all accounts for emitting events
    /// @param _marginAsset: address of the Synthetix ProxyERC20sUSD contract used as the margin asset
    /// @param _perpsV2ExchangeRate: address of the Synthetix PerpsV2ExchangeRate
    /// @param _futuresMarketManager: address of the Synthetix FuturesMarketManager
    /// @param _gelato: address of Gelato
    /// @param _ops: address of Ops
    /// @param _settings: address of contract used to store global settings
    constructor(
        address _factory,
        address _events,
        address _marginAsset,
        address _perpsV2ExchangeRate,
        address _futuresMarketManager,
        address _systemStatus,
        address _gelato,
        address _ops,
        address _settings
    ) Auth(address(0)) OpsReady(_gelato, _ops) {
        FACTORY = IFactory(_factory);
        EVENTS = IEvents(_events);
        MARGIN_ASSET = IERC20(_marginAsset);
        PERPS_V2_EXCHANGE_RATE = IPerpsV2ExchangeRate(_perpsV2ExchangeRate);
        FUTURES_MARKET_MANAGER = IFuturesMarketManager(_futuresMarketManager);
        SYSTEM_STATUS = ISystemStatus(_systemStatus);
        SETTINGS = ISettings(_settings);
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

    /// @inheritdoc IAccount
    function setInitialOwnership(address _owner) external override {
        if (msg.sender != address(FACTORY)) revert Unauthorized();
        owner = _owner;
        emit OwnershipTransferred(address(0), _owner);
    }

    /// @notice transfer ownership of account to new address
    /// @dev update factory's record of account ownership
    /// @param _newOwner: new account owner
    function transferOwnership(address _newOwner) public override {
        // will revert if msg.sender is *NOT* owner
        super.transferOwnership(_newOwner);

        // update the factory's record of owners and account addresses
        FACTORY.updateAccountOwnership({
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
        isAccountExecutionEnabled
    {
        uint256 numCommands = _commands.length;
        if (_inputs.length != numCommands) {
            revert LengthMismatch();
        }

        // loop through all given commands and execute them
        for (uint256 commandIndex = 0; commandIndex < numCommands;) {
            _dispatch(_commands[commandIndex], _inputs[commandIndex]);
            unchecked {
                ++commandIndex;
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
                // Command.ACCOUNT_MODIFY_MARGIN
                int256 amount;
                assembly {
                    amount := calldataload(_inputs.offset)
                }
                _modifyAccountMargin({_amount: amount});
            } else {
                // Command.ACCOUNT_WITHDRAW_ETH
                uint256 amount;
                assembly {
                    amount := calldataload(_inputs.offset)
                }
                _withdrawEth({_amount: amount});
            }
        } else {
            /// @dev only owner and delegate(s) can execute the following commands
            if (!isAuth()) revert Unauthorized();

            if (commandIndex < 4) {
                if (_command == Command.PERPS_V2_MODIFY_MARGIN) {
                    // Command.PERPS_V2_MODIFY_MARGIN
                    address market;
                    int256 amount;
                    assembly {
                        market := calldataload(_inputs.offset)
                        amount := calldataload(add(_inputs.offset, 0x20))
                    }
                    _perpsV2ModifyMargin({_market: market, _amount: amount});
                } else {
                    // Command.PERPS_V2_WITHDRAW_ALL_MARGIN
                    address market;
                    assembly {
                        market := calldataload(_inputs.offset)
                    }
                    _perpsV2WithdrawAllMargin({_market: market});
                }
            } else if (commandIndex < 6) {
                if (_command == Command.PERPS_V2_SUBMIT_ATOMIC_ORDER) {
                    // Command.PERPS_V2_SUBMIT_ATOMIC_ORDER
                    address market;
                    int256 sizeDelta;
                    uint256 desiredFillPrice;
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
                } else {
                    // Command.PERPS_V2_SUBMIT_DELAYED_ORDER
                    address market;
                    int256 sizeDelta;
                    uint256 desiredTimeDelta;
                    uint256 desiredFillPrice;
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
                }
            } else if (commandIndex < 8) {
                if (_command == Command.PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER)
                {
                    // Command.PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER
                    address market;
                    int256 sizeDelta;
                    uint256 desiredFillPrice;
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
                } else {
                    // Command.PERPS_V2_CLOSE_POSITION
                    address market;
                    uint256 desiredFillPrice;
                    assembly {
                        market := calldataload(_inputs.offset)
                        desiredFillPrice :=
                            calldataload(add(_inputs.offset, 0x20))
                    }
                    _perpsV2ClosePosition({
                        _market: market,
                        _desiredFillPrice: desiredFillPrice
                    });
                }
            } else if (commandIndex < 10) {
                if (_command == Command.PERPS_V2_SUBMIT_CLOSE_DELAYED_ORDER) {
                    // Command.PERPS_V2_SUBMIT_CLOSE_DELAYED_ORDER
                    address market;
                    uint256 desiredTimeDelta;
                    uint256 desiredFillPrice;
                    assembly {
                        market := calldataload(_inputs.offset)
                        desiredTimeDelta :=
                            calldataload(add(_inputs.offset, 0x20))
                        desiredFillPrice :=
                            calldataload(add(_inputs.offset, 0x40))
                    }
                    _perpsV2SubmitCloseDelayedOrder({
                        _market: market,
                        _desiredTimeDelta: desiredTimeDelta,
                        _desiredFillPrice: desiredFillPrice
                    });
                } else {
                    // Command.PERPS_V2_SUBMIT_CLOSE_OFFCHAIN_DELAYED_ORDER
                    address market;
                    uint256 desiredFillPrice;
                    assembly {
                        market := calldataload(_inputs.offset)
                        desiredFillPrice :=
                            calldataload(add(_inputs.offset, 0x20))
                    }
                    _perpsV2SubmitCloseOffchainDelayedOrder({
                        _market: market,
                        _desiredFillPrice: desiredFillPrice
                    });
                }
            } else if (commandIndex < 12) {
                if (_command == Command.PERPS_V2_CANCEL_DELAYED_ORDER) {
                    // Command.PERPS_V2_CANCEL_DELAYED_ORDER
                    address market;
                    assembly {
                        market := calldataload(_inputs.offset)
                    }
                    _perpsV2CancelDelayedOrder({_market: market});
                } else {
                    // Command.PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER
                    address market;
                    assembly {
                        market := calldataload(_inputs.offset)
                    }
                    _perpsV2CancelOffchainDelayedOrder({_market: market});
                }
            } else if (commandIndex < 14) {
                if (_command == Command.GELATO_PLACE_CONDITIONAL_ORDER) {
                    // Command.GELATO_PLACE_CONDITIONAL_ORDER
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
                } else {
                    // Command.GELATO_CANCEL_CONDITIONAL_ORDER
                    uint256 orderId;
                    assembly {
                        orderId := calldataload(_inputs.offset)
                    }
                    _cancelConditionalOrder({_conditionalOrderId: orderId});
                }
            } else {
                revert InvalidCommandType(commandIndex);
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

            EVENTS.emitEthWithdraw({user: msg.sender, amount: _amount});
        }
    }

    /// @notice deposit/withdraw margin to/from this smart margin account
    /// @param _amount: amount of margin to deposit/withdraw
    function _modifyAccountMargin(int256 _amount) internal {
        // if amount is positive, deposit
        if (_amount > 0) {
            /// @dev failed Synthetix asset transfer will revert and not return false if unsuccessful
            MARGIN_ASSET.transferFrom(owner, address(this), _abs(_amount));

            EVENTS.emitDeposit({user: msg.sender, amount: _abs(_amount)});
        } else if (_amount < 0) {
            // if amount is negative, withdraw
            _sufficientMargin(_amount);

            /// @dev failed Synthetix asset transfer will revert and not return false if unsuccessful
            MARGIN_ASSET.transfer(owner, _abs(_amount));

            EVENTS.emitWithdraw({user: msg.sender, amount: _abs(_amount)});
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
            _sufficientMargin(_amount);
        }
        IPerpsV2MarketConsolidated(_market).transferMargin(_amount);
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
    /// @dev atomic orders are executed immediately and incur a *significant* fee
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
    ) internal {
        if (_sizeDelta == 0) revert ZeroSizeDelta();

        // if more margin is desired on the position we must commit the margin
        if (_marginDelta > 0) {
            _sufficientMargin(_marginDelta);
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

        EVENTS.emitConditionalOrderPlaced({
            conditionalOrderId: conditionalOrderId,
            gelatoTaskId: taskId,
            marketKey: _marketKey,
            marginDelta: _marginDelta,
            sizeDelta: _sizeDelta,
            targetPrice: _targetPrice,
            conditionalOrderType: _conditionalOrderType,
            desiredFillPrice: _desiredFillPrice,
            reduceOnly: _reduceOnly
        });

        ++conditionalOrderId;
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
            modules: new IOps.Module[](1),
            args: new bytes[](1)
        });

        moduleData.modules[0] = IOps.Module.RESOLVER;
        moduleData.args[0] = abi.encode(
            address(this), abi.encodeCall(this.checker, conditionalOrderId)
        );
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

        EVENTS.emitConditionalOrderCancelled({
            conditionalOrderId: _conditionalOrderId,
            gelatoTaskId: conditionalOrder.gelatoTaskId,
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
        isAccountExecutionEnabled
        onlyOps
    {
        // store conditional order in memory
        ConditionalOrder memory conditionalOrder =
            getConditionalOrder(_conditionalOrderId);

        // remove conditional order from internal accounting
        delete conditionalOrders[_conditionalOrderId];

        // remove gelato task from their accounting
        /// @dev will revert if task id does not exist {Automate.cancelTask: Task not found}
        IOps(OPS).cancelTask({taskId: conditionalOrder.gelatoTaskId});

        // pay Gelato imposed fee for conditional order execution
        (uint256 fee, address feeToken) = IOps(OPS).getFeeDetails();
        _transfer({_amount: fee, _paymentToken: feeToken});

        // define Synthetix PerpsV2 market
        IPerpsV2MarketConsolidated market =
            _getPerpsV2Market(conditionalOrder.marketKey);

        /// @dev conditional order is valid given checker() returns true; define fill price
        (uint256 fillPrice, PriceOracleUsed priceOracle) = _sUSDRate(market);

        // if conditional order is reduce only, ensure position size is only reduced
        if (conditionalOrder.reduceOnly) {
            int256 currentSize = market.positions({account: address(this)}).size;

            // ensure position exists and incoming size delta is NOT the same sign
            /// @dev if incoming size delta is the same sign, then the conditional order is not reduce only
            if (
                currentSize == 0
                    || _isSameSign(currentSize, conditionalOrder.sizeDelta)
            ) {
                EVENTS.emitConditionalOrderCancelled({
                    conditionalOrderId: _conditionalOrderId,
                    gelatoTaskId: conditionalOrder.gelatoTaskId,
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

        // execute trade
        _perpsV2ModifyMargin({
            _market: address(market),
            _amount: conditionalOrder.marginDelta
        });
        _perpsV2SubmitOffchainDelayedOrder({
            _market: address(market),
            _sizeDelta: conditionalOrder.sizeDelta,
            _desiredFillPrice: conditionalOrder.desiredFillPrice
        });

        EVENTS.emitConditionalOrderFilled({
            conditionalOrderId: _conditionalOrderId,
            gelatoTaskId: conditionalOrder.gelatoTaskId,
            fillPrice: fillPrice,
            keeperFee: fee,
            priceOracle: priceOracle
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

        // return false if market is paused
        try SYSTEM_STATUS.requireFuturesMarketActive(conditionalOrder.marketKey)
        {} catch {
            return false;
        }

        /// @dev if marketKey is invalid, this will revert
        (uint256 price,) =
            _sUSDRate(_getPerpsV2Market(conditionalOrder.marketKey));

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
                            MARGIN UTILITIES
    //////////////////////////////////////////////////////////////*/

    /// @notice check that margin attempted to be moved/locked is within free margin bounds
    /// @param _marginOut: amount of margin to be moved/locked
    function _sufficientMargin(int256 _marginOut) internal view {
        if (_abs(_marginOut) > freeMargin()) {
            revert InsufficientFreeMargin(freeMargin(), _abs(_marginOut));
        }
    }

    /*//////////////////////////////////////////////////////////////
                            GETTER UTILITIES
    //////////////////////////////////////////////////////////////*/

    /// @notice fetch PerpsV2Market market defined by market key
    /// @param _marketKey: key for Synthetix PerpsV2 market
    /// @return IPerpsV2MarketConsolidated contract interface
    function _getPerpsV2Market(bytes32 _marketKey)
        internal
        view
        returns (IPerpsV2MarketConsolidated)
    {
        return IPerpsV2MarketConsolidated(
            FUTURES_MARKET_MANAGER.marketForKey(_marketKey)
        );
    }

    /// @notice get exchange rate of underlying market asset in terms of sUSD
    /// @param _market: Synthetix PerpsV2 Market
    /// @return price in sUSD
    function _sUSDRate(IPerpsV2MarketConsolidated _market)
        internal
        view
        returns (uint256, PriceOracleUsed)
    {
        /// @dev will revert if market is invalid
        bytes32 assetId = _market.baseAsset();

        /// @dev can revert if assetId is invalid OR there's no price for the given asset
        (uint256 price, uint256 publishTime) =
            PERPS_V2_EXCHANGE_RATE.resolveAndGetLatestPrice(assetId);

        // resolveAndGetLatestPrice is provide by pyth
        PriceOracleUsed priceOracle = PriceOracleUsed.PYTH;

        // if the price is stale, get the latest price from the market
        // (i.e. Chainlink provided price)
        if (publishTime < block.timestamp - MAX_PRICE_LATENCY) {
            // set price oracle used to Chainlink
            priceOracle = PriceOracleUsed.CHAINLINK;

            // fetch asset price and ensure it is valid
            bool invalid;
            (price, invalid) = _market.assetPrice();
            if (invalid) revert InvalidPrice();
        }

        /// @dev see IPerpsV2ExchangeRates to understand risks associated with this price
        return (price, priceOracle);
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
