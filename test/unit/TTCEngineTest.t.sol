// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployTTC} from "../../script/DeployTTC.s.sol";
import {TTCStableCoin} from "../../src/TTCStableCoin.sol";
import {TTCEngine} from "../../src/TTCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";


contract TTCEngineTest is Test{
    DeployTTC deployer;
    TTCStableCoin ttc;
    TTCEngine ttce;
    HelperConfig config;
    address ethUSDPriceFeed;
    address btcUSDPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployTTC();
        (ttc, ttce, config) = deployer.run();
        (ethUSDPriceFeed, btcUSDPriceFeed, weth,,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER,STARTING_ERC20_BALANCE);
    }

    //=================================//
    //        Constructor Tests        //
    //=================================//
    
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    
    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUSDPriceFeed);
        priceFeedAddresses.push(btcUSDPriceFeed);

        vm.expectRevert(TTCEngine.TTCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new TTCEngine(tokenAddresses, priceFeedAddresses, address(ttc));
    }

    //===========================//
    //        Price Tests        //
    //===========================//

    function testGetUSDValue() public {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30,000ee18
        uint256 expectedUSD = 30000e18;
        uint256 actualUSD = ttce.getUSDValue(weth,ethAmount);
        assertEq(expectedUSD,actualUSD);
    }

    function testGetTokenAmountFromUSD() public {
        uint256 usdAmount = 100 ether;
        // $2000 / ETH, $100
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = ttce.getTokenAmountFromUSD(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    //=======================================//
    //        depositCollateral Tests        //
    //=======================================//

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(ttce), AMOUNT_COLLATERAL);

        vm.expectRevert(TTCEngine.TTCEngine__NeedsMoreThanZero.selector);
        ttce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock();
        vm.startPrank(USER);
        vm.expectRevert(TTCEngine.TTCEngine__NotAllowedToken.selector);
        ttce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();

    }

}

// 3:03:23