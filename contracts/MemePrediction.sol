// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "contracts/ArraySearch.sol";




contract MemePrediction is Ownable, ArraySearch {
    event DebugUint256(uint256 value);
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
        Open,
        Resolved,
        Cancelled
    }

    mapping(uint256 => MemeOption[]) private roundOptionStats;

    State public state = State.Resolved;
    uint256 public currentPredictionRound = 0;
    uint256 public lockedCurrency;

    IERC20Metadata public predictionCurrency;

    mapping(uint256 => mapping(address => Predictions)) private predictions;
    mapping(address => uint256[]) public unclaimedPredictionRounds;
    mapping(uint256 => bool[]) public roundResults;
    mapping(uint256 => uint256) public feesCollectedForRound;

    //TODO: Add set of participants for given round

    uint256 public MINIMUM_PREDICTION_AMOUNT;
    uint256 public MAXIMUM_PREDICTION_AMOUNT;

    // Uses 2 decimal places so 12.34% = 1234
    uint256 public FEE_PERCENTAGE;
    uint256 public constant FEE_DECIMALS = 2;

    //In seconds
    uint256 public OPEN_PERIOD = 3 * 24 * 60 * 60;
    uint256 public WAITING_PERIOD = 7 * 24 * 60 * 60;
    uint256 public TIMEOUT_FOR_RESOLVING_PREDICTION = 24 * 60 * 60;

    //Timestamps
    uint256 public started_at;
    uint256 public open_until;
    uint256 public waiting_until;
    uint256 public timeout_at;

    function startNewPredictionRound() public {
        require(state == State.Resolved || state == State.Cancelled, "ERROR: Cannot start new prediction round until last one is resolved or cancelled");
        require(roundOptionStats[currentPredictionRound].length > 0, "ERRPR: There needs to be atleast one prediction option");
        started_at = block.timestamp;
        open_until = block.timestamp + OPEN_PERIOD;
        waiting_until = open_until + WAITING_PERIOD;
        timeout_at = waiting_until + TIMEOUT_FOR_RESOLVING_PREDICTION;
        _copyroundOptionStatsForNextRound();
        state = State.Open;
        currentPredictionRound += 1;

        //TODO: Emit
    }

    function predict(
        uint256 memeOptionIndex,
        uint256 amount,
        bool isUpPrediction
    ) public {
        require(state == State.Open);
        require(block.timestamp < open_until);
        require(roundOptionStats[currentPredictionRound].length > memeOptionIndex);

        uint256[] memory alreadyPredictedMemes = predictions[currentPredictionRound][msg.sender].memeOptionIndexes;
        (bool alreadyPredicted, uint256 predictionIndex) = findElement(alreadyPredictedMemes, memeOptionIndex);

        uint256 weiAmount = amount * (10**predictionCurrency.decimals());
        uint256 currentTotalAmount = 0;
        if (alreadyPredicted) {
            currentTotalAmount = predictions[currentPredictionRound][msg.sender].predictionAmounts[predictionIndex];
        }
        require(weiAmount >= MINIMUM_PREDICTION_AMOUNT);
        require(weiAmount + currentTotalAmount <= MAXIMUM_PREDICTION_AMOUNT);

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
            //TODO: Emit
        }
    }

    // True means up outcome won
    function resolve(bool[] calldata _predictionOutcomes) public {
        require(_predictionOutcomes.length == roundOptionStats[currentPredictionRound].length);
        require(block.timestamp > waiting_until);
        //TODO: When implementing bonus, check for sufficient aviable funds

        state = State.Resolved;
        roundResults[currentPredictionRound] = _predictionOutcomes;
        lockedCurrency -= feesCollectedForRound[currentPredictionRound];
        //TODO: Emit
    }

    function claim() public returns (uint256 claimedAmount) {
        claimedAmount = 0;
        uint256[] memory unclaimedRounds = unclaimedPredictionRounds[msg.sender];
        for (uint256 i = 0; i < unclaimedRounds.length; i++) {
            uint256 unclaimedRound = unclaimedRounds[i];
            if (unclaimedRound == currentPredictionRound && state == State.Open) {
                continue;
            }

            Predictions memory roundPredictions = predictions[unclaimedRound][msg.sender];
            if (roundResults[unclaimedRound].length == 0) {
                uint256 cancelledAmount = _calculateRefundForCancelledRound(unclaimedRound);
                claimedAmount += cancelledAmount;
                lockedCurrency -= cancelledAmount;
            } else {
                uint256 wonAmount = _calculateRewardForRound(unclaimedRound);
                claimedAmount += wonAmount;
                lockedCurrency -= wonAmount;
                lockedCurrency -= roundPredictions.feesCollected;
            }
        }
        if (!predictionCurrency.transferFrom(address(this), msg.sender, claimedAmount)) {
            revert();
        }
        //TODO: Emit
    }

    function cancel() public {
        require(state != State.Resolved);
        require(msg.sender == this.owner() || block.timestamp > timeout_at);

        state = State.Cancelled;
        //TODO: Emit
    }

    function getCurrentOdds(uint256 index) public view returns (uint256 totalUpAmount, uint256 totalDownAmount) {
        require(index < roundOptionStats[currentPredictionRound].length);
        totalUpAmount = roundOptionStats[currentPredictionRound][index].totalUpAmount / (10**predictionCurrency.decimals());
        totalDownAmount = roundOptionStats[currentPredictionRound][index].totalDownAmount / (10**predictionCurrency.decimals());
    }

    function getAvailableCurrency() public view returns (uint256) {
        return predictionCurrency.balanceOf(address(this));
    }

    // NOTE: Keeps the fee
    function withdraw(uint256 optionIndex) public returns (uint256) {
        require(state == State.Open);

        uint256[] memory alreadyPredictedMemes = predictions[currentPredictionRound][msg.sender].memeOptionIndexes;
        (bool predicted, uint256 predictionIndex) = findElement(alreadyPredictedMemes, optionIndex);
        require(predicted);

        Predictions storage userPredictions = predictions[currentPredictionRound][msg.sender];
        uint256 amountToWithdraw = userPredictions.predictionNetAmounts[predictionIndex];

        if (predictionCurrency.transferFrom(address(this), msg.sender, amountToWithdraw)) {
            uint256 upNetAmount = userPredictions.predictionUpNetAmounts[predictionIndex];
            uint256 downNetAmount = userPredictions.predictionDownNetAmounts[predictionIndex];

            _storeWithdrawal(predictionIndex, optionIndex);

            userPredictions.totalPredictionAmount -= amountToWithdraw;
            userPredictions.totalPredictionNetAmount -= amountToWithdraw;
            lockedCurrency -= amountToWithdraw;

            return amountToWithdraw;
        }

        revert("Withdrawal failed");
    }

    function withdrawAll() public returns (uint256) {
        require(state == State.Open);

        Predictions storage userPredictions = predictions[currentPredictionRound][msg.sender];
        uint256 amountToWithdraw = userPredictions.totalPredictionNetAmount;

        if (predictionCurrency.transferFrom(address(this), msg.sender, amountToWithdraw)) {
            for (uint256 i = 0; i < userPredictions.memeOptionIndexes.length; i++) {
                _storeWithdrawal(i, userPredictions.memeOptionIndexes[i]);
            }

            userPredictions.totalPredictionAmount = 0;
            userPredictions.totalPredictionNetAmount = 0;
            lockedCurrency -= amountToWithdraw;

            return amountToWithdraw;
        }

        revert("Withdrawal failed");
    }

    function setCurrentPredictibleOptions(string[] calldata memeIdentifiers) public onlyOwner {
        delete roundOptionStats[currentPredictionRound];
        for (uint256 i = 0; i < memeIdentifiers.length; i++) {
            emit DebugUint256(i);
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

    function setOpenPeriod(uint256 _hours) public {
        OPEN_PERIOD = _hours * 60 * 60;
    }

    function setWaitingPeriod(uint256 _hours) public {
        WAITING_PERIOD = _hours * 60 * 60;
    }

    function setTimoutLimit(uint256 _hours) public {
        TIMEOUT_FOR_RESOLVING_PREDICTION = _hours * 60 * 60;
    }

    function getCurrentPredictibleOptions() public view returns (MemeOption[] memory) {
        return roundOptionStats[currentPredictionRound];
    }

    function getCurrentPredictions() public view returns (Predictions memory) {
        return predictions[currentPredictionRound][msg.sender];
    }

    function _copyroundOptionStatsForNextRound() private {
        for (uint256 i = 0; i < roundOptionStats[currentPredictionRound].length; i++) {
            string memory memeIdentifier = roundOptionStats[currentPredictionRound][i].identifier;
            roundOptionStats[currentPredictionRound + 1].push(MemeOption(memeIdentifier, 0, 0));
        }
    }

    function _calculateRefundForCancelledRound(uint256 round) private view returns (uint256 amount) {
        amount = 0;
        Predictions memory roundPredictions = predictions[round][msg.sender];
        for (uint256 i = 0; i < roundPredictions.predictionAmounts.length; i++) {
            amount += roundPredictions.predictionAmounts[i];
        }
    }

    function _calculateRewardForRound(uint256 round) private view returns (uint256 amount) {
        amount = 0;
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
            uint256 totalPredictionAmount = totalWinningAmount + totalLosingAmount;
            amount += (predictionAmount * totalPredictionAmount) / totalWinningAmount;
        }
    }

    function _addNewPrediction(
        uint256 memeOptionIndex,
        uint256 weiAmount,
        uint256 weiNetAmount,
        uint256 weiFee,
        bool isUpPrediction
    ) private {
        predictions[currentPredictionRound][msg.sender].memeOptionIndexes.push(memeOptionIndex);

        if (isUpPrediction) {
            predictions[currentPredictionRound][msg.sender].predictionUpNetAmounts.push(weiNetAmount);
        } else {
            predictions[currentPredictionRound][msg.sender].predictionDownNetAmounts.push(weiNetAmount);
        }
        predictions[currentPredictionRound][msg.sender].predictionNetAmounts.push(weiNetAmount);
        predictions[currentPredictionRound][msg.sender].predictionAmounts.push(weiAmount);

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
    ) private {
        if (isUpPrediction) {
            predictions[currentPredictionRound][msg.sender].predictionUpNetAmounts[index] += weiNetAmount;
        } else {
            predictions[currentPredictionRound][msg.sender].predictionDownNetAmounts[index] += weiNetAmount;
        }
        predictions[currentPredictionRound][msg.sender].predictionNetAmounts[index] += weiNetAmount;
        predictions[currentPredictionRound][msg.sender].predictionAmounts[index] += weiAmount;

        predictions[currentPredictionRound][msg.sender].feesCollected += weiFee;
        feesCollectedForRound[currentPredictionRound] += weiFee;
        lockedCurrency += weiFee;
        lockedCurrency += weiNetAmount;
    }

    function _storeWithdrawal(uint256 predictionIndex, uint256 optionIndex) private {
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
