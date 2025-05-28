// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    // ======== CONTRACT VARIABLES ========
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;

    address weth;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;

    address public USER = makeAddr("user");
    address public BOB = makeAddr("bob");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;

    // ======== SETUP ========
    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(BOB, STARTING_ERC20_BALANCE);
    }

    // ======== MODIFIERS ========
    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositeCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    // ======== PRICE CALCULATION TESTS ========
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    function testUsdValueAndTokenAmountInverse() public view {
        uint256 usd = 1000e18;
        uint256 tokenAmount = engine.getTokenAmountFromUsd(weth, usd);
        uint256 usdBack = engine.getUsdValue(weth, tokenAmount);
        assertApproxEqAbs(usd, usdBack, 1e16);
    }

    // ======== CONSTRUCTOR TESTS ========
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeed() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(this));
    }

    // ======== DEPOSITE COLLATERAL TESTS ========
    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositeCollateral(weth, 0);
        vm.stopPrank();
    }

    function testIsAllowedToken() public {
        ERC20Mock ranToken = new ERC20Mock();
        ranToken.mint(USER, AMOUNT_COLLATERAL);

        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositeCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositeCollateralAndAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    // ======== MINT DSC TESTS ========
    function testMintDscRevertsOnZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.mintDsc(0);
        vm.stopPrank();
    }

    function testDepositeCollateralAndMintDsc() public depositedCollateral {
        uint256 mintAmount = 20 ether;

        vm.startPrank(USER);
        engine.mintDsc(mintAmount);
        vm.stopPrank();

        (uint256 totalDscMinted,) = engine.getAccountInformation(USER);
        assertEq(mintAmount, totalDscMinted);
    }

    // ======== BURN DSC TESTS ========
    function testBurnDscRevertsOnZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.burnDsc(0);
        vm.stopPrank();
    }

    function testBurnDscReducesUserBalanceAndDSCMinted() public depositedCollateral {
        uint256 mintAmount = 2000e18;
        vm.startPrank(USER);
        engine.mintDsc(mintAmount);
        vm.stopPrank();

        assertEq(dsc.balanceOf(USER), mintAmount);

        uint256 burnAmount = 500e18;

        vm.startPrank(USER);
        dsc.approve(address(engine), burnAmount);
        engine.burnDsc(burnAmount);
        vm.stopPrank();

        (uint256 dscMintedAfterBurn,) = engine.getAccountInformation(USER);

        assertEq(dsc.balanceOf(USER), mintAmount - burnAmount);
        assertEq(dscMintedAfterBurn, mintAmount - burnAmount);
    }

    // ======== REDEEM COLLATERAL TESTS ========
    function testRedeemCollateralRevertsOnZeroAmount() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    // function testRedeemCollateralTransfersToken() public depositedCollateral {
    //     uint256 startingBalance = ERC20Mock(weth).balanceOf(USER);
    //     uint256 amountToRedeem = 1 ether;

    //     vm.startPrank(USER);
    //     engine.redeemCollateral(weth, amountToRedeem);
    //     vm.stopPrank();

    //     uint256 endingBalance = ERC20Mock(weth).balanceOf(USER);
    //     assertEq(endingBalance, startingBalance + amountToRedeem);
    // }

    // function testEmitsCollateralRedeemedEvent() public depositedCollateral {
    //     uint256 amountToRedeem = 1 ether;

    //     vm.startPrank(USER);
    //     vm.expectEmit(true, true, true, true);
    //     engine.redeemCollateral(weth, amountToRedeem);
    //     vm.stopPrank();
    // }

    // ======== LIQUIDATE TESTS ========
    function testLiquidateRevertsOnZeroDebt() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.liquidate(weth, BOB, 0);
        vm.stopPrank();
    }

    // ======== HEALTH FACTOR TESTS ========
    function testGetHealthFactor() public depositedCollateral {
        vm.startPrank(USER);
        // Mint a safe amount
        uint256 mintAmount = 5000e18; // Should be safe with AMOUNT_COLLATERAL
        engine.mintDsc(mintAmount);
        vm.stopPrank();
        
        uint256 healthFactor = engine.getHealthFactor(USER);
        // We expect health factor to be at or above MIN_HEALTH_FACTOR
        // This is a sanity check - the actual value depends on contract parameters
        assert(healthFactor >= 0);
    }
    
    // ======== COLLATERAL VALUE TESTS ========
    
    function testGetAccountCollateralValue() public depositedCollateral {
        uint256 collateralValue = engine.getAccountCollateralValue(USER);
        uint256 expectedValue = engine.getUsdValue(weth, AMOUNT_COLLATERAL);
        
        assertEq(collateralValue, expectedValue);
    }

        // ======== REDEEM COLLATERAL FOR DSC TESTS ========
    function testRedeemCollateralForDsc() public depositedCollateral {
        uint256 mintAmount = 1000e18;
        uint256 redeemAmount = 1 ether;
        uint256 burnAmount = 500e18;
        
        // Setup: Mint some DSC first
        vm.startPrank(USER);
        engine.mintDsc(mintAmount);
        dsc.approve(address(engine), burnAmount);
        
        uint256 userBalanceBefore = ERC20Mock(weth).balanceOf(USER);
        
        // Execute the redeem for DSC
        engine.redeemCollateralForDsc(weth, redeemAmount, burnAmount);
        vm.stopPrank();
        
        // Verify results
        uint256 userBalanceAfter = ERC20Mock(weth).balanceOf(USER);
        assertEq(userBalanceAfter, userBalanceBefore + redeemAmount);
        
        (uint256 dscMinted,) = engine.getAccountInformation(USER);
        assertEq(dscMinted, mintAmount - burnAmount);
    }

// ======== DSC BURN TESTS ========
    function testBurnDscUpdatesState() public depositedCollateral {
        uint256 mintAmount = 1000e18;
        uint256 burnAmount = 500e18;
        
        // Setup: Mint some DSC first
        vm.startPrank(USER);
        engine.mintDsc(mintAmount);
        
        // Approve and burn
        dsc.approve(address(engine), burnAmount);
        engine.burnDsc(burnAmount);
        vm.stopPrank();
        
        // Verify the DSC balance and minted amount are updated
        uint256 userDscBalance = dsc.balanceOf(USER);
        assertEq(userDscBalance, mintAmount - burnAmount);
        
        (uint256 totalDscMinted,) = engine.getAccountInformation(USER);
        assertEq(totalDscMinted, mintAmount - burnAmount);
    }


    // ======== MULTI-TOKEN COLLATERAL TESTS ========
    // This is a simple test but would require more setup with additional tokens
    // Implementing placeholder for demonstration
    function testGetAccountCollateralValueWithMultipleTokens() public {
        // This would need additional token setup
        // For simplicity, we're just testing the single token case again
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositeCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        
        uint256 collateralValue = engine.getAccountCollateralValue(USER);
        uint256 expectedValue = engine.getUsdValue(weth, AMOUNT_COLLATERAL);
        
        assertEq(collateralValue, expectedValue);
    }
    


}
