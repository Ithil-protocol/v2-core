// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IVault } from "../../interfaces/IVault.sol";
import { IOracle } from "../../interfaces/IOracle.sol";
import { IFactory } from "../../interfaces/external/wizardex/IFactory.sol";
import { IPool } from "../../interfaces/external/wizardex/IPool.sol";
import { Whitelisted } from "../Whitelisted.sol";
import { Service } from "../Service.sol";
import { VeIthil } from "../../VeIthil.sol";

/// @title    FeeCollectorService contract
/// @author   Ithil
/// @notice   A service to perform leveraged staking on any Aave markets
contract FeeCollectorService is Service {
    using SafeERC20 for IERC20;

    // Percentage of fees which can be harvested. Only locked fees can be harvested
    uint256 public immutable feePercentage;
    IERC20 public immutable weth;
    VeIthil public immutable veToken;
    IOracle public immutable oracle;
    IFactory public immutable dex;

    // weights for different tokens, 0 => not supported
    // assumes 18 digit fixed point math
    mapping(address => uint256) public weights;
    // Necessary to avoid a double harvest: harvesting is allowed only once after each repay
    mapping(address => uint256) public latestHarvest;
    // Necessary to properly distribute fees and prevent snatching
    mapping(uint256 => uint256) public virtualDeposit;
    uint256 public totalVirtualDeposits;
    // 2^((n+1)/12) with 18 digit fixed point
    uint64[] internal _rewards;

    event TokenWeightWasChanged(address indexed token, uint256 weight);

    error Throttled();
    error InsufficientProfits();
    error ZeroLoan();
    error BeforeExpiry();
    error ZeroAmount();
    error UnsupportedToken();
    error MaxLockExceeded();
    error LockPeriodStillActive();

    // Since the maximum lock is 1 year, the deadline is 1 year + one month
    // (By convention, a month is 30 days, therefore the actual deadline is 5 or 6 days less)
    constructor(
        address _manager,
        address _weth,
        uint256 _feePercentage,
        address _oracle,
        address _dex
    ) Service("FeeCollector", "FEE-COLLECTOR", _manager, 13 * 30 * 86400) {
        veToken = new VeIthil();

        weth = IERC20(_weth);
        oracle = IOracle(_oracle);
        dex = IFactory(_dex);

        feePercentage = _feePercentage;
        _rewards = new uint64[](12);
        _rewards[0] = 1059463094359295265;
        _rewards[1] = 1122462048309372981;
        _rewards[2] = 1189207115002721067;
        _rewards[3] = 1259921049894873165;
        _rewards[4] = 1334839854170034365;
        _rewards[5] = 1414213562373095049;
        _rewards[6] = 1498307076876681499;
        _rewards[7] = 1587401051968199475;
        _rewards[8] = 1681792830507429086;
        _rewards[9] = 1781797436280678609;
        _rewards[10] = 1887748625363386993;
        _rewards[11] = 2000000000000000000;
    }

    function totalAssets() public view returns (uint256) {
        return weth.balanceOf(address(this)) + totalVirtualDeposits;
    }

    function setTokenWeight(address token, uint256 weight) external onlyOwner {
        weights[token] = weight;

        emit TokenWeightWasChanged(token, weight);
    }

    function _open(Agreement memory agreement, bytes memory data) internal override {
        if (agreement.loans[0].margin == 0) revert ZeroAmount();
        if (weights[agreement.loans[0].token] == 0) revert UnsupportedToken();
        // gas savings
        uint256 totalAssets = totalAssets();
        // Apply reward based on lock
        uint256 monthsLocked = abi.decode(data, (uint256));
        if (monthsLocked > 11) revert MaxLockExceeded();

        // we conventionally put the agreement's creation date as t0 - deadline + months + 1
        // in this way, the expiry day is equal to the maturity of the option plus one month
        // therefore, the user will have 1 month to autonomously exercise or withdraw the option after expiry
        // after that, the position will be liquidated
        agreement.createdAt = block.timestamp + (monthsLocked + 2) * 30 * 86400 - deadline;

        // Collateral is equal to the amount of veTokens to mint
        agreement.collaterals[0].amount =
            (agreement.loans[0].margin * (_rewards[monthsLocked] * weights[agreement.loans[0].token])) /
            1e36;

        // we assign a virtual deposit of v * A / S, __afterwards__ we update the total deposits
        virtualDeposit[id] = totalAssets == 0
            ? agreement.collaterals[0].amount
            : (agreement.collaterals[0].amount * totalAssets) / veToken.totalSupply();
        totalVirtualDeposits += virtualDeposit[id];

        veToken.mint(msg.sender, agreement.collaterals[0].amount);
        // Deposit Ithil
        IERC20(agreement.loans[0].token).safeTransferFrom(msg.sender, address(this), agreement.loans[0].margin);
    }

    function _close(uint256 tokenID, Agreement memory agreement, bytes memory /*data*/) internal override {
        // The position can be closed only after the locking period
        if (block.timestamp < agreement.createdAt + deadline - 30 * 86400) revert BeforeExpiry();
        uint256 totalWithdraw = (totalAssets() * agreement.collaterals[0].amount) / veToken.totalSupply();
        // Subtracting the virtual deposit we get the weth part: this is the weth the user is entitled to
        uint256 toTransfer = totalWithdraw - virtualDeposit[tokenID];
        // delete virtual deposits
        totalVirtualDeposits -= virtualDeposit[tokenID];
        delete virtualDeposit[tokenID];

        veToken.burn(msg.sender, agreement.collaterals[0].amount);
        // give back Ithil tokens
        IERC20(agreement.loans[0].token).safeTransfer(msg.sender, agreement.loans[0].margin);
        // Transfer weth
        weth.safeTransfer(msg.sender, toTransfer);
    }

    function withdrawFees(uint256 tokenId) external returns (uint256) {
        if (ownerOf(tokenId) != msg.sender) revert RestrictedAccess();
        Agreement memory agreement = agreements[tokenId];
        // gas savings
        uint256 totalAssets = totalAssets();
        uint256 totalSupply = veToken.totalSupply();
        // This is the total withdrawable, consisting of weth + virtual deposit
        uint256 totalWithdraw = (totalAssets * agreement.collaterals[0].amount) / totalSupply;
        // Subtracting the virtual deposit we get the weth part: this is the weth the user is entitled to
        uint256 toTransfer = totalWithdraw - virtualDeposit[tokenId];
        // we update the virtual deposit, and the total ones, so to mock a re-deposit after withdraw
        uint256 newVirtualDeposit = (agreement.collaterals[0].amount * (totalAssets - totalWithdraw)) /
            (totalSupply - agreement.collaterals[0].amount);
        totalVirtualDeposits = totalVirtualDeposits - virtualDeposit[tokenId] + newVirtualDeposit;
        virtualDeposit[tokenId] = newVirtualDeposit;

        weth.safeTransfer(msg.sender, toTransfer);

        return toTransfer;
    }

    function withdrawable(uint256 tokenId) public view returns (uint256) {
        Agreement memory agreement = agreements[tokenId];
        // gas savings
        uint256 totalAssets = totalAssets();
        uint256 totalSupply = veToken.totalSupply();
        // This is the total withdrawable, consisting of weth + virtual deposit
        uint256 totalWithdraw = (totalAssets * agreement.collaterals[0].amount) / totalSupply;
        // Subtracting the virtual deposit we get the weth part: this is the weth the user is entitled to
        return totalWithdraw - virtualDeposit[tokenId];
    }

    function _harvestFees(address token) internal returns (uint256, address) {
        IVault vault = IVault(manager.vaults(token));
        (uint256 profits, uint256 losses, , uint256 latestRepay) = vault.getFeeStatus();
        if (latestRepay <= latestHarvest[token]) revert Throttled();
        if (profits <= losses) revert InsufficientProfits();
        latestHarvest[token] = block.timestamp;

        uint256 feesToHarvest = ((profits - losses) * feePercentage) / 1e18;
        manager.borrow(token, feesToHarvest, 0, address(this));
        // todo: reward harvester

        return (feesToHarvest, address(vault));
    }

    function harvestAndSwap(address[] calldata tokens) external returns (uint256[] memory, uint256[] memory) {
        uint256[] memory amounts = new uint256[](tokens.length);
        uint256[] memory prices = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            (uint256 amount, ) = _harvestFees(tokens[i]);
            amounts[i] = amount;

            // Swap if not WETH
            if (tokens[i] != address(weth)) {
                // TODO check assumption: all pools will have same the tick
                IPool pool = IPool(dex.pools(tokens[i], address(weth), 5));
                // We allow for a 10% discount in the price
                uint256 price = (oracle.getPrice(address(weth), tokens[i], IERC20Metadata(tokens[i]).decimals()) * 9) /
                    10;
                prices[i] = price;
                IERC20(tokens[i]).approve(address(pool), amount);
                pool.createOrder(amount, price, address(this), block.timestamp + 3600);
            }
        }
        return (amounts, prices);
    }
}
