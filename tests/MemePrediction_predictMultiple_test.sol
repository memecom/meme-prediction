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
        predictionContract.setMaximumPredictionAmount(1000);

        //Initializing prediction round
        predictionContract.startNewPredictionRound();

        predictionContract.setOpenState(true);
        predictionContract.setWaitingPeriodOverState(false);
        predictionContract.setTimedOutState(false);
    }

    function checkUserPlacedMultiplePredictions() public {
        uint256[] memory optionIndexes = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        bool[] memory isUpPrediction = new bool[](2);

        optionIndexes[0] = 0;
        optionIndexes[1] = 1;
        amounts[0] = 10;
        amounts[1] = 100;
        isUpPrediction[0] = true;
        isUpPrediction[1] = false;
        predictor_1.predictMultiple(predictionContract, optionIndexes, amounts, isUpPrediction);

        Assert.equal(predictionContract.lockedCurrency(), 110 * 10 ** currency.decimals(), "110 should be locked");

        bool[] memory outcomes = new bool[](2);
        outcomes[0] = true;
        outcomes[1] = false;

        predictionContract.setWaitingPeriodOverState(true);

        predictionContract.resolve(outcomes);

        predictionContract.setOpenState(false);

        uint256 reward = predictor_1.claim(predictionContract);

        Assert.equal(currency.balanceOf(address(predictor_1)), 989 * 10 ** currency.decimals(), "Should lose only fee");
        Assert.equal(currency.balanceOf(address(predictionContract)), 11 * 10 ** currency.decimals(), "Should own fee currency");
        Assert.equal(predictionContract.lockedCurrency(), 0, "No currency should be locked");
        Assert.equal(reward, 99 * 10 ** currency.decimals(), "Reward should be 99");
    }

    function checkUsersPlacedMultiplePredictions() public {
        uint256[] memory optionIndexes = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        bool[] memory isUpPrediction = new bool[](2);

        optionIndexes[0] = 0;
        optionIndexes[1] = 1;
        amounts[0] = 100;
        amounts[1] = 100;
        isUpPrediction[0] = true;
        isUpPrediction[1] = false;
        predictor_1.predictMultiple(predictionContract, optionIndexes, amounts, isUpPrediction);

        optionIndexes[0] = 0;
        optionIndexes[1] = 0;
        predictor_2.predictMultiple(predictionContract, optionIndexes, amounts, isUpPrediction);

        Assert.equal(predictionContract.lockedCurrency(), 400 * 10 ** currency.decimals(), "400 should be locked");

        bool[] memory outcomes = new bool[](2);
        outcomes[0] = true;
        outcomes[1] = false;

        predictionContract.setWaitingPeriodOverState(true);

        predictionContract.resolve(outcomes);

        predictionContract.setOpenState(false);

        uint256 reward_1 = predictor_1.claim(predictionContract);
        uint256 reward_2 = predictor_2.claim(predictionContract);

        Assert.equal(currency.balanceOf(address(predictor_1)), 1025 * 10 ** currency.decimals(), "Should win 45 and loose 20 on fees");
        Assert.equal(currency.balanceOf(address(predictor_2)), 935 * 10 ** currency.decimals(), "Should win 45 and loose 100 and 20 on fees");
        Assert.equal(currency.balanceOf(address(predictionContract)), 40 * 10 ** currency.decimals(), "Should own fee currency");
        Assert.equal(predictionContract.lockedCurrency(), 0, "No currency should be locked");
        Assert.equal(reward_1, 225 * 10 ** currency.decimals(), "Reward should be 225");
        Assert.equal(reward_2, 135 * 10 ** currency.decimals(), "Reward should be 135");
    }
}
