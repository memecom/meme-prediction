// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ArraySearch {
    function findElement(uint256[] memory array, uint256 element) public pure returns (bool exists, uint256 index) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == element) {
                return (true, i);
            }
        }
        return (false, 0);
    }
}
