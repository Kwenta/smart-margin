// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IMarginAccountFactory.sol";
import "./interfaces/IMarginAccountFactoryStorage.sol";
import "./MarginBase.sol";
import "./utils/MinimalProxyFactory.sol";

/// @title Kwenta MarginBase Factory
/// @author JaredBorders (jaredborders@pm.me), JChiaramonte7 (jeremy@bytecode.llc)
/// @notice Factory which enables deploying a MarginBase account for any user
contract MarginAccountFactory is IMarginAccountFactory, MinimalProxyFactory {
    string public constant VERSION = "2.0.0";

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice MarginBase contract acting as user's account
    MarginBase public immutable implementation;

    /// @notice ERC20 token used to interact with markets
    IERC20 public immutable marginAsset;

    /// @notice persistent storage for all accounts/factories v2.0.0 and later
    IMarginAccountFactoryStorage public immutable store;

    /// @notice synthetix address resolver
    address public immutable addressResolver;

    /// @notice settings for accounts
    address public immutable marginBaseSettings;

    /// @notice gelato ops
    address payable public immutable ops;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice deploy MarginBase implementation to later be cloned
    /// @param _store: address of store for persistent account data
    /// @param _marginAsset: token contract address used for account margin
    /// @param _addressResolver: contract address for synthetix address resolver
    /// @param _marginBaseSettings: contract address for MarginBase account settings
    /// @param _ops: contract address for gelato ops -- must be payable
    constructor(
        address _store,
        address _marginAsset,
        address _addressResolver,
        address _marginBaseSettings,
        address payable _ops
    ) {
        store = IMarginAccountFactoryStorage(_store);
        marginAsset = IERC20(_marginAsset);
        addressResolver = _addressResolver;

        // deploy proxy logic
        implementation = new MarginBase();

        /// @dev MarginBaseSettings must exist prior to MarginAccountFactory
        marginBaseSettings = _marginBaseSettings;

        // assign Gelato ops
        ops = _ops;
    }

    /*//////////////////////////////////////////////////////////////
                           ACCOUNT DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IMarginAccountFactory
    function newAccount()
        external
        override
        returns (address payable accountAddress)
    {
        // ensure one account per address
        if (store.deployedMarginAccounts(msg.sender) != address(0)) {
            revert AlreadyCreatedAccount(
                store.deployedMarginAccounts(msg.sender)
            );
        }

        // create account
        accountAddress = payable(
            _cloneAsMinimalProxy(address(implementation), "Creation failure")
        );

        // update store
        store.addDeployedAccount(msg.sender, accountAddress);

        // initialize new account
        MarginBase account = MarginBase(accountAddress);
        account.initialize(
            address(marginAsset),
            addressResolver,
            marginBaseSettings,
            ops
        );

        // transfer ownership of account to caller
        account.transferOwnership(msg.sender);

        emit NewAccount(msg.sender, accountAddress);
    }
}
