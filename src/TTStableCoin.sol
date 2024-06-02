// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive functino (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
    @title TTC - (T&T Coin)
    @author Tariq Lashley
    Collateral: Exogenus (ETH & BTC)
    Minting: Algorithmic
    
    Relative Stability: Pegged to TTD


*/

contract TTStableCoin is ERC20Burnable, Ownable{
    error TTStableCoin__MustBeMoreThanZero();
    error TTStableCoin__BurnAmountExceedsBalance();
    error TTStableCoin__NotZeroAddress();


    constructor() Ownable(msg.sender) ERC20("TTStableCoin", "TTC") {}

    function burn(uint256 _amount) public override onlyOwner{
        uint256 balance = balanceOf(msg.sender);
        if(_amount <= 0){
            revert TTStableCoin__MustBeMoreThanZero();
        }
        if(balance < _amount){
            revert TTStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns(bool){
        if(_to == address(0)){
            revert TTStableCoin__NotZeroAddress();
        }
        if(_amount <= 0){
            revert TTStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }

    
    
}