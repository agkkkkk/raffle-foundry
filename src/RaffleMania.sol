// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

/**
 * @title Raffle Mania Contract
 * @author AGK
 * @notice Generating random number for lottery system
 * @dev Chainlink VRF for random number generation
 */
contract RaffleMania is VRFConsumerBaseV2, AutomationCompatibleInterface {
    error NotEnoughEthSent();
    error TransferFailed();
    error RaffleNotOpen();
    error RaffleUpkeepNotNeeded();

    /** Type Declarations */
    enum RaffleState {
        ONGOING,
        CLOSED
    }

    uint16 private constant REQUEST_CONFIRMATION = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private _joiningFee;
    // address private _joiningToken;
    /// @dev Duration of raffle lottery
    uint256 private _raffleInterval;
    address payable[] private _participants;
    uint256 private _lastTimestamp;

    VRFCoordinatorV2Interface private immutable _vrfCordinator;
    bytes32 private immutable _gasLaneKeyHash;
    uint64 private immutable _subscriptionId;
    uint32 private immutable _callbackGasLimit;
    RaffleState private _raffleState;

    /** Events */
    event EnterRaffle(address indexed players);
    event Winner(address indexed winner);

    constructor(
        uint256 joiningFee,
        uint256 interval,
        address vrfCordinator,
        bytes32 keyHash,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCordinator) {
        _joiningFee = joiningFee;
        _raffleInterval = interval;
        _lastTimestamp = block.timestamp;
        _vrfCordinator = VRFCoordinatorV2Interface(vrfCordinator);
        _gasLaneKeyHash = keyHash;
        _subscriptionId = subscriptionId;
        _callbackGasLimit = callbackGasLimit;
        _raffleState = RaffleState.ONGOING;
    }

    function enterRaffle() external payable {
        if (msg.value >= _joiningFee) {
            revert NotEnoughEthSent();
        }
        if (_raffleState != RaffleState.ONGOING) {
            revert RaffleNotOpen();
        }
        _participants.push(payable(msg.sender));

        emit EnterRaffle(msg.sender);
    }

    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory performData) {
        bool isTimePassed = block.timestamp - _lastTimestamp >= _raffleInterval;
        bool isRaffleOpen = RaffleState.ONGOING == _raffleState;
        bool isParticipantEnough = _participants.length > 1;

        upkeepNeeded = (isTimePassed && isRaffleOpen && isParticipantEnough);
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert RaffleUpkeepNotNeeded();
        }

        _raffleState = RaffleState.CLOSED;
        _vrfCordinator.requestRandomWords(
            _gasLaneKeyHash,
            _subscriptionId,
            REQUEST_CONFIRMATION,
            _callbackGasLimit,
            NUM_WORDS
        );
    }

    function fulfillRandomWords(
        uint256 /* _requestId */,
        uint256[] memory _randomWords
    ) internal override {
        uint256 indexOfWinner = _randomWords[0] % _participants.length;
        address winner = _participants[indexOfWinner];
        _raffleState = RaffleState.ONGOING;
        _participants = new address payable[](0);
        _lastTimestamp = block.timestamp;
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert TransferFailed();
        }

        emit Winner(winner);
    }

    /** Getter Functions */

    function getJoiningFee() external view returns (uint256) {
        return _joiningFee;
    }

    // function getJoiningAddress() external view returns (address) {
    //     return _joiningToken;
    // }
}
