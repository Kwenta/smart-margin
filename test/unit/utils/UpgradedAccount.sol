// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.18;

import {
    IAccount,
    IAddressResolver,
    IExchanger,
    IFactory,
    IFuturesMarketManager,
    IPerpsV2MarketConsolidated,
    ISettings,
    IEvents
} from "../../../src/interfaces/IAccount.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {OpsReady, IOps} from "../../../src/utils/OpsReady.sol";
import {Owned} from "@solmate/auth/Owned.sol";

/// @title Kwenta Smart Margin Account Implementation
/// @author JaredBorders (jaredborders@pm.me), JChiaramonte7 (jeremy@bytecode.llc)
/// @notice flexible smart margin account enabling users to trade on-chain derivatives
contract UpgradedAccount is IAccount, OpsReady, Owned, Initializable {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAccount
    bytes32 public constant VERSION = "6.9.0";

    /// @notice address of the Synthetix ReadProxyAddressResolver
    IAddressResolver private constant ADDRESS_RESOLVER =
        IAddressResolver(0x1Cb059b7e74fD21665968C908806143E744D5F30); // Optimism
    // IAddressResolver private constant ADDRESS_RESOLVER =
    //     IAddressResolver(0x9Fc84992dF5496797784374B810E04238728743d); // Optimism Goerli

    /// @notice address of the Synthetix ProxyERC20sUSD address used as the margin asset
    IERC20 private constant MARGIN_ASSET = IERC20(0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9); // Optimism
    // IERC20 private constant MARGIN_ASSET = IERC20(0xeBaEAAD9236615542844adC5c149F86C36aD1136); // Optimism Goerli

    /// @notice tracking code used when modifying positions
    bytes32 private constant TRACKING_CODE = "KWENTA";

    /// @notice name for futures market manager
    bytes32 private constant FUTURES_MARKET_MANAGER = "FuturesMarketManager";

    /// @notice constant for sUSD currency key
    bytes32 private constant SUSD = "sUSD";

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
    constructor() Owned(address(0)) {
        // recommended to use this to lock implementation contracts
        // that are designed to be called through proxies
        _disableInitializers();
    }

    /// @notice allows ETH to be deposited directly into a margin account
    /// @notice ETH can be withdrawn
    receive() external payable onlyOwner {}

    /// @notice initialize contract (only once) and transfer ownership to specified address
    /// @dev ensure resolver and sUSD addresses are set to their proxies and not implementations
    /// @param _owner: account owner
    /// @param _settings: contract address for account settings
    /// @param _events: address of events contract for accounts
    /// @param _factory: contract address for account factory
    function initialize(address _owner, address _settings, address _events, address _factory)
        external
        initializer
    {
        owner = _owner;
        emit OwnershipTransferred(address(0), _owner);

        settings = ISettings(_settings);
        events = IEvents(_events);
        factory = IFactory(_factory);

        // get address for futures market manager
        futuresMarketManager = IFuturesMarketManager(
            ADDRESS_RESOLVER.requireAndGetAddress(
                FUTURES_MARKET_MANAGER, "Account: Could not get Futures Market Manager"
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
        order = getPerpsV2Market(_marketKey).delayedOrders(address(this));
    }

    /// @inheritdoc IAccount
    function checker(uint256 _conditionalOrderId)
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        (canExec,) = validConditionalOrder(_conditionalOrderId);
        // calldata for execute func
        execPayload =
            abi.encodeWithSelector(this.executeConditionalOrder.selector, _conditionalOrderId);
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
        position = getPerpsV2Market(_marketKey).positions(address(this));
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
                           ACCOUNT OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    /// @notice transfer ownership of this account to a new address
    /// @dev will update factory's mapping record of owner to account
    /// @param _newOwner: address to transfer ownership to
    function transferOwnership(address _newOwner) public override onlyOwner {
        factory.updateAccountOwner({_oldOwner: owner, _newOwner: _newOwner});
        super.transferOwnership(_newOwner);
    }

    /*//////////////////////////////////////////////////////////////
                        ACCOUNT DEPOSIT/WITHDRAW
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAccount
    function deposit(uint256 _amount) external override onlyOwner notZero(_amount, "_amount") {
        // attempt to transfer margin asset from user into this account
        bool success = MARGIN_ASSET.transferFrom(owner, address(this), _amount);
        if (!success) revert FailedMarginTransfer();

        events.emitDeposit({user: msg.sender, account: address(this), amount: _amount});
    }

    /// @inheritdoc IAccount
    function withdraw(uint256 _amount) external override notZero(_amount, "_amount") onlyOwner {
        // make sure committed margin isn't withdrawn
        if (_amount > freeMargin()) {
            revert InsufficientFreeMargin(freeMargin(), _amount);
        }

        // attempt to transfer margin asset from this account to the user
        bool success = MARGIN_ASSET.transfer(owner, _amount);
        if (!success) revert FailedMarginTransfer();

        events.emitWithdraw({user: msg.sender, account: address(this), amount: _amount});
    }

    /// @inheritdoc IAccount
    function withdrawEth(uint256 _amount) external override onlyOwner notZero(_amount, "_amount") {
        (bool success,) = payable(owner).call{value: _amount}("");
        if (!success) revert EthWithdrawalFailed();

        events.emitEthWithdraw({user: msg.sender, account: address(this), amount: _amount});
    }

    /*//////////////////////////////////////////////////////////////
                               EXECUTION
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAccount
    function execute(Command[] memory commands, bytes[] memory inputs)
        public
        payable
        override
        onlyOwner
    {
        _execute({commands: commands, inputs: inputs});
    }

    function _execute(Command[] memory commands, bytes[] memory inputs) internal {
        uint256 numCommands = commands.length;
        if (inputs.length != numCommands) revert LengthMismatch();

        // loop through all given commands and execute them
        for (uint256 commandIndex = 0; commandIndex < numCommands;) {
            Command command = commands[commandIndex];

            bytes memory input = inputs[commandIndex];

            _dispatch(command, input);

            unchecked {
                commandIndex++;
            }
        }
    }

    function _dispatch(Command command, bytes memory inputs) internal {
        // @TODO optimize via grouping commands: i.e. if uint(command) > 5, etc.

        // if-else logic to dispatch commands
        if (command == Command.PERPS_V2_MODIFY_MARGIN) {
            (address market, int256 amount) = abi.decode(inputs, (address, int256));
            _perpsV2ModifyMargin({_market: market, _amount: amount});
        } else if (command == Command.PERPS_V2_WITHDRAW_ALL_MARGIN) {
            address market = abi.decode(inputs, (address));
            _perpsV2WithdrawAllMargin({_market: market});
        } else if (command == Command.PERPS_V2_SUBMIT_ATOMIC_ORDER) {
            (address market, int256 sizeDelta, uint256 priceImpactDelta) =
                abi.decode(inputs, (address, int256, uint256));
            _perpsV2SubmitAtomicOrder({
                _market: market,
                _sizeDelta: sizeDelta,
                _priceImpactDelta: priceImpactDelta
            });
        } else if (command == Command.PERPS_V2_SUBMIT_DELAYED_ORDER) {
            (address market, int256 sizeDelta, uint256 priceImpactDelta, uint256 desiredTimeDelta) =
                abi.decode(inputs, (address, int256, uint256, uint256));
            _perpsV2SubmitDelayedOrder({
                _market: market,
                _sizeDelta: sizeDelta,
                _priceImpactDelta: priceImpactDelta,
                _desiredTimeDelta: desiredTimeDelta
            });
        } else if (command == Command.PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER) {
            (address market, int256 sizeDelta, uint256 priceImpactDelta) =
                abi.decode(inputs, (address, int256, uint256));
            _perpsV2SubmitOffchainDelayedOrder({
                _market: market,
                _sizeDelta: sizeDelta,
                _priceImpactDelta: priceImpactDelta
            });
        } else if (command == Command.PERPS_V2_CANCEL_DELAYED_ORDER) {
            address market = abi.decode(inputs, (address));
            _perpsV2CancelDelayedOrder({_market: market});
        } else if (command == Command.PERPS_V2_CANCEL_OFFCHAIN_DELAYED_ORDER) {
            address market = abi.decode(inputs, (address));
            _perpsV2CancelOffchainDelayedOrder({_market: market});
        } else if (command == Command.PERPS_V2_CLOSE_POSITION) {
            (address market, uint256 priceImpactDelta) = abi.decode(inputs, (address, uint256));
            _perpsV2ClosePosition({_market: market, _priceImpactDelta: priceImpactDelta});
        } else {
            // placeholder area for further commands
            revert InvalidCommandType(uint256(command));
        }
    }

    /*//////////////////////////////////////////////////////////////
                                COMMANDS
    //////////////////////////////////////////////////////////////*/

    function _perpsV2ModifyMargin(address _market, int256 _amount) internal {
        if (_amount > 0) {
            if (uint256(_amount) > freeMargin()) {
                revert InsufficientFreeMargin(freeMargin(), uint256(_amount));
            } else {
                IPerpsV2MarketConsolidated(_market).transferMargin(_amount);
            }
        } else if (_amount < 0) {
            IPerpsV2MarketConsolidated(_market).transferMargin(_amount);
        } else {
            // _amount == 0
            revert InvalidMarginDelta();
        }
    }

    function _perpsV2WithdrawAllMargin(address _market) internal {
        // withdraw margin from market back to this account
        /// @dev this will not fail if market has zero margin; it will just waste gas
        IPerpsV2MarketConsolidated(_market).withdrawAllMargin();
    }

    function _perpsV2SubmitAtomicOrder(
        address _market,
        int256 _sizeDelta,
        uint256 _priceImpactDelta
    ) internal {
        // impose fee (comes from account's margin)
        _imposeFee(
            _calculateTradeFee({
                _sizeDelta: _sizeDelta,
                _market: IPerpsV2MarketConsolidated(_market),
                _conditionalOrderFee: 0
            })
        );

        IPerpsV2MarketConsolidated(_market).modifyPositionWithTracking({
            sizeDelta: _sizeDelta,
            priceImpactDelta: _priceImpactDelta,
            trackingCode: TRACKING_CODE
        });
    }

    function _perpsV2SubmitDelayedOrder(
        address _market,
        int256 _sizeDelta,
        uint256 _priceImpactDelta,
        uint256 _desiredTimeDelta
    ) internal {
        // impose fee (comes from account's margin)
        _imposeFee(
            _calculateTradeFee({
                _sizeDelta: _sizeDelta,
                _market: IPerpsV2MarketConsolidated(_market),
                _conditionalOrderFee: 0
            })
        );

        IPerpsV2MarketConsolidated(_market).submitDelayedOrderWithTracking({
            sizeDelta: _sizeDelta,
            priceImpactDelta: _priceImpactDelta,
            desiredTimeDelta: _desiredTimeDelta,
            trackingCode: TRACKING_CODE
        });
    }

    function _perpsV2SubmitOffchainDelayedOrder(
        address _market,
        int256 _sizeDelta,
        uint256 _priceImpactDelta
    ) internal {
        // impose fee (comes from account's margin)
        _imposeFee(
            _calculateTradeFee({
                _sizeDelta: _sizeDelta,
                _market: IPerpsV2MarketConsolidated(_market),
                _conditionalOrderFee: 0
            })
        );

        IPerpsV2MarketConsolidated(_market).submitOffchainDelayedOrderWithTracking({
            sizeDelta: _sizeDelta,
            priceImpactDelta: _priceImpactDelta,
            trackingCode: TRACKING_CODE
        });
    }

    function _perpsV2CancelDelayedOrder(address _market) internal {
        /// @dev will revert if no previous delayed order
        IPerpsV2MarketConsolidated(_market).cancelDelayedOrder(address(this));
    }

    function _perpsV2CancelOffchainDelayedOrder(address _market) internal {
        /// @dev will revert if no previous offchain delayed order
        IPerpsV2MarketConsolidated(_market).cancelOffchainDelayedOrder(address(this));
    }

    function _perpsV2ClosePosition(address _market, uint256 _priceImpactDelta) internal {
        // establish position
        bytes32 marketKey = IPerpsV2MarketConsolidated(_market).marketKey();

        // close position (i.e. reduce size to zero)
        /// @dev this does not remove margin from market
        IPerpsV2MarketConsolidated(_market).closePositionWithTracking(
            _priceImpactDelta, TRACKING_CODE
        );

        // impose fee (comes from account's margin)
        /// @dev this fee is based on the position's size delta
        _imposeFee(
            _calculateTradeFee({
                _sizeDelta: getPosition(marketKey).size,
                _market: IPerpsV2MarketConsolidated(_market),
                _conditionalOrderFee: 0
            })
        );
    }

    /*//////////////////////////////////////////////////////////////
                           CONDITIONAL ORDERS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAccount
    function placeConditionalOrder(
        bytes32 _marketKey,
        int256 _marginDelta,
        int256 _sizeDelta,
        uint256 _targetPrice,
        ConditionalOrderTypes _conditionalOrderType,
        uint128 _priceImpactDelta,
        bool _reduceOnly
    )
        external
        payable
        override
        notZero(_abs(_sizeDelta), "_sizeDelta")
        onlyOwner
        returns (uint256)
    {
        // ensure account has enough eth to eventually pay for the conditional order
        if (address(this).balance < 1 ether / 100) {
            revert InsufficientEthBalance(address(this).balance, 1 ether / 100);
        }

        // if more margin is desired on the position we must commit the margin
        if (_marginDelta > 0) {
            // ensure margin doesn't exceed max
            if (uint256(_marginDelta) > freeMargin()) {
                revert InsufficientFreeMargin(freeMargin(), uint256(_marginDelta));
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
            priceImpactDelta: _priceImpactDelta,
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
            priceImpactDelta: _priceImpactDelta,
            reduceOnly: _reduceOnly
        });

        return conditionalOrderId++;
    }

    /// @inheritdoc IAccount
    function cancelConditionalOrder(uint256 _conditionalOrderId) external override onlyOwner {
        ConditionalOrder memory conditionalOrder = getConditionalOrder(_conditionalOrderId);

        // if margin was committed, free it
        if (conditionalOrder.marginDelta > 0) {
            committedMargin -= _abs(conditionalOrder.marginDelta);
        }

        // cancel gelato task
        IOps(OPS).cancelTask({taskId: conditionalOrder.gelatoTaskId});

        // delete order from conditional orders
        delete conditionalOrders[_conditionalOrderId];

        events.emitConditionalOrderCancelled({
            account: address(this),
            conditionalOrderId: _conditionalOrderId,
            reason: ConditionalOrderCancelledReason.CONDITIONAL_ORDER_CANCELLED_BY_USER
        });
    }

    /// @inheritdoc IAccount
    function executeConditionalOrder(uint256 _conditionalOrderId) external override onlyOps {
        (bool isValidConditionalOrder, uint256 fillPrice) =
            validConditionalOrder(_conditionalOrderId);

        if (!isValidConditionalOrder) {
            revert ConditionalOrderInvalid();
        }

        ConditionalOrder memory conditionalOrder = getConditionalOrder(_conditionalOrderId);
        address market = address(getPerpsV2Market(conditionalOrder.marketKey));

        // if conditional order is reduce only, ensure position size is only reduced
        if (conditionalOrder.reduceOnly) {
            int256 currentSize = getPerpsV2Market(conditionalOrder.marketKey).positions({
                account: address(this)
            }).size;

            // ensure position exists and incoming size delta is NOT the same sign
            /// @dev if incoming size delta is the same sign, then the conditional order is not reduce only
            if (currentSize == 0 || _isSameSign(currentSize, conditionalOrder.sizeDelta)) {
                // remove task from gelato's side
                /// @dev optimization done for gelato
                IOps(OPS).cancelTask(conditionalOrder.gelatoTaskId);

                // delete conditional order from conditional orders
                delete conditionalOrders[_conditionalOrderId];

                events.emitConditionalOrderCancelled({
                    account: address(this),
                    conditionalOrderId: _conditionalOrderId,
                    reason: ConditionalOrderCancelledReason.CONDITIONAL_ORDER_CANCELLED_NOT_REDUCE_ONLY
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

        // init commands and inputs
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        bytes[] memory inputs = new bytes[](2);

        /// @dev deconstruct conditional order to compose necessary commands and inputs
        if (conditionalOrder.marginDelta != 0) {
            commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
            inputs[0] = abi.encode(market, conditionalOrder.marginDelta);
            commands[1] = IAccount.Command.PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER;
            inputs[1] =
                abi.encode(market, conditionalOrder.sizeDelta, conditionalOrder.priceImpactDelta);
        } else {
            commands = new IAccount.Command[](1);
            inputs = new bytes[](1);
            commands[1] = IAccount.Command.PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER;
            inputs[1] =
                abi.encode(market, conditionalOrder.sizeDelta, conditionalOrder.priceImpactDelta);
        }

        // remove task from gelato's side
        /// @dev optimization done for gelato
        IOps(OPS).cancelTask(conditionalOrder.gelatoTaskId);

        // delete conditional order from conditional orders
        delete conditionalOrders[_conditionalOrderId];

        uint256 conditionalOrderFee = conditionalOrder.conditionalOrderType
            == ConditionalOrderTypes.LIMIT ? settings.limitOrderFee() : settings.stopOrderFee();

        // execute trade
        _execute({commands: commands, inputs: inputs});

        // pay fee to Gelato for order execution
        (uint256 fee, address feeToken) = IOps(OPS).getFeeDetails();
        _transfer({_amount: fee, _paymentToken: feeToken});

        // impose conditional order fee
        _imposeFee(
            _calculateTradeFee({
                _sizeDelta: conditionalOrder.sizeDelta,
                _market: IPerpsV2MarketConsolidated(market),
                _conditionalOrderFee: conditionalOrderFee
            })
        );

        events.emitConditionalOrderFilled({
            account: address(this),
            conditionalOrderId: _conditionalOrderId,
            fillPrice: fillPrice,
            keeperFee: fee
        });
    }

    /// @notice create a new Gelato task for a conditional order
    /// @return taskId of the new Gelato task
    function _createGelatoTask() internal returns (bytes32 taskId) {
        // establish required data for creating a Gelato task
        IOps.Module[] memory modules = new IOps.Module[](1);
        modules[0] = IOps.Module.RESOLVER;
        bytes[] memory args = new bytes[](1);
        args[0] = abi.encodeWithSelector(this.checker.selector, conditionalOrderId);
        IOps.ModuleData memory moduleData = IOps.ModuleData({modules: modules, args: args});

        // submit new task to Gelato and store the task id
        taskId = IOps(OPS).createTask({
            execAddress: address(this),
            execData: abi.encodeWithSelector(this.executeConditionalOrder.selector, conditionalOrderId),
            moduleData: moduleData,
            feeToken: ETH
        });
    }

    /// @notice order logic condition checker
    /// @dev this is where order type logic checks are handled
    /// @param _conditionalOrderId: key for an active order
    /// @return true if conditional order is valid by execution rules
    /// @return price that the order will be filled at (only valid if prev is true)
    function validConditionalOrder(uint256 _conditionalOrderId)
        internal
        view
        returns (bool, uint256)
    {
        ConditionalOrder memory conditionalOrder = getConditionalOrder(_conditionalOrderId);

        // check if markets satisfy specific order type
        if (conditionalOrder.conditionalOrderType == ConditionalOrderTypes.LIMIT) {
            return validLimitOrder(conditionalOrder);
        } else if (conditionalOrder.conditionalOrderType == ConditionalOrderTypes.STOP) {
            return validStopOrder(conditionalOrder);
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
    function validLimitOrder(ConditionalOrder memory _conditionalOrder)
        internal
        view
        returns (bool, uint256)
    {
        /// @dev is marketKey is invalid, this will revert
        uint256 price = sUSDRate(getPerpsV2Market(_conditionalOrder.marketKey));

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
    function validStopOrder(ConditionalOrder memory _conditionalOrder)
        internal
        view
        returns (bool, uint256)
    {
        /// @dev is marketKey is invalid, this will revert
        uint256 price = sUSDRate(getPerpsV2Market(_conditionalOrder.marketKey));

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
    function _calculateTradeFee(
        int256 _sizeDelta,
        IPerpsV2MarketConsolidated _market,
        uint256 _conditionalOrderFee
    ) internal view returns (uint256 fee) {
        fee = (_abs(_sizeDelta) * (settings.tradeFee() + _conditionalOrderFee)) / settings.MAX_BPS();

        /// @notice fee is currently measured in the underlying base asset of the market
        /// @dev fee will be measured in sUSD, thus exchange rate is needed
        fee = (sUSDRate(_market) * fee) / 1e18;
    }

    /// @notice impose fee on account
    /// @param _fee: fee to impose
    function _imposeFee(uint256 _fee) internal {
        /// @dev send fee to Kwenta's treasury
        if (_fee > freeMargin()) {
            // fee canot be greater than available margin
            revert CannotPayFee();
        } else {
            // attempt to transfer margin asset from user to Kwenta's treasury
            bool success = MARGIN_ASSET.transfer(settings.treasury(), _fee);
            if (!success) revert FailedMarginTransfer();

            events.emitFeeImposed({account: address(this), amount: _fee});
        }
    }

    /*//////////////////////////////////////////////////////////////
                            GETTER UTILITIES
    //////////////////////////////////////////////////////////////*/

    /// @notice fetch PerpsV2Market market defined by market key
    /// @param _marketKey: key for Synthetix PerpsV2 market
    /// @return IPerpsV2Market contract interface
    function getPerpsV2Market(bytes32 _marketKey)
        internal
        view
        returns (IPerpsV2MarketConsolidated)
    {
        return IPerpsV2MarketConsolidated(futuresMarketManager.marketForKey(_marketKey));
    }

    /// @notice get exchange rate of underlying market asset in terms of sUSD
    /// @param _market: Synthetix PerpsV2 Market
    /// @return price in sUSD
    function sUSDRate(IPerpsV2MarketConsolidated _market) internal view returns (uint256) {
        (uint256 price, bool invalid) = _market.assetPrice();
        if (invalid) {
            revert InvalidPrice();
        }
        return price;
    }

    /// @notice exchangeRates() fetches current ExchangeRates contract
    function exchanger() internal view returns (IExchanger) {
        return IExchanger(
            ADDRESS_RESOLVER.requireAndGetAddress("Exchanger", "Account: Could not get Exchanger")
        );
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
