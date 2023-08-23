// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {VRFCoordinatorV2Interface} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
* @title A sample Raffle contract
* @author 0xwtfwtf
* @notice This contract is for creating a proveably fair raffle
* @dev implements Chainlink VRFv2
*/

contract Raffle is VRFConsumerBaseV2 {

    /* Custom errors */
    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__NotEnoughTimeHasPassed();
    error Raffle__UpKeepNotNeeded(
            uint256 currentBalance,
            uint256 numPlayers,
            RaffleState raffleState);

    /* Type declarations */ 
    //enums: create a new type to check state..custom types with finite set of custom values
    enum RaffleState { OPEN, CALCULATING }

    /* Constant Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    /* Immutable Variables */
    uint256 internal immutable i_entranceFee;
    uint256 internal immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 internal immutable i_gasLane;
    uint64 internal immutable i_subscriptionId;
    uint32 internal immutable i_callbackGasLimit;

    /* State Variables */
    address payable[] internal s_players;
    uint256 internal s_lastTimeStamp;
    address internal s_recentWinner;
    RaffleState public s_raffleState;

    /* Events */
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor (
        uint256 entranceFee, 
        uint256 interval, 
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        //cast this variable as type VRFCoordinatorV2Interface
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_lastTimeStamp = block.timestamp; //start clock
        s_raffleState = RaffleState.OPEN; //default state is open

    }

    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        emit EnteredRaffle(msg.sender);
    }

    //* @dev This is the function that the Chainlink Automation nodes call to see if it's time to perform upkeep (pick winner)
    //The following should be true if this returns true:
    //1. The specified interval has passed between raffle runs
    //2. The raffle is in the OPEN state
    //3. The contract has ETH
    //4. There are players in the raffle
    function checkUpKeep(bytes memory /* checkData */) public view returns (bool upKeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = block.timestamp - s_lastTimeStamp >= i_interval;
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upKeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upKeepNeeded, "0x0");
    }

    function performUpKeep(bytes calldata /* performData */) external {
        (bool upKeepNeeded, ) = checkUpKeep("");
        if (!upKeepNeeded) {
            revert Raffle__UpKeepNotNeeded(
                    address(this).balance,
                    s_players.length,
                    s_raffleState);

        }
        s_raffleState = RaffleState.CALCULATING;
        //set Raffle State to calculating to prevent people from entering
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 requestId, 
        uint256[] memory randomWords) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;
        //after we pick a winner, switch state back to open
        emit PickedWinner(winner);

        s_players = new address payable[](0);
        //reset the array after winner ic chosen
        s_lastTimeStamp = block.timestamp;
        //reset the clock for new lottery

        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
        
    }
    
    //function to get random number back

    /** Getter Functions */

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address){
        return s_players[indexOfPlayer];
    }

    function getPlayerIndexLength() external view returns (uint256) {
        return s_players.length;
    }

    function getRecentWinner() external view returns (address) { 
        return s_recentWinner;
    }

    function getLastTimeStamp() external view returns (uint256) { 
        return s_lastTimeStamp;
    }

}

//whenver a contract is inherited, we need to pass the arguments in the constructor (otherwise it is an abstract contract)
//add the arguments in the constructor of the inheriting contract (contractname(ARGUMENTS))