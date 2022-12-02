// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

contract MinimalProxyFactory {
    function _cloneAsMinimalProxy(address _base, string memory _revertMsg)
        internal
        returns (address clone)
    {
        bytes memory createData = _generateMinimalProxyCreateData(_base);

        assembly {
            clone := create(
                0, // no value
                add(createData, 0x20), // data
                55 // data is always 55 bytes (10 constructor + 45 code)
            )
        }

        // If CREATE fails for some reason, address(0) is returned
        require(clone != address(0), _revertMsg);
    }

    function _generateMinimalProxyCreateData(address _base)
        internal
        pure
        returns (bytes memory)
    {
        return
            abi.encodePacked(
                //---- constructor -----
                bytes10(0x3d602d80600a3d3981f3),
                //---- proxy code -----
                bytes11(0x3d3d3d3d363d3d37363d73),
                _base,
                bytes13(0x5af43d3d93803e602a57fd5bf3)
            );
    }
}