// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "contracts/MemePredictionAdmin.sol";
import "contracts/MemePredictionUser.sol";

contract MemePrediction is MemePredictionAdmin, MemePredictionUser {

    constructor(address currencyAddress) {
        predictionCurrency = IERC20Metadata(currencyAddress);
    }

    /**
     * @notice Used for canceling current prediction round it can be used on unresolved round by owner
     *         or by anyone if timout has happened. After calling this participants of given prediction
     *         round can claim refunded funds (prediction placed, fee is included in refund amount).
     */
    function cancelPredictionRound() public {
        require(state == State.InProgress);
        require(msg.sender == this.owner() || isTimedOut());

        state = State.Cancelled;
        emit RoundCancelled(currentPredictionRound);
    }
}
