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

    function checkWithdawCorrectly() public {
        predictor_1.predict(predictionContract, 0, 100, true);
        predictor_1.predict(predictionContract, 1, 100, true);

        uint256 amout = predictor_1.cancelPrediction(predictionContract, 0);

        Assert.equal(currency.balanceOf(address(predictor_1)), 890 * 10 ** currency.decimals(), "Should lose only fee");
        Assert.equal(currency.balanceOf(address(predictionContract)), 110 * 10 ** currency.decimals(), "Should own fee currency and other prediction amount");
        Assert.equal(predictionContract.lockedCurrency(), 110 * 10 ** currency.decimals(), "Fee and amount should be locked until predictions are resolved");
        Assert.equal(amout, 90  * 10 ** currency.decimals(), "Withdraw amount should be 90");
    }

    function checkWithdawAllCorrectly() public {
        predictor_1.predict(predictionContract, 0, 100, true);
        predictor_1.predict(predictionContract, 1, 100, true);

        uint256 amout = predictor_1.cancelAllPredictions(predictionContract);

        Assert.equal(currency.balanceOf(address(predictor_1)), 980 * 10 ** currency.decimals(), "Should lose only fee");
        Assert.equal(currency.balanceOf(address(predictionContract)), 20 * 10 ** currency.decimals(), "Should own fee currency");
        Assert.equal(predictionContract.lockedCurrency(), 20 * 10 ** currency.decimals(), "Fee should be locked until predictions are resolved");
        Assert.equal(amout, 180  * 10 ** currency.decimals(), "Withdraw amount should be 180");
    }

    function checkCancelledClaimThenReceiveEverything() public {
        predictor_1.predict(predictionContract, 0, 10, true);
        predictor_1.predict(predictionContract, 0, 50, false);
        predictor_1.predict(predictionContract, 1, 100, false);

        predictionContract.cancelPredictionRound();
        predictionContract.setOpenState(false);

        uint256 amout = predictor_1.claim(predictionContract);

        Assert.equal(currency.balanceOf(address(predictor_1)), 1000 * 10 ** currency.decimals(), "Should get all funds");
        Assert.equal(currency.balanceOf(address(predictionContract)), 0, "Should own nothing currency");
        Assert.equal(predictionContract.lockedCurrency(), 0, "There shouldnt be locked anything");
        Assert.equal(amout, 160  * 10 ** currency.decimals(), "Withdraw amount should be 100");
    }

    function checkWithdrawAndThenCancelledClaimThenFeesGetRefunded() public {
        predictor_1.predict(predictionContract, 0, 100, false);
        predictor_1.cancelAllPredictions(predictionContract);

        predictionContract.cancelPredictionRound();
        predictionContract.setOpenState(false);

        uint256 amout = predictor_1.claim(predictionContract);
        Assert.equal(amout, 10  * 10 ** currency.decimals(), "Withdraw amount should be 10");

        Assert.equal(currency.balanceOf(address(predictor_1)), 1000 * 10 ** currency.decimals(), "Should get all funds");
        Assert.equal(currency.balanceOf(address(predictionContract)), 0, "Should own nothing currency");
        Assert.equal(predictionContract.lockedCurrency(), 0, "There shouldnt be locked anything");
    }

    function checkMultiRoundPredictions() public {
        predictor_1.predict(predictionContract, 0, 100, true);
        predictor_2.predict(predictionContract, 0, 100, false);
        predictor_3.predict(predictionContract, 1, 100, false);
        predictor_4.predict(predictionContract, 1, 100, false);

        predictor_4.cancelAllPredictions(predictionContract);
        
        predictionContract.setWaitingPeriodOverState(true);

        bool[] memory outcomes = new bool[](2);
        outcomes[0] = true;
        outcomes[1] = false;

        predictionContract.resolve(outcomes);

        Assert.equal(predictionContract.lockedCurrency(), 270 * 10 ** currency.decimals(), "There should be 270 locked");

        predictionContract.startNewPredictionRound();

        predictionContract.setOpenState(true);
        predictionContract.setWaitingPeriodOverState(true);

        predictionContract.resolve(outcomes);

        predictionContract.setOpenState(false);

        predictionContract.startNewPredictionRound();

        predictionContract.setOpenState(true);

        predictor_1.predict(predictionContract, 0, 100, true);
        predictor_2.predict(predictionContract, 0, 100, false);

        uint256 reward_2 = predictor_2.claim(predictionContract);
        uint256 reward_3 = predictor_3.claim(predictionContract);

        Assert.equal(predictionContract.lockedCurrency(), 380 * 10 ** currency.decimals(), "There shouldn be 380 locked");


        predictionContract.setOpenState(true);
        predictionContract.setWaitingPeriodOverState(true);

        predictionContract.resolve(outcomes);

        predictionContract.setOpenState(false);

        Assert.equal(predictionContract.lockedCurrency(), 360 * 10 ** currency.decimals(), "There shouldn be 180 locked");

        uint256 reward_1 = predictor_1.claim(predictionContract);

        
        Assert.equal(reward_1, 360  * 10 ** currency.decimals(), "claimed reward amount should be 360");
        Assert.equal(reward_2, 0, "Claimed reward should be 0");
        Assert.equal(reward_3, 90 * 10 ** currency.decimals(), "Claimed reward should be 90");

        Assert.equal(currency.balanceOf(address(predictor_1)), 1160 * 10 ** currency.decimals(), "Should get 1160");
        Assert.equal(currency.balanceOf(address(predictor_2)), 800 * 10 ** currency.decimals(), "Should get 800");
        Assert.equal(currency.balanceOf(address(predictor_3)), 990 * 10 ** currency.decimals(), "Should get 990");
        Assert.equal(currency.balanceOf(address(predictor_4)), 990 * 10 ** currency.decimals(), "Should get 990");
        Assert.equal(currency.balanceOf(address(predictionContract)), 60 * 10 ** currency.decimals(), "Should own 60 from fees");
        Assert.equal(predictionContract.lockedCurrency(), 0, "There shouldnt be locked anything");
    }

    
}