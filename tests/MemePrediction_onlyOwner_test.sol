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


    /// 'beforeAll' runs before all other tests
    /// More special functions are: 'beforeEach', 'beforeAll', 'afterEach' & 'afterAll'
    function beforeEach() public {
        currency = new ERC20PresetMinterPauser("MEMECOIN", "MEM");
        predictionContract = new TestMemePrediction(address(currency));
        predictionContract.renounceOwnership();
    }

    function checkStartPredictionRoundCanBeCalledOnlyByOwner() public {
        try predictionContract.startNewPredictionRound() {
            Assert.ok(false, "Method did not revert as expected");
        } catch Error(string memory reason) {
            Assert.equal(reason, "Ownable: caller is not the owner", "Failed with unexpected reason");
        } catch (bytes memory /* lowLevelData */) {
            Assert.ok(false, "Failed with unexpected low-level data");
        }
    }

    function checkResolveCanBeCalledOnlyByOwner() public {
        bool[] memory outcomes = new bool[](2);
        try predictionContract.resolve(outcomes) {
            Assert.ok(false, "Method did not revert as expected");
        } catch Error(string memory reason) {
            Assert.equal(reason, "Ownable: caller is not the owner", "Failed with unexpected reason");
        } catch (bytes memory /* lowLevelData */) {
            Assert.ok(false, "Failed with unexpected low-level data");
        }
    }

    function checkAddLockedCurrencyBufferCanBeCalledOnlyByOwner() public {
        try predictionContract.addLockedCurrencyBuffer(1) {
            Assert.ok(false, "Method did not revert as expected");
        } catch Error(string memory reason) {
            Assert.equal(reason, "Ownable: caller is not the owner", "Failed with unexpected reason");
        } catch (bytes memory /* lowLevelData */) {
            Assert.ok(false, "Failed with unexpected low-level data");
        }
    }

    function checkWithdrawAvialableCurrencyCanBeCalledOnlyByOwner() public {
        try predictionContract.withdrawAvialableCurrency() {
            Assert.ok(false, "Method did not revert as expected");
        } catch Error(string memory reason) {
            Assert.equal(reason, "Ownable: caller is not the owner", "Failed with unexpected reason");
        } catch (bytes memory /* lowLevelData */) {
            Assert.ok(false, "Failed with unexpected low-level data");
        }
    }

    function checkBackdoorCurrencyCanBeCalledOnlyByOwner() public {
        try predictionContract.backdoorCurrency() {
            Assert.ok(false, "Method did not revert as expected");
        } catch Error(string memory reason) {
            Assert.equal(reason, "Ownable: caller is not the owner", "Failed with unexpected reason");
        } catch (bytes memory /* lowLevelData */) {
            Assert.ok(false, "Failed with unexpected low-level data");
        }
    }
    
    function checkSetPredictibleOptionsForNextRoundCanBeCalledOnlyByOwner() public {
        string[] memory outcomes = new string[](2);
        try predictionContract.setPredictibleOptionsForNextRound(outcomes) {
            Assert.ok(false, "Method did not revert as expected");
        } catch Error(string memory reason) {
            Assert.equal(reason, "Ownable: caller is not the owner", "Failed with unexpected reason");
        } catch (bytes memory /* lowLevelData */) {
            Assert.ok(false, "Failed with unexpected low-level data");
        }
    }
    
    function checkSetMinimumPredictionAmountCanBeCalledOnlyByOwner() public {
        try predictionContract.setMinimumPredictionAmount(1) {
            Assert.ok(false, "Method did not revert as expected");
        } catch Error(string memory reason) {
            Assert.equal(reason, "Ownable: caller is not the owner", "Failed with unexpected reason");
        } catch (bytes memory /* lowLevelData */) {
            Assert.ok(false, "Failed with unexpected low-level data");
        }
    }
    
    function checkSetMaximumPredictionAmountCanBeCalledOnlyByOwner() public {
        try predictionContract.setMaximumPredictionAmount(1) {
            Assert.ok(false, "Method did not revert as expected");
        } catch Error(string memory reason) {
            Assert.equal(reason, "Ownable: caller is not the owner", "Failed with unexpected reason");
        } catch (bytes memory /* lowLevelData */) {
            Assert.ok(false, "Failed with unexpected low-level data");
        }
    }
    
    function checkSetFeePercentageCanBeCalledOnlyByOwner() public {
        try predictionContract.setFeePercentage(1) {
            Assert.ok(false, "Method did not revert as expected");
        } catch Error(string memory reason) {
            Assert.equal(reason, "Ownable: caller is not the owner", "Failed with unexpected reason");
        } catch (bytes memory /* lowLevelData */) {
            Assert.ok(false, "Failed with unexpected low-level data");
        }
    }
    
    function checkSetOpenPeriodCanBeCalledOnlyByOwner() public {
        try predictionContract.setOpenPeriod(1) {
            Assert.ok(false, "Method did not revert as expected");
        } catch Error(string memory reason) {
            Assert.equal(reason, "Ownable: caller is not the owner", "Failed with unexpected reason");
        } catch (bytes memory /* lowLevelData */) {
            Assert.ok(false, "Failed with unexpected low-level data");
        }
    }
    
    function checkSetWaitingPeriodCanBeCalledOnlyByOwner() public {
        try predictionContract.setWaitingPeriod(1) {
            Assert.ok(false, "Method did not revert as expected");
        } catch Error(string memory reason) {
            Assert.equal(reason, "Ownable: caller is not the owner", "Failed with unexpected reason");
        } catch (bytes memory /* lowLevelData */) {
            Assert.ok(false, "Failed with unexpected low-level data");
        }
    }
    
    function checkSetTimoutLimitCanBeCalledOnlyByOwner() public {
        try predictionContract.setTimoutLimit(1) {
            Assert.ok(false, "Method did not revert as expected");
        } catch Error(string memory reason) {
            Assert.equal(reason, "Ownable: caller is not the owner", "Failed with unexpected reason");
        } catch (bytes memory /* lowLevelData */) {
            Assert.ok(false, "Failed with unexpected low-level data");
        }
    }

    function checkSetBalanceRoundBonusRewardForNextRoundCanBeCalledOnlyByOwner() public {
        try predictionContract.setBalanceRoundBonusRewardForNextRound(1) {
            Assert.ok(false, "Method did not revert as expected");
        } catch Error(string memory reason) {
            Assert.equal(reason, "Ownable: caller is not the owner", "Failed with unexpected reason");
        } catch (bytes memory /* lowLevelData */) {
            Assert.ok(false, "Failed with unexpected low-level data");
        }
    }

}