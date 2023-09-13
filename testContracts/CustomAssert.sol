// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.4.22 <0.9.0;

library CustomAssert {
    event AssertionEventUint(bool passed, string message, string methodName, uint256 returned, uint256 expected);

    function almostEqual(
        uint256 a,
        uint256 b,
        uint256 e,
        string memory message
    ) public returns (bool result) {
        if (a > b) {
            result = (a - b) <= e;
        } else {
            result = (b - a) <= e;
        }
        emit AssertionEventUint(result, message, "almostEqual", a, b);
        return result;
    }
}
