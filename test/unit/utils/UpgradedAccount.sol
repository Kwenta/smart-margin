// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {IAccount, IAddressResolver, IERC20, IExchanger, IFactory, IFuturesMarketManager, IPerpsV2MarketConsolidated, ISettings} from "../../../src/interfaces/IAccount.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {OpsReady, IOps} from "../../../src/utils/OpsReady.sol";
import {Owned} from "@solmate/auth/Owned.sol";

contract UpgradedAccount is IAccount, OpsReady, Owned, Initializable {
    bytes32 public constant VERSION = "2.0.1";
    bytes32 private constant TRACKING_CODE = "KWENTA";
    bytes32 private constant FUTURES_MARKET_MANAGER = "FuturesMarketManager";
    bytes32 private constant SUSD = "sUSD";

    IFactory public factory;
    IAddressResolver public addressResolver;
    IFuturesMarketManager public futuresMarketManager;
    ISettings public settings;
    IERC20 public marginAsset;
    uint256 public committedMargin;
    uint256 public orderId;
    mapping(uint256 => Order) private orders;

    modifier notZero(uint256 value, bytes32 valueName) {
        if (value == 0) revert ValueCannotBeZero(valueName);
        _;
    }

    constructor() Owned(address(0)) {
        _disableInitializers();
    }

    receive() external payable onlyOwner {}

    function initialize(
        address _owner,
        address _marginAsset,
        address _addressResolver,
        address _settings,
        address payable _ops,
        address _factory
    ) external initializer {
        owner = _owner;
        emit OwnershipTransferred(address(0), _owner);
        marginAsset = IERC20(_marginAsset);
        addressResolver = IAddressResolver(_addressResolver);
        settings = ISettings(_settings);
        ops = _ops;
        factory = IFactory(_factory);
        futuresMarketManager = IFuturesMarketManager(
            addressResolver.requireAndGetAddress(
                FUTURES_MARKET_MANAGER,
                "Account: Could not get Futures Market Manager"
            )
        );
    }

    function getDelayedOrder(bytes32 _marketKey)
        external
        view
        override
        returns (IPerpsV2MarketConsolidated.DelayedOrder memory order)
    {
        order = getPerpsV2Market(_marketKey).delayedOrders(address(this));
    }

    function checker(uint256 _orderId)
        external
        view
        override
        returns (bool canExec, bytes memory execPayload)
    {
        (canExec, ) = validOrder(_orderId);
        execPayload = abi.encodeWithSelector(
            this.executeOrder.selector,
            _orderId
        );
    }

    function freeMargin() public view override returns (uint256) {
        return marginAsset.balanceOf(address(this)) - committedMargin;
    }

    function getPosition(bytes32 _marketKey)
        public
        view
        override
        returns (IPerpsV2MarketConsolidated.Position memory position)
    {
        position = getPerpsV2Market(_marketKey).positions(address(this));
    }

    function calculateTradeFee(
        int256 _sizeDelta,
        IPerpsV2MarketConsolidated _market,
        uint256 _advancedOrderFee
    ) public view override returns (uint256 fee) {
        fee =
            (_abs(_sizeDelta) * (settings.tradeFee() + _advancedOrderFee)) /
            settings.MAX_BPS();
        fee = (sUSDRate(_market) * fee) / 1e18;
    }

    function getOrder(uint256 _orderId)
        public
        view
        override
        returns (Order memory)
    {
        return orders[_orderId];
    }

    function transferOwnership(address _newOwner) public override onlyOwner {
        factory.updateAccountOwner({_oldOwner: owner, _newOwner: _newOwner});
        super.transferOwnership(_newOwner);
    }

    function deposit(uint256 _amount)
        public
        override
        onlyOwner
        notZero(_amount, "_amount")
    {
        bool success = marginAsset.transferFrom(owner, address(this), _amount);
        if (!success) revert FailedMarginTransfer();
        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount)
        external
        override
        notZero(_amount, "_amount")
        onlyOwner
    {
        if (_amount > freeMargin()) {
            revert InsufficientFreeMargin(freeMargin(), _amount);
        }
        bool success = marginAsset.transfer(owner, _amount);
        if (!success) revert FailedMarginTransfer();
        emit Withdraw(msg.sender, _amount);
    }

    function withdrawEth(uint256 _amount)
        external
        override
        onlyOwner
        notZero(_amount, "_amount")
    {
        (bool success, ) = payable(owner).call{value: _amount}("");
        if (!success) revert EthWithdrawalFailed();
        emit EthWithdraw(msg.sender, _amount);
    }

    function execute(Command[] calldata commands, bytes[] calldata inputs)
        external
        payable
        override
        onlyOwner
    {
        uint256 numCommands = commands.length;
        if (inputs.length != numCommands) revert LengthMismatch();
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
            revert InvalidCommandType(uint256(command));
        }
    }

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
            revert InvalidMarginDelta();
        }
    }

    function _perpsV2WithdrawAllMargin(address _market) internal {
        IPerpsV2MarketConsolidated(_market).withdrawAllMargin();
    }

    function _perpsV2SubmitAtomicOrder(
        address _market,
        int256 _sizeDelta,
        uint256 _priceImpactDelta
    ) internal {
        _imposeFee(
            calculateTradeFee({
                _sizeDelta: _sizeDelta,
                _market: IPerpsV2MarketConsolidated(_market),
                _advancedOrderFee: 0
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
        _imposeFee(
            calculateTradeFee({
                _sizeDelta: _sizeDelta,
                _market: IPerpsV2MarketConsolidated(_market),
                _advancedOrderFee: 0
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
        _imposeFee(
            calculateTradeFee({
                _sizeDelta: _sizeDelta,
                _market: IPerpsV2MarketConsolidated(_market),
                _advancedOrderFee: 0
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
        IPerpsV2MarketConsolidated(_market).cancelDelayedOrder(address(this));
    }

    function _perpsV2CancelOffchainDelayedOrder(address _market) internal {
        IPerpsV2MarketConsolidated(_market).cancelOffchainDelayedOrder(
            address(this)
        );
    }

    function _perpsV2ClosePosition(address _market, uint256 _priceImpactDelta)
        internal
    {
        bytes32 marketKey = IPerpsV2MarketConsolidated(_market).marketKey();
        IPerpsV2MarketConsolidated(_market).closePositionWithTracking(
            _priceImpactDelta,
            TRACKING_CODE
        );
        _imposeFee(
            calculateTradeFee({
                _sizeDelta: getPosition(marketKey).size,
                _market: IPerpsV2MarketConsolidated(_market),
                _advancedOrderFee: 0
            })
        );
    }

    function validOrder(uint256 _orderId)
        public
        view
        override
        returns (bool, uint256)
    {
        Order memory order = getOrder(_orderId);
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
        if (order.orderType == OrderTypes.LIMIT) {
            return validLimitOrder(order);
        } else if (order.orderType == OrderTypes.STOP) {
            return validStopOrder(order);
        }
        return (false, 0);
    }

    function validLimitOrder(Order memory order)
        internal
        view
        returns (bool, uint256)
    {
        uint256 price = sUSDRate(getPerpsV2Market(order.marketKey));
        if (order.sizeDelta > 0) {
            return (price <= order.targetPrice, price);
        } else if (order.sizeDelta < 0) {
            return (price >= order.targetPrice, price);
        }
        return (false, price);
    }

    function validStopOrder(Order memory order)
        internal
        view
        returns (bool, uint256)
    {
        uint256 price = sUSDRate(getPerpsV2Market(order.marketKey));
        if (order.sizeDelta > 0) {
            return (price >= order.targetPrice, price);
        } else if (order.sizeDelta < 0) {
            return (price <= order.targetPrice, price);
        }
        return (false, price);
    }

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
        if (address(this).balance < 1 ether / 100) {
            revert InsufficientEthBalance(address(this).balance, 1 ether / 100);
        }
        if (_marginDelta > 0) {
            if (uint256(_marginDelta) > freeMargin()) {
                revert InsufficientFreeMargin(
                    freeMargin(),
                    uint256(_marginDelta)
                );
            }
            committedMargin += _abs(_marginDelta);
        }
        bytes32 taskId = IOps(ops).createTaskNoPrepayment(
            address(this),
            this.executeOrder.selector,
            address(this),
            abi.encodeWithSelector(this.checker.selector, orderId),
            ETH
        );
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
        emit OrderPlaced(
            address(this),
            orderId,
            _marketKey,
            _marginDelta,
            _sizeDelta,
            _targetPrice,
            _orderType,
            _priceImpactDelta,
            _maxDynamicFee
        );
        return orderId++;
    }

    function cancelOrder(uint256 _orderId) external override onlyOwner {
        Order memory order = getOrder(_orderId);
        if (order.marginDelta > 0) {
            committedMargin -= _abs(order.marginDelta);
        }
        IOps(ops).cancelTask(order.gelatoTaskId);
        delete orders[_orderId];
        emit OrderCancelled(address(this), _orderId);
    }

    function executeOrder(uint256 _orderId) external override onlyOps {
        (bool isValidOrder, uint256 fillPrice) = validOrder(_orderId);
        if (!isValidOrder) {
            revert OrderInvalid();
        }
        Order memory order = getOrder(_orderId);
        if (order.marginDelta > 0) {
            committedMargin -= _abs(order.marginDelta);
        }

        NewPosition[] memory newPositions = new NewPosition[](1);
        newPositions[0] = NewPosition({
            marketKey: order.marketKey,
            marginDelta: order.marginDelta,
            sizeDelta: order.sizeDelta,
            priceImpactDelta: order.priceImpactDelta
        });

        IOps(ops).cancelTask(order.gelatoTaskId);

        delete orders[_orderId];

        // uint256 advancedOrderFee = order.orderType == OrderTypes.LIMIT
        //     ? settings.limitOrderFee()
        //     : settings.stopOrderFee();

        // execute trade
        //_distributeMargin(newPositions, advancedOrderFee);

        // pay fee
        (uint256 fee, address feeToken) = IOps(ops).getFeeDetails();
        _transfer(fee, feeToken);
        emit OrderFilled(address(this), _orderId, fillPrice, fee);
    }

    function _imposeFee(uint256 _fee) internal {
        if (_fee > freeMargin()) {
            revert CannotPayFee();
        } else {
            bool success = marginAsset.transfer(settings.treasury(), _fee);
            if (!success) revert FailedMarginTransfer();
            emit FeeImposed(address(this), _fee);
        }
    }

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

    function exchanger() internal view returns (IExchanger) {
        return
            IExchanger(
                addressResolver.requireAndGetAddress(
                    "Exchanger",
                    "Account: Could not get Exchanger"
                )
            );
    }

    function _abs(int256 x) internal pure returns (uint256) {
        return uint256(x < 0 ? -x : x);
    }
}
