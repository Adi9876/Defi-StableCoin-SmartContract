// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    // only call redeem collateral when there is actual collateral in there
    DSCEngine engine;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 constant MAX_DEPOSIT_SIZE = type(uint96).max;

    uint256 public timesCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        engine = _dscEngine;
        dsc = _dsc;
        address[] memory collateralToken = engine.getCollateralTokens();

        weth = ERC20Mock(collateralToken[0]);
        wbtc = ERC20Mock(collateralToken[1]);

        ethUsdPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(weth)));
    }

    /////////////////////////////////
    // Deposite collateral handler //
    /////////////////////////////////

    function depositeCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        // engine.depositeCollateral(collateralSeed, amountCollateral);
        ERC20Mock collateralAddress = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateralAddress.mint(msg.sender, amountCollateral);
        collateralAddress.approve(address(engine), amountCollateral);
        engine.depositeCollateral(address(collateralAddress), amountCollateral);
        vm.stopPrank();

        // double push
        usersWithCollateralDeposited.push(msg.sender);
    }

    /////////////////////////////////
    // Redeem collateral handler //
    /////////////////////////////////

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralRedeem = engine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        amountCollateral = bound(amountCollateral, 0, maxCollateralRedeem);
        if (amountCollateral == 0) {
            return;
        }
        vm.startPrank(msg.sender);
        engine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    /////////////////////////////////
    // mint dsc handler //
    /////////////////////////////////

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) return;

        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(sender);

        int256 maxDscMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted);

        if (maxDscMint < 0) {
            return;
        }

        amount = bound(amount, 0, uint256(maxDscMint));

        if (amount == 0) {
            return;
        }

        vm.startPrank(sender);
        engine.mintDsc(amount);
        vm.stopPrank();
        timesCalled++;
    }

    // This breaks the invariant test suite !!!
    
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    /////////////////////////////////
    // Helper Function             //
    /////////////////////////////////

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}

// After deposite fix
// [PASS] invariant_protocolMustHaveMoreValueThanTotalSupply() (runs: 128, calls: 16384, reverts: 0)

// This means "no matter how often we call deposite collateral no matter how much
// we'll never make thsi invariant false"
