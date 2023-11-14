// SPDX-License-Identifier: GPL-3.0
        
pragma solidity >=0.4.22 <0.9.0;

// This import is automatically injected by Remix
import "remix_tests.sol"; 

// This import is required to use custom transaction context
// Although it may fail compilation in 'Solidity Compiler' plugin
// But it will work fine in 'Solidity Unit Testing' plugin
import "remix_accounts.sol";
import "../contracts/MemePrediction.sol";
import "../testContracts/TestMemePrediction.sol";
import "testContracts/PredictorWrapper.sol";


// File name has to end with '_test.sol', this file can contain more than one testSuite contracts
contract testSuite {
    TestMemePrediction public predictionContract;
    ERC20PresetMinterPauser public currency;

    PredictorWrapper predictor_1;
    PredictorWrapper predictor_2;
    PredictorWrapper predictor_3;
    PredictorWrapper predictor_4;


    /// 'beforeAll' runs before all other tests
    /// More special functions are: 'beforeEach', 'beforeAll', 'afterEach' & 'afterAll'
    function beforeEach() public {
        currency = new ERC20PresetMinterPauser("MEMECOIN", "MEM");
        predictionContract = new TestMemePrediction(address(currency));

        predictor_1 = new PredictorWrapper();
        predictor_2 = new PredictorWrapper();
        predictor_3 = new PredictorWrapper();
        predictor_4 = new PredictorWrapper();
        uint256 amount =  1000 * 10 ** currency.decimals();
        currency.mint(address(predictor_1), amount);
        currency.mint(address(predictor_2), amount);
        currency.mint(address(predictor_3), amount);
        currency.mint(address(predictor_4), amount);

        predictor_1.approveERC20(currency, address(predictionContract), amount);
        predictor_2.approveERC20(currency, address(predictionContract), amount);
        predictor_3.approveERC20(currency, address(predictionContract), amount);
        predictor_4.approveERC20(currency, address(predictionContract), amount);

        string[] memory predictibleOptions = new string[](1);
        predictibleOptions[0] = "MEME";
        predictionContract.setPredictibleOptionsForNextRound(predictibleOptions);
        predictionContract.setFeePercentage(1000);
        predictionContract.setOpenPeriod(1);
        predictionContract.setWaitingPeriod(1);
        predictionContract.setTimoutLimit(1);


        predictionContract.setMinimumPredictionAmount(1);
        predictionContract.setMaximumPredictionAmount(100);

        predictionContract.setBalanceRoundBonusRewardForNextRound(10);

        //Initializing prediction round
        predictionContract.startNewPredictionRound();

        predictionContract.setOpenState(true);
        predictionContract.setWaitingPeriodOverState(false);
        predictionContract.setTimedOutState(false);
    }

    function checkPredictSameAmountAgainstEachotherCalculatesOddsCorrectly() public {
        predictor_1.predict(predictionContract, 0, 10, true);
        predictor_2.predict(predictionContract, 0, 10, false);

        (uint256[] memory memeOptionIndexes, uint256[] memory upRewardMultipliers, uint256[] memory downRewardMultipliers) = predictionContract.getCurrentRoundOdds();

        Assert.equal(memeOptionIndexes.length, 1, "There should be values for 1 option");
        Assert.equal(upRewardMultipliers[0], 2 * 10 ** currency.decimals(), "Odds for UP should be 2x");
        Assert.equal(downRewardMultipliers[0], 2 * 10 ** currency.decimals(), "Odds for DOWN should be 2x");
    }

    function checkPredictSameAmountOnSameOutcomeWithRewardCoveringCompletelyCalculatesOddsCorrectly() public {
        predictor_1.predict(predictionContract, 0, 5, true);
        predictor_2.predict(predictionContract, 0, 5, true);

        (uint256[] memory memeOptionIndexes, uint256[] memory upRewardMultipliers, uint256[] memory downRewardMultipliers) = predictionContract.getCurrentRoundOdds();

        Assert.equal(memeOptionIndexes.length, 1, "There should be values for 1 option");
        Assert.equal(upRewardMultipliers[0], 2 * 10 ** currency.decimals(), "Odds for UP should be 2x");
        Assert.equal(downRewardMultipliers[0], 0, "Odds for DOWN should be 0");
    }

    function checkPredictSameAmountOnSameOutcomeWithRewardCoveringPartialyCalculatesOddsCorrectly() public {
        predictor_1.predict(predictionContract, 0, 20, true);
        predictor_2.predict(predictionContract, 0, 20, true);

        (uint256[] memory memeOptionIndexes, uint256[] memory upRewardMultipliers, uint256[] memory downRewardMultipliers) = predictionContract.getCurrentRoundOdds();

        Assert.equal(memeOptionIndexes.length, 1, "There should be values for 1 option");
        bool isUpInRange = upRewardMultipliers[0] < 128 * 10 ** (currency.decimals() - 2) && upRewardMultipliers[0] > 127 * 10 ** (currency.decimals() - 2);
        Assert.ok(isUpInRange , "Odds for UP should be approximatly ~1.277x");
        Assert.equal(downRewardMultipliers[0], 0, "Odds for DOWN should be 0");
    }

    function checkPredictDiferentAmountOnDifferentOutcomesWithRewardCoveringPartialyCalculatesOddsCorrectly() public {
        predictor_1.predict(predictionContract, 0, 100, true);
        predictor_2.predict(predictionContract, 0, 10, false);

        (uint256[] memory memeOptionIndexes, uint256[] memory upRewardMultipliers, uint256[] memory downRewardMultipliers) = predictionContract.getCurrentRoundOdds();

        Assert.equal(memeOptionIndexes.length, 1, "There should be values for 1 option");
        bool isUpInRange = upRewardMultipliers[0] < 122 * 10 ** (currency.decimals() - 2) && upRewardMultipliers[0] > 121 * 10 ** (currency.decimals() - 2);
        Assert.ok(isUpInRange , "Odds for UP should be approximatly ~1.211x");
        Assert.equal(downRewardMultipliers[0], 11 * 10 ** currency.decimals(), "Odds for DOWN should be 11x");
    }

    function checkPredictDiferentAmountOnDifferentOutcomesWithRewardCoveringCompletelyCalculatesOddsCorrectly() public {
        predictor_1.predict(predictionContract, 0, 10, true);
        predictor_2.predict(predictionContract, 0, 1, false);

        (uint256[] memory memeOptionIndexes, uint256[] memory upRewardMultipliers, uint256[] memory downRewardMultipliers) = predictionContract.getCurrentRoundOdds();

        Assert.equal(memeOptionIndexes.length, 1, "There should be values for 1 option");
        Assert.equal(upRewardMultipliers[0], 2 * 10 ** currency.decimals(), "Odds for UP should be 2x");
        Assert.equal(downRewardMultipliers[0], 11 * 10 ** currency.decimals(), "Odds for DOWN should be 11x");
    }
    
}
