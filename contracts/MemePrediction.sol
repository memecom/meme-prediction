// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "contracts/ArraySearch.sol";

contract MemePrediction is Ownable, ArraySearch {
    struct MemeOption {
        string identifier;
        uint256 totalUpAmount;
        uint256 totalDownAmount;
    }

    struct Predictions {
        uint256[] memeOptionIndexes;
        uint256[] predictionNetAmounts;
        uint256[] preditionAmounts;
        bool[] isUpPrediction;

        uint256 totalPredictionAmount;
        uint256 feesCollected;
    }

    enum State {
        Open,
        Resolved,
        Cancelled
    }

    mapping(uint256 => MemeOption[]) private optionStats;

    State state = State.Resolved;
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
        require(state == State.Resolved || state == State.Cancelled);
        require(optionStats[currentPredictionRound].length > 0);
        started_at = block.timestamp;
        open_until = block.timestamp + OPEN_PERIOD;
        waiting_until = open_until + WAITING_PERIOD;
        timeout_at = waiting_until + TIMEOUT_FOR_RESOLVING_PREDICTION;
        _copyOptionStatsForNextRound();
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
        require(optionStats[currentPredictionRound].length > memeOptionIndex);

        //TODO: this is wrong user should be able to bet as manytimes he wants until he hits max bet amount
        //      this will force us to add another variable to predictions and make refunding simpler (totalRawAmountPerPrediction)
        uint256[] memory alreadyPredictedMemes = predictions[currentPredictionRound][msg.sender].memeOptionIndexes;
        (bool alreadyPredicted, ) = findElement(alreadyPredictedMemes, memeOptionIndex);

        require(!alreadyPredicted);

        uint256 weiAmount = amount * (10**predictionCurrency.decimals());

        require(weiAmount >= MINIMUM_PREDICTION_AMOUNT);
        require(weiAmount <= MAXIMUM_PREDICTION_AMOUNT);

        uint256 weiFee = (weiAmount * FEE_PERCENTAGE) / 10**FEE_DECIMALS;
        uint256 weiNetAmount = weiAmount - weiFee;

        if (predictionCurrency.transferFrom(msg.sender, address(this), weiAmount)) {
            if (isUpPrediction) {
                optionStats[currentPredictionRound][memeOptionIndex].totalUpAmount += weiNetAmount;
            } else {
                optionStats[currentPredictionRound][memeOptionIndex].totalDownAmount += weiNetAmount;
            }
            predictions[currentPredictionRound][msg.sender].memeOptionIndexes.push(memeOptionIndex);
            predictions[currentPredictionRound][msg.sender].predictionNetAmounts.push(weiNetAmount);
            predictions[currentPredictionRound][msg.sender].isUpPrediction.push(isUpPrediction);
            predictions[currentPredictionRound][msg.sender].feesCollected += weiFee;
            feesCollectedForRound[currentPredictionRound] += weiFee;
            lockedCurrency += weiFee;
            lockedCurrency += weiNetAmount;

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
        require(_predictionOutcomes.length == optionStats[currentPredictionRound].length);
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

            if (roundResults[unclaimedRound].length == 0) {
                uint256 cancelledAmount = _calculateRefundForCancelledRound(unclaimedRound);
                claimedAmount += cancelledAmount;
                lockedCurrency -= cancelledAmount;
            } else {
                Predictions memory roundPredictions = predictions[unclaimedRound][msg.sender];
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
        require(index < optionStats[currentPredictionRound].length);
        totalUpAmount = optionStats[currentPredictionRound][index].totalUpAmount / (10**predictionCurrency.decimals());
        totalDownAmount = optionStats[currentPredictionRound][index].totalDownAmount / (10**predictionCurrency.decimals());
    }

    function getAvailableCurrency() public view returns (uint256) {
        return predictionCurrency.balanceOf(address(this));
    }

    function withdraw(uint256 optionIndex) public {}

    function withdrawAll() public returns (uint256 currentKeyContract) {}

    function setCurrentPredictibleOptions(string[] calldata memeIdentifiers) public onlyOwner {
        require(state == State.Resolved || state == State.Cancelled);
        delete optionStats[currentPredictionRound];
        for (uint256 i = 0; i < memeIdentifiers.length; i++) {
            optionStats[currentPredictionRound].push(MemeOption(memeIdentifiers[i], 0, 0));
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
        return optionStats[currentPredictionRound];
    }

    function getCurrentPredictions() public view returns (Predictions memory) {
        return predictions[currentPredictionRound][msg.sender];
    }

    function _copyOptionStatsForNextRound() private {
        for (uint256 i = 0; i < optionStats[currentPredictionRound].length; i++) {
            string memory memeIdentifier = optionStats[currentPredictionRound][i].identifier;
            optionStats[currentPredictionRound + 1][i] = MemeOption(memeIdentifier, 0, 0);
        }
    }

    function _calculateRefundForCancelledRound(uint256 round) private view returns (uint256 amount) {
        amount = 0;
        Predictions memory roundPredictions = predictions[round][msg.sender];
        for (uint256 i = 0; i < roundPredictions.predictionNetAmounts.length; i++) {
            amount += roundPredictions.predictionNetAmounts[i];
        }
        amount += roundPredictions.feesCollected;
    }

    function _calculateRewardForRound(uint256 round) private view returns (uint256 amount) {
        amount = 0;
        Predictions memory roundPredictions = predictions[round][msg.sender];
        for (uint256 i = 0; i < roundPredictions.predictionNetAmounts.length; i++) {
            uint256 memeIndex = roundPredictions.memeOptionIndexes[i];

            bool isUpPrediction = roundPredictions.isUpPrediction[i];
            bool upIsCorrect = roundResults[round][memeIndex];
            if (upIsCorrect == isUpPrediction) {
                uint256 totalWinningAmount;
                uint256 totalLosingAmount;
                if (upIsCorrect == true) {
                    totalWinningAmount = optionStats[round][memeIndex].totalUpAmount;
                    totalLosingAmount = optionStats[round][memeIndex].totalDownAmount;
                } else {
                    totalWinningAmount = optionStats[round][memeIndex].totalDownAmount;
                    totalLosingAmount = optionStats[round][memeIndex].totalUpAmount;
                }

                uint256 totalPredictionAmount = totalWinningAmount + totalLosingAmount;
                uint256 predictionAmount = roundPredictions.predictionNetAmounts[i];
                amount += (predictionAmount * totalPredictionAmount) / totalWinningAmount;
            }
        }
        amount += roundPredictions.feesCollected;
    }
}
