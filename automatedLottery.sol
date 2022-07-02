// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;


// modify for tickets and higher chance to win based on amount entered (1 ticket per 0.01 eth/usd value($10)
// add an oracle for the eth price the determines entry value
// if there is only one entrant then return funds back to them at the winner selection time

/*
https://docs.chain.link/docs/chainlink-vrf/
VRF v2 requests receive funding from subscription accounts. 
The Subscription Manager lets you create an account and pre-pay for VRF v2, 
so you don't provide funding each time your application requests randomness. 
This reduces the total gas cost to use VRF v2. It also provides a simple way 
to fund your use of Chainlink products from a single location, so you don't have 
to manage multiple wallets across several different systems and applications.
*/

// Chainlink VRFV2 Contracts (RNG)
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol"; 
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

// Chainlink Data Feed Interface
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol"; 

/*
Chainlink Keepers 
KeeperCompatible.sol imports the functions from both ./KeeperBase.sol and
./interfaces/KeeperCompatibleInterface.sol */
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";

/// @author Suthan Somadeva
/// @title automatedLottery
/// @dev interface addresses(VRFV2, Data Feed) hardcoded for Rinkeby Network
contract automatedLottery is VRFConsumerBaseV2, KeeperCompatibleInterface {

    // Initalizes VRFV2 interface
    VRFCoordinatorV2Interface COORDINATOR; 
    // Initalizes Data Feed interface
    AggregatorV3Interface internal priceFeed; // Data Feed

    /// object generated for each lottery participant
     struct Player {
        uint weight; // 1 weight = $1 at time of entry based on chainlink data feed (ex. $100 = 100 weight)
        address playerAddress; // address of player
    }
    
    // Keeper vars
    uint public immutable interval;
    uint public timeKeeper;

    Player[] public players; // index maps to a player object  
    uint public totalPlayers; // # of current players in the lottery session 
    address payable public currWinner; // latest lottery winner
    bool lotteryOpen; // State of the lottery {true, false}

    // Chainlink VRF Initiliazation
    address vrfCoordinator = 0x6168499c0cFfCaCD319c818142124B7A15E857ab; // RINKEBY
    uint64 subscriptionId; // Subscription ID
    uint256 public s_requestId; // requestID assigned to coordinator randomWords call
    bytes32 public keyHash = 0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc; // 30gwei hash
    uint32 callbackGasLimit = 300000; // max fee for calling fulfillRandomWords() used by coordinator
    uint16 requestConfirmations = 3; // minimum confirmations for random number request to be recieved
    uint32 numWords =  3; // amount of random numbers to query	
    
    uint256[] public randomResult; // return random number

    constructor(uint64 _subscriptionId, uint _interval) 
    VRFConsumerBaseV2(vrfCoordinator) 
    {
        // Initalize lottery
        totalPlayers = 0;
        lotteryOpen = true;

        // Keeper 
        interval = _interval;

        // VRFV2
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator); // coordinator
        subscriptionId = _subscriptionId;

        // Data Feed
        priceFeed = AggregatorV3Interface(0x8A753747A1Fa494EC906cE90E9f37563A8AF630e); // data feed (ETH/USD) RINKEBY
    }

    function concludeLottery() internal { // only performUpKeep calls this
        // Will revert if subscription is not set and funded. 
        s_requestId = COORDINATOR.requestRandomWords
        (
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
    }

    function fulfillRandomWords //called by VRF coodinator returns random result only VRF coordinator can call raw -> which calls this function
    (
        uint256, /* requestId */
        uint256[] memory randomWords
    ) internal override {
        randomResult = randomWords;
        pickWinner();
    }

    /**
     * Returns the latest price
    */
    function getLatestPrice() public view returns (uint) {
        (,int price,,,) = priceFeed.latestRoundData();
        return uint(price); // returns price in eth 10^8 
    }

    function enter() public payable {
        // minimum required players to start lottery is 2
        require(lotteryOpen);

        if (totalPlayers == 1) { // executed when a second player enters the lottery
            timeKeeper = block.timestamp; // lottery will close specified interval after this entry    
        }
        
        uint dollarsPassed = (msg.value * getLatestPrice()) / 10**26; // 10**8 price * 10**18 to wei = 10**26 is (price ** amt) / 10^26
        require(dollarsPassed >= 10); // min entry $10

        Player memory player = Player(dollarsPassed, address(msg.sender)); // initalize new player using players count as index
        players.push(player); 
        totalPlayers++; // increment players
    }

    function viewPlayers() public view returns(address[] memory) {
        // Gets all player objects by using the totalPlayers count
        address[] memory playerAdresses  = new address[](totalPlayers);

        for (uint i=0; i < totalPlayers; i++) {
            playerAdresses[i] = (players[i].playerAddress);
        }

        return playerAdresses;
    }

    function pickWinner() internal {
        // generates 3 random numbers
        // gets 2 random players and uses their weight values
        // 3rd random value is modulo'd against the sum weight of the 2 players rand(0,totalWeight) to produce the settler
        // using algo from https://stackoverflow.com/questions/1761626/weighted-random-numbers
        
        uint playerOneIndex = randomResult[0] % totalPlayers;
        uint playerTwoIndex = randomResult[1] % totalPlayers;

        Player memory playerOne = players[playerOneIndex];
        Player memory playerTwo = players[playerTwoIndex];

        uint weight =  playerOne.weight + playerTwo.weight;
        uint settler = randomResult[2] % weight; 

        if(settler < playerOne.weight) {
            currWinner = payable(playerOne.playerAddress);
        } else {
            currWinner = payable(playerTwo.playerAddress); 
        }

        // settle the lottery for winner
        currWinner.transfer(address(this).balance); // transfer all funds to winner

        // reinitalize lottery
        delete players; // clear existing 
        totalPlayers = 0;
        lotteryOpen = true; // reopen lottery

    }

    function checkUpkeep(bytes calldata /*checkData*/) external view override returns (bool upkeepNeeded, bytes memory /*performData*/) {
        /// Upkeep is only needed if their is a valid lottery (2 players in contention)
        /// and if the the interval is greater than what is specified upon those 2 players entering
        if  (timeKeeper != 0 
            && 
            (block.timestamp - timeKeeper) > interval) 
        {
            upkeepNeeded = true;
        } else {
            upkeepNeeded = false;  
        }
        
        // We don't use the checkData (possible arg passed in by keeper as default)
    }

    function performUpkeep(bytes calldata /*performData*/) external override {
        /// if 0 then 2 players haven't entered, or the lottery is finished
        require(timeKeeper != 0); 
        /// 
        require(lotteryOpen);

        /// Revalidates checkUpKeep then closes and concludes lottery
        if ((block.timestamp - timeKeeper) > interval ) {
            /// close so that no one can enter after/during when random numbers are calculated (can't game system)
            lotteryOpen = false;
            /// set to nil so keeper won't execute when there are less than 2 players 
            timeKeeper = 0; 
            concludeLottery();
        }
        // We don't use the performData in this example. The performData is generated by the Keeper's call to your checkUpkeep function
    }    



    // 1) if lottery is active, and time since last lottery ended is > interval (lottery can only be closed 1 hour after open)
    // 2) copy players array into memory   
    // 3) using sum of weight (dollars entered)
    // 4) gen rand(0, weight)
    // 5) loop over all players if weight greater then rand return player else rand-=weight keep looping
    // this is costly would need to find a way to do this off-chain
}