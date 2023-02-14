// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import { ERC4626, IERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IManager } from "./interfaces/IManager.sol";
import { console2 } from "forge-std/console2.sol";

contract FeeCollector is ERC4626, ERC20Permit, Ownable {
    using SafeERC20 for IERC20;

    IManager public immutable manager;
    IERC20 public immutable weth;
    mapping(address => uint256) public weights;
    uint256 public fee;
    mapping(address => uint256) public harvests;
    mapping(address => mapping(address => uint256)) public deposits;

    event TokenWeightWasChanged(address indexed token, uint256 newWeight);
    event FeePercentageWasChanged(uint256 newVal);
    error TokenNotSupported();
    error InsufficientAmountDeposited();

    constructor(address _manager, IERC20 _weth) ERC20("stIthil", "STAKED ITHIL") ERC20Permit("stIthil") ERC4626(_weth) {
        manager = IManager(_manager);
        weth = _weth;
    }

    function decimals() public view override(ERC4626, ERC20) returns (uint8) {
        return ERC4626.decimals();
    }

    function stake(address token, uint256 amount) external {
        if (weights[token] == 0) revert TokenNotSupported();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        deposits[msg.sender][token] += amount;
        _mint(msg.sender, amount * weights[token]);
    }

    function unstake(address token, uint256 amount) external {
        if (deposits[msg.sender][token] < amount) revert InsufficientAmountDeposited();

        deposits[msg.sender][token] -= amount;
        _burn(msg.sender, amount);
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    function harvestFees(address[] calldata tokens) external {
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; i++) {
            manager.harvestFees(tokens[i], fee, address(this), harvests[tokens[i]]);
            harvests[tokens[i]] = block.timestamp;
            console2.log("balance", IERC20(tokens[i]).balanceOf(address(this)));
            // TODO swap if not WETH for WETH
        }
    }

    function setFee(uint256 val) external onlyOwner {
        fee = val;

        emit FeePercentageWasChanged(val);
    }

    function setTokenWeight(address token, uint256 val) external onlyOwner {
        weights[token] = val;

        emit TokenWeightWasChanged(token, val);
    }
}
