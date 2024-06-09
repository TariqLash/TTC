// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;

import {TTCStableCoin} from "./TTCStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title TTCEngine
 * @author Tariq Lashley
 * 
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg.
 * 
 * This stablecoin had the properties:
 *         - Exogenous Collateral
 *         - Dollar Pegged
 *         - Algorithmically Stable
 * 
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by WETH and WBTC.
 * 
 * Our TTC system should always be "overcollateralized". At no point, should the value of all collateral <= the $ 
 * backed value of all TTC.
 * 
 * @notice This contract is the core of the TTC System. It handles all the logic for mining and redeeming TTC, as 
 * well as depositing and withdrawing collateral.
 */

contract TTCEngine is ReentrancyGuard {

    //======================//
    //        Errors        //
    //======================//

    error TTCEngine__NeedsMoreThanZero();
    error TTCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error TTCEngine__NotAllowedToken();
    error TTCEngine__TransferFailed();
    error TTCEngine__BreaksHealthFactor(uint256 healthFactor);
    error TTCEngine__MintFailed();
    error TTCEngine__HealthFactorOk();
    error TTCEngine__HealthFactorNotImproved();

    //===============================//
    //        State Variables        //
    //===============================//

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping (address token => address priceFeed) private s_priceFeeds; //tokenToPriceFeed
    mapping (address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping (address user => uint256 amountTTCMinted) private s_TTCMinted;
    address[] private s_collateralTokens;

    TTCStableCoin private immutable i_ttc;

    //======================//
    //        Events        //
    //======================//

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, 
        address indexed token, uint256 amount);

    //=========================//
    //        Modifiers        //
    //=========================//

    modifier moreThanZero(uint256 amount) {
        if(amount == 0){
            revert TTCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if(s_priceFeeds[token] == address(0)){
            revert TTCEngine__NotAllowedToken();
        }
        _;
    }

    //=========================//
    //        Functions        //
    //=========================//

    constructor(
        address[] memory tokenAddresses, 
        address[] memory priceFeedAddresses,
        address ttcAddress
    ){
        // USD Price Feeds
        // Will be changed to TTD in future update
        if(tokenAddresses.length != priceFeedAddresses.length){
            revert TTCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for(uint256 i=0; i<tokenAddresses.length; i++){
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_ttc = TTCStableCoin(ttcAddress);
    }

    //==================================//
    //        External Functions        //
    //==================================//

    /**
     * 
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountTTCToMint The amount of decentralized stablecoin to mint
     * @notice This function will deposit your collateral and mint TTC in one transaction
     */
    function depositCollateralAndMintTTC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountTTCToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintTTC(amountTTCToMint);
    }

    /**
     * 
     * @notice follows CEI
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress,uint256 amountCollateral) 
        public 
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant    
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if(!success){
            revert TTCEngine__TransferFailed();
        }
    }

    /**
     * 
     * @param tokenCollateralAddress The collateral address to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountTTCToBurn The amount of TTC to burn
     * This function burns TTC and redeems underlying collateral in one transaction
     */

    function redeemCollateralForTTC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountTTCToBurn) 
        external 
    {
        burnTTC(amountTTCToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeemCollateral already checks health factor
    }

    // in order to redeem collateral:
    // 1. health factor must be over 1 AFTER collateral pulled
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) 
        public
        moreThanZero(amountCollateral)
        nonReentrant 
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI
     * @param amountTTCToMint The amount of decentralized stablecoin to mint
     * @notice they must have more collateral value that the minimum threshold
     */
    function mintTTC(uint256 amountTTCToMint) 
        public 
        moreThanZero(amountTTCToMint) 
        nonReentrant
    {
        s_TTCMinted[msg.sender] += amountTTCToMint;

        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_ttc.mint(msg.sender, amountTTCToMint);
        if(!minted){
            revert TTCEngine__MintFailed();
        }
    }

    function burnTTC(uint256 amount) 
        public 
        moreThanZero(amount)
    {
        _burnTTC(amount, msg.sender, msg.sender);
        i_ttc.burn(amount);
    }

    /**
     * 
     * @param collateral The ERC20 collateral address to liquidate from the user
     * @param user The user who has broken the health factor. Their _healthFactor should be below MIN_HEALTH_FACTOR
     * @param debtToCover The amount of DSC you want to burn to improve the users health factor
     * @notice You can partially liquidate a user.
     * @notice You will get a liquidation bonus for taking the users funds
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized in order for this
     * to work
     * @notice A known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to
     * incentivize the liquidators. For example, if the price of the collateral plummeted before anyone could be 
     * liquidated
     * 
     */
    function liquidate(address collateral, address user, uint256 debtToCover) 
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        // need to check health factor of the user
        uint256 startingUserHealthFactor = _healthFactor(user);
        if(startingUserHealthFactor >= MIN_HEALTH_FACTOR){
            revert TTCEngine__HealthFactorOk();
        }
        // we want to burn their TTC "debt" and take their collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUSD(collateral, debtToCover);
        // and give them a 10% bonus
        // so we are giving the liquidator $110 of WETH for 100 TTC
        // we should implement a feature to liquidate in the event the protocol is insolvent
        // and sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
        // we need to burn the TTC
        _burnTTC(debtToCover, user, msg.sender);

        // check to make sure the health factors are okay
        uint256 endingUserHealthFactor = _healthFactor(user);
        if(endingUserHealthFactor <= startingUserHealthFactor){
            revert TTCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() 
        external 
        view 
    {

    }

    //=================================================//
    //        Private & Internal View Functions        //
    //=================================================//

    /**
     * @dev Low-level internal function, do not call unless the function calling it is checking for health factors
     * being broken
     */
    function _burnTTC(uint256 amountTTCToBurn, address onBehalfOf, address ttcFrom)
        private
    {
        s_TTCMinted[onBehalfOf] -= amountTTCToBurn;
        bool success = i_ttc.transferFrom(ttcFrom, address(this), amountTTCToBurn);

        // this condition is hypothetically unreachable since we will be sending transferFrom error
        if(!success){
            revert TTCEngine__TransferFailed();
        }
        i_ttc.burn(amountTTCToBurn);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if(!success){
            revert TTCEngine__TransferFailed();
        }
    } 


    function _getAccountInformation(address user) 
        private
        view 
        returns(uint256 totalTTCMinted, uint256 collateralValueInUSD)
    {
        totalTTCMinted = s_TTCMinted[user];
        collateralValueInUSD = getAccountCollateralValue(user);
    }

    /*
     * Returns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) 
        private 
        view 
        returns (uint256)
    {
        (uint256 totalTTCMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalTTCMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) 
        internal 
        view 
    {
        uint256 userHealthFactor = _healthFactor(user);
        if(userHealthFactor < MIN_HEALTH_FACTOR){
            revert TTCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    //================================================//
    //        Public & External View Functions        //
    //================================================//

    function getTokenAmountFromUSD(address token, uint256 usdAmountInWei)
        public
        view
        returns(uint256)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();
        (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) 
        public 
        view 
        returns(uint256 totalCollateralValueInUSD)
    {
        // loop through each collateral token, get the amount they have deposited, and map it to
        // the price, to get the USD value

        for(uint256 i=0; i<s_collateralTokens.length; i++){
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += getUSDValue(token, amount);
        }
        return totalCollateralValueInUSD;
    }

    function getUSDValue(address token, uint256 amount) 
        public 
        view 
        returns(uint256)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}

// 2:54:01