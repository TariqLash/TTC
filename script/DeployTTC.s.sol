// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {TTCStableCoin} from "../src/TTCStableCoin.sol";
import {TTCEngine} from "../src/TTCEngine.sol";

contract DeployTTC is Script{
    function run() external returns(TTCStableCoin, TTCEngine){
        vm.startBroadcast();

        TTCStableCoin ttc = new TTCStableCoin();
        //TTCEngine engine = new TTCEngine();

        vm.stopBroadcast();
    }
}