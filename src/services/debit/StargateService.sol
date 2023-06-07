// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IOracle } from "../../interfaces/IOracle.sol";
import { IFactory } from "../../interfaces/external/dex/IFactory.sol";
import { IPool } from "../../interfaces/external/dex/IPool.sol";
import { IStargateRouter } from "../../interfaces/external/stargate/IStargateRouter.sol";
import { IStargateLPStaking, IStargatePool } from "../../interfaces/external/stargate/IStargateLPStaking.sol";
import { VaultHelper } from "../../libraries/VaultHelper.sol";
import { ConstantRateModel } from "../../irmodels/ConstantRateModel.sol";
import { DebitService } from "../DebitService.sol";
import { Service } from "../Service.sol";
import { Whitelisted } from "../Whitelisted.sol";

/// @title    StargateService contract
/// @author   Ithil
/// @notice   A service to perform leveraged lping on any Stargate pool
contract StargateService is Whitelisted, ConstantRateModel, DebitService {
    using SafeERC20 for IERC20;
    using SafeERC20 for IStargatePool;

    struct PoolData {
        uint16 poolID;
        uint256 stakingPoolID;
        address lpToken;
    }
    IStargateRouter public immutable stargateRouter;
    IStargateLPStaking public immutable stargateLPStaking;
    address public immutable stargate;
    mapping(address => PoolData) public pools;
    mapping(address => uint256) public totalDeposits;
    IOracle public immutable oracle;
    IFactory public immutable factory;

    event PoolWasAdded(address indexed token);
    event PoolWasRemoved(address indexed token);
    error InexistentPool();
    error AmountTooLow();
    error InsufficientAmountOut();
    error ZeroConvertRate();
    error ZeroTotalLiquidity();
    error ZeroTotalSupply();

    constructor(
        address _manager,
        address _oracle,
        address _factory,
        address _stargateRouter,
        address _stargateLPStaking,
        uint256 _deadline
    ) Service("StargateService", "STARGATE-SERVICE", _manager, _deadline) {
        oracle = IOracle(_oracle);
        factory = IFactory(_factory);
        stargateRouter = IStargateRouter(_stargateRouter);
        stargateLPStaking = IStargateLPStaking(_stargateLPStaking);
        stargate = stargateLPStaking.stargate();
    }

    function _open(Agreement memory agreement, bytes memory /*data*/) internal override {
        PoolData memory pool = pools[agreement.loans[0].token];
        if (pool.poolID == 0) revert InexistentPool();

        if (_expectedMintedTokens(agreement.loans[0].amount + agreement.loans[0].margin, pool.lpToken) == 0)
            revert AmountTooLow();
        stargateRouter.addLiquidity(pool.poolID, agreement.loans[0].amount + agreement.loans[0].margin, address(this));
        agreement.collaterals[0].amount = IERC20(pool.lpToken).balanceOf(address(this));

        stargateLPStaking.deposit(pool.stakingPoolID, agreement.collaterals[0].amount);
        // upon deposit you receive some STG tokens
    }

    function _close(uint256 /*tokenID*/, Agreement memory agreement, bytes memory data) internal override {
        PoolData memory pool = pools[agreement.loans[0].token];

        uint256 minAmountsOut = abi.decode(data, (uint256));
        uint256 initialBalance = IERC20(agreement.loans[0].token).balanceOf(address(this));
        stargateLPStaking.withdraw(pool.stakingPoolID, agreement.collaterals[0].amount);
        // upon withdrawal you receive some STG tokens

        stargateRouter.instantRedeemLocal(
            pools[agreement.loans[0].token].poolID,
            agreement.collaterals[0].amount,
            address(this)
        );

        if (IERC20(agreement.loans[0].token).balanceOf(address(this)) - initialBalance < minAmountsOut)
            revert InsufficientAmountOut();
    }

    function quote(Agreement memory agreement) public view override returns (uint256[] memory results) {
        PoolData memory pool = pools[agreement.loans[0].token];
        if (pool.poolID == 0) revert InexistentPool();

        uint256[] memory quoted = new uint256[](1);
        quoted[0] = _expectedObtainedTokens(agreement.collaterals[0].amount, pool.lpToken);

        return quoted;
    }

    function addPool(address token, uint256 stakingPoolID) external onlyOwner {
        (address lpToken, , , ) = stargateLPStaking.poolInfo(stakingPoolID);
        IStargatePool pool = IStargatePool(lpToken);
        // check that the token provided and staking pool ID are correct
        assert(token == pool.token());

        pools[token] = PoolData({ poolID: uint16(pool.poolId()), stakingPoolID: stakingPoolID, lpToken: lpToken });

        // Approval for the main token
        if (IERC20(token).allowance(address(this), address(stargateRouter)) == 0)
            IERC20(token).safeApprove(address(stargateRouter), type(uint256).max);
        // Approval for the lpToken
        if (pool.allowance(address(this), address(stargateLPStaking)) == 0)
            pool.safeApprove(address(stargateLPStaking), type(uint256).max);

        emit PoolWasAdded(token);
    }

    function removePool(address token) external onlyOwner {
        PoolData memory pool = pools[token];
        assert(pool.poolID != 0);

        delete pools[token];

        emit PoolWasRemoved(token);
    }

    function harvest(address poolToken) external {
        PoolData memory pool = pools[poolToken];
        if (pools[poolToken].poolID == 0) revert InexistentPool();

        address[] memory tokens = new address[](1);
        tokens[0] = poolToken;
        (address token, address vault) = VaultHelper.getBestVault(tokens, manager);

        stargateLPStaking.withdraw(pool.stakingPoolID, 0);

        // TODO check oracle
        uint256 price = oracle.getPrice(stargate, token, 1);
        address dexPool = factory.pools(stargate, token);
        // TODO add discount
        IPool(dexPool).createOrder(IERC20(stargate).balanceOf(address(this)), price, vault, block.timestamp + 30 days);

        // TODO add premium to the caller
    }

    function _expectedMintedTokens(uint256 amount, address lpToken) internal view returns (uint256 expected) {
        IStargatePool pool = IStargatePool(lpToken);

        (uint256 convertRate, uint256 totalLiquidity) = (pool.convertRate(), pool.totalLiquidity());
        if (convertRate == 0) revert ZeroConvertRate();
        if (totalLiquidity == 0) revert ZeroTotalLiquidity();
        uint256 amountSD = amount / convertRate;
        uint256 mintFeeSD = (amountSD * pool.mintFeeBP()) / 10000;
        // The following will not underflow if mintFeeBP <= 10000;
        amountSD = amountSD - mintFeeSD;
        expected = (amountSD * pool.totalSupply()) / totalLiquidity;
    }

    function _expectedObtainedTokens(uint256 amount, address lpToken) internal view returns (uint256 expected) {
        IStargatePool pool = IStargatePool(lpToken);

        uint256 totalSupply = pool.totalSupply();
        if (totalSupply == 0) revert ZeroTotalSupply();
        uint256 amountSD = (amount * pool.totalLiquidity()) / totalSupply;
        expected = amountSD * pool.convertRate();
    }
}
