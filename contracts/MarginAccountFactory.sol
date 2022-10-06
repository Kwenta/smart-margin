// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "./utils/MinimalProxyFactory.sol";
import "./MarginBase.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Kwenta MarginBase Factory
/// @author JaredBorders (jaredborders@proton.me), JChiaramonte7 (jeremy@bytecode.llc)
/// @notice Factory which enables deploying a MarginBase account for any user 
contract MarginAccountFactory is MinimalProxyFactory {
    
    string public version; // format: (0.1.0)

    /*///////////////////////////////////////////////////////////////
                                Immutables
    ///////////////////////////////////////////////////////////////*/

    /// @notice MarginBase contract acting as user's account
    MarginBase public immutable implementation;

    /// @notice ERC20 token used to interact with markets
    IERC20 public immutable marginAsset;

    /// @notice synthetix address resolver
    address public immutable addressResolver;

    /// @notice settings for MarginBase accounts
    address public immutable marginBaseSettings;
    
    /// @notice gelato ops
    address payable public immutable ops;

    /*///////////////////////////////////////////////////////////////
                                Events
    ///////////////////////////////////////////////////////////////*/

    event NewAccount(address indexed owner, address account);

    /*///////////////////////////////////////////////////////////////
                                Constructor
    ///////////////////////////////////////////////////////////////*/

    /// @notice deploy MarginBase implementation to later be cloned
    /// @param _version: version of contract
    /// @param _marginAsset: token contract address used for account margin
    /// @param _addressResolver: contract address for synthetix address resolver
    /// @param _marginBaseSettings: contract address for MarginBase account settings
    /// @param _ops: contract address for gelato ops -- must be payable
    constructor(
        string memory _version,
        address _marginAsset,
        address _addressResolver,
        address _marginBaseSettings,
        address payable _ops
    ) {
        version = _version;
        implementation = new MarginBase();
        marginAsset = IERC20(_marginAsset);
        addressResolver = _addressResolver;

        /// @dev MarginBaseSettings must exist prior to MarginAccountFactory
        marginBaseSettings = _marginBaseSettings;

        ops = _ops;
    }

    /*///////////////////////////////////////////////////////////////
                            Account Deployment
    ///////////////////////////////////////////////////////////////*/

    /// @notice clone MarginBase (i.e. create new account for user)
    /// @dev this contract is the initial owner of cloned MarginBase,
    /// but ownership is transferred after successful initialization
    function newAccount() external returns (address) {
        MarginBase account = MarginBase(
            _cloneAsMinimalProxy(address(implementation), "Creation failure")
        );
        account.initialize(address(marginAsset), addressResolver, marginBaseSettings, ops);
        account.transferOwnership(msg.sender);

        emit NewAccount(msg.sender, address(account));
        return address(account);
    }
}
