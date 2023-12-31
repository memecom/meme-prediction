// SPDX-License-Identifier: GPL-3.0
        
pragma solidity >=0.4.22 <0.9.0;

// This import is automatically injected by Remix
import "remix_tests.sol"; 

// This import is required to use custom transaction context
// Although it may fail compilation in 'Solidity Compiler' plugin
// But it will work fine in 'Solidity Unit Testing' plugin
import "remix_accounts.sol";
import "../contracts/MemePredictionBase.sol";
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

    function checksetPredictibleOptionsForNextRoundSetsThemCorrectly() public {
        bool[] memory outcomes = new bool[](2);
        outcomes[0] = true;
        outcomes[1] = false;

        predictionContract.setWaitingPeriodOverState(true);

        predictionContract.resolve(outcomes);

        predictionContract.setOpenState(false);

        string[] memory predictibleOptions = new string[](3);
        predictibleOptions[0] = "MEME";
        predictibleOptions[1] = "CHAD";
        predictibleOptions[2] = "NOUNS";

        predictionContract.setPredictibleOptionsForNextRound(predictibleOptions);

        predictionContract.startNewPredictionRound();

        Assert.equal(predictionContract.getCurrentPredictibleOptions().length, 3, "Should have 3 predictible options");

    }

    function checkOnePredictorPredictsCorrectly() public {
        predictor_1.predict(predictionContract, 0, 100, true);

        Assert.equal(predictionContract.lockedCurrency(), 100 * 10 ** currency.decimals(), "100 should be locked");

        bool[] memory outcomes = new bool[](2);
        outcomes[0] = true;
        outcomes[1] = false;

        predictionContract.setWaitingPeriodOverState(true);

        predictionContract.resolve(outcomes);

        predictionContract.setOpenState(false);

        uint256 reward = predictor_1.claim(predictionContract);

        Assert.equal(currency.balanceOf(address(predictor_1)), 990 * 10 ** currency.decimals(), "Should lose only fee");
        Assert.equal(currency.balanceOf(address(predictionContract)), 10 * 10 ** currency.decimals(), "Should own fee currency");
        Assert.equal(predictionContract.lockedCurrency(), 0, "No currency should be locked");
        Assert.equal(reward, 90 * 10 ** currency.decimals(), "Reward should be 90");
    }

    function checkOnePredictorPredictsIncorrectly() public {
        predictor_1.predict(predictionContract, 0, 100, false);

        Assert.equal(predictionContract.lockedCurrency(), 100 * 10 ** currency.decimals(), "100 should be locked");

        bool[] memory outcomes = new bool[](2);
        outcomes[0] = true;
        outcomes[1] = false;

        predictionContract.setWaitingPeriodOverState(true);

        predictionContract.resolve(outcomes);

        predictionContract.setOpenState(false);

        uint256 reward = predictor_1.claim(predictionContract);

        Assert.equal(currency.balanceOf(address(predictor_1)), 900 * 10 ** currency.decimals(), "Should lose prediction amount");
        Assert.equal(currency.balanceOf(address(predictionContract)), 100 * 10 ** currency.decimals(), "Should own 100 currency");
        Assert.equal(predictionContract.lockedCurrency(), 0, "No currency should be locked");
        Assert.equal(reward, 0, "Reward should be 0");
    }

    function checkTwoPredictorsPredictsCorrectly() public {
        predictor_1.predict(predictionContract, 0, 100, true);
        predictor_2.predict(predictionContract, 0, 100, true);

        Assert.equal(predictionContract.lockedCurrency(), 200 * 10 ** currency.decimals(), "200 should be locked");

        bool[] memory outcomes = new bool[](2);
        outcomes[0] = true;
        outcomes[1] = false;

        predictionContract.setWaitingPeriodOverState(true);

        predictionContract.resolve(outcomes);

        predictionContract.setOpenState(false);

        uint256 reward_1 = predictor_1.claim(predictionContract);
        uint256 reward_2 = predictor_2.claim(predictionContract);

        Assert.equal(currency.balanceOf(address(predictor_1)), 990 * 10 ** currency.decimals(), "Should lose only fee");
        Assert.equal(currency.balanceOf(address(predictor_2)), 990 * 10 ** currency.decimals(), "Should lose only fee");
        Assert.equal(predictionContract.lockedCurrency(), 0, "No currency should be locked");
        Assert.equal(reward_1, 90 * 10 ** currency.decimals(), "Reward should be 90");
        Assert.equal(reward_2, 90 * 10 ** currency.decimals(), "Reward should be 90");
    }
    
    function checkOnePredictorPredictsCorrectlyOtherNot() public {
        predictor_1.predict(predictionContract, 0, 100, true);
        predictor_2.predict(predictionContract, 0, 100, false);

        Assert.equal(predictionContract.lockedCurrency(), 200 * 10 ** currency.decimals(), "200 should be locked");

        bool[] memory outcomes = new bool[](2);
        outcomes[0] = true;
        outcomes[1] = false;

        predictionContract.setWaitingPeriodOverState(true);

        predictionContract.resolve(outcomes);

        predictionContract.setOpenState(false);

        uint256 reward_1 = predictor_1.claim(predictionContract);
        uint256 reward_2 = predictor_2.claim(predictionContract);

        Assert.equal(currency.balanceOf(address(predictor_1)), 1080 * 10 ** currency.decimals(), "Should gain 2x");
        Assert.equal(currency.balanceOf(address(predictor_2)), 900 * 10 ** currency.decimals(), "Should lose");
        Assert.equal(reward_1, 180 * 10 ** currency.decimals(), "Reward should be 90");
        Assert.equal(reward_2, 0, "Reward should be 0");
        Assert.equal(predictionContract.lockedCurrency(), 0, "No currency should be locked");

    }

        
    function checkTwoPredictorPredictsCorrectlyOtherNot() public {
        predictor_1.predict(predictionContract, 0, 100, true);
        predictor_2.predict(predictionContract, 0, 100, true);
        predictor_3.predict(predictionContract, 0, 100, false);

        bool[] memory outcomes = new bool[](2);
        outcomes[0] = true;
        outcomes[1] = false;

        predictionContract.setWaitingPeriodOverState(true);

        predictionContract.resolve(outcomes);

        Assert.equal(predictionContract.lockedCurrency(), 270 * 10 ** currency.decimals(), "Should have 270 locked");

        predictionContract.setOpenState(false);

        uint256 reward_1 = predictor_1.claim(predictionContract);
        uint256 reward_2 = predictor_2.claim(predictionContract);
        uint256 reward_3 = predictor_3.claim(predictionContract);

        Assert.equal(currency.balanceOf(address(predictor_1)), 1035 * 10 ** currency.decimals(), "Should gain 1.5x their");
        Assert.equal(currency.balanceOf(address(predictor_2)), 1035 * 10 ** currency.decimals(), "Should gain 1.5x their");
        Assert.equal(currency.balanceOf(address(predictor_3)), 900 * 10 ** currency.decimals(), "Should lose");
        Assert.equal(predictionContract.lockedCurrency(), 0, "Nothing should be locked");
        Assert.equal(reward_1, 135 * 10 ** currency.decimals(), "Reward should be 135");
        Assert.equal(reward_2, 135 * 10 ** currency.decimals(), "Reward should be 135");
        Assert.equal(reward_3, 0, "Reward should be 0");
    }
}