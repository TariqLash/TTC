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
// receive functino (if exists)
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
 * Our TTC system should always be "overcollateralized". At no point, should the value of all collateral <= the $ backed value of all TTC.
 * 
 * @notice This contract is the core of the TTC System. It handles all the logic for mining and redeeming TTC, as well as depositing and withdrawing collateral.
 * @notice This contract is the work of Patrick Collins' DSCEngine.sol and was only slightly modified
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


    //===============================//
    //        State Variables        //
    //===============================//

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping (address token => address priceFeed) private s_priceFeeds; //tokenToPriceFeed
    mapping (address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping (address user => uint256 amountTTCMinted) private s_TTCMinted;
    address[] private s_collateralTokens;

    TTCStableCoin private immutable i_ttc;

    //======================//
    //        Events        //
    //======================//

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

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

    function depositCollateralAndMintTTC() external {}

    /**
     * @notice follows CEI
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress,uint256 amountCollateral) 
        external 
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

    function redeemCollateralForTTC() external {}

    function redeemCollateral() external {}

    /**
     * @notice follows CEI
     * @param amountTTCToMint The amount of decentralized stablecoin to mint
     * @notice they must have more collateral value that the minimum threshold
     */
    function mintTTC(uint256 amountTTCToMint) external moreThanZero(amountTTCToMint) nonReentrant{
        s_TTCMinted[msg.sender] += amountTTCToMint;

        _revertIfHealthFactorIsBroken(msg.sender);

    }

    function burnTTC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    //=================================================//
    //        Private & Internal View Functions        //
    //=================================================//

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
    function _healthFactor(address user) private view returns (uint256){
        (uint256 totalTTCMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalTTCMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if(userHealthFactor < MIN_HEALTH_FACTOR){
            revert TTCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    //================================================//
    //        Public & External View Functions        //
    //================================================//

    function getAccountCollateralValue(address user) public view returns(uint256 totalCollateralValueInUSD){
        // loop through each collateral token, get the amount they have deposited, and map it to
        // the price, to get the USD value

        for(uint256 i=0; i<s_collateralTokens.length; i++){
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += getUSDValue(token, amount);
        }
        return totalCollateralValueInUSD;
    }

    function getUSDValue(address token, uint256 amount) public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}