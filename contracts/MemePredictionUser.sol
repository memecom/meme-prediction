// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "contracts/MemePredictionBase.sol";

contract MemePredictionUser is MemePredictionBase {

    event UserMadePredictions(address user, uint256[] memeOptionIndex, uint256[] amount, uint256[] netAmount, bool[] isUpPrediction);
    event UserCancelledPrediction(address user, uint256 memeOptionIndex, uint256 amount);
    event UserCancelledAllPredictions(address user, uint256 amount);
    event UserClaimed(address user, uint256 amountClaimed);
    event RoundCancelled(uint256 roundIndex);


    /**
     * @notice Used for players to predict on given meme (choosen by memeOptionIndex). Amount for prediction is
     *         limited by minimumPredictionAmount and maximumPredictionAmount. Parameter isUpPrediction
     *         indicates if user predicts that given meme will go up or down (true means up, false means down).
     *         Predictions are stored for each prediction round and can be claimed at any date (after prediction
     *         round was resolved/cancelled)
     *
     * @param memeOptionIndex index of meme option in predictions for current round
     * @param weiAmount amount of prediciton currency used for prediction in Wei
     * @param isUpPrediction true means up prediction, false means down prediction
     */
    function predict(
        uint256 memeOptionIndex,
        uint256 weiAmount,
        bool isUpPrediction
    ) public {

        uint256 netAmount = _placePrediction(memeOptionIndex, weiAmount, isUpPrediction);
        require(predictionCurrency.transferFrom(msg.sender, address(this), weiAmount), "ERROR: Currency transfer failed");

        uint256[] memory memeOptionIndexArray = new uint256[](1);
        uint256[] memory weiAmountArray = new uint256[](1);
        uint256[] memory netAmountArray = new uint256[](1);
        bool[] memory isUpPredictionArray = new bool[](1);

        memeOptionIndexArray[0] = memeOptionIndex;
        weiAmountArray[0] = weiAmount;
        netAmountArray[0] = netAmount;
        isUpPredictionArray[0] = isUpPrediction;

        emit UserMadePredictions(msg.sender, memeOptionIndexArray, weiAmountArray, netAmountArray, isUpPredictionArray);
    }

    /*
     * @notice Used for players to predict on multiple memes (choosen by memeOptionIndex). Amount for prediction is
     *         limited by minimumPredictionAmount and maximumPredictionAmount. Parameter isUpPrediction
     *         indicates if user predicts that given meme will go up or down (true means up, false means down).
     *         Predictions are stored for each prediction round and can be claimed at any date (after prediction
     *         round was resolved/cancelled)
     *
     * @param memeOptionIndexes indexes of meme options in predictions for current round
     * @param weiAmounts amounts of prediciton currency used for prediction in Wei
     * @param isUpPrediction true means up prediction, false means down prediction
    */
    function predictMultiple(
        uint256[] calldata memeOptionIndexes,
        uint256[] calldata weiAmounts,
        bool[] calldata isUpPrediction
    ) public {
        uint256[] memory netWeiAmounts = new uint256[](memeOptionIndexes.length);
        uint256 totalWeiAmount;
        for (uint256 i = 0; i < memeOptionIndexes.length; i++){
            netWeiAmounts[i] = _placePrediction(memeOptionIndexes[i], weiAmounts[i], isUpPrediction[i]);
            totalWeiAmount += weiAmounts[i];

        }
        require(predictionCurrency.transferFrom(msg.sender, address(this), totalWeiAmount), "ERROR: Currency transfer failed");
        emit UserMadePredictions(msg.sender, memeOptionIndexes, weiAmounts, netWeiAmounts, isUpPrediction);
    }

    /**
     * @notice Used for players to claim their winnings or claim funds from
     *         cancled rounds (if round was canceled fee is also returned).
     *         All clamied funds get transfered to the caller.
     *
     * @dev Clears all marked rounds from unclaimedPredictionRounds
     *      (if current round is not resolved it does not get removed).
     *      Claimed amount gets removed from locked currency.
     *
     * @return claimedAmount in wei
     */
    function claim() public returns (uint256 claimedAmount) {
        claimedAmount = calculateClaimableAmount(msg.sender);

        lockedCurrency -= claimedAmount;

        delete unclaimedPredictionRounds[msg.sender];
        if (state == State.InProgress) {
            unclaimedPredictionRounds[msg.sender].push(currentPredictionRound);
        }

        require(predictionCurrency.transfer(msg.sender, claimedAmount), "ERROR: Transaction failed");
        emit UserClaimed(msg.sender, claimedAmount);
    }

    /**
     * @notice Used for canceling given user prediction while prediction round is open for predictions.
     *         Warnign fee is not refunded as to prevent odds manipulation. Prediction amount - fee gets
     *         transfered to the called and prediction entry is removed from round.
     *
     * @param optionIndex index of meme prediction to be cancelled
     */
    function cancelPrediction(uint256 optionIndex) public returns (uint256 amountToWithdraw) {
        require(isOpen(), "ERROR: for canceling predictions on option round in progress needs to be open");

        uint256[] memory alreadyPredictedMemes = predictions[currentPredictionRound][msg.sender].memeOptionIndexes;
        (bool predicted, uint256 predictionIndex) = findElement(alreadyPredictedMemes, optionIndex);
        require(predicted);

        Predictions storage userPredictions = predictions[currentPredictionRound][msg.sender];
        amountToWithdraw = userPredictions.predictionNetAmounts[predictionIndex];

        _storeWithdrawal(predictionIndex, optionIndex);

        lockedCurrency -= amountToWithdraw;

        require(predictionCurrency.transfer(msg.sender, amountToWithdraw), "ERROR: Withdrawal failed");
        emit UserCancelledPrediction(msg.sender, optionIndex, amountToWithdraw);
    }

    /**
     * @notice Same as cancelPrediction but cancells all prediction for current round.
     *         Warnign fee is not refunded as to prevent odds manipulation.
     */
    function cancelAllPredictions() public returns (uint256 amountToWithdraw) {
        require(isOpen(), "ERROR: for canceling all predictions on option round in progress needs to be open");

        Predictions storage userPredictions = predictions[currentPredictionRound][msg.sender];
        amountToWithdraw = userPredictions.totalPredictionNetAmount;

        for (uint256 i = 0; i < userPredictions.memeOptionIndexes.length; i++) {
            _storeWithdrawal(i, userPredictions.memeOptionIndexes[i]);
        }

        require(lockedCurrency >= amountToWithdraw, "ERROR: Locked currency underflow");
        lockedCurrency -= amountToWithdraw;

        require(predictionCurrency.transfer(msg.sender, amountToWithdraw), "ERROR: Withdrawal failed");
        emit UserCancelledAllPredictions(msg.sender, amountToWithdraw);
    }

    function _placePrediction(
        uint256 memeOptionIndex,
        uint256 weiAmount,
        bool isUpPrediction
    ) internal returns (uint256) {
        require(isOpen(), "ERROR: Must be open to predict");
        require(memeOptionIndex < roundOptionStats[currentPredictionRound].length, "ERROR: Index out of range");

        uint256[] memory alreadyPredictedMemes = predictions[currentPredictionRound][msg.sender].memeOptionIndexes;
        (bool alreadyPredicted, uint256 predictionPredictionIndex) = findElement(alreadyPredictedMemes, memeOptionIndex);

        uint256 currentTotalAmount = 0;

        if (alreadyPredicted) {
            currentTotalAmount = predictions[currentPredictionRound][msg.sender].predictionAmounts[predictionPredictionIndex];
        }
        require(weiAmount >= minimumPredictionAmount, "ERROR: Prediction amount is too small");
        require(weiAmount + currentTotalAmount <= maximumPredictionAmount, "ERROR: Total prediction amount must be within range");

        uint256 weiFee = (weiAmount * feePercentage) / 10**feeDecimals;
        uint256 weiNetAmount = weiAmount - weiFee;

        if (isUpPrediction) {
            roundOptionStats[currentPredictionRound][memeOptionIndex].totalUpAmount += weiNetAmount;
        } else {
            roundOptionStats[currentPredictionRound][memeOptionIndex].totalDownAmount += weiNetAmount;
        }

        if (alreadyPredicted) {
            _addToExistingPrediction(predictionPredictionIndex, weiAmount, weiNetAmount, weiFee, isUpPrediction);
        } else {
            _addPredictionOnNewOption(memeOptionIndex, weiAmount, weiNetAmount, weiFee, isUpPrediction);
        }

        uint256[] memory unclaimedRounds = unclaimedPredictionRounds[msg.sender];
        (bool alreadyMarked, ) = findElement(unclaimedRounds, currentPredictionRound);
        if (!alreadyMarked) {
            unclaimedPredictionRounds[msg.sender].push(currentPredictionRound);
        }

        return weiAmount;
    }

    function _addPredictionOnNewOption(
        uint256 memeOptionIndex,
        uint256 weiAmount,
        uint256 weiNetAmount,
        uint256 weiFee,
        bool isUpPrediction
    ) internal {
        predictions[currentPredictionRound][msg.sender].memeOptionIndexes.push(memeOptionIndex);

        if (isUpPrediction) {
            predictions[currentPredictionRound][msg.sender].predictionUpNetAmounts.push(weiNetAmount);
            predictions[currentPredictionRound][msg.sender].predictionUpAmounts.push(weiAmount);
            predictions[currentPredictionRound][msg.sender].predictionDownNetAmounts.push(0);
            predictions[currentPredictionRound][msg.sender].predictionDownAmounts.push(0);
        } else {
            predictions[currentPredictionRound][msg.sender].predictionDownNetAmounts.push(weiNetAmount);
            predictions[currentPredictionRound][msg.sender].predictionDownAmounts.push(weiAmount);
            predictions[currentPredictionRound][msg.sender].predictionUpNetAmounts.push(0);
            predictions[currentPredictionRound][msg.sender].predictionUpAmounts.push(0);
        }
        predictions[currentPredictionRound][msg.sender].predictionNetAmounts.push(weiNetAmount);
        predictions[currentPredictionRound][msg.sender].predictionAmounts.push(weiAmount);

        predictions[currentPredictionRound][msg.sender].totalPredictionNetAmount += weiNetAmount;
        predictions[currentPredictionRound][msg.sender].totalPredictionAmount += weiAmount;

        predictions[currentPredictionRound][msg.sender].feesCollected += weiFee;
        feesCollectedForRound[currentPredictionRound] += weiFee;
        lockedCurrency += weiFee;
        lockedCurrency += weiNetAmount;
    }

    function _addToExistingPrediction(
        uint256 index,
        uint256 weiAmount,
        uint256 weiNetAmount,
        uint256 weiFee,
        bool isUpPrediction
    ) internal {
        if (isUpPrediction) {
            predictions[currentPredictionRound][msg.sender].predictionUpNetAmounts[index] += weiNetAmount;
            predictions[currentPredictionRound][msg.sender].predictionUpAmounts[index] += weiAmount;
        } else {
            predictions[currentPredictionRound][msg.sender].predictionDownNetAmounts[index] += weiNetAmount;
            predictions[currentPredictionRound][msg.sender].predictionDownAmounts[index] += weiAmount;
        }
        predictions[currentPredictionRound][msg.sender].predictionNetAmounts[index] += weiNetAmount;
        predictions[currentPredictionRound][msg.sender].predictionAmounts[index] += weiAmount;

        predictions[currentPredictionRound][msg.sender].totalPredictionNetAmount += weiNetAmount;
        predictions[currentPredictionRound][msg.sender].totalPredictionAmount += weiAmount;

        predictions[currentPredictionRound][msg.sender].feesCollected += weiFee;
        feesCollectedForRound[currentPredictionRound] += weiFee;
        lockedCurrency += weiFee;
        lockedCurrency += weiNetAmount;
    }

    function _storeWithdrawal(uint256 predictionIndex, uint256 optionIndex) internal {
        Predictions storage userPredictions = predictions[currentPredictionRound][msg.sender];
        uint256 upNetAmount = userPredictions.predictionUpNetAmounts[predictionIndex];
        uint256 downNetAmount = userPredictions.predictionDownNetAmounts[predictionIndex];

        roundOptionStats[currentPredictionRound][optionIndex].totalUpAmount -= upNetAmount;
        roundOptionStats[currentPredictionRound][optionIndex].totalDownAmount -= downNetAmount;

        userPredictions.totalPredictionAmount -= userPredictions.predictionAmounts[predictionIndex];
        userPredictions.totalPredictionNetAmount -= userPredictions.predictionNetAmounts[predictionIndex];

        userPredictions.predictionNetAmounts[predictionIndex] = 0;
        userPredictions.predictionUpNetAmounts[predictionIndex] = 0;
        userPredictions.predictionDownNetAmounts[predictionIndex] = 0;
        userPredictions.predictionUpAmounts[predictionIndex] = 0;
        userPredictions.predictionDownAmounts[predictionIndex] = 0;
        userPredictions.predictionAmounts[predictionIndex] = 0;
    }
}
