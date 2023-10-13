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
import "../testContracts/CustomAssert.sol";
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

    function checkThreePredictorPredictsCorrectlyOtherNotWholeAmounts() public {
        predictor_1.predict(predictionContract, 0, 100, true);
        predictor_2.predict(predictionContract, 0, 100, true);
        predictor_3.predict(predictionContract, 0, 100, true);
        predictor_4.predict(predictionContract, 0, 23, false);

        Assert.equal(predictionContract.lockedCurrency(), 323 * 10 ** currency.decimals(), "323 should be locked");

        bool[] memory outcomes = new bool[](2);
        outcomes[0] = true;
        outcomes[1] = false;

        predictionContract.setWaitingPeriodOverState(true);

        predictionContract.resolve(outcomes);

        predictionContract.setOpenState(false);

        uint256 reward_1 = predictor_1.claim(predictionContract);
        uint256 reward_2 = predictor_2.claim(predictionContract);
        uint256 reward_3 = predictor_3.claim(predictionContract);
        uint256 reward_4 = predictor_3.claim(predictionContract);

        uint256 epsilon = 1 * 10 ** currency.decimals();

        Assert.equal(predictionContract.lockedCurrency(), 0, "No currency should be locked");

        CustomAssert.almostEqual(currency.balanceOf(address(predictor_1)), 997 * 10 ** currency.decimals(), epsilon, "Should gain around 7");
        CustomAssert.almostEqual(currency.balanceOf(address(predictor_2)), 997 * 10 ** currency.decimals(), epsilon, "Should gain around 7");
        CustomAssert.almostEqual(currency.balanceOf(address(predictor_3)), 997 * 10 ** currency.decimals(), epsilon, "Should gain around 7");
        Assert.equal(currency.balanceOf(address(predictor_4)), 977 * 10 ** currency.decimals(), "Remaining ballance should be 977");
        
        CustomAssert.almostEqual(reward_1, 97 * 10 ** currency.decimals(), epsilon, "Reward should be around 97");
        CustomAssert.almostEqual(reward_2, 97 * 10 ** currency.decimals(), epsilon, "Reward should be around 97");
        CustomAssert.almostEqual(reward_3, 97 * 10 ** currency.decimals(), epsilon, "Reward should be around 97");
        Assert.equal(reward_4, 0, "Reward should be 0");
    }

    function checkThreePredictorPredictsCorrectlyOtherUndevisibleAmounts() public {
        predictionContract.setFeePercentage(0);

        predictor_1.predict(predictionContract, 0, 100, true);
        predictor_2.predict(predictionContract, 0, 100, true);
        predictor_3.predict(predictionContract, 0, 100, true);
        predictor_4.predict(predictionContract, 0, 20, false);

        Assert.equal(predictionContract.lockedCurrency(), 320 * 10 ** currency.decimals(), "323 should be locked");

        bool[] memory outcomes = new bool[](2);
        outcomes[0] = true;
        outcomes[1] = false;

        predictionContract.setWaitingPeriodOverState(true);

        predictionContract.resolve(outcomes);

        predictionContract.setOpenState(false);

        uint256 reward_1 = predictor_1.claim(predictionContract);
        uint256 reward_2 = predictor_2.claim(predictionContract);
        uint256 reward_3 = predictor_3.claim(predictionContract);
        uint256 reward_4 = predictor_3.claim(predictionContract);

        uint256 epsilon = 1 * 10 ** currency.decimals();
        uint256 smallEpsilon = 10;

        CustomAssert.almostEqual(predictionContract.lockedCurrency(), 0, smallEpsilon, "No currency should be locked");

        CustomAssert.almostEqual(currency.balanceOf(address(predictor_1)), 1006 * 10 ** currency.decimals(), epsilon, "Should gain around 6");
        CustomAssert.almostEqual(currency.balanceOf(address(predictor_2)), 1006 * 10 ** currency.decimals(), epsilon, "Should gain around 6");
        CustomAssert.almostEqual(currency.balanceOf(address(predictor_3)), 1006 * 10 ** currency.decimals(), epsilon, "Should gain around 6");
        Assert.equal(currency.balanceOf(address(predictor_4)), 980 * 10 ** currency.decimals(), "Remaining ballance should be 976");
        
        CustomAssert.almostEqual(reward_1, 106 * 10 ** currency.decimals(), epsilon, "Reward should be around 96");
        CustomAssert.almostEqual(reward_2, 106 * 10 ** currency.decimals(), epsilon, "Reward should be around 96");
        CustomAssert.almostEqual(reward_3, 106 * 10 ** currency.decimals(), epsilon, "Reward should be around 96");
        Assert.equal(reward_4, 0, "Reward should be 0");
    }

    function checkTwoPredictorPredictsCorrectlyOnlyOneClaims() public {
        predictor_1.predict(predictionContract, 0, 100, true);
        predictor_2.predict(predictionContract, 0, 100, true);
        predictor_3.predict(predictionContract, 0, 100, false);

        Assert.equal(predictionContract.lockedCurrency(), 300 * 10 ** currency.decimals(), "400 should be locked");

        bool[] memory outcomes = new bool[](2);
        outcomes[0] = true;
        outcomes[1] = false;

        predictionContract.setWaitingPeriodOverState(true);

        predictionContract.resolve(outcomes);

        predictionContract.setOpenState(false);

        uint256 reward_1 = predictor_1.claim(predictionContract);


        Assert.equal(currency.balanceOf(address(predictor_1)), 1035 * 10 ** currency.decimals(), "Should gain 1.5x their (amount - fee)");
        Assert.equal(currency.balanceOf(address(predictor_2)), 900 * 10 ** currency.decimals(), "Should not gain anything, did not claim yet");
        Assert.equal(currency.balanceOf(address(predictor_3)), 900 * 10 ** currency.decimals(), "Should lose prediction amount");
        Assert.equal(predictionContract.lockedCurrency(), 135 * 10 ** currency.decimals(), "Unclaimed amount should be locked");
        Assert.equal(reward_1, 135 * 10 ** currency.decimals(), "Reward should be 135");
    }

}