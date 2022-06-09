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

    constructor(
        string memory _version,
        address _marginAsset,
        address _addressResolver
    ) {
        version = _version;
        implementation = new MarginBase();
        marginAsset = IERC20(_marginAsset);
        addressResolver = _addressResolver;
    }

    function newAccount() external returns (address) {
        MarginBase account = MarginBase(
            _cloneAsMinimalProxy(address(implementation), "Creation failure")
        );
        account.initialize(address(marginAsset), addressResolver);
        account.transferOwnership(msg.sender);

        emit NewAccount(msg.sender, address(account));
        return address(account);
    }

    event NewAccount(address indexed owner, address account);
}
