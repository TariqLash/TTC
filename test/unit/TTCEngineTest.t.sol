// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployTTC} from "../../script/DeployTTC.s.sol";
import {TTCStableCoin} from "../../src/TTCStableCoin.sol";
import {TTCEngine} from "../../src/TTCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";


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
    uint256 public STARTING_MINT_BALANCE = 100;
    uint256 public BURN_AMOUNT = 50;


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

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30,000ee18
        uint256 expectedUSD = 30000e18;
        uint256 actualUSD = ttce.getUsdValue(weth,ethAmount);
        assertEq(expectedUSD,actualUSD);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        // $2000 / ETH, $100
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = ttce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    //=======================================//
    //        depositCollateral Tests        //
    //=======================================//

    function testRevertsIfTransferFromFails() public {
        // Setup
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransferFrom mockTtc = new MockFailedTransferFrom();
        tokenAddress = [address(mockTtc)];
        feedAddressees = [ethUSDPriceFeed];
        vm.prank(owner);
        TTCEngine mockTtce = new TTCEngine(tokenAddresses, feedAddresses, address(mockTtc));
        
        vm.prank(owner);
        mockTtc.transferOwnership(address(mockTtce));

        // Arrange - User
        vm.startPrank(user);
        ERC20Mock(address(mockTtc)).approve(address(mockTtce), amountCollateral);

        // Act/assert
        vm.expectRevert(TTCEngine.TTCEngine__TransferFailed.selector);
        mockTtce.depositCollateral(address(mockTtc), amountCollateral);
        
        vm.stopPrank();
    }

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

    // deposits 10 ether to use as collateral
    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(ttce), AMOUNT_COLLATERAL);
        ttce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 userBalance = ttc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {

        (uint256 totalTtcMinted, uint256 collateralValueInUsd) = ttce.getAccountInfo(USER);

        uint256 expectedTotalTtcMinted = 0;

        uint256 startingDepositAmount = ttce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        uint256 expectedDepositAmount =AMOUNT_COLLATERAL;

        assertEq(totalTtcMinted, expectedTotalTtcMinted);
        assertEq(startingDepositAmount, expectedDepositAmount);
    }

        modifier depositedCollateralAndMintedTtc() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(ttce), amountCollateral);
        ttce.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        uint256 userBalance = ttc.balanceOf(user);
        assertEq(userBalance, amountToMint);
    }

    //=============================//
    //        mintTTC Tests        //
    //=============================//

    function testRevertsIfMintAmountZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(ttce), AMOUNT_COLLATERAL);

        vm.expectRevert(TTCEngine.TTCEngine__NeedsMoreThanZero.selector);
        ttce.mintTTC(0);
        vm.stopPrank();
    }

    // mints 100 TTC
    modifier mintTTC() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(ttce), STARTING_MINT_BALANCE);
        ttce.mintTTC(STARTING_MINT_BALANCE);        
        vm.stopPrank();
        _;
    }

    function testMintTTC() public depositedCollateral mintTTC {

        (uint256 totalTtcMinted, uint256 collateralValueInUsd) = ttce.getAccountInfo(USER);
        uint256 expectedTotalTtcMinted = STARTING_MINT_BALANCE;
        assertEq(totalTtcMinted, expectedTotalTtcMinted);
        
    }

    function testCanMintDsc() public depositedCollateral {
        vm.prank(user);
        dsce.mintDsc(amountToMint);

        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, amountToMint);
    }

    //=============================//
    //        burnTTC Tests        //
    //=============================//

    function testRevertsIfBurnAmountZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(ttce), AMOUNT_COLLATERAL);

        vm.expectRevert(TTCEngine.TTCEngine__NeedsMoreThanZero.selector);
        ttce.burnTTC(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanUserHas() public {
        vm.prank(user);
        vm.expectRevert();
        ttce.burnTtc(1);
    }

    function testCanBurnTtc() public depositedCollateralAndMintedTtc {
        vm.startPrank(user);
        ttc.approve(address(ttce), amountToMint);
        ttce.burnTtc(amountToMint);
        vm.stopPrank();

        uint256 userBalance = ttc.balanceOf(user);
        assertEq(userBalance, 0);
    }
}

// 3:13