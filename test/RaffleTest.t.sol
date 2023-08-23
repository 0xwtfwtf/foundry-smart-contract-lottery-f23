// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DeployRaffle} from "../script/DeployRaffle.s.sol";
import {Raffle} from "../src/Raffle.sol";
import {Test, console} from "../lib/forge-std/src/Test.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {Vm} from "../lib/forge-std/src/Vm.sol";
import {VRFCoordinatorV2Mock} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {

    event EnteredRaffle (address indexed player);

    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 1 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        (
            entranceFee, 
            interval, 
            vrfCoordinator, 
            gasLane, 
            subscriptionId, 
            callbackGasLimit,
            link,
            deployerKey
        ) = helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertsWhenYouDontPayEnough() public {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();}

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEmitsEventUponEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER); //tell them we expect the event at the next transaction
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterRaffleWhenRaffleIsCalculating() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval +1);
        vm.roll(block.number + 1);
        raffle.performUpKeep(""); //put the lottery into calculating state
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector); //we expect the new tx to revert with this error
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    
    
    function testReturnsFalseIfNotEnoughTimeHasPassed() public {
        vm.prank(PLAYER);
        vm.warp(block.timestamp + interval - 1);
        (bool upKeepNeeded, ) = raffle.checkUpKeep("");
        assert(!upKeepNeeded);
    }

    function testCheckUpKeepReturnsFalseIfItHasNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        
        (bool upKeepNeeded, ) = raffle.checkUpKeep("");

        assert (!upKeepNeeded);
    }

    function testCheckUpKeepReturnFalseIfRaffleStateIsnotOpen() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpKeep("");
        (bool upKeepNeeded, ) = raffle.checkUpKeep("");
        assert (!upKeepNeeded);
    }

    function testCheckUpKeepReturnsFalseIfThereAreNoPlayers() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        (bool upKeepNeeded, ) = raffle.checkUpKeep("");
        assert (!upKeepNeeded);
    }

    function testCheckPerformUpKeepRevertsIfUpKeepNotNeeded() public { 
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 raffleState = 0; //0 is OPEN, 1 is CALCULATING
        vm.expectRevert(abi.encodeWithSelector(
            Raffle.Raffle__UpKeepNotNeeded.selector, 
            currentBalance, 
            numPlayers, 
            raffleState)
            );
        //abi.encodeWithSelector allows you to expect revert for custom error with parameters
        raffle.performUpKeep("");
    }

    

    function testCheckUpKeepReturnsTrueWhenParamtersAreGood() public { 
        vm.recordLogs();
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        (bool upKeepNeeded, ) = raffle.checkUpKeep("");
        assert(upKeepNeeded == true);
        console.log("number of players: ", raffle.getPlayerIndexLength());
        Vm.Log[] memory entries = vm.getRecordedLogs();
    }

    function testPerformUpKeepCanOnlyRunIfCheckUpKeepIsTrue() public { 
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpKeep("");
    }

    modifier raffleEnteredAndTimePassed() { 
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testPerformUpKeepUpdatesRaffleAndEmitsRequest() public raffleEnteredAndTimePassed { 
        vm.recordLogs(); //record event logs
        raffle.performUpKeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs(); //get all recorded logs in an array
        //but where in this array is our requested winner being emitted?
        //all logs are in bytes32
        bytes32 requestId = entries[1].topics[1];
        Raffle.RaffleState rState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(rState) == 1);
    }

    modifier skipFork() { 
        if (block.chainid != 31337) {
        return;
        }
        _;
    }
    //modifier for tests that can't run on sepolia

    function testFulFillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId) skipFork public
    raffleEnteredAndTimePassed { 
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }

    function testFulFillRandomWordsPicksAWinnerResetsAndSendsMoney() raffleEnteredAndTimePassed public { 
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1;
        for(uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) { 
            address player = address(uint160(i)); //equivalent of makeAddr
            hoax(player, STARTING_USER_BALANCE); //equivalent of prank and deal
            raffle.enterRaffle{value: entranceFee}();
        }
        
        vm.recordLogs();
        raffle.performUpKeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs(); 
        bytes32 requestId = entries[1].topics[1];
        uint256 previousTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entranceFee * (additionalEntrants + 1);

        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));
        //requestId is bytes32 but we need to cast it to uint256
        
        assert((raffle.getRaffleState)() == Raffle.RaffleState.OPEN);
        assert(raffle.getRecentWinner() != address(0));
        console.log("recent winner: ", raffle.getRecentWinner());
        assert(raffle.getPlayerIndexLength() == 0);
        console.log("player index length: ", raffle.getPlayerIndexLength());
        assert(previousTimeStamp < raffle.getLastTimeStamp());
        assert(raffle.getRecentWinner().balance == (STARTING_USER_BALANCE + prize - entranceFee));
        console.log("recent winner balance: ", raffle.getRecentWinner().balance);
    }

}

//vm.warp sets the block timestamp to whatever we want
//vm.roll sets the block number