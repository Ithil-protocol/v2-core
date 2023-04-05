// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Service } from "../Service.sol";
import { IVault } from "../../interfaces/IVault.sol";
import { GeneralMath } from "../../libraries/GeneralMath.sol";
import { Whitelisted } from "../Whitelisted.sol";

import { console2 } from "forge-std/console2.sol";

/// @title    FeeCollector contract
/// @author   Ithil
/// @notice   A service to perform leveraged staking on any Aave markets
contract FeeCollector is Service {
    using GeneralMath for uint256;

    IERC20 public immutable weth;
    IERC20 public immutable ithil;

    // todo: must be non-transferrable
    IERC20 public immutable veToken;

    // 2^((n+1)/12) with 18 digit fixed point
    uint64[] internal rewards;

    // Locking of the position in seconds
    mapping(uint256 => uint256) public locktimes;

    // Percentage of fees which can be harvested. Only locked fees can be harvested
    uint256 public immutable feePercentage;

    // Necessary to avoid a double harvest: harvesting is allowed only once after each repay
    mapping(address => uint256) public latestHarvest;

    // Necessary to properly distribute fees and prevent snatching
    uint256 public totalCollateral;
    // Necessary to implement convexity in locktimes
    uint256 public virtualIthilBalance;

    error Throttled();
    error BeforeExpiry();
    error ZeroAmount();
    error WrongTokens();
    error MaxLockExceeded();

    constructor(address _manager, address _weth, address _ithil, address _veToken, uint256 _feePercentage)
        Service("FeeCollector", "FEE-COLLECTOR", _manager)
    {
        weth = IERC20(_weth);
        ithil = IERC20(_ithil);
        veToken = IERC20(_veToken);
        feePercentage = _feePercentage;
        rewards = new uint64[](12);
        rewards[0] = 1059463094359295265;
        rewards[1] = 1122462048309372981;
        rewards[2] = 1189207115002721067;
        rewards[3] = 1259921049894873165;
        rewards[4] = 1334839854170034365;
        rewards[5] = 1414213562373095049;
        rewards[6] = 1498307076876681499;
        rewards[7] = 1587401051968199475;
        rewards[8] = 1681792830507429086;
        rewards[9] = 1781797436280678609;
        rewards[10] = 1887748625363386993;
        rewards[11] = 2000000000000000000;
    }

    modifier expired(uint256 tokenId) {
        if (agreements[tokenId].createdAt + locktimes[tokenId] * 86400 * 30 > block.timestamp) revert BeforeExpiry();
        _;
    }

    // Weth weight is the same as virtual balance rather than balance
    // In this way, who locks for more time has right to more shares
    function totalAssets() public view returns (uint256) {
        return virtualIthilBalance + weth.balanceOf(address(this));
    }

    function _open(Agreement memory agreement, bytes memory data) internal override {
        if (agreement.loans[0].margin == 0) revert ZeroAmount();
        if (agreement.loans[0].token != address(ithil)) revert WrongTokens();
        // Update collateral using ERC4626 formula
        agreement.collaterals[0].amount = totalCollateral == 0
            ? agreement.loans[0].margin
            : agreement.loans[0].margin.safeMulDiv(totalCollateral, totalAssets());
        // Apply reward based on lock
        uint256 monthsLocked = abi.decode(data, (uint256));
        if (monthsLocked > 11) revert MaxLockExceeded();
        agreement.collaterals[0].amount = agreement.collaterals[0].amount.safeMulDiv(rewards[monthsLocked], 1e18);
        // Total collateral is updated
        totalCollateral += agreement.collaterals[0].amount;
        // Virtual balance is updated
        virtualIthilBalance += agreement.loans[0].margin.safeMulDiv(rewards[monthsLocked], 1e18);
        // register locktime
        locktimes[id] = monthsLocked;
        // Deposit Ithil
        ithil.transferFrom(msg.sender, address(this), agreement.loans[0].margin);
        // todo: transfer/mint veToken
    }

    function _close(uint256 tokenID, Agreement memory agreement, bytes memory /*data*/)
        internal
        override
        expired(tokenID)
    {
        uint256 totalWithdraw = totalAssets().safeMulDiv(agreement.collaterals[0].amount, totalCollateral);
        totalCollateral -= agreement.collaterals[0].amount;
        virtualIthilBalance -= agreement.loans[0].margin.safeMulDiv(rewards[locktimes[tokenID]], 1e18);
        // give back Ithil tokens
        ithil.transfer(msg.sender, agreement.loans[0].margin);
        // Transfer weth
        weth.transfer(
            msg.sender,
            totalWithdraw.positiveSub(agreement.loans[0].margin.safeMulDiv(rewards[locktimes[tokenID]], 1e18))
        );
        // todo: transfer/burn veToken
    }

    function withdrawFees(uint256 tokenId) external returns (uint256) {
        if (ownerOf(tokenId) != msg.sender) revert RestrictedAccess();
        Agreement memory agreement = agreements[tokenId];
        // This is the total withdrawable, consisting of virtualIthil + weth
        // Thus it has no physical meaning: it's an auxiliary variable
        uint256 totalWithdraw = totalAssets().safeMulDiv(agreement.collaterals[0].amount, totalCollateral);
        // By subtracting the Ithil staked we get only the weth part: this is the weth the user is entitled to
        uint256 toTransfer = totalWithdraw.positiveSub(
            agreement.loans[0].margin.safeMulDiv(rewards[locktimes[tokenId]], 1e18)
        );
        // Update collateral and totalCollateral
        // With the new state, we will have totalAssets * collateral / totalCollateral = margin
        // Thus, the user cannot withdraw again (unless other fees are generated)
        agreement.collaterals[0].amount -= agreement.collaterals[0].amount.safeMulDiv(toTransfer, totalWithdraw);
        totalCollateral -= agreement.collaterals[0].amount.safeMulDiv(toTransfer, totalWithdraw);
        weth.transfer(msg.sender, toTransfer);
    }

    function _harvestFees(address token) internal {
        IVault vault = IVault(manager.vaults(token));
        (uint256 profits, uint256 losses, uint256 latestRepay) = vault.getStatus();
        if (latestRepay < latestHarvest[token]) revert Throttled();
        latestHarvest[token] = block.timestamp;

        uint256 feesToHarvest = (profits.positiveSub(losses)).safeMulDiv(feePercentage, GeneralMath.RESOLUTION);
        uint256 sharesToMint = vault.convertToShares(feesToHarvest);
        // todo: what is that "maxAmountIn"? For now it's uint256(-1) to avoid reversals
        manager.directMint(token, address(this), sharesToMint, exposures[token], type(uint256).max);
        uint256 assets = vault.redeem(sharesToMint, address(this), address(this));
        // todo: reward harvester
    }

    function harvestAndSwap(address[] calldata tokens) external {
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; i++) {
            _harvestFees(tokens[i]);
            // TODO swap if not WETH for WETH
        }
    }
}
