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
        predictionContract.setBalanceRoundBonusRewardForNextRound(40);

        //Initializing prediction round
        predictionContract.startNewPredictionRound();

        predictionContract.setOpenState(true);
        predictionContract.setWaitingPeriodOverState(false);
        predictionContract.setTimedOutState(false);
    }

    
    function checkCalculateCurrentRequriedFundsForGuaranteedWinningsIsCalculatedCorrectly() public {
        predictor_1.predict(predictionContract, 0, 50, true);
        predictor_1.predict(predictionContract, 0, 10, false);
        predictor_1.predict(predictionContract, 1, 100, false);

        bool[] memory outcomes = new bool[](2);
        outcomes[0] = false;
        outcomes[1] = false;
        
        uint256 fundsNeeded = predictionContract.calculateCurrentRequriedFundsForGuaranteedWinnings(outcomes);
        Assert.equal(fundsNeeded, 40 * 10 ** currency.decimals(), "Funds needed should be 40");

        outcomes[0] = false;
        outcomes[1] = true;

        fundsNeeded = predictionContract.calculateCurrentRequriedFundsForGuaranteedWinnings(outcomes);
        Assert.equal(fundsNeeded, 0, "Funds needed should be 0");
        
        outcomes[0] = true;
        outcomes[1] = false;

        fundsNeeded = predictionContract.calculateCurrentRequriedFundsForGuaranteedWinnings(outcomes);
        Assert.equal(fundsNeeded, 76 * 10 ** currency.decimals(), "Funds needed should be 76");
    }

    function checkhasBonusFundsForCurrentRound() public {
        predictor_1.predict(predictionContract, 0, 50, true);
        predictor_1.predict(predictionContract, 0, 10, false);
        predictor_1.predict(predictionContract, 1, 100, false);

        currency.mint(address(predictionContract), 45 * 10 ** currency.decimals());

        bool[] memory outcomes = new bool[](2);
        outcomes[0] = false;
        outcomes[1] = false;

        bool hasFunds = predictionContract.hasBonusFundsForCurrentRound(outcomes);
        Assert.ok(hasFunds, "Should have enought founds");

        outcomes[0] = false;
        outcomes[1] = true;

        hasFunds = predictionContract.hasBonusFundsForCurrentRound(outcomes);
        Assert.ok(hasFunds, "Should have enought founds");

        outcomes[0] = true;
        outcomes[1] = false;

        hasFunds = predictionContract.hasBonusFundsForCurrentRound(outcomes);
        Assert.ok(!hasFunds, "Should not have enought founds");
    }

    function checkOnePredictorPredictsCorrectlyAndBonusAppliedCorrectly() public {
        currency.mint(address(predictionContract), 50 * 10 ** currency.decimals());
        
        predictor_1.predict(predictionContract, 0, 100, true);
        
        Assert.equal(predictionContract.lockedCurrency(), 100 * 10 ** currency.decimals(), "100 should be locked");

        bool[] memory outcomes = new bool[](2);
        outcomes[0] = true;
        outcomes[1] = false;

        predictionContract.setWaitingPeriodOverState(true);

        predictionContract.resolve(outcomes);

        predictionContract.setOpenState(false);

        Assert.equal(predictionContract.lockedCurrency(), 130 * 10 ** currency.decimals(), "Prediction + bonus funds should be locked");
        

        uint256 reward = predictor_1.claim(predictionContract);

        Assert.equal(currency.balanceOf(address(predictor_1)), 1030 * 10 ** currency.decimals(), "Should own 1.5x prediction amount");
        Assert.equal(currency.balanceOf(address(predictionContract)), (10 + 10) * 10 ** currency.decimals(), "Should own fee currency + remaining bonus funds");
        Assert.equal(predictionContract.lockedCurrency(), 0, "No currency should be locked");
        Assert.equal(reward, 130 * 10 ** currency.decimals(), "Reward should be 135");
    }
    
}