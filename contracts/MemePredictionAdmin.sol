// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "contracts/MemePredictionBase.sol";

contract MemePredictionAdmin is MemePredictionBase {
    event NewPredictionRoundStarted(
        uint256 currentPredictionRound,
        uint256 startedAt,
        uint256 openUntil,
        uint256 waitingUntil,
        uint256 timeoutAt
    );
    event RoundResolved(uint256 roundIndex, bool[] outcomes);



    /**
     * @dev Stats a new prediction round copies prediction options from previous round if none were set for next round.
     *      Starting and prediction round sets coresponding timers to hold certain states for periods of time that also includes timeout period
     *      which is used as safeguard if something goes wrong so anyone can cancel prediction round and claim all funds used in given prediction round
     */
    function startNewPredictionRound() public onlyOwner {
        require(
            state == State.Resolved || state == State.Cancelled,
            "ERROR: Cannot start new prediction round until last one is resolved or cancelled"
        );
        require(
            roundOptionStats[currentPredictionRound].length > 0 || roundOptionStats[currentPredictionRound + 1].length > 0,
            "ERROR: There needs to be atleast one prediction option to be copied from current round or already set for next round"
        );
        startedAt = block.timestamp;
        openUntil = block.timestamp + openPeriod;
        waitingUntil = openUntil + waitingPeriod;
        timeoutAt = waitingUntil + timoutForResolvingPrediction;
        state = State.InProgress;

        _copyRoundOptionStatsForNextRound();
        _copybalanceRoundBonusRewardForNextRound();

        currentPredictionRound += 1;
        emit NewPredictionRoundStarted(currentPredictionRound, startedAt, openUntil, waitingUntil, timeoutAt);
    }

    /**
     * @dev Resolves current prediction round if waiting period is over. Unlocks/locks neccesery currency
     *      depending on the outcome of given meme prediction. If there are some minimum reward payouts then
     *      it locks needed available currency for claiming process.
     *
     *  @param predictionOutcomes array of bools indicating if given meme prediction has gone up or down
     *                             (true up, false down)
     */
    function resolve(bool[] calldata predictionOutcomes) public onlyOwner {
        require(isWaitingPeriodOver(), "ERROR: Waiting period is not over yet");
        require(
            predictionOutcomes.length == roundOptionStats[currentPredictionRound].length,
            "ERROR: Outcomes needs to have same amount of elements as prediction options"
        );
        require(
            hasBonusFundsForCurrentRound(predictionOutcomes),
            "ERROR: Does not have enought available funds to apply minimum prediction reward"
        );

        state = State.Resolved;
        roundResults[currentPredictionRound] = predictionOutcomes;
        lockedCurrency -= feesCollectedForRound[currentPredictionRound];

        //Collect winnings if no one won
        for (uint256 i = 0; i < predictionOutcomes.length; i++) {
            bool upIsCorrect = predictionOutcomes[i];
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
                uint256 bonusAmount = adjustedWinningAmount - (totalWinningAmount + totalLosingAmount);
                lockedCurrency += bonusAmount;
                roundOptionStats[currentPredictionRound][i].usedBonusReward = bonusAmount;
            }
        }
        emit RoundResolved(currentPredictionRound, predictionOutcomes);
    }

    /**
     * @dev Adds wei amount of locked currency as a buffer in case of rounding errors
     *
     * @param bufferAmountWei wei amount by which is locked currency increased
     */
    function addLockedCurrencyBuffer(uint256 bufferAmountWei) public onlyOwner {
        require(predictionCurrency.transferFrom(msg.sender, address(this), bufferAmountWei));
        lockedCurrency += bufferAmountWei;
    }

    /**
     * @dev Withdraws available currency while leaving locked currency untouched
     */
    function withdrawAvialableCurrency() public onlyOwner {
        predictionCurrency.transfer(msg.sender, availableFunds());
    }

    /**
     * @dev WARGNING! World ending method use if everything else is on fire. Withdraws all currency
     *      disregarding locked currency. It WILL break the contract.
     */
    function backdoorCurrency() public onlyOwner {
        uint256 availableFunds = predictionCurrency.balanceOf(address(this));
        predictionCurrency.transfer(msg.sender, availableFunds);
    }
}
