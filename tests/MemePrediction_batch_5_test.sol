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
import "@openzeppelin/contracts@4.5.0/token/ERC20/presets/ERC20PresetMinterPauser.sol";
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

        string[] memory predictibleOptions = new string[](2);
        predictibleOptions[0] = "MEME";
        predictibleOptions[1] = "CHAD";
        predictionContract.setPredictibleOptionsForNextRound(predictibleOptions);
        predictionContract.setFeePercentage(1000);
        predictionContract.setOpenPeriod(1);
        predictionContract.setWaitingPeriod(1);
        predictionContract.setTimoutLimit(1);

        predictionContract.setMinimumPredictionAmount(10);
        predictionContract.setMaximumPredictionAmount(100);

        //Initializing prediction round
        predictionContract.startNewPredictionRound();

        predictionContract.setOpenState(true);
        predictionContract.setWaitingPeriodOverState(false);
        predictionContract.setTimedOutState(false);
    }

    function checkPredictionRoundInitializedCorrectly() public {

        Assert.ok(predictionContract.state() == MemePredictionBase.State.InProgress, "Contract round should be in progress");
        Assert.equal(predictionContract.currentPredictionRound(), 1, "Should be first prediction round");
        Assert.equal(predictionContract.FEE_PERCENTAGE(), 1000, "Fee should be 10%");
        Assert.equal(predictionContract.getOpenPeriod(), 1, "Open period should be 1 hour");
        Assert.equal(predictionContract.getWaitingPeriod(), 1, "Waiting period should be 1 hour");
        Assert.equal(predictionContract.getTimoutForResolvingPrediction(), 1, "Timiout period should be 1 hour");
    
        Assert.equal(predictionContract.open_until(), predictionContract.started_at() + 60 * 60, "Should be open till 1 hour");
        Assert.equal(predictionContract.waiting_until(), predictionContract.started_at() + 2 * 60 * 60, "Should be waiting till 2 hours");
        Assert.equal(predictionContract.timeout_at(), predictionContract.started_at() + 3 * 60 * 60, "Should timeout in 3 hours");
    
        Assert.equal(predictionContract.getCurrentPredictibleOptions().length, 2, "Should have 2 predictible options");
    }

    function checkMultiRoundPredictionsWithBonusEnabled() public {
        predictionContract.setCurrentRoundMinimumPredictionReward(150);
        predictor_1.predict(predictionContract, 0, 100, true);
        predictor_2.predict(predictionContract, 0, 100, false);
        predictor_3.predict(predictionContract, 1, 100, false);
        predictor_4.predict(predictionContract, 1, 100, false);
        
        predictionContract.setWaitingPeriodOverState(true);

        bool[] memory outcomes = new bool[](2);
        outcomes[0] = true;
        outcomes[1] = true;

        predictionContract.resolve(outcomes);
        predictionContract.setOpenState(false);

        Assert.equal(predictionContract.lockedCurrency(), 180 * 10 ** currency.decimals(), "There should be 180 locked");
        Assert.equal(predictionContract.availableFounds(), 220 * 10 ** currency.decimals(), "There should be 220 available");
        
        
        uint256 reward_1 = predictor_1.claim(predictionContract);

        Assert.equal(reward_1, 180 * 10 ** currency.decimals(), "Reward should be 180");
        Assert.equal(currency.balanceOf(address(predictor_1)), 1080 * 10 ** currency.decimals(), "Should own 1080 from reward");
        Assert.equal(currency.balanceOf(address(predictionContract)), 220 * 10 ** currency.decimals(), "Should own 220 from fees and loosing side");
        Assert.equal(predictionContract.availableFounds(), 220 * 10 ** currency.decimals(), "There should be no locked currency so it should have access to all funds");
        Assert.equal(predictionContract.lockedCurrency(), 0, "There should be no locked currency");

        predictionContract.startNewPredictionRound();

        predictionContract.setOpenState(true);
        predictionContract.setWaitingPeriodOverState(true);

        predictionContract.resolve(outcomes);

        predictionContract.setOpenState(false);

        predictionContract.startNewPredictionRound();

        predictionContract.setOpenState(true);

        predictor_1.predict(predictionContract, 0, 10, true);
        predictor_2.predict(predictionContract, 0, 10, true);

        predictionContract.resolve(outcomes);

        predictionContract.setOpenState(false);

        Assert.equal(predictionContract.availableFounds(), 213 * 10 ** currency.decimals(), "There should be 213 available");
        Assert.equal(predictionContract.lockedCurrency(), 27 * 10 ** currency.decimals(), "There should be 27 locked");

        predictor_1.claim(predictionContract);
        predictor_2.claim(predictionContract);

        Assert.equal(predictionContract.lockedCurrency(), 0, "There should be no locked currency");
        Assert.equal(predictionContract.availableFounds(), 213 * 10 ** currency.decimals(), "There should be 213 available");

        predictionContract.startNewPredictionRound();

        predictionContract.setOpenState(true);

        predictionContract.setCurrentRoundMinimumPredictionReward(250);

        predictor_1.predict(predictionContract, 0, 10, true);
        predictor_2.predict(predictionContract, 0, 10, true);

        predictionContract.resolve(outcomes);

        predictionContract.setOpenState(false);

        Assert.equal(predictionContract.availableFounds(), 188 * 10 ** currency.decimals(), "There should be 168 available");
        Assert.equal(predictionContract.lockedCurrency(), 45 * 10 ** currency.decimals(), "There should be 45 locked");

        predictor_1.claim(predictionContract);
        predictor_2.claim(predictionContract);

        Assert.equal(predictionContract.lockedCurrency(), 0, "There should be no locked currency");
        Assert.equal(predictionContract.availableFounds(), 188 * 10 ** currency.decimals(), "There should be 168 available");

        Assert.equal(currency.balanceOf(address(predictor_1)), 1096 * 10 ** currency.decimals(), "Should own 1098 from reward");
        Assert.equal(currency.balanceOf(address(predictor_2)), 916 * 10 ** currency.decimals(), "Should own 1098 from reward");
    }

}