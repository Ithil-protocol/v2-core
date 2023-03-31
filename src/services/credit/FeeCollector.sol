pragma solidity =0.8.17;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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

    // Locking of the position in seconds
    uint256 public immutable duration;

    // Percentage of fees which can be harvested. Only locked fees can be harvested
    uint256 public immutable feePercentage;

    // Necessary to avoid a double harvest: harvesting is allowed only once after each repay
    mapping(address => uint256) public latestHarvest;

    // Necessary to prevent donation attacks which could lock weth inside the contract forever
    // This also allows this contract to support fees in ITHIL
    uint256 public totalDeposits;

    error Throttled();
    error BeforeExpiry();
    error ZeroAmount();

    constructor(address _manager, address _weth, address _ithil, uint256 _duration, uint256 _feePercentage)
        Service("FeeCollector", "FEE-COLLECTOR", _manager)
    {
        weth = IERC20(_weth);
        ithil = IERC20(_ithil);
        duration = _duration;
        feePercentage = _feePercentage;
    }

    modifier expired(Agreement memory agreement) {
        if (agreement.createdAt + duration > block.timestamp) revert BeforeExpiry();
        _;
    }

    function _open(Agreement memory agreement, bytes memory data) internal override {
        if (agreement.loans[0].margin == 0) revert ZeroAmount();
        totalDeposits += agreement.loans[0].margin;
        ithil.transferFrom(msg.sender, address(this), agreement.loans[0].margin);
    }

    function _close(uint256 /*tokenID*/, Agreement memory agreement, bytes memory /*data*/)
        internal
        override
        expired(agreement)
    {
        console2.log("0");
        totalDeposits -= agreement.loans[0].margin;
        console2.log("1");
        uint256 currentBalance = weth.balanceOf(address(this)); // gas savings
        console2.log("2");
        ithil.transfer(msg.sender, agreement.loans[0].margin);
        console2.log("3");
        if (currentBalance > 0)
            weth.transfer(
                msg.sender,
                currentBalance.safeMulDiv(agreement.loans[0].margin, totalDeposits + agreement.loans[0].margin)
            );
        console2.log("4");
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
        vault.redeem(sharesToMint, address(this), address(this));
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
