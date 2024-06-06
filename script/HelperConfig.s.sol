// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";

contract HelperConfig is Script{
    struct NetworkConfig{
        address wethUSDPriceFeed;
        address wbtcUSDPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    constructor(){

    }

    function getSepoliaEthConfig() public view returns(NetworkConfig memory){
        return NetworkConfig({
            wethUSDPriceFeed:  ,
            wbtcUSDPriceFeed:  ,
            weth:  ,
            wbtc:  ,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });

    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory){
        if(activeNetworkConfig.wethUSDPriceFeed != address(0)){
            return activeNetworkConfig;
        }
    }
}