// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { console2 } from "forge-std/console2.sol";
import { Test } from "forge-std/Test.sol";
import { IVault } from "../src/interfaces/IVault.sol";
import { GeneralMath } from "../src/libraries/GeneralMath.sol";
import { FeeCollector } from "../src/FeeCollector.sol";
import { IManager, Manager } from "../src/Manager.sol";
import { Ithil } from "../src/Ithil.sol";

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Router {
    function factory() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);

    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}

contract FeeCollectorTest is Test {
    using GeneralMath for uint256;

    address internal constant user1 = address(uint160(uint(keccak256(abi.encodePacked("User1")))));
    address internal constant user2 = address(uint160(uint(keccak256(abi.encodePacked("User2")))));
    IERC20 internal constant weth = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address internal constant wethWhale = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
    IUniswapV2Router internal constant router = IUniswapV2Router(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
    IERC20 internal immutable ithil;
    Manager internal immutable manager;
    FeeCollector internal immutable collector;
    address internal immutable pair;
    IVault internal immutable wethVault;

    constructor() {
        uint256 forkId = vm.createFork(vm.envString("ARBITRUM_RPC_URL"), 56960635);
        vm.selectFork(forkId);

        manager = new Manager();
        collector = new FeeCollector(address(manager), weth);
        ithil = new Ithil();
        pair = IUniswapV2Factory(router.factory()).createPair(address(ithil), address(weth));

        manager.create(address(weth));
        wethVault = IVault(manager.vaults(address(weth)));
    }

    function setUp() public {
        manager.setFeeCollector(address(collector));

        vm.deal(wethWhale, 1 ether);
        vm.startPrank(wethWhale);
        weth.transfer(address(this), 10 * 1e18);
        weth.approve(address(wethVault), type(uint256).max);
        vm.stopPrank();

        weth.approve(address(router), type(uint256).max);
        ithil.approve(address(router), type(uint256).max);
        ithil.approve(address(collector), type(uint256).max);

        vm.startPrank(user1);
        weth.approve(address(router), type(uint256).max);
        ithil.approve(address(router), type(uint256).max);
        vm.stopPrank();

        router.addLiquidity(address(ithil), address(weth), 1e5 * 1e18, 10 * 1e18, 1, 1, address(this), block.timestamp);
    }

    function testStakingBase(uint256 amount) public {
        amount = bound(amount, 1, ithil.balanceOf(address(this)));

        uint256 balance = ithil.balanceOf(address(this));

        vm.expectRevert(bytes4(keccak256(abi.encodePacked("TokenNotSupported()"))));
        collector.stake(address(ithil), amount);

        collector.setTokenWeight(address(ithil), 1);

        assertTrue(IERC20(address(collector)).balanceOf(address(this)) == 0);
        collector.stake(address(ithil), amount);
        assertTrue(IERC20(address(collector)).balanceOf(address(this)) == amount);

        collector.unstake(address(ithil), amount);
        assertTrue(IERC20(address(collector)).balanceOf(address(this)) == 0);
        assertTrue(ithil.balanceOf(address(this)) == balance);

        balance = ithil.balanceOf(address(this));

        collector.setTokenWeight(address(ithil), 2);
        collector.stake(address(ithil), amount);

        vm.expectRevert(bytes4(keccak256(abi.encodePacked("InsufficientAmountDeposited()"))));
        collector.unstake(address(ithil), amount + 1);

        collector.setTokenWeight(address(ithil), 1);
        collector.unstake(address(ithil), amount);

        assertTrue(IERC20(address(collector)).balanceOf(address(this)) == 0);
        assertTrue(ithil.balanceOf(address(this)) == balance);
    }

    function testStakingAdvanced() public {
        uint256 amountIthil = 1000 * 1e18;
        uint256 amountWeth = 1 * 1e18;

        vm.prank(wethWhale);
        weth.transfer(user1, amountWeth);
        ithil.transfer(user1, amountIthil);

        vm.prank(user1);
        router.addLiquidity(address(ithil), address(weth), amountIthil, amountWeth, 1, 1, user1, block.timestamp);
        uint256 obtained = IERC20(pair).balanceOf(user1);

        collector.setTokenWeight(address(ithil), 1);
        collector.setTokenWeight(pair, 2);

        vm.startPrank(user1);
        IERC20(pair).approve(address(collector), obtained);
        collector.stake(pair, obtained);
        vm.stopPrank();

        assertTrue(IERC20(pair).balanceOf(user1) == 0);

        vm.prank(user1);
        collector.unstake(pair, obtained);

        assertTrue(IERC20(pair).balanceOf(user1) == obtained);
    }

    function testCollectFees() public {
        vm.prank(wethWhale);
        wethVault.deposit(1e18, wethWhale);

        uint256 amount = 1000 * 1e18;
        ithil.transfer(user1, amount);

        collector.setTokenWeight(address(ithil), 1);

        vm.startPrank(user1);
        ithil.approve(address(collector), amount);
        collector.stake(address(ithil), amount);
        vm.stopPrank();

        // generate fees
        vm.prank(wethWhale);
        weth.transfer(address(wethVault), 100 * 1e18);

        address[] memory tokens = new address[](1);
        tokens[0] = address(weth);
        collector.harvestFees(tokens);
    }
}
