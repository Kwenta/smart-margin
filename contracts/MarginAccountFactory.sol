// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "./utils/MinimalProxyFactory.sol";
import "./MarginBase.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MarginAccountFactory is MinimalProxyFactory {
    string public version; // 0.1.0
    MarginBase public immutable implementation;
    IERC20 public immutable marginAsset;
    address public immutable addressResolver;
    address payable public immutable ops;

    constructor(
        string memory _version,
        address _marginAsset,
        address _addressResolver,
        address payable _ops
    ) {
        version = _version;
        implementation = new MarginBase();
        marginAsset = IERC20(_marginAsset);
        addressResolver = _addressResolver;
        ops = _ops;
    }

    function newAccount() external returns (address) {
        MarginBase account = MarginBase(
            _cloneAsMinimalProxy(address(implementation), "Creation failure")
        );
        account.initialize(address(marginAsset), addressResolver, ops);
        account.transferOwnership(msg.sender);

        emit NewAccount(msg.sender, address(account));
        return address(account);
    }

    event NewAccount(address indexed owner, address account);
}
