## Automated Verifiably Random Lottery Ethereum

Smart Contract, and React App developed by Suthan Somadeva \
Styling done by Asvin Aravinthan

## Intro

This is a lottery on Ethereum which is automated using Chainlink Keepers. It employs a weighted system for determining the winner, which is achieved by input provided from a Chainlink Data Feed oracle for the USD price of ETH at time of entry. Furtheremore, it produces a verifiably random result, as opposed to a pseudorandom approach that could be gamed. As it uses Chainlink VRFV2 to generate random numbers for the settlement process. The winner of the lottery receives the sum of funds that users have paid to enter. In this instance of the contract the interval is set to 180(3 minutes). See the lottery settlement selection below for more information on this. I have also provided well documented comments in the solidity code that I recommend you check out :)

## Detailed Execution Flow

### Constructor
The constructor takes two arguments. "_subscriptionId" which is the identifer for the subscription to the VRFV2 service. As well as "_interval" which is the max time the lottery will be running for once 2 players have entered. After which it will be allowed to settle the lottery between the contesting players.

### Player Entry
A player is expected to call the "enter" function. This function requires that the lottery state be set to open, and that the value of the ethereum they are passing in is greater than $10. This is determined by a call to a Chainlink USD/ETH Data Feed Contract.

When the [Chainlink Data Feed](https://docs.chain.link/docs/using-chainlink-reference-contracts/) returns the price, it does so as the value(10^8). This is done because Solidity does not have capability for floating point numbers. The dollars passed is checked by running the calculation (amt passed in * ETH price) / 10^26. Division by 10^26 is because amt passed(msg.value) is always in the units of wei, which is 10^18 of 1 ether. Thus, 10^8 * 10^18 = 10^26.

If both conditions are met then a new player object is initalized and stored in a struct which contains their weight(dollars passed in), and address. This struct is then stored in a players array.

It should also be noted that on the second succesful entry to the lottery the current block timestamp is stored in a variable called "timeKeeper". So that the lottery is only eligible to be concluded if there are at least 2 players in the running, and a specified time interval has passed. More on this is mentioned in the lottery settlement section. 

### Lottery Settlement
Every block a [Chainlink Keepers](https://docs.chain.link/docs/chainlink-keepers/introduction/) node will call the [Keepers Registry](https://docs.chain.link/docs/chainlink-keepers/overview/). If the contract has been registered for upkeep, then a Chainlink node will run an off-chain simulation of the checkUpkeep function. If upkeepNeeded returns true then performUpkeep will be called.

In this contract the conditions neccessary for checkUpKeep to resolve true are the timeKeeper being initalized (not equaling 0, as it was initalized as) and the interval duration having since past the time stamp stored in timeKeeper.  

performUpKeep revalidates the conditions as checkUpKeep is an external function, and anyone can call it. As we are automating a function that is public to everyone. This lottery is intended to be ended after a specific interval, if there are a minimum of two players. Within performUpKeep we call concludeLottery.

concludeLottery generates a random words(numbers) request to the [VRFV2 Coordinator](https://docs.chain.link/docs/chainlink-vrf/). The VRFV2 coordinator is called by a Chainlink node which goes on to generate the random number and returns it back to the coordinator contract. Which verfies the legitimacy of it using a mathematical proof. The coordinator contract then calls back to the lottery contracts rawfulfillRandomWords function passing the requested random numbers. In this lottery we are requesting three random words. 

rawfulfillRandomWords invokes fulfillRandomWords which calls pickWinner(). Within pickWinner we use the first two random words to select random indexes from the players array. Each random number is moudulo'd against the total players to produce any index in the players array. The sum of the two player's weights is also calculated. This is used to generate a number that will act as a 'settler'. This settler is produced by moduloing the third random number against the weight sum Range(0,weight-1). This enables a weighted random selection between the two players. As the winner is finally selected by seeing if any of the players has a weight value greater than that number. In the case that 2 players have the same weight, it is the player of the first index selected that will win. There is however a weakness to this approach that I document in the weakness section.        

## Flow of Execution Diagrams

### Player Entry 
![Player Entry](https://i.ibb.co/fNSP1dz/player-Entry-drawio.png)

### Lottery Settlement
![Lottery Settlement](https://i.ibb.co/rcH1C8S/settlement-Process-drawio.png)

## Weakness
When two random numbers are used to select the two indexes it is a verifiably random process. Furthermore, between the two players the one that entered more value into the lottery will always have greater odds. Despite this, if one was to have multiple entires into the lottery (be it same account or alts) then there exists a chance that those two indexes resolve to the same player. Initially I wanted to solve this by employing the algorithm specified [here](https://stackoverflow.com/questions/1761626/weighted-random-numbers):

```
int rnd = random(sum_of_weight);
for(int i=0; i<num_choices; i++) {
  if(rnd < choice_weight[i])
    return i;
  rnd -= choice_weight[i];
}
```

However, this would be unfeasible gas wise, as if there was a large amount of players who entered the lottery it would cost an exuberant amount of gas. I want to revisit this with a solution where we can consider the weight values of all players in contention without the gas issue. For now the only reasonable fix would be to set a higher minimum entry value to make the weakness too costly to attempt exploiting.

## How to Run

Generate optimized build:
```
npm run build
```

Launch localhost:

```
serve -s build
```

## Notes for Deploying Your Own Instance

1) The flattened lottery contract provided has been optimized using default settings (200)

2) You must deploy using the flattened contract, as to set up a chainlink keepers upkeep the contract
   must be verified on etherscan (or pass in the abi)

3) You get a '_subscriptionId' by creating a subscription to the [VRFV2 Service](https://vrf.chain.link/)
   Do not forget to whitelist the address of you contract under said subscription:
   url:
   ```
   https://vrf.chain.link/rinkeby/{Your_SubscriptionID}
   
   ```
   ![VRFV2](https://i.ibb.co/7VhQCmG/Capture.jpg)

4) Edit the lottery.js file under ./src with your contracts address, and ABI (Remember to use the ABI of the flattened contract not the base file as this is what you deployed)

5) [Register](https://keepers.chain.link/rinkeby) a new upkeep so that automation can occur
   Use custom logic under trigger mechanism (use gas limit of at least 150,000)

   ![Keeper](https://i.ibb.co/BKNq1w5/Capture2.jpg)

6) If both these services are not kept properly funded with LINK they will not process your
   requests. See more in the resources below

## Plans for Future

1) Build a more eye pleasing front end interface

2) Emit logs so that front end is updated dynamically

## Resources
* [Chainlink Data Feeds](https://docs.chain.link/docs/using-chainlink-reference-contracts/)
    * [Get latest price](https://docs.chain.link/docs/get-the-latest-price/)
* [Chainlink VRFV2](https://docs.chain.link/docs/chainlink-vrf/)
    * [Get a Random Number](https://docs.chain.link/docs/get-a-random-number/)
* [Chainlink Keepers](https://docs.chain.link/docs/chainlink-keepers/introduction/)
    * [Make contract Keepers Compatible](https://docs.chain.link/docs/chainlink-keepers/compatible-contracts/)
