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

contract StakedToken is ERC4626, ERC20Permit {
    address internal immutable owner;

    error RestrictedToOwner();
    error NotImplemented();

    constructor(IERC20Metadata _token)
        ERC20(string(abi.encodePacked("Staked ", _token.name())), string(abi.encodePacked("st", _token.symbol())))
        ERC20Permit(string(abi.encodePacked("st", _token.name())))
        ERC4626(_token)
    {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (owner != msg.sender) revert RestrictedToOwner();
        _;
    }

    function decimals() public view override(ERC4626, ERC20) returns (uint8) {
        return ERC4626.decimals();
    }

    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        revert NotImplemented();
    }

    function mint(uint256 shares, address receiver) public override returns (uint256) {
        revert NotImplemented();
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        revert NotImplemented();
    }

    function withdraw(uint256 assets, address receiver, address _owner) public override returns (uint256) {
        revert NotImplemented();
    }
}

contract FeeCollector is Ownable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Metadata;

    /// @dev tokens with relative weights, if 0 then not supported
    mapping(address => uint256) public weights;
    /// @dev staked token => ERC4626 token
    mapping(address => address) public stakedTokens;
    // fee sharing mechanism
    uint256 public fee;
    mapping(address => uint256) public harvests;
    IManager public immutable manager;

    event TokenWeightWasChanged(address indexed token, uint256 newWeight);
    event FeePercentageWasChanged(uint256 newVal);
    error TokenNotSupported();
    error InsufficientAmountDeposited();
    error NullAmount();

    constructor(address _manager) {
        manager = IManager(_manager);
    }

    function stake(address token, uint256 amount) external {
        if (weights[token] == 0) revert TokenNotSupported();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC4626(stakedTokens[token]).deposit(amount, msg.sender);
    }

    function unstake(address token, uint256 amount) external {
        IERC4626(stakedTokens[token]).withdraw(amount, msg.sender, msg.sender);
    }

    function harvestFees(address[] calldata tokens) external {
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; i++) {
            manager.harvestFees(tokens[i], fee, address(this), harvests[tokens[i]]);
            harvests[tokens[i]] = block.timestamp;
            console2.log("balance", IERC20(tokens[i]).balanceOf(address(this)));
        }
    }

    function setFee(uint256 val) external onlyOwner {
        fee = val;

        emit FeePercentageWasChanged(val);
    }

    function setTokenWeight(address token, uint256 val) external onlyOwner {
        weights[token] = val;

        IERC20Metadata tkn = IERC20Metadata(token);
        if (stakedTokens[token] == address(0)) stakedTokens[token] = address(new StakedToken(tkn));
        tkn.safeApprove(stakedTokens[token], type(uint256).max);

        emit TokenWeightWasChanged(token, val);
    }
}
