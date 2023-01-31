// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IVault } from "../src/interfaces/IVault.sol";
import { GeneralMath } from "../src/libraries/GeneralMath.sol";
import { FeeRedistributor } from "../src/FeeRedistributor.sol";
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

contract FeeRedistributorTest is PRBTest, StdCheats {
    using GeneralMath for uint256;

    address internal constant user1 = address(uint160(uint(keccak256(abi.encodePacked("User1")))));
    address internal constant user2 = address(uint160(uint(keccak256(abi.encodePacked("User2")))));
    IERC20 internal constant weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address internal constant wethWhale = 0x2fEb1512183545f48f6b9C5b4EbfCaF49CfCa6F3;
    IUniswapV2Router internal constant router = IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IERC20 internal immutable ithil;
    FeeRedistributor internal immutable redistributor;
    address internal immutable pair;

    constructor() {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"), 16448665);
        vm.selectFork(forkId);

        redistributor = new FeeRedistributor();
        ithil = new Ithil();
        pair = IUniswapV2Factory(router.factory()).createPair(address(ithil), address(weth));
    }

    function setUp() public {
        vm.deal(wethWhale, 1 ether);
        vm.prank(wethWhale);
        weth.transfer(address(this), 10 * 1e18);

        weth.approve(address(router), type(uint256).max);
        ithil.approve(address(router), type(uint256).max);

        vm.startPrank(user1);
        weth.approve(address(router), type(uint256).max);
        ithil.approve(address(router), type(uint256).max);
        vm.stopPrank();

        router.addLiquidity(address(ithil), address(weth), 1e5 * 1e18, 10 * 1e18, 1, 1, address(this), block.timestamp);
    }

    function testStakingBase() public {
        uint256 initialBalance = ithil.balanceOf(address(this));

        ithil.approve(address(redistributor), type(uint256).max);
        vm.expectRevert(bytes4(keccak256(abi.encodePacked("TokenNotSupported()"))));
        redistributor.stake(address(ithil), 1e18);

        redistributor.setTokenWeight(address(ithil), 1);

        assertTrue(IERC20(address(redistributor)).balanceOf(address(this)) == 0);
        redistributor.stake(address(ithil), 1e18);
        assertTrue(IERC20(address(redistributor)).balanceOf(address(this)) == 1e18);

        redistributor.unstake(address(ithil), 1e18);
        assertTrue(IERC20(address(redistributor)).balanceOf(address(this)) == 0);
        assertTrue(ithil.balanceOf(address(this)) == initialBalance);
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

        redistributor.setTokenWeight(address(ithil), 1);
        redistributor.setTokenWeight(pair, 2);

        vm.startPrank(user1);
        IERC20(pair).approve(address(redistributor), obtained);
        redistributor.stake(pair, obtained);
        vm.stopPrank();

        assertTrue(IERC20(address(redistributor)).balanceOf(user1) == obtained * 2);
    }
}
