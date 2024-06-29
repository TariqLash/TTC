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

/**
 * @title TTC - (T&T Coin)
 * @author Tariq Lashley
 * 
 * Collateral: Exogenus (ETH & BTC)
 * Minting: Algorithmic
 * 
 * Relative Stability: Pegged to TTD
 * 
 * @notice This contract is the work of Patrick Collins' DecentralizedStableCoin.sol and was only slightly modified
 */

contract TTCStableCoin is ERC20Burnable, Ownable{
    error TTCStableCoin__MustBeMoreThanZero();
    error TTCStableCoin__BurnAmountExceedsBalance();
    error TTCStableCoin__NotZeroAddress();

    event testingBurn(uint256 balance);

    constructor() Ownable(msg.sender) ERC20("TTCStableCoin", "TTC") {}

    function burn(uint256 _amount) public override onlyOwner{
        uint256 balance = balanceOf(msg.sender);
        emit testingBurn(balance);

        if(_amount <= 0){
            revert TTCStableCoin__MustBeMoreThanZero();
        }
        if(balance < _amount){
            revert TTCStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns(bool){
        if(_to == address(0)){
            revert TTCStableCoin__NotZeroAddress();
        }
        if(_amount <= 0){
            revert TTCStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }

    
    
}