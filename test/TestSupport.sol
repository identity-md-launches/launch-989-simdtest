// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Only the Foundry cheatcodes used by this dependency-free test suite.
interface Vm {
    function prank(address caller) external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
    function deal(address account, uint256 balance) external;
}

abstract contract TestSupport {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertEq(uint256 actual, uint256 expected) internal pure {
        require(actual == expected, "unexpected value");
    }

    function assertTrue(bool value) internal pure {
        require(value, "expected true");
    }
}
