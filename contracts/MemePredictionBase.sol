// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

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
    mapping(uint256 => bool[]) public roundResults;
    mapping(uint256 => uint256) public feesCollectedForRound;

    uint256 public MINIMUM_PREDICTION_AMOUNT;
    uint256 public MAXIMUM_PREDICTION_AMOUNT;

    // Uses 4 decimal places so 12.34% = 0.1234 = 1234
    uint256 public FEE_PERCENTAGE;
    uint256 public constant FEE_DECIMALS = 4;

    //In seconds
    uint256 public OPEN_PERIOD = 3 * 24 * 60 * 60;
    uint256 public WAITING_PERIOD = 7 * 24 * 60 * 60;
    uint256 public TIMEOUT_FOR_RESOLVING_PREDICTION = 24 * 60 * 60;

    //Timestamps
    uint256 public started_at;
    uint256 public open_until;
    uint256 public waiting_until;
    uint256 public timeout_at;


    function setCurrentPredictibleOptions(string[] calldata memeIdentifiers) public onlyOwner {
        require(state == State.Resolved || state == State.Cancelled);
        delete roundOptionStats[currentPredictionRound];
        for (uint256 i = 0; i < memeIdentifiers.length; i++) {
            roundOptionStats[currentPredictionRound].push(MemeOption(memeIdentifiers[i], 0, 0));
        }
    }

    function setPredictionCurrency(address currencyAddress) public onlyOwner {
        predictionCurrency = IERC20Metadata(currencyAddress);
    }

    function setMinimumPredictionAmount(uint256 amount) public onlyOwner {
        MINIMUM_PREDICTION_AMOUNT = amount * (10**predictionCurrency.decimals());
    }

    function setMaximumPredictionAmount(uint256 amount) public onlyOwner {
        MAXIMUM_PREDICTION_AMOUNT = amount * (10**predictionCurrency.decimals());
    }

    // Uses 2 Decimal palces 12.34% = 1234
    function setFeePercentage(uint256 percentage) public {
        FEE_PERCENTAGE = percentage;
    }

    //TODO MAKE THIS HOURS!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    function setOpenPeriod(uint256 _hours) public {
        OPEN_PERIOD = _hours  * 60;
    }

    //TODO MAKE THIS HOURS!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    function setWaitingPeriod(uint256 _hours) public {
        WAITING_PERIOD = _hours * 60 ;
    }

    //TODO MAKE THIS HOURS!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    function setTimoutLimit(uint256 _hours) public {
        TIMEOUT_FOR_RESOLVING_PREDICTION = _hours * 60;
    }

    function getCurrentPredictibleOptions() public view returns (MemeOption[] memory) {
        return roundOptionStats[currentPredictionRound];
    }

    function getCurrentPredictions() public view returns (Predictions memory) {
        return predictions[currentPredictionRound][msg.sender];
    }

    function isOpen() public view virtual returns (bool){
        return state == State.InProgress && block.timestamp < open_until;
    }

    function isWaitingPeriodOver() public view virtual returns (bool){
        return block.timestamp < waiting_until;
    }

    function isTimedOut() public view virtual returns (bool){
        return block.timestamp < timeout_at;
    }

    function _copyroundOptionStatsForNextRound() internal {
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
                uint256 totalPredictionAmount = totalWinningAmount + totalLosingAmount;
                amount += (predictionAmount * totalPredictionAmount) / totalWinningAmount;
            }
        }
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

        userPredictions.predictionNetAmounts[predictionIndex] = 0;
        userPredictions.predictionUpNetAmounts[predictionIndex] = 0;
        userPredictions.predictionDownNetAmounts[predictionIndex] = 0;
        userPredictions.predictionAmounts[predictionIndex] = 0;
    }
}
