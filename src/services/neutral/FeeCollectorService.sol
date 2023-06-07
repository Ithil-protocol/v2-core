// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IVault } from "../../interfaces/IVault.sol";
import { GeneralMath } from "../../libraries/GeneralMath.sol";
import { Whitelisted } from "../Whitelisted.sol";
import { Service } from "../Service.sol";
import { VeIthil } from "../../VeIthil.sol";

/// @title    FeeCollectorService contract
/// @author   Ithil
/// @notice   A service to perform leveraged staking on any Aave markets
contract FeeCollectorService is Service {
    using GeneralMath for uint256;
    using SafeERC20 for IERC20;

    // Percentage of fees which can be harvested. Only locked fees can be harvested
    uint256 public immutable feePercentage;
    IERC20 public immutable weth;
    VeIthil public immutable veToken;

    // weights for different tokens, 0 => not supported
    mapping(address => uint256) public weights;
    // Locking of the position in seconds
    mapping(uint256 => uint256) public locktimes;
    // Necessary to avoid a double harvest: harvesting is allowed only once after each repay
    mapping(address => uint256) public latestHarvest;
    // Necessary to properly distribute fees and prevent snatching
    uint256 public totalLoans;
    // 2^((n+1)/12) with 18 digit fixed point
    uint64[] internal rewards;

    event TokenWeightWasChanged(address indexed token, uint256 weight);

    error Throttled();
    error BeforeExpiry();
    error ZeroAmount();
    error UnsupportedToken();
    error MaxLockExceeded();

    constructor(address _manager, address _weth, uint256 _feePercentage)
        Service("FeeCollector", "FEE-COLLECTOR", _manager, type(uint256).max)
    {
        weth = IERC20(_weth);
        veToken = new VeIthil();

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

    function setTokenWeight(address token, uint256 weight) external onlyOwner {
        weights[token] = weight;

        emit TokenWeightWasChanged(token, weight);
    }

    // Weth weight is the same as virtual balance rather than balance
    // In this way, who locks for more time has right to more shares
    function totalAssets() public view returns (uint256) {
        return veToken.totalSupply() + weth.balanceOf(address(this));
    }

    function _open(Agreement memory agreement, bytes memory data) internal override {
        if (agreement.loans[0].margin == 0) revert ZeroAmount();
        if (weights[agreement.loans[0].token] == 0) revert UnsupportedToken();
        // Update collateral using ERC4626 formula
        agreement.loans[0].amount = totalLoans == 0
            ? agreement.loans[0].margin
            : agreement.loans[0].margin.safeMulDiv(totalLoans, totalAssets());
        // Apply reward based on lock
        uint256 monthsLocked = abi.decode(data, (uint256));
        if (monthsLocked > 11) revert MaxLockExceeded();
        agreement.loans[0].amount = agreement.loans[0].amount.safeMulDiv(
            rewards[monthsLocked] * weights[agreement.loans[0].token],
            1e36
        );
        // Total loans is updated
        totalLoans += agreement.loans[0].amount;
        // Collateral is equal to the amount of veTokens to mint
        agreement.collaterals[0].amount = agreement.loans[0].margin.safeMulDiv(
            rewards[monthsLocked] * weights[agreement.loans[0].token],
            1e36
        );
        veToken.mint(msg.sender, agreement.collaterals[0].amount);
        // register locktime
        locktimes[id] = monthsLocked + 1;
        // Deposit Ithil
        IERC20(agreement.loans[0].token).safeTransferFrom(msg.sender, address(this), agreement.loans[0].margin);
    }

    function _close(uint256 tokenID, Agreement memory agreement, bytes memory /*data*/)
        internal
        override
        expired(tokenID)
    {
        uint256 totalWithdraw = totalAssets().safeMulDiv(agreement.loans[0].amount, totalLoans);
        totalLoans -= agreement.loans[0].amount;
        veToken.burn(msg.sender, agreement.collaterals[0].amount);
        // give back Ithil tokens
        IERC20(agreement.loans[0].token).safeTransfer(msg.sender, agreement.loans[0].margin);
        // Transfer weth
        weth.safeTransfer(msg.sender, totalWithdraw.positiveSub(agreement.collaterals[0].amount));
    }

    function withdrawFees(uint256 tokenId) external returns (uint256) {
        if (ownerOf(tokenId) != msg.sender) revert RestrictedAccess();
        Agreement memory agreement = agreements[tokenId];
        // This is the total withdrawable, consisting of virtualIthil + weth
        // Thus it has no physical meaning: it's an auxiliary variable
        uint256 totalWithdraw = totalAssets().safeMulDiv(agreement.loans[0].amount, totalLoans);
        // By subtracting the Ithil staked we get only the weth part: this is the weth the user is entitled to
        uint256 toTransfer = totalWithdraw.positiveSub(agreement.collaterals[0].amount);
        // Update collateral and totalCollateral
        // With the new state, we will have totalAssets * collateral / totalCollateral = margin
        // Thus, the user cannot withdraw again (unless other fees are generated)
        uint256 toSubtract = agreement.loans[0].amount.safeMulDiv(toTransfer, totalWithdraw);
        agreement.loans[0].amount -= toSubtract;
        totalLoans -= toSubtract;
        weth.safeTransfer(msg.sender, toTransfer);

        return toTransfer;
    }

    function _harvestFees(address token) internal {
        IVault vault = IVault(manager.vaults(token));
        (uint256 profits, uint256 losses, uint256 latestRepay) = vault.getFeeStatus();
        if (latestRepay < latestHarvest[token]) revert Throttled();
        latestHarvest[token] = block.timestamp;

        uint256 feesToHarvest = (profits.positiveSub(losses)).safeMulDiv(feePercentage, GeneralMath.RESOLUTION);
        // todo: what is that "maxAmountIn"? For now it's uint256(-1) to avoid reversals
        manager.borrow(token, feesToHarvest, 0, address(this));
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
