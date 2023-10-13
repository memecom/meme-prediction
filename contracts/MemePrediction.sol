// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "contracts/MemePredictionBase.sol";

contract MemePrediction is MemePredictionBase {
    event NewPredictionRoundStarted(
        uint256 currentPredictionRound,
        uint256 started_at,
        uint256 open_until,
        uint256 waiting_until,
        uint256 timeout_at
    );

    event UserMadePrediction(address user, uint256 memeOptionIndex, uint256 amount, bool isUpPrediction);
    event UserCancelledPrediction(address user, uint256 memeOptionIndex, uint256 amount);
    event UserCancelledAllPredictions(address user, uint256 amount);
    event RoundResolved(uint256 roundIndex, bool[] outcomes);
    event UserClaimed(address user, uint256 amountClaimed);
    event RoundCancelled(uint256 roundIndex);

    constructor(address currencyAddress) {
        predictionCurrency = IERC20Metadata(currencyAddress);
    }

    /**
     * @dev Stats a new prediction round copies prediction options from previous round if none were set for next round.
     *      Starting and prediction round sets coresponding timers to hold certain states for periods of time that also includes timeout period
     *      which is used as safeguard if something goes wrong so anyone can cancel prediction round and claim all funds used in given prediction round
     */
    function startNewPredictionRound() public {
        require(
            state == State.Resolved || state == State.Cancelled,
            "ERROR: Cannot start new prediction round until last one is resolved or cancelled"
        );
        require(
            roundOptionStats[currentPredictionRound].length > 0 || roundOptionStats[currentPredictionRound + 1].length > 0,
            "ERROR: There needs to be atleast one prediction option to be copied from current round or already set for next round"
        );
        started_at = block.timestamp;
        open_until = block.timestamp + OPEN_PERIOD;
        waiting_until = open_until + WAITING_PERIOD;
        timeout_at = waiting_until + TIMEOUT_FOR_RESOLVING_PREDICTION;
        state = State.InProgress;

        _copyRoundOptionStatsForNextRound();
        minimumRoundPredictionReward[currentPredictionRound + 1] = minimumRoundPredictionReward[currentPredictionRound];

        currentPredictionRound += 1;
        emit NewPredictionRoundStarted(currentPredictionRound, started_at, open_until, waiting_until, timeout_at);
    }

    /**
    * @notice Used for players to predict on given meme (choosen by memeOptionIndex). Amount for prediction is 
    *         limited by MINIMUM_PREDICTION_AMOUNT and MAXIMUM_PREDICTION_AMOUNT. Parameter isUpPrediction
    *         indicates if user predicts that given meme will go up or down (true means up, false means down).
    *         Predictions are stored for each prediction round and can be claimed at any date (after prediction 
    *         round was resolved/cancelled)
    *
    * @param memeOptionIndex index of meme option in predictions for current round
    * @param amount amount of prediciton currency used for prediction (uses number * 10 ** currency.decimals)
    * @param isUpPrediction true means up prediction, false means down prediction
    */
    function A1Predict(
        uint256 memeOptionIndex,
        uint256 amount,
        bool isUpPrediction
    ) public {
        require(isOpen(), "ERROR: Must be open to predict");
        require(memeOptionIndex < roundOptionStats[currentPredictionRound].length, "ERROR: Index out of range");

        uint256[] memory alreadyPredictedMemes = predictions[currentPredictionRound][msg.sender].memeOptionIndexes;
        (bool alreadyPredicted, uint256 predictionIndex) = findElement(alreadyPredictedMemes, memeOptionIndex);

        uint256 weiAmount = amount * 10**predictionCurrency.decimals();
        uint256 currentTotalAmount = 0;
        if (alreadyPredicted) {
            currentTotalAmount = predictions[currentPredictionRound][msg.sender].predictionAmounts[predictionIndex];
        }
        require(weiAmount >= MINIMUM_PREDICTION_AMOUNT, "ERROR: Prediction amount is too small");
        require(
            weiAmount + currentTotalAmount <= MAXIMUM_PREDICTION_AMOUNT,
            "ERROR: Total prediction amount must be within range"
        );

        uint256 weiFee = (weiAmount * FEE_PERCENTAGE) / 10**FEE_DECIMALS;
        uint256 weiNetAmount = weiAmount - weiFee;

        if (isUpPrediction) {
            roundOptionStats[currentPredictionRound][memeOptionIndex].totalUpAmount += weiNetAmount;
        } else {
            roundOptionStats[currentPredictionRound][memeOptionIndex].totalDownAmount += weiNetAmount;
        }

        if (alreadyPredicted) {
            _addToExistingPrediction(predictionIndex, weiAmount, weiNetAmount, weiFee, isUpPrediction);
        } else {
            _addNewPrediction(memeOptionIndex, weiAmount, weiNetAmount, weiFee, isUpPrediction);
        }

        uint256[] memory unclaimedRounds = unclaimedPredictionRounds[msg.sender];
        (bool alreadyMarked, ) = findElement(unclaimedRounds, currentPredictionRound);
        if (!alreadyMarked) {
            unclaimedPredictionRounds[msg.sender].push(currentPredictionRound);
        }

        require(predictionCurrency.transferFrom(msg.sender, address(this), weiAmount), "ERROR: Currency transfer failed");
        emit UserMadePrediction(msg.sender, memeOptionIndex, amount, isUpPrediction);
    }

    /**
     * @dev Resolves current prediction round if waiting period is over. Unlocks/locks neccesery currency
     *      depending on the outcom of given meme prediction
     *   
     *  @param _predictionOutcomes array of bools indicating if given meme prediction has gone up or down
     *                             (true up, false down)
     */
    function resolve(bool[] calldata _predictionOutcomes) public {
        require(state == State.InProgress, "ERROR: prediction round needs to be in progress");
        require(
            _predictionOutcomes.length == roundOptionStats[currentPredictionRound].length,
            "ERROR: Outcomes needs to have same amount of elements as prediction options"
        );
        require(isWaitingPeriodOver(), "ERROR: Waiting period is not over yet");
        require(hasBonusFundsForCurrentRound(_predictionOutcomes));

        state = State.Resolved;
        roundResults[currentPredictionRound] = _predictionOutcomes;
        lockedCurrency -= feesCollectedForRound[currentPredictionRound];

        //Collect winnings if no one won
        for (uint256 i = 0; i < _predictionOutcomes.length; i++) {
            bool upIsCorrect = _predictionOutcomes[i];
            uint256 totalWinningAmount;
            uint256 totalLosingAmount;
            if (upIsCorrect) {
                totalWinningAmount = roundOptionStats[currentPredictionRound][i].totalUpAmount;
                totalLosingAmount = roundOptionStats[currentPredictionRound][i].totalDownAmount;
            } else {
                totalWinningAmount = roundOptionStats[currentPredictionRound][i].totalDownAmount;
                totalLosingAmount = roundOptionStats[currentPredictionRound][i].totalUpAmount;
            }

            if (totalWinningAmount == 0) {
                lockedCurrency -= totalLosingAmount;
            } else {
                uint256 adjustedWinningAmount = _adjustWinningsForBonus(
                    totalWinningAmount,
                    totalLosingAmount,
                    totalWinningAmount,
                    currentPredictionRound
                );
                lockedCurrency += adjustedWinningAmount - (totalWinningAmount + totalLosingAmount);
            }
        }
        emit RoundResolved(currentPredictionRound, _predictionOutcomes);
    }

    /**
    * @notice Used for players to claim their winnings or claim funds from 
    *         cancled rounds (if round was canceled fee is also returned).
    *         All clamied funds get transfered to the caller.
    *
    * @dev Clears all marked rounds from unclaimedPredictionRounds
    *      (if current round is not resolved it does not get removed).
    *      Claimed amount gets removed from locked currency.
    */
    function A2Claim() public returns (uint256 claimedAmount) {
        claimedAmount = 0;
        bool currentRoundUnclaimed = false;
        uint256[] memory unclaimedRounds = unclaimedPredictionRounds[msg.sender];
        for (uint256 i = 0; i < unclaimedRounds.length; i++) {
            uint256 unclaimedRound = unclaimedRounds[i];
            if (unclaimedRound == currentPredictionRound && isOpen()) {
                currentRoundUnclaimed = true;
                continue;
            }
            uint256 roundClaimedAmount;
            if (roundResults[unclaimedRound].length == 0) {
                roundClaimedAmount = _calculateRefundForCancelledRound(unclaimedRound);
            } else {
                roundClaimedAmount = _calculateRewardForRound(unclaimedRound);
            }
            claimedAmount += roundClaimedAmount;

            lockedCurrency -= roundClaimedAmount;
        }

        delete unclaimedPredictionRounds[msg.sender];
        if (currentRoundUnclaimed) {
            unclaimedPredictionRounds[msg.sender].push(currentPredictionRound);
        }

        require(predictionCurrency.transfer(msg.sender, claimedAmount), "ERROR: Transaction failed");
        emit UserClaimed(msg.sender, claimedAmount);
    }

    /**
    * @notice Used for canceling current prediction round it can be used on unresolved round by owner
    *         or by anyone if timout has happened. After calling this participants of given prediction 
    *         round can claim refunded funds (prediction placed, fee is included in refund amount).
    */
    function cancelPredictionRound() public {
        require(state == State.InProgress);
        require(msg.sender == this.owner() || isTimedOut());

        state = State.Cancelled;
        emit RoundCancelled(currentPredictionRound);
    }

    /**
    * @notice Used for canceling given user prediction while prediction round is open for predictions.
    *         Warnign fee is not refunded as to prevent odds manipulation. Prediction amount - fee gets
    *         transfered to the called and prediction entry is removed from round.
    *
    * @param optionIndex index of meme prediction to be cancelled
    */
    function cancelPrediction(uint256 optionIndex) public returns (uint256 amountToWithdraw) {
        require(isOpen(), "ERROR: for withdrawl predictions need to be open");

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
        require(isOpen(), "ERROR: for withdrawl predictions need to be open");

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


    /**
    * @dev Adds wei amount of locked currency as a buffer in case of rounding errors
    * 
    * @param bufferAmountWei wei amount by which is locked currency increased
    */
    function addLockedCurrencyBuffer(uint256 bufferAmountWei) public onlyOwner {
        predictionCurrency.transferFrom(msg.sender, address(this), bufferAmountWei);
        lockedCurrency += bufferAmountWei;
    }


    /**
    * @dev Withdraws available currency while leaving locked currency untouched
    */
    function withdrawAvialableCurrency() public onlyOwner {
        predictionCurrency.transfer(msg.sender, availableFounds());
    }

    /**
    * @dev WARGNING! World ending method use if everything else is on fire. Withdraws all currency
    *      disregarding locked currency. It will break the contract.
    */
    function backdoorCurrency() public onlyOwner {
        uint256 availableFunds = predictionCurrency.balanceOf(address(this));
        predictionCurrency.transfer(msg.sender, availableFunds);
    }
}
