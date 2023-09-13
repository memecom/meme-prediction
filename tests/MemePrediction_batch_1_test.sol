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
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
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
        predictionContract = new TestMemePrediction();
        currency = new ERC20PresetMinterPauser("MEMECOIN", "MEM");
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
        predictionContract.setCurrentPredictibleOptions(predictibleOptions);
        predictionContract.setFeePercentage(1000);
        predictionContract.setOpenPeriod(1);
        predictionContract.setWaitingPeriod(1);
        predictionContract.setTimoutLimit(1);

        predictionContract.setPredictionCurrency(address(currency));

        predictionContract.setMinimumPredictionAmount(10);
        predictionContract.setMaximumPredictionAmount(100);

        //Initializin prediction round
        predictionContract.startNewPredictionRound();

        predictionContract.setOpenState(true);
        predictionContract.setWaitingPeriodOverState(false);
        predictionContract.setTimedOutState(false);
    }

    function checkPredictionRoundInitializedCorrectly() public {
        // No msgs to save contract size
        Assert.ok(predictionContract.state() == MemePredictionBase.State.InProgress, "");
        Assert.equal(predictionContract.currentPredictionRound(), 1, "");
        Assert.equal(predictionContract.FEE_PERCENTAGE(), 1000, "");
        Assert.equal(predictionContract.OPEN_PERIOD(), 60 * 60, "");
        Assert.equal(predictionContract.WAITING_PERIOD(), 60 * 60, "");
        Assert.equal(predictionContract.TIMEOUT_FOR_RESOLVING_PREDICTION(), 60 * 60, "");
    
        Assert.equal(predictionContract.open_until(), predictionContract.started_at() + 60 * 60, "");
        Assert.equal(predictionContract.waiting_until(), predictionContract.started_at() + 2 * 60 * 60, "");
        Assert.equal(predictionContract.timeout_at(), predictionContract.started_at() + 3 * 60 * 60, "");
    
        Assert.equal(predictionContract.waiting_until(), predictionContract.started_at() + 2 * 60 * 60, "");
        Assert.equal(predictionContract.getCurrentPredictibleOptions().length, 2, "");
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

        Assert.equal(currency.balanceOf(address(predictor_1)), 1080 * 10 ** currency.decimals(), "Should gain 2x their (amount - fee)");
        Assert.equal(currency.balanceOf(address(predictor_2)), 900 * 10 ** currency.decimals(), "Should lose prediction amount");
        Assert.equal(predictionContract.lockedCurrency(), 0, "No currency should be locked");
        Assert.equal(reward_1, 180 * 10 ** currency.decimals(), "Reward should be 90");
        Assert.equal(reward_2, 0, "Reward should be 0");
    }

        
    function checkTwoPredictorPredictsCorrectlyOtherNot() public {
        predictor_1.predict(predictionContract, 0, 100, true);
        predictor_2.predict(predictionContract, 0, 100, true);
        predictor_3.predict(predictionContract, 0, 100, false);

        Assert.equal(predictionContract.lockedCurrency(), 300 * 10 ** currency.decimals(), "300 should be locked");

        bool[] memory outcomes = new bool[](2);
        outcomes[0] = true;
        outcomes[1] = false;

        predictionContract.setWaitingPeriodOverState(true);

        predictionContract.resolve(outcomes);

        predictionContract.setOpenState(false);

        uint256 reward_1 = predictor_1.claim(predictionContract);
        uint256 reward_2 = predictor_2.claim(predictionContract);
        uint256 reward_3 = predictor_3.claim(predictionContract);

        Assert.equal(currency.balanceOf(address(predictor_1)), 1035 * 10 ** currency.decimals(), "Should gain 1.5x their (amount - fee)");
        Assert.equal(currency.balanceOf(address(predictor_2)), 1035 * 10 ** currency.decimals(), "Should gain 1.5x their (amount - fee)");
        Assert.equal(currency.balanceOf(address(predictor_3)), 900 * 10 ** currency.decimals(), "Should lose prediction amount");
        Assert.equal(predictionContract.lockedCurrency(), 0, "No currency should be locked");
        Assert.equal(reward_1, 135 * 10 ** currency.decimals(), "Reward should be 135");
        Assert.equal(reward_2, 135 * 10 ** currency.decimals(), "Reward should be 135");
        Assert.equal(reward_3, 0, "Reward should be 0");
    }

    function checkTwoPredictorPredictsCorrectlyOthersNot() public {
        predictor_1.predict(predictionContract, 0, 100, true);
        predictor_2.predict(predictionContract, 0, 100, true);
        predictor_3.predict(predictionContract, 0, 100, false);
        predictor_4.predict(predictionContract, 1, 100, true);

        Assert.equal(predictionContract.lockedCurrency(), 400 * 10 ** currency.decimals(), "400 should be locked");

        bool[] memory outcomes = new bool[](2);
        outcomes[0] = true;
        outcomes[1] = false;

        predictionContract.setWaitingPeriodOverState(true);

        predictionContract.resolve(outcomes);

        predictionContract.setOpenState(false);

        uint256 reward_1 = predictor_1.claim(predictionContract);
        uint256 reward_2 = predictor_2.claim(predictionContract);
        uint256 reward_3 = predictor_3.claim(predictionContract);
        // predictor_4 does not claim

        Assert.equal(currency.balanceOf(address(predictor_1)), 1035 * 10 ** currency.decimals(), "Should gain 1.5x their (amount - fee)");
        Assert.equal(currency.balanceOf(address(predictor_2)), 1035 * 10 ** currency.decimals(), "Should gain 1.5x their (amount - fee)");
        Assert.equal(currency.balanceOf(address(predictor_3)), 900 * 10 ** currency.decimals(), "Should lose prediction amount");
        Assert.equal(predictionContract.lockedCurrency(), 0, "No currency should be locked");
        Assert.equal(reward_1, 135 * 10 ** currency.decimals(), "Reward should be 135");
        Assert.equal(reward_2, 135 * 10 ** currency.decimals(), "Reward should be 135");
        Assert.equal(reward_3, 0, "Reward should be 0");
    }
}