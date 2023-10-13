// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@openzeppelin/contracts@4.5.0/access/Ownable.sol";
import "@openzeppelin/contracts@4.5.0/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts@4.5.0/utils/Strings.sol";

import "contracts/ArraySearch.sol";

contract MemePredictionBase is Ownable, ArraySearch {
    struct MemeOption {
        string identifier;
        uint256 totalUpAmount;
        uint256 totalDownAmount;
    }

    struct Predictions {
        uint256[] memeOptionIndexes;
        uint256[] predictionUpNetAmounts;
        uint256[] predictionDownNetAmounts;
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

    mapping(uint256 => uint256) public minimumRoundPredictionReward;
    uint256 public ODDS_DECIMALS = 2;

    uint256 public MINIMUM_PREDICTION_AMOUNT;
    uint256 public MAXIMUM_PREDICTION_AMOUNT;

    // Uses 4 decimal places so 12.34% = 0.1234 = 1234
    uint256 public FEE_PERCENTAGE;
    uint256 public constant FEE_DECIMALS = 4;

    //In seconds
    uint256 internal OPEN_PERIOD = 3 * 24 * 60 * 60;
    uint256 internal WAITING_PERIOD = 7 * 24 * 60 * 60;
    uint256 internal TIMEOUT_FOR_RESOLVING_PREDICTION = 24 * 60 * 60;

    //Timestamps
    uint256 public started_at;
    uint256 public open_until;
    uint256 public waiting_until;
    uint256 public timeout_at;

    function setPredictibleOptionsForNextRound(string[] calldata memeIdentifiers) public onlyOwner {
        require(state == State.Resolved || state == State.Cancelled);
        delete roundOptionStats[currentPredictionRound + 1];
        for (uint256 i = 0; i < memeIdentifiers.length; i++) {
            roundOptionStats[currentPredictionRound + 1].push(MemeOption(memeIdentifiers[i], 0, 0));
        }
    }

    function setMinimumPredictionAmount(uint256 amount) public onlyOwner {
        MINIMUM_PREDICTION_AMOUNT = amount * (10**predictionCurrency.decimals());
    }

    function setMaximumPredictionAmount(uint256 amount) public onlyOwner {
        MAXIMUM_PREDICTION_AMOUNT = amount * (10**predictionCurrency.decimals());
    }

    // Uses 4 decimal places so 12.34% = 0.1234 = 1234
    function setFeePercentage(uint256 percentage) public {
        FEE_PERCENTAGE = percentage;
    }

    //TODO MAKE THIS HOURS!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    function setOpenPeriod(uint256 _hours) public {
        OPEN_PERIOD = _hours * 60 * 60;
    }

    //TODO MAKE THIS HOURS!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    function setWaitingPeriod(uint256 _hours) public {
        WAITING_PERIOD = _hours * 60 * 60;
    }

    //TODO MAKE THIS HOURS!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    function setTimoutLimit(uint256 _hours) public {
        TIMEOUT_FOR_RESOLVING_PREDICTION = _hours * 60 * 60;
    }

    function getOpenPeriod() public view returns (uint256){
        return OPEN_PERIOD / (60 * 60);
    }

    function getWaitingPeriod() public view returns (uint256){
        return WAITING_PERIOD / (60 * 60);
    }

    function getTimoutForResolvingPrediction() public view returns (uint256){
        return TIMEOUT_FOR_RESOLVING_PREDICTION / (60 * 60);
    }

    // Uses 2 decimal places so 1.23 = 1234
    function setCurrentRoundMinimumPredictionReward(uint256 minimumReward) public {
        minimumRoundPredictionReward[currentPredictionRound] = minimumReward;
    }

    function getCurrentPredictibleOptions() public view returns (MemeOption[] memory) {
        return roundOptionStats[currentPredictionRound];
    }

    function getCurrentPredictions() public view returns (Predictions memory) {
        return predictions[currentPredictionRound][msg.sender];
    }

    function getCurrentRoundResults() public view returns (bool[] memory) {
        return roundResults[currentPredictionRound];
    }

    function getCurrentRoundOdds() public view returns (string memory) {
        string memory odds;
        for (uint256 i = 0; i < roundOptionStats[currentPredictionRound].length; i++) {
            uint256 upAmount = roundOptionStats[currentPredictionRound][i].totalUpAmount;
            uint256 downAmount = roundOptionStats[currentPredictionRound][i].totalDownAmount;
            uint256 totalAmount = upAmount + downAmount;
            uint256 upReward;
            uint256 downReward;
            if (upAmount > 0) {
                upReward = ((totalAmount * 10**ODDS_DECIMALS) / upAmount);
            }
            if (downAmount > 0) {
                downReward = ((totalAmount * 10**ODDS_DECIMALS) / downAmount);
            }
            odds = string.concat(odds, roundOptionStats[currentPredictionRound][i].identifier);
            odds = string.concat(odds, "\n\tUp predictions wins reward: ");
            odds = string.concat(odds, Strings.toString(upReward));
            odds = string.concat(odds, "\n\tDown predictions wins reward: ");
            odds = string.concat(odds, Strings.toString(downReward));
            odds = string.concat(odds, "\n");
        }

        return odds;
    }

    function isOpen() public view virtual returns (bool) {
        return state == State.InProgress && block.timestamp < open_until;
    }

    function isWaitingPeriodOver() public view virtual returns (bool) {
        return block.timestamp > waiting_until;
    }

    function isTimedOut() public view virtual returns (bool) {
        return block.timestamp > timeout_at;
    }

    function availableFounds() public view returns (uint256) {
        return predictionCurrency.balanceOf(address(this)) - lockedCurrency;
    }

    function hasBonusFundsForCurrentRound(bool[] calldata _predictionOutcomes) public view returns (bool) {
        return calculateCurrentRequriedFundsForGuaranteedWinnings(_predictionOutcomes) <= availableFounds();
    }

    function calculateCurrentRequriedFundsForGuaranteedWinnings(bool[] calldata _predictionOutcomes)
        public
        view
        returns (uint256)
    {
        require(
            _predictionOutcomes.length == roundOptionStats[currentPredictionRound].length,
            "ERROR: Outcomes needs to have same amount of elements as prediction options"
        );

        uint256 amount = 0;

        for (uint256 i = 0; i < roundOptionStats[currentPredictionRound].length; i++) {
            uint256 upAmount = roundOptionStats[currentPredictionRound][i].totalUpAmount;
            uint256 downAmount = roundOptionStats[currentPredictionRound][i].totalDownAmount;
            uint256 totalAmount = upAmount + downAmount;

            uint256 winning_amount;
            uint256 loosing_amount;

            if (_predictionOutcomes[i]) {
                winning_amount = upAmount;
                loosing_amount = downAmount;
            }
            if (!_predictionOutcomes[i]) {
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
    * @dev Copies round options from current round to next one, 
    *      if stats for next round were not set by setPredictibleOptionsForNextRound.
    */
    function _copyRoundOptionStatsForNextRound() internal {
        if (roundOptionStats[currentPredictionRound + 1].length != 0){
            return;
        }
        
        for (uint256 i = 0; i < roundOptionStats[currentPredictionRound].length; i++) {
            string memory memeIdentifier = roundOptionStats[currentPredictionRound][i].identifier;
            roundOptionStats[currentPredictionRound + 1].push(MemeOption(memeIdentifier, 0, 0));
        }
    }

    function _calculateRefundForCancelledRound(uint256 round) internal view returns (uint256 amount) {
        amount = 0;
        Predictions memory roundPredictions = predictions[round][msg.sender];
        for (uint256 i = 0; i < roundPredictions.predictionNetAmounts.length; i++) {
            amount += roundPredictions.predictionNetAmounts[i];
        }
        amount += roundPredictions.feesCollected;
    }

    function _calculateRewardForRound(uint256 round) internal view returns (uint256 amount) {
        Predictions memory roundPredictions = predictions[round][msg.sender];
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
        uint256 totalPredictionAmount = totalWinningAmount + totalLosingAmount;
        uint256 baseReward = (predictionAmount * totalPredictionAmount) / totalWinningAmount;
        uint256 minimumReward = (predictionAmount * minimumRoundPredictionReward[round]) / 10**ODDS_DECIMALS;
        if (baseReward > minimumReward) {
            return baseReward;
        }
        return minimumReward;
    }

    function _addNewPrediction(
        uint256 memeOptionIndex,
        uint256 weiAmount,
        uint256 weiNetAmount,
        uint256 weiFee,
        bool isUpPrediction
    ) internal {
        predictions[currentPredictionRound][msg.sender].memeOptionIndexes.push(memeOptionIndex);

        if (isUpPrediction) {
            predictions[currentPredictionRound][msg.sender].predictionUpNetAmounts.push(weiNetAmount);
            predictions[currentPredictionRound][msg.sender].predictionDownNetAmounts.push(0);
        } else {
            predictions[currentPredictionRound][msg.sender].predictionUpNetAmounts.push(0);
            predictions[currentPredictionRound][msg.sender].predictionDownNetAmounts.push(weiNetAmount);
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
        } else {
            predictions[currentPredictionRound][msg.sender].predictionDownNetAmounts[index] += weiNetAmount;
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
        userPredictions.predictionAmounts[predictionIndex] = 0;
    }
}
