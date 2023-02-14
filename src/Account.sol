// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {IAccount, IAddressResolver, IERC20, IExchanger, IFactory, IFuturesMarketManager, IPerpsV2MarketConsolidated, ISettings, IEvents} from "./interfaces/IAccount.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {OpsReady, IOps} from "./utils/OpsReady.sol";
import {Owned} from "@solmate/auth/Owned.sol";

/// @title Kwenta Smart Margin Account Implementation
/// @author JaredBorders (jaredborders@pm.me), JChiaramonte7 (jeremy@bytecode.llc)
/// @notice flexible smart margin account enabling users to trade on-chain derivatives
contract Account is IAccount, OpsReady, Owned, Initializable {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAccount
    bytes32 public constant VERSION = "2.0.0";

    /// @inheritdoc IAccount
    IAddressResolver public constant ADDRESS_RESOLVER =
        IAddressResolver(0x1Cb059b7e74fD21665968C908806143E744D5F30);

    /// @inheritdoc IAccount
    IERC20 public constant MARGIN_ASSET =
        IERC20(0x8c6f28f2F1A3C87F0f938b96d27520d9751ec8d9);

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
    uint256 public orderId;

    /// @notice order id mapped to order struct
    mapping(uint256 => Order) private orders;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice helpful modifier to check non-zero values
    /// @param value: value to check if zero
    modifier notZero(uint256 value, bytes32 valueName) {
        /// @notice value cannot be zero
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
        order = getPerpsV2Market(_marketKey).delayedOrders(address(this));
    }

    /// @inheritdoc IAccount
    function checker(uint256 _orderId)
        external
        view
        override
        returns (bool canExec, bytes memory execPayload)
    {
        (canExec, ) = validOrder(_orderId);
        // calldata for execute func
        execPayload = abi.encodeWithSelector(
            this.executeOrder.selector,
            _orderId
        );
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
    function calculateTradeFee(
        int256 _sizeDelta,
        IPerpsV2MarketConsolidated _market,
        uint256 _conditionalOrderFee
    ) public view override returns (uint256 fee) {
        fee =
            (_abs(_sizeDelta) * (settings.tradeFee() + _conditionalOrderFee)) /
            settings.MAX_BPS();

        /// @notice fee is currently measured in the underlying base asset of the market
        /// @dev fee will be measured in sUSD, thus exchange rate is needed
        fee = (sUSDRate(_market) * fee) / 1e18;
    }

    /// @inheritdoc IAccount
    function getOrder(uint256 _orderId)
        public
        view
        override
        returns (Order memory)
    {
        return orders[_orderId];
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
    function deposit(uint256 _amount)
        public
        override
        onlyOwner
        notZero(_amount, "_amount")
    {
        // attempt to transfer margin asset from user into this account
        bool success = MARGIN_ASSET.transferFrom(owner, address(this), _amount);
        if (!success) revert FailedMarginTransfer();

        events.emitDeposit({account: address(this), amountDeposited: _amount});
    }

    /// @inheritdoc IAccount
    function withdraw(uint256 _amount)
        external
        override
        notZero(_amount, "_amount")
        onlyOwner
    {
        // make sure committed margin isn't withdrawn
        if (_amount > freeMargin()) {
            revert InsufficientFreeMargin(freeMargin(), _amount);
        }

        // attempt to transfer margin asset from this account to the user
        bool success = MARGIN_ASSET.transfer(owner, _amount);
        if (!success) revert FailedMarginTransfer();

        events.emitWithdraw({account: address(this), amountWithdrawn: _amount});
    }

    /// @inheritdoc IAccount
    function withdrawEth(uint256 _amount)
        external
        override
        onlyOwner
        notZero(_amount, "_amount")
    {
        (bool success, ) = payable(owner).call{value: _amount}("");
        if (!success) revert EthWithdrawalFailed();

        events.emitEthWithdraw({
            account: address(this),
            amountWithdrawn: _amount
        });
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
        uint256 numCommands = commands.length;
        if (inputs.length != numCommands) revert LengthMismatch();

        // loop through all given commands and execute them
        for (uint256 commandIndex = 0; commandIndex < numCommands; ) {
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
            (address market, int256 amount) = abi.decode(
                inputs,
                (address, int256)
            );
            _perpsV2ModifyMargin({_market: market, _amount: amount});
        } else if (command == Command.PERPS_V2_WITHDRAW_ALL_MARGIN) {
            address market = abi.decode(inputs, (address));
            _perpsV2WithdrawAllMargin({_market: market});
        } else if (command == Command.PERPS_V2_SUBMIT_ATOMIC_ORDER) {
            (address market, int256 sizeDelta, uint256 priceImpactDelta) = abi
                .decode(inputs, (address, int256, uint256));
            _perpsV2SubmitAtomicOrder({
                _market: market,
                _sizeDelta: sizeDelta,
                _priceImpactDelta: priceImpactDelta
            });
        } else if (command == Command.PERPS_V2_SUBMIT_DELAYED_ORDER) {
            (
                address market,
                int256 sizeDelta,
                uint256 priceImpactDelta,
                uint256 desiredTimeDelta
            ) = abi.decode(inputs, (address, int256, uint256, uint256));
            _perpsV2SubmitDelayedOrder({
                _market: market,
                _sizeDelta: sizeDelta,
                _priceImpactDelta: priceImpactDelta,
                _desiredTimeDelta: desiredTimeDelta
            });
        } else if (command == Command.PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER) {
            (address market, int256 sizeDelta, uint256 priceImpactDelta) = abi
                .decode(inputs, (address, int256, uint256));
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
            (address market, uint256 priceImpactDelta) = abi.decode(
                inputs,
                (address, uint256)
            );
            _perpsV2ClosePosition({
                _market: market,
                _priceImpactDelta: priceImpactDelta
            });
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
            calculateTradeFee({
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
            calculateTradeFee({
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
            calculateTradeFee({
                _sizeDelta: _sizeDelta,
                _market: IPerpsV2MarketConsolidated(_market),
                _conditionalOrderFee: 0
            })
        );

        IPerpsV2MarketConsolidated(_market)
            .submitOffchainDelayedOrderWithTracking({
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
        IPerpsV2MarketConsolidated(_market).cancelOffchainDelayedOrder(
            address(this)
        );
    }

    function _perpsV2ClosePosition(address _market, uint256 _priceImpactDelta)
        internal
    {
        // establish position
        bytes32 marketKey = IPerpsV2MarketConsolidated(_market).marketKey();

        // close position (i.e. reduce size to zero)
        /// @dev this does not remove margin from market
        IPerpsV2MarketConsolidated(_market).closePositionWithTracking(
            _priceImpactDelta,
            TRACKING_CODE
        );

        // impose fee (comes from account's margin)
        /// @dev this fee is based on the position's size delta
        _imposeFee(
            calculateTradeFee({
                _sizeDelta: getPosition(marketKey).size,
                _market: IPerpsV2MarketConsolidated(_market),
                _conditionalOrderFee: 0
            })
        );
    }

    /*//////////////////////////////////////////////////////////////
                            ADVANCED ORDERS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IAccount
    function validOrder(uint256 _orderId)
        public
        view
        override
        returns (bool, uint256)
    {
        Order memory order = getOrder(_orderId);

        // check dynamic fee is not too high
        if (order.maxDynamicFee != 0) {
            (uint256 dynamicFee, bool tooVolatile) = exchanger()
                .dynamicFeeRateForExchange(
                    SUSD,
                    getPerpsV2Market(order.marketKey).baseAsset()
                );
            if (tooVolatile || dynamicFee > order.maxDynamicFee) {
                return (false, 0);
            }
        }

        // check if markets satisfy specific order type
        if (order.orderType == OrderTypes.LIMIT) {
            return validLimitOrder(order);
        } else if (order.orderType == OrderTypes.STOP) {
            return validStopOrder(order);
        } else {
            // unknown order type
            return (false, 0);
        }
    }

    /// @notice limit order logic condition checker
    /// @dev sizeDelta will never be zero due to check when submitting order
    /// @param order: struct for an active order
    /// @return true if order is valid by execution rules
    /// @return price that the order will be submitted
    function validLimitOrder(Order memory order)
        internal
        view
        returns (bool, uint256)
    {
        uint256 price = sUSDRate(getPerpsV2Market(order.marketKey));

        if (order.sizeDelta > 0) {
            // Long: increase position size (buy) once *below* target price
            // ex: open long position once price is below target
            return (price <= order.targetPrice, price);
        } else {
            // Short: decrease position size (sell) once *above* target price
            // ex: open short position once price is above target
            return (price >= order.targetPrice, price);
        }
    }

    /// @notice stop order logic condition checker
    /// @dev sizeDelta will never be zero due to check when submitting order
    /// @param order: struct for an active order
    /// @return true if order is valid by execution rules
    /// @return price that the order will be submitted
    function validStopOrder(Order memory order)
        internal
        view
        returns (bool, uint256)
    {
        uint256 price = sUSDRate(getPerpsV2Market(order.marketKey));

        if (order.sizeDelta > 0) {
            // Long: increase position size (buy) once *above* target price
            // ex: unwind short position once price is above target (prevent further loss)
            return (price >= order.targetPrice, price);
        } else {
            // Short: decrease position size (sell) once *below* target price
            // ex: unwind long position once price is below target (prevent further loss)
            return (price <= order.targetPrice, price);
        }
    }

    /// @inheritdoc IAccount
    function placeOrder(
        bytes32 _marketKey,
        int256 _marginDelta,
        int256 _sizeDelta,
        uint256 _targetPrice,
        OrderTypes _orderType,
        uint128 _priceImpactDelta
    ) external payable override returns (uint256) {
        return
            _placeOrder({
                _marketKey: _marketKey,
                _marginDelta: _marginDelta,
                _sizeDelta: _sizeDelta,
                _targetPrice: _targetPrice,
                _orderType: _orderType,
                _priceImpactDelta: _priceImpactDelta,
                _maxDynamicFee: 0
            });
    }

    /// @inheritdoc IAccount
    function placeOrderWithFeeCap(
        bytes32 _marketKey,
        int256 _marginDelta,
        int256 _sizeDelta,
        uint256 _targetPrice,
        OrderTypes _orderType,
        uint128 _priceImpactDelta,
        uint256 _maxDynamicFee
    ) external payable override returns (uint256) {
        return
            _placeOrder({
                _marketKey: _marketKey,
                _marginDelta: _marginDelta,
                _sizeDelta: _sizeDelta,
                _targetPrice: _targetPrice,
                _orderType: _orderType,
                _priceImpactDelta: _priceImpactDelta,
                _maxDynamicFee: _maxDynamicFee
            });
    }

    function _placeOrder(
        bytes32 _marketKey,
        int256 _marginDelta,
        int256 _sizeDelta,
        uint256 _targetPrice,
        OrderTypes _orderType,
        uint128 _priceImpactDelta,
        uint256 _maxDynamicFee
    )
        internal
        notZero(_abs(_sizeDelta), "_sizeDelta")
        onlyOwner
        returns (uint256)
    {
        // ensure account has enough eth to eventually pay for the order
        if (address(this).balance < 1 ether / 100) {
            revert InsufficientEthBalance(address(this).balance, 1 ether / 100);
        }

        // if more margin is desired on the position we must commit the margin
        if (_marginDelta > 0) {
            // ensure margin doesn't exceed max
            if (uint256(_marginDelta) > freeMargin()) {
                revert InsufficientFreeMargin(
                    freeMargin(),
                    uint256(_marginDelta)
                );
            }
            committedMargin += _abs(_marginDelta);
        }

        // generate an id associated with a task that can be executed by gelato
        bytes32 taskId = IOps(OPS).createTaskNoPrepayment({
            _execAddress: address(this),
            _execSelector: this.executeOrder.selector,
            _resolverAddress: address(this),
            _resolverData: abi.encodeWithSelector(
                this.checker.selector,
                orderId
            ),
            _feeToken: ETH
        });

        orders[orderId] = Order({
            marketKey: _marketKey,
            marginDelta: _marginDelta,
            sizeDelta: _sizeDelta,
            targetPrice: _targetPrice,
            gelatoTaskId: taskId,
            orderType: _orderType,
            priceImpactDelta: _priceImpactDelta,
            maxDynamicFee: _maxDynamicFee
        });

        events.emitOrderPlaced({
            account: address(this),
            orderId: orderId,
            marketKey: _marketKey,
            marginDelta: _marginDelta,
            sizeDelta: _sizeDelta,
            targetPrice: _targetPrice,
            orderType: _orderType,
            priceImpactDelta: _priceImpactDelta,
            maxDynamicFee: _maxDynamicFee
        });

        return orderId++;
    }

    /// @inheritdoc IAccount
    function cancelOrder(uint256 _orderId) external override onlyOwner {
        Order memory order = getOrder(_orderId);

        // if margin was committed, free it
        if (order.marginDelta > 0) {
            committedMargin -= _abs(order.marginDelta);
        }

        // cancel gelato task
        IOps(OPS).cancelTask({_taskId: order.gelatoTaskId});

        // delete order from orders
        delete orders[_orderId];

        events.emitOrderCancelled({account: address(this), orderId: _orderId});
    }

    /// @inheritdoc IAccount
    function executeOrder(uint256 _orderId) external override onlyOps {
        // @TODO consider removing onlyOps modifier

        (bool isValidOrder, uint256 fillPrice) = validOrder(_orderId);

        if (!isValidOrder) {
            revert OrderInvalid();
        }

        Order memory order = getOrder(_orderId);
        address market = address(getPerpsV2Market(order.marketKey));

        // if margin was committed, free it
        if (order.marginDelta > 0) {
            committedMargin -= _abs(order.marginDelta);
        }

        // init commands and inputs
        IAccount.Command[] memory commands = new IAccount.Command[](2);
        bytes[] memory inputs = new bytes[](2);

        /// @dev deconstruct order to compose necessary commands and inputs
        if (order.marginDelta != 0) {
            commands[0] = IAccount.Command.PERPS_V2_MODIFY_MARGIN;
            inputs[0] = abi.encode(market, order.marginDelta);
            commands[1] = IAccount
                .Command
                .PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER;
            inputs[1] = abi.encode(
                market,
                order.sizeDelta,
                order.priceImpactDelta
            );
        } else {
            commands = new IAccount.Command[](1);
            inputs = new bytes[](1);
            commands[1] = IAccount
                .Command
                .PERPS_V2_SUBMIT_OFFCHAIN_DELAYED_ORDER;
            inputs[1] = abi.encode(
                market,
                order.sizeDelta,
                order.priceImpactDelta
            );
        }

        // remove task from gelato's side
        /// @dev optimization done for gelato
        IOps(OPS).cancelTask(order.gelatoTaskId);

        // delete order from orders
        delete orders[_orderId];

        uint256 conditionalOrderFee = order.orderType == OrderTypes.LIMIT
            ? settings.limitOrderFee()
            : settings.stopOrderFee();

        // execute trade
        execute({commands: commands, inputs: inputs});

        // pay fee to Gelato for order execution
        (uint256 fee, address feeToken) = IOps(OPS).getFeeDetails();
        _transfer({_amount: fee, _paymentToken: feeToken});

        // impose conditional order fee
        _imposeFee(
            calculateTradeFee({
                _sizeDelta: order.sizeDelta,
                _market: IPerpsV2MarketConsolidated(market),
                _conditionalOrderFee: conditionalOrderFee
            })
        );

        events.emitOrderFilled({
            account: address(this),
            orderId: _orderId,
            fillPrice: fillPrice,
            keeperFee: fee
        });
    }

    /*//////////////////////////////////////////////////////////////
                             FEE UTILITIES
    //////////////////////////////////////////////////////////////*/
    
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
        return
            IPerpsV2MarketConsolidated(
                futuresMarketManager.marketForKey(_marketKey)
            );
    }

    /// @notice get exchange rate of underlying market asset in terms of sUSD
    /// @param _market: Synthetix PerpsV2 Market
    /// @return price in sUSD
    function sUSDRate(IPerpsV2MarketConsolidated _market)
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

    /// @notice exchangeRates() fetches current ExchangeRates contract
    function exchanger() internal view returns (IExchanger) {
        return
            IExchanger(
                ADDRESS_RESOLVER.requireAndGetAddress(
                    "Exchanger",
                    "Account: Could not get Exchanger"
                )
            );
    }

    /*//////////////////////////////////////////////////////////////
                             MATH UTILITIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Absolute value of the input, returned as an unsigned number.
    /// @param x: signed number
    function _abs(int256 x) internal pure returns (uint256) {
        return uint256(x < 0 ? -x : x);
    }
}
