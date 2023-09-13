// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "contracts/MemePrediction.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract PredictorWrapper{

    function predict(MemePrediction _contract, uint256 index, uint256 amount, bool isUpPrediction) public  {
        _contract.predict(index, amount, isUpPrediction);
    }

    function claim(MemePrediction _contract) public returns (uint256){
        return _contract.claim();
    }

    function withdraw(MemePrediction _contract, uint256 index) public returns (uint256){
        return _contract.withdraw(index);
    }
     
    function withdrawAll(MemePrediction _contract) public returns (uint256){
        return _contract.withdrawAll();
    }

    function approveERC20(ERC20PresetMinterPauser currency, address spender, uint256 amount) public {
        currency.approve(spender, amount);
    }

}