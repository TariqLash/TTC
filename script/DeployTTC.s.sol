// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {TTCStableCoin} from "../src/TTCStableCoin.sol";
import {TTCEngine} from "../src/TTCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployTTC is Script{
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns(TTCStableCoin, TTCEngine, HelperConfig){

        HelperConfig config = new HelperConfig();

        (address wethUSDPriceFeed, address wbtcUSDPriceFeed, address weth, address wbtc, 
            uint256 deployerKey) = config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUSDPriceFeed, wbtcUSDPriceFeed];

        vm.startBroadcast();

            TTCStableCoin ttc = new TTCStableCoin();
            TTCEngine engine = new TTCEngine(tokenAddresses, priceFeedAddresses, address(ttc));
            ttc.transferOwnership(address(engine));

        vm.stopBroadcast();
        return(ttc, engine, config);
    }
}