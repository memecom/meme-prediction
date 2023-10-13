// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "contracts/MemePrediction.sol";

contract TestMemePrediction is MemePrediction {

    bool public isOpenState; 
    bool public isWaitingPeriodOverState; 
    bool public isTimedOutState; 

    constructor(address currencyAddress) MemePrediction(currencyAddress) {}

    function isOpen() public view override returns(bool){
        return isOpenState;
    }

    function isWaitingPeriodOver() public view override returns(bool){
        return isWaitingPeriodOverState;
    } 

    function isTimedOut() public view override returns(bool){
        return isTimedOutState;
    }

    function setOpenState(bool _isOpen) public{
        isOpenState = _isOpen;
    }

    function setWaitingPeriodOverState(bool _isWaitingPeriodOver) public{
        isWaitingPeriodOverState = _isWaitingPeriodOver;
    }

    function setTimedOutState(bool _isTimedOut) public{
        isTimedOutState = _isTimedOut;
    }
}