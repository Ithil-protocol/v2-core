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

    // Locking of the position in seconds
    uint256 public immutable duration;

    // Percentage of fees which can be harvested. Only locked fees can be harvested
    uint256 public immutable feePercentage;

    // Necessary to avoid a double harvest: harvesting is allowed only once after each repay
    mapping(address => uint256) public latestHarvest;

    // Necessary to properly distribute fees and prevent snatching
    uint256 public totalCollateral;

    error Throttled();
    error BeforeExpiry();
    error ZeroAmount();
    error WrongTokens();

    constructor(address _manager, address _weth, address _ithil, uint256 _duration, uint256 _feePercentage)
        Service("FeeCollector", "FEE-COLLECTOR", _manager)
    {
        weth = IERC20(_weth);
        ithil = IERC20(_ithil);
        veToken = IERC20(
            new ERC20(
                string(abi.encodePacked("vested Ithil ", _duration / 604800, " weeks")),
                string(abi.encodePacked("ve", IERC20Metadata(_ithil).symbol(), _duration / 604800))
            )
        );
        duration = _duration;
        feePercentage = _feePercentage;
    }

    modifier expired(Agreement memory agreement) {
        if (agreement.createdAt + duration > block.timestamp) revert BeforeExpiry();
        _;
    }

    // The 1:1 weight is arbitrary, but we use it because it makes computations simpler
    function totalAssets() public view returns (uint256) {
        return ithil.balanceOf(address(this)) + weth.balanceOf(address(this));
    }

    function _open(Agreement memory agreement, bytes memory data) internal override {
        if (agreement.loans[0].margin == 0) revert ZeroAmount();
        if (agreement.loans[0].token != address(ithil)) revert WrongTokens();
        // Update collateral using ERC4626 formula
        agreement.collaterals[0].amount = totalCollateral == 0
            ? agreement.loans[0].margin
            : agreement.loans[0].margin.safeMulDiv(totalCollateral, totalAssets());
        // Total collateral is updated
        totalCollateral += agreement.collaterals[0].amount;
        // Deposit Ithil
        ithil.transferFrom(msg.sender, address(this), agreement.loans[0].margin);
        // todo: transfer/mint veToken
    }

    function _close(uint256 /*tokenID*/, Agreement memory agreement, bytes memory /*data*/)
        internal
        override
        expired(agreement)
    {
        uint256 totalWithdraw = totalAssets().safeMulDiv(agreement.collaterals[0].amount, totalCollateral);
        totalCollateral -= agreement.collaterals[0].amount;
        // give back Ithil tokens
        ithil.transfer(msg.sender, agreement.loans[0].margin);
        // Transfer weth
        weth.transfer(msg.sender, totalWithdraw.positiveSub(agreement.loans[0].margin));
        // todo: transfer/burn veToken
    }

    function withdrawFees(uint256 tokenId) external returns (uint256) {
        if (ownerOf(tokenId) != msg.sender) revert RestrictedAccess();
        Agreement memory agreement = agreements[tokenId];
        // This is the total withdrawable, consisting of ithil + weth at 1:1 weight
        // This thus has no physical meaning: it's an auxiliary variable
        uint256 totalWithdraw = totalAssets().safeMulDiv(agreement.collaterals[0].amount, totalCollateral);
        // By subtracting the Ithil staked we get only the weth part: this is the weth the user is entitled to
        uint256 toTransfer = totalWithdraw.positiveSub(agreement.loans[0].margin);
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
