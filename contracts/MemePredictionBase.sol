// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@openzeppelin/contracts@4.5.0/access/Ownable.sol";
import "@openzeppelin/contracts@4.5.0/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts@4.5.0/utils/Strings.sol";

import "contracts/ArraySearch.sol";

contract MemePredictionBase is Ownable, ArraySearch {
    struct MemeOption {
        string identifier;
        uint256 memeOptionIndex;
        uint256 totalUpAmount;
        uint256 totalDownAmount;
        uint256 usedBonusReward;
    }

    struct Predictions {
        uint256[] memeOptionIndexes;
        uint256[] predictionUpNetAmounts;
        uint256[] predictionDownNetAmounts;
        uint256[] predictionUpAmounts;
        uint256[] predictionDownAmounts;
        uint256[] predictionAmounts;
        uint256[] predictionNetAmounts;
        uint256 totalPredictionAmount;
        uint256 totalPredictionNetAmount;
        uint256 feesCollected;
    }

    enum State {
        InProgress,
        Resolved,
        Cancelled
    }

    mapping(uint256 => MemeOption[]) internal roundOptionStats;

    State public state = State.Resolved;
    uint256 public currentPredictionRound = 0;
    uint256 public lockedCurrency;

    IERC20Metadata public predictionCurrency;

    mapping(uint256 => mapping(address => Predictions)) internal predictions;
    mapping(address => uint256[]) public unclaimedPredictionRounds;
    mapping(uint256 => bool[]) internal roundResults;
    mapping(uint256 => uint256) public feesCollectedForRound;

    mapping(uint256 => uint256) public balanceRoundBonusReward;

    uint256 public minimumPredictionAmount;
    uint256 public maximumPredictionAmount;

    // Uses 4 decimal places so 12.34% = 0.1234 = 1234
    uint256 public feePercentage;
    uint256 public constant feeDecimals = 4;

    //In seconds
    uint256 internal openPeriod = 3 * 24 * 60 * 60;
    uint256 internal waitingPeriod = 7 * 24 * 60 * 60;
    uint256 internal timoutForResolvingPrediction = 24 * 60 * 60;

    //Timestamps
    uint256 public startedAt;
    uint256 public openUntil;
    uint256 public waitingUntil;
    uint256 public timeoutAt;

    /**
     * @dev Sets predictible options for next round. Cant be set while round is in progress.
     *
     * @param memeIdentifiers List of names (strings) of predictible options.
     */
    function setPredictibleOptionsForNextRound(string[] calldata memeIdentifiers) public onlyOwner {
        require(state == State.Resolved || state == State.Cancelled);
        delete roundOptionStats[currentPredictionRound + 1];
        for (uint256 i = 0; i < memeIdentifiers.length; i++) {
            roundOptionStats[currentPredictionRound + 1].push(MemeOption(memeIdentifiers[i], i, 0, 0, 0));
        }
    }

    /**
     * @dev Sets minimum prediction amount per prediction.
     *
     * @param amount Minimum prediction amount in whole currency.
     */
    function setMinimumPredictionAmount(uint256 amount) public onlyOwner {
        minimumPredictionAmount = amount * (10**predictionCurrency.decimals());
    }

    /**
     * @dev Sets maximum prediction net amount for each prediction option.
     *
     * @param amount Maximum prediction amount in whole currency.
     */
    function setMaximumPredictionAmount(uint256 amount) public onlyOwner {
        maximumPredictionAmount = amount * (10**predictionCurrency.decimals());
    }

    /**
     * @dev Sets fee percentage.
     *
     * @param percentage Fee percentage, uses 4 decimal places so 12.34% = 0.1234 = 1234
     */
    function setFeePercentage(uint256 percentage) public onlyOwner {
        feePercentage = percentage;
    }

    /**
     * @dev Sets open period lenght, until open period expires, users can place predictions.
     *
     * @param _minutes Open preriod lenghts in minutes.
     */
    function setOpenPeriod(uint256 _minutes) public onlyOwner {
        openPeriod = _minutes * 60;
    }

    /**
     * @dev Sets waiting period lenght, this period starts after open period expires,
     *           after that no action can be made (except owner canceling the prediction).
     *
     * @param _minutes Waiting preriod lenghts in minutes.
     */
    function setWaitingPeriod(uint256 _minutes) public onlyOwner {
        waitingPeriod = _minutes * 60;
    }

    /**
     * @dev Sets timout limit lenght, timout limit starts after waiting period expires,
     *           after that owner can resolve prediction round, and if timeout is hit users
     *           can cancel prediction round.
     *
     * @param _minutes Timout limit lenghts in minutes.
     */
    function setTimoutLimit(uint256 _minutes) public onlyOwner {
        timoutForResolvingPrediction = _minutes * 60;
    }

    function getOpenPeriod() public view returns (uint256) {
        return openPeriod / (60);
    }

    function getWaitingPeriod() public view returns (uint256) {
        return waitingPeriod / (60);
    }

    function getTimoutForResolvingPrediction() public view returns (uint256) {
        return timoutForResolvingPrediction / (60);
    }

    /**
     * @dev Sets minimum prediction reward for next round.
     *      Reward is applied like so (minimum reward is 1000):
     *      Winning side | Loosing side | Adjusted loosing side
     *      500          | 10           | 500 (10 + 490)
     *      1000         | 0            | 1000 (0 + 1000)
     *      1800         | 500          | 1500 (500 + 1000)
     *      100          | 1000         | 1000 (1000 + 0)
     *
     *      Since prediction reward is based on loosing side amount adjusted loosing side
     *      represents minimum prediction reward in action. We want to ensure that
     *      Winning side gets to 1:1 odds as much as possible with available minimum prediction
     *      reward pool. In parentheses you can see the calculation used (x + y) where x is loosing side
     *      and y is minimum reward used from pool.
     *
     * @param minimumReward Reward in whole amount that is then converted to wei
     */
    function setBalanceRoundBonusRewardForNextRound(uint256 minimumReward) public onlyOwner {
        balanceRoundBonusReward[currentPredictionRound + 1] = minimumReward * (10**predictionCurrency.decimals());
    }

    /**
     * @dev Gets current predictible options with name up and down amounts in wei
     *
     * @return List of MemeOption struts with data on current state of prediction round
     */
    function getCurrentPredictibleOptions() public view returns (MemeOption[] memory) {
        return roundOptionStats[currentPredictionRound];
    }

    /**
     * @dev Gets users prediction stats for current round
     *
     * @param user The address of the user whose predictions we want to fetch.
     *
     * @return memeOptionIndexes The indexes of the memes the user has predicted.
     * @return predictionUpNetAmounts The net amounts (amount - fee) the user has predicted will go up, in wei.
     * @return predictionDownNetAmounts The net amounts (amount - fee) the user has predicted will go down, in wei.
     * @return predictionUpAmounts The sums of actual amounts placed by user in wei, where user predicted will go up.
     * @return predictionDownAmounts The sums of actual amounts placed by user in wei, where user predicted will go down.
     * @return predictionAmounts The sums of actual amounts placed by user in wei.
     */
    function getCurrentPredictions(address user)
        public
        view
        returns (
            uint256[] memory memeOptionIndexes,
            uint256[] memory predictionUpNetAmounts,
            uint256[] memory predictionDownNetAmounts,
            uint256[] memory predictionUpAmounts,
            uint256[] memory predictionDownAmounts,
            uint256[] memory predictionAmounts
        )
    {
        return (
            predictions[currentPredictionRound][user].memeOptionIndexes,
            predictions[currentPredictionRound][user].predictionUpNetAmounts,
            predictions[currentPredictionRound][user].predictionDownNetAmounts,
            predictions[currentPredictionRound][user].predictionUpAmounts,
            predictions[currentPredictionRound][user].predictionDownAmounts,
            predictions[currentPredictionRound][user].predictionAmounts
        );
    }

    /**
     * @dev Gets results for current prediction round, note upon starting new round it will
     *      return empty list. Returns list with results only when round is in resolved state.
     *
     * @return List of bools that correspond to each option index (true means up, false means down)
     */
    function getCurrentRoundResults() public view returns (bool[] memory) {
        return roundResults[currentPredictionRound];
    }

    /**
     * @notice Returns string with odds for prediction index, reward is multiplier of
     *         prediction amount - fee. Multiplier uses currency decimal places (in example we asume its 2)
     *         so 123 is 1.23 multiplier. If your prediction amount is 100 fee is 10 and multiplier is 1.5
     *         then minimum reward is (100 - 10) * 1.5
     *
     * @return memeOptionIndexes list of indexes of meme option indexes. It indicates to what other entries point to.
     * @return upRewardMultipliers list of up rewards multiplers
     * @return downRewardMultipliers list of down rewards multiplers
     */
    function getCurrentRoundOdds()
        public
        view
        returns (
            uint256[] memory memeOptionIndexes,
            uint256[] memory upRewardMultipliers,
            uint256[] memory downRewardMultipliers
        )
    {
        uint256 optionsLength = roundOptionStats[currentPredictionRound].length;
        memeOptionIndexes = new uint256[](optionsLength);
        upRewardMultipliers = new uint256[](optionsLength);
        downRewardMultipliers = new uint256[](optionsLength);

        for (uint256 i = 0; i < roundOptionStats[currentPredictionRound].length; i++) {
            uint256 upAmount = roundOptionStats[currentPredictionRound][i].totalUpAmount;
            uint256 downAmount = roundOptionStats[currentPredictionRound][i].totalDownAmount;
            
            memeOptionIndexes[i] = i;
            if (upAmount > 0) {
                uint256 upWinningAmount = _adjustWinningsForBonus(upAmount, downAmount, upAmount, currentPredictionRound);
                upRewardMultipliers[i] = (upWinningAmount * 10**predictionCurrency.decimals()) / upAmount;
            } else {
                upRewardMultipliers[i] = 0;
            }
            if (downAmount > 0) {
                uint256 downWinningAmount = _adjustWinningsForBonus(downAmount, upAmount, downAmount, currentPredictionRound);
                downRewardMultipliers[i] = (downWinningAmount * 10**predictionCurrency.decimals()) / downAmount;
            } else {
                downRewardMultipliers[i] = 0;
            }
        }
    }

    function isOpen() public view virtual returns (bool) {
        return state == State.InProgress && block.timestamp < openUntil;
    }

    function isWaitingPeriodOver() public view virtual returns (bool) {
        return block.timestamp > waitingUntil;
    }

    function isTimedOut() public view virtual returns (bool) {
        return block.timestamp > timeoutAt;
    }

    /**
     * @dev Funds that are free to withdraw or used for minimum reward payouts.
     *
     * @return amount in wei
     */
    function availableFunds() public view returns (uint256) {
        return predictionCurrency.balanceOf(address(this)) - lockedCurrency;
    }

    /**
     * @dev Used to check contract has enought available funds in contract for resolving current round
     *      with given prediction outcomes.
     *
     * @param predictionOutcomes list of bools that would be used for resolving current prediction round
     * @return bool
     */
    function hasBonusFundsForCurrentRound(bool[] calldata predictionOutcomes) public view returns (bool) {
        return calculateCurrentRequriedFundsForGuaranteedWinnings(predictionOutcomes) <= availableFunds();
    }

    /**
     * @dev Used to check how much funds are needed to be available in contract for resolving current round
     *      with given prediction outcomes. Required funds are used to payout minimum reward bonus.
     *
     * @param predictionOutcomes list of bools that would be used for resolving current prediction round
     * @return Amount needed in wei
     */
    function calculateCurrentRequriedFundsForGuaranteedWinnings(bool[] calldata predictionOutcomes)
        public
        view
        returns (uint256)
    {
        require(
            predictionOutcomes.length == roundOptionStats[currentPredictionRound].length,
            "ERROR: Outcomes needs to have same amount of elements as prediction options"
        );

        uint256 amount = 0;

        for (uint256 i = 0; i < roundOptionStats[currentPredictionRound].length; i++) {
            uint256 upAmount = roundOptionStats[currentPredictionRound][i].totalUpAmount;
            uint256 downAmount = roundOptionStats[currentPredictionRound][i].totalDownAmount;
            uint256 totalAmount = upAmount + downAmount;

            uint256 winning_amount;
            uint256 loosing_amount;

            if (predictionOutcomes[i]) {
                winning_amount = upAmount;
                loosing_amount = downAmount;
            } else {
                winning_amount = downAmount;
                loosing_amount = upAmount;
            }

            if (winning_amount > 0) {
                uint256 adjustedAmount = _adjustWinningsForBonus(
                    winning_amount,
                    loosing_amount,
                    winning_amount,
                    currentPredictionRound
                );
                uint256 missing_amount = adjustedAmount - totalAmount;
                amount += missing_amount;
            }
        }
        return amount;
    }

    /**
     * @notice Calculates amount that can be claimed
     *
     * @param user address of user used for calculation of claimable amount
     * @return claimableAmount amount in wei that can be claimed
     */
    function calculateClaimableAmount(address user) public view returns (uint256) {
        uint256 claimableAmount = 0;
        uint256[] memory unclaimedRounds = unclaimedPredictionRounds[user];
        for (uint256 i = 0; i < unclaimedRounds.length; i++) {
            uint256 unclaimedRound = unclaimedRounds[i];
            if (unclaimedRound == currentPredictionRound && state == State.InProgress) {
                continue;
            }
            uint256 roundClaimableAmount;
            if (roundResults[unclaimedRound].length == 0) {
                roundClaimableAmount = _calculateRefundForCancelledRound(unclaimedRound, user);
            } else {
                roundClaimableAmount = _calculateRewardForRound(unclaimedRound, user);
            }
            claimableAmount += roundClaimableAmount;
        }
        return claimableAmount;
    }

    /**
     * @dev Copies round options from current round to next one,
     *      if stats for next round were not set by setPredictibleOptionsForNextRound.
     */
    function _copyRoundOptionStatsForNextRound() internal {
        if (roundOptionStats[currentPredictionRound + 1].length != 0) {
            return;
        }

        for (uint256 i = 0; i < roundOptionStats[currentPredictionRound].length; i++) {
            string memory memeIdentifier = roundOptionStats[currentPredictionRound][i].identifier;
            roundOptionStats[currentPredictionRound + 1].push(MemeOption(memeIdentifier, i, 0, 0, 0));
        }
    }

    /**
     * @dev Copies balanceRoundBonusReward from current round to next one,
     *      if bonus for next round was not set by setPredictibleOptionsForNextRound.
     */
    function _copybalanceRoundBonusRewardForNextRound() internal {
        if (balanceRoundBonusReward[currentPredictionRound + 1] != 0) {
            return;
        }
        balanceRoundBonusReward[currentPredictionRound + 1] = balanceRoundBonusReward[currentPredictionRound];
    }

    function _calculateRefundForCancelledRound(uint256 round, address user) internal view returns (uint256 amount) {
        amount = 0;
        Predictions memory roundPredictions = predictions[round][user];
        for (uint256 i = 0; i < roundPredictions.predictionNetAmounts.length; i++) {
            amount += roundPredictions.predictionNetAmounts[i];
        }
        amount += roundPredictions.feesCollected;
    }

    function _calculateRewardForRound(uint256 round, address user) internal view returns (uint256 amount) {
        Predictions memory roundPredictions = predictions[round][user];
        for (uint256 i = 0; i < roundPredictions.memeOptionIndexes.length; i++) {
            uint256 memeIndex = roundPredictions.memeOptionIndexes[i];

            bool upIsCorrect = roundResults[round][memeIndex];
            uint256 totalWinningAmount;
            uint256 totalLosingAmount;
            uint256 predictionAmount;
            if (upIsCorrect) {
                totalWinningAmount = roundOptionStats[round][memeIndex].totalUpAmount;
                totalLosingAmount = roundOptionStats[round][memeIndex].totalDownAmount;
                predictionAmount = roundPredictions.predictionUpNetAmounts[i];
            } else {
                totalWinningAmount = roundOptionStats[round][memeIndex].totalDownAmount;
                totalLosingAmount = roundOptionStats[round][memeIndex].totalUpAmount;
                predictionAmount = roundPredictions.predictionDownNetAmounts[i];
            }
            if (totalWinningAmount != 0) {
                amount += _adjustWinningsForBonus(totalWinningAmount, totalLosingAmount, predictionAmount, round);
            }
        }
    }

    function _adjustWinningsForBonus(
        uint256 totalWinningAmount,
        uint256 totalLosingAmount,
        uint256 predictionAmount,
        uint256 round
    ) internal view returns (uint256) {
        uint256 usedBonusReward = _calculateBonus(totalWinningAmount, totalLosingAmount, round);
        uint256 totalPredictionAmount = totalWinningAmount + totalLosingAmount + usedBonusReward;
        uint256 reward = (predictionAmount * totalPredictionAmount) / totalWinningAmount;
        return reward;
    }

    function _calculateBonus(
        uint256 totalWinningAmount,
        uint256 totalLosingAmount,
        uint256 round
    ) internal view returns (uint256) {
        uint256 usedBonusReward = 0;
        if (totalWinningAmount > totalLosingAmount) {
            uint256 diff = totalWinningAmount - totalLosingAmount;
            usedBonusReward = min(diff, balanceRoundBonusReward[round]);
        }
        return usedBonusReward;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a <= b ? a : b;
    }
}
