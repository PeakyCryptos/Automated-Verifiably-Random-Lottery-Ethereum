import React, { Component } from 'react';
import './App.css';
import web3 from './web3';
import lottery from './lottery';

class App extends Component {
  state = {
    players: [],
    totalPlayers: '',
    balance: '',
    entryValue: '',
    entryMessage: '',
    winner: ''
  };

  async componentDidMount() {
    const players = await lottery.methods.viewPlayers().call();
    const totalPlayers = await lottery.methods.totalPlayers().call();
    const balance = await web3.eth.getBalance(lottery.options.address);
    const winner = await lottery.methods.currWinner().call();
    
    this.setState({ players, totalPlayers, balance, winner});
  };

  onSubmit = async (event) => {
    event.preventDefault();

    const accounts = await web3.eth.getAccounts();
    
    this.setState({entryMessage: 'Waiting on transaction success...'});

    await lottery.methods.enter().send({
      from: accounts[0],
      value: web3.utils.toWei(this.state.entryValue, 'ether')
    })
    .then( 
      (result) => {
      this.setState({entryMessage: 'You have been entered! :)'});
      console.log(result);
      //window.location.reload(true);
    })
    .catch( 
      (err) => {
      this.setState({ entryMessage: `${JSON.stringify(err)}` });
    })
  };

  render() {
    return (
      <div class="col-md-3 w-50 mx-auto text-center position-absolute top-50 start-50 translate-middle card card-body text-bg-secondary mb-3">
        <h2 class="card-title">Lottery Contract</h2>
        <p class="card-text">
        The are currently {this.state.totalPlayers} players, competing for {web3.utils.fromWei(this.state.balance, 'ether')} ethereum!
        The current winner is: {this.state.winner}
        <br/>
        Current players entered: {
          this.state.players.map((item,index) => 
          <li key={index}>{item}</li>
        )}
        </p>
        <hr />
        
        <form onSubmit={this.onSubmit}>
          <h4>Want to try your luck? (minimum of $10)</h4>
          <div>
            <input type="number" class="w-25 p-1 mx-auto text-center form-control" id="FormControlInput" placeholder="Amount of ether to enter"
            value={this.state.entryValue} 
            onChange={event => this.setState( { entryValue: event.target.value })} 
        />
          </div><br></br>
          <button class="btn btn-dark">Enter</button>
        </form>
        <hr />
        <div>
          <h1>{this.state.entryMessage}</h1>
        </div>       
      </div>
    );
  };
}

export default App;
