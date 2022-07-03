// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

// Chainlink VRFV2 Contracts (RNG)
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol"; 
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

// Chainlink Data Feed Interface
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol"; 

/*
Chainlink Keepers 
KeeperCompatible.sol imports the functions from both ./KeeperBase.sol and
./interfaces/KeeperCompatibleInterface.sol 
*/
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";

/** 
 *  @author Suthan Somadeva
 *  @title Automated Lottery w/ Weighted Winner Selection
 *  @dev interface addresses(VRFV2, Data Feed) hardcoded for Rinkeby Network
*/
contract automatedLottery is VRFConsumerBaseV2, KeeperCompatibleInterface {

    // Initalizes VRFV2 interface
    VRFCoordinatorV2Interface COORDINATOR;

    // Initalizes Data Feed interface
    AggregatorV3Interface internal priceFeed; // Data Feed

    // object generated for each lottery participant
     struct Player {
        // 1 weight = $1 at time of entry based on chainlink data feed (ex. $100 = 100 weight)
        uint weight;
        // address of player 
        address playerAddress; 
    }

    // Lottery Variables ------------------------------------------------
    // index maps to a player object
    Player[] public players; 
    // # of current players in the lottery session
    uint public totalPlayers;
    // latest lottery winner 
    address payable public currWinner; 
    // State of the lottery {true, false}
    bool lotteryOpen; 
    // stores random numbers
    uint256[] public randomResult; 
    //-------------------------------------------------------------------
    
    // Keeper vars------------------------------------------------------
    // timeKeeper (activated when 2 players enter the lottery)
    // block.time >= timeKeeper + interval = keeper call of performUpKeep
    uint public immutable interval; 
    uint public timeKeeper;
    //------------------------------------------------------------------

    /// Chainlink VRF Initiliazation-------------------------------------	
    // Returns a random number from a chainlink node and verifies it's integrity
    address vrfCoordinator = 0x6168499c0cFfCaCD319c818142124B7A15E857ab;
    // Subscription number tied to the account that is funding the VRFV2 service
    uint64 subscriptionId;
    // Request number assigned to the current/previous random number call
    uint256 public s_requestId;
    // Using the 30gwei key hash
    // This specifies the max gas used for the random number request
    // if that gas price is above this then there will be no random numbers recieved
    bytes32 public keyHash = 0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc; // 30gwei hash
    // max gas uints for calling fulfillRandomWords() used by coordinator
    // if over this amount then call is reverted
    uint32 callbackGasLimit = 300000; 
    // minimum confirmations for random number request to be recieved
    uint16 requestConfirmations = 3;
    // amount of random numbers that will be requested 
    uint32 numWords =  3; 
    //------------------------------------------------------------------	
    
    constructor(uint64 _subscriptionId, uint _interval) 
    VRFConsumerBaseV2(vrfCoordinator) 
    {
        // Initalize lottery
        totalPlayers = 0;
        lotteryOpen = true;

        // Keeper 
        interval = _interval;

        // VRFV2
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        subscriptionId = _subscriptionId;

        // Data Feed (ETH/USD) 
        priceFeed = AggregatorV3Interface(0x8A753747A1Fa494EC906cE90E9f37563A8AF630e); 
    }

    /** 
     *  @dev Gets latest USD price of ETH from chainlink oracle
     *  @return price USD(10^8) of 1 ETH
     */
    function getLatestPrice() public view returns (uint) {
        (,int price,,,) = priceFeed.latestRoundData();
        return uint(price); 
    }

    /** 
     *  @dev Allows users to enter the lottery
     *  @dev Checks minimum value passed in to enter is greater than $10
     */
    function enter() public payable {
        // Stops players from entering if the winner selection process has been initiated
        require(lotteryOpen);

        if (totalPlayers == 1) {
            // executed when a second player enters the lottery
            // initalizes the time stamp which checkUpKeep monitors  
            timeKeeper = block.timestamp;    
        }
        
        // 10**8 price * 10**18 (wei conversion) = 10**26
        // (amt ** price) / 10^26
        uint dollarsPassed = (msg.value * getLatestPrice()) / 10**26; 
        // min entry $10
        require(dollarsPassed >= 10); 

        // initalize new player with weight and address
        Player memory player = Player(dollarsPassed, address(msg.sender)); 
        // store player in players arr
        players.push(player); 
        // update amount of active participants
        totalPlayers++; 
    }

    /** 
     *  @dev View function so does not cost gas to call directly
     *  @return List of participating player's addresses
     */
    function viewPlayers() public view returns(address[] memory) {
        // Gets all player objects by using the totalPlayers count for array max len
        address[] memory playerAdresses  = new address[](totalPlayers);

        // loop over all players and append them to array
        for (uint i=0; i < totalPlayers; i++) {
            playerAdresses[i] = (players[i].playerAddress);
        }

        return playerAdresses;
    }

    /** 
     *  @dev Initates the VRFV2 random numbers request
     *  @dev If call is succesful, the VRF coordinator will call rawfulfillRandomWords 
     *  @dev Only performUpKeep calls this as it's an internal function
     */
    function concludeLottery() internal { 
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

    /** 
     *  @dev Only VRF coordinator can call rawfulfillRandomWords -> which calls this function
     *  @dev Recieves the random numbers array from the VRF coodinator
     *  @dev Initates the call to settle the lottery -> pickWinner()  
     */
    function fulfillRandomWords 
    (
        uint256, /* requestId */
        uint256[] memory randomWords
    ) internal override {
        randomResult = randomWords;
        pickWinner();
    }

    /** 
     *  @dev Settles the lottery for the winner
     *  @dev Reinitalizes the lottery state
     */
    function pickWinner() internal {
        // Gets 2 random indexes using the first 2 random numbers
        // Which were stored in randomResult
        // These numbers are modulos against the count of total players
        // Produces an index in the range (0,totalPlayers-1)       
        uint playerOneIndex = randomResult[0] % totalPlayers;
        uint playerTwoIndex = randomResult[1] % totalPlayers;

        // copies those player's objects to memory
        Player memory playerOne = players[playerOneIndex];
        Player memory playerTwo = players[playerTwoIndex];

        // gets the total sum of their weights
        uint weight =  playerOne.weight + playerTwo.weight;
        // Settler is a random number used to apply weighted randomness
        // Using the 3rd random number stored in randomResult
        // Produces a number in the range of (0, weight-1) 
        uint settler = randomResult[2] % weight; 

        // Weighted randomness using the generated weight
        if(settler < playerOne.weight) {
            currWinner = payable(playerOne.playerAddress);
        } else {
            currWinner = payable(playerTwo.playerAddress); 
        }

        // Transfer all funds to winner
        currWinner.transfer(address(this).balance); 

        // Reinitalize lottery
        delete players; // clear existing 
        totalPlayers = 0;
        lotteryOpen = true; // reopen lottery

    }

    /** 
     *  @dev This function is called by the chainlink keepers node
     *  @dev The node simulates this function locally to see if upKeep conditions are met
     *  @dev If uplink conditions are met performUpKeep is called on-chain
     *  @dev Upkeep is only needed if there is a valid lottery (2 players in contention)
     *  @dev Or if the interval is greater than what is specified upon 2 players entering
     */     
    function checkUpkeep(bytes calldata /*checkData*/) external view override returns (bool upkeepNeeded, bytes memory /*performData*/) {
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

    /** 
     *  @dev Called by Chainlink Keepers node if upkeep conditions met
     *  @dev Initiates lottery conclusion process     
     */
    function performUpkeep(bytes calldata /*performData*/) external override {
        // if 0 then 2 players haven't entered, or the lottery is finished
        require(timeKeeper != 0); 

        // Revalidates checkUpKeep then closes and concludes lottery
        if ((block.timestamp - timeKeeper) > interval ) {
            // Close so that no one can enter after/during when random numbers 
            // Are calculated (can't game system)
            lotteryOpen = false;
            /// Set to nil so keeper won't execute twice in the same lottery
            timeKeeper = 0; 
            concludeLottery();
        }
        // We don't use the performData 
        // The performData is generated by the Keeper's call to your checkUpkeep function
    }    
}