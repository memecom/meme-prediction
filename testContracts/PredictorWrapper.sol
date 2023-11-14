// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "contracts/MemePrediction.sol";
import "@openzeppelin/contracts@4.5.0/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract PredictorWrapper {
    function predict(
        MemePrediction _contract,
        uint256 index,
        uint256 amount,
        bool isUpPrediction
    ) public {
        _contract.predict(index, amount * 10**18, isUpPrediction);
    }

    function predictMultiple(
        MemePrediction _contract,
        uint256[] calldata memeOptionIndexes,
        uint256[] calldata amounts,
        bool[] calldata isUpPrediction
    ) public {
        uint256[] memory weiAmounts = new uint256[](memeOptionIndexes.length);
        for (uint256 i = 0; i < memeOptionIndexes.length; i++){
            weiAmounts[i] = amounts[i] * 10**18;
        }
        _contract.predictMultiple(memeOptionIndexes, weiAmounts , isUpPrediction);
    }

    function claim(MemePrediction _contract) public returns (uint256) {
        return _contract.claim();
    }

    function cancelPrediction(MemePrediction _contract, uint256 index)
        public
        returns (uint256)
    {
        return _contract.cancelPrediction(index);
    }

    function cancelAllPredictions(MemePrediction _contract)
        public
        returns (uint256)
    {
        return _contract.cancelAllPredictions();
    }

    function approveERC20(
        ERC20PresetMinterPauser currency,
        address spender,
        uint256 amount
    ) public {
        currency.approve(spender, amount);
    }
}
