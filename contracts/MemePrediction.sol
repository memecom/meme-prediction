// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "contracts/MemePredictionBase.sol";

contract MemePrediction is MemePredictionBase {
    
    event NewPredictionRoundStarted(uint256 currentPredictionRound, uint256 started_at, uint256 open_until, uint256 waiting_until, uint256 timeout_at);
    event UserMadePrediction(address user, uint256 memeOptionIndex, uint256 amount, bool isUpPrediction, uint256 newTotalAmount);
    event RoundResolved(uint256 roundIndex, bool[] outcomes);
    event UserClaimed(address user, uint256 amountClaimed);
    event RoundCancelled(uint256 roundIndex);

    function startNewPredictionRound() public {
        require(
            state == State.Resolved || state == State.Cancelled,
            "ERROR: Cannot start new prediction round until last one is resolved or cancelled"
        );
        require(roundOptionStats[currentPredictionRound].length > 0, "ERRPR: There needs to be atleast one prediction option");
        started_at = block.timestamp;
        open_until = block.timestamp + OPEN_PERIOD;
        waiting_until = open_until + WAITING_PERIOD;
        timeout_at = waiting_until + TIMEOUT_FOR_RESOLVING_PREDICTION;
        _copyroundOptionStatsForNextRound();
        state = State.InProgress;
        currentPredictionRound += 1;

        emit NewPredictionRoundStarted(currentPredictionRound, started_at, open_until, waiting_until, timeout_at);
    }

    function predict(
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

        if (predictionCurrency.transferFrom(msg.sender, address(this), weiAmount)) {
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
            uint256 newTotalAmount = alreadyPredicted ? currentTotalAmount + weiAmount : weiAmount;
            emit UserMadePrediction(msg.sender, memeOptionIndex, amount, isUpPrediction, newTotalAmount);
        } else {
            revert();
        }
        
    }

    // True means up outcome won
    function resolve(bool[] calldata _predictionOutcomes) public {
        require(
            _predictionOutcomes.length == roundOptionStats[currentPredictionRound].length,
            "ERROR: Outcomes needs to have same amount of elements as prediction options"
        );
        require(isWaitingPeriodOver(), "ERROR: Waiting period is not over yet");
        //TODO: When implementing bonus, check for sufficient aviable funds

        state = State.Resolved;
        roundResults[currentPredictionRound] = _predictionOutcomes;
        require(lockedCurrency >= feesCollectedForRound[currentPredictionRound], "ERROR: Locked currency underflow");
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
                require(lockedCurrency >= totalLosingAmount, "ERROR: Locked currency underflow");
                lockedCurrency -= totalLosingAmount;
            }
        }

        emit RoundResolved(currentPredictionRound, _predictionOutcomes);
    }

    function claim() public returns (uint256 claimedAmount) {
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

            require(lockedCurrency >= roundClaimedAmount, "ERROR: Locked currency underflow");
            lockedCurrency -= roundClaimedAmount;
        }

        delete unclaimedPredictionRounds[msg.sender];
        if (currentRoundUnclaimed) {
            unclaimedPredictionRounds[msg.sender].push(currentPredictionRound);
        }

        require(predictionCurrency.transfer(msg.sender, claimedAmount), "ERROR: Transaction failed");
        emit UserClaimed(msg.sender, claimedAmount);
    }

    function cancel() public {
        require(state == State.InProgress);
        require(msg.sender == this.owner() || isTimedOut());

        state = State.Cancelled;
        emit RoundCancelled(currentPredictionRound);
    }

    // NOTE: Keeps the fee
    function withdraw(uint256 optionIndex) public returns (uint256) {
        require(isOpen(), "ERROR: for withdrawl predictions need to be open");

        uint256[] memory alreadyPredictedMemes = predictions[currentPredictionRound][msg.sender].memeOptionIndexes;
        (bool predicted, uint256 predictionIndex) = findElement(alreadyPredictedMemes, optionIndex);
        require(predicted);

        Predictions storage userPredictions = predictions[currentPredictionRound][msg.sender];
        uint256 amountToWithdraw = userPredictions.predictionNetAmounts[predictionIndex];

        userPredictions.totalPredictionAmount -= userPredictions.predictionAmounts[predictionIndex];
        userPredictions.totalPredictionNetAmount -= amountToWithdraw;

        _storeWithdrawal(predictionIndex, optionIndex);

        require(lockedCurrency >= amountToWithdraw, "ERROR: Locked currency underflow");
        lockedCurrency -= amountToWithdraw;

        require(predictionCurrency.transfer(msg.sender, amountToWithdraw), "ERROR: Withdrawal failed");
        return amountToWithdraw;
    }

    function withdrawAll() public returns (uint256) {
        require(isOpen(), "ERROR: for withdrawl predictions need to be open");

        Predictions storage userPredictions = predictions[currentPredictionRound][msg.sender];
        uint256 amountToWithdraw = userPredictions.totalPredictionNetAmount;

        for (uint256 i = 0; i < userPredictions.memeOptionIndexes.length; i++) {
            _storeWithdrawal(i, userPredictions.memeOptionIndexes[i]);
        }
        userPredictions.totalPredictionAmount = 0;
        userPredictions.totalPredictionNetAmount = 0;

        require(lockedCurrency >= amountToWithdraw, "ERROR: Locked currency underflow");
        lockedCurrency -= amountToWithdraw;

        require(predictionCurrency.transfer(msg.sender, amountToWithdraw), "ERROR: Withdrawal failed");
        return amountToWithdraw;
    }

    function addLockedCurrencyBuffer(uint256 bufferAmountWei) public onlyOwner {
        predictionCurrency.transferFrom(msg.sender, address(this), bufferAmountWei);
        lockedCurrency += bufferAmountWei;
    }
}
