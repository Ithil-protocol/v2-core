// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20, ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract FeeRedistributor is ERC20, ERC20Permit, ERC20Votes, Ownable {
    using SafeERC20 for IERC20;

    struct Balance {
        uint256 deposited;
        uint256 minted;
    }

    /// @dev tokens with relative weights, if 0 then not supported
    mapping(address => uint256) public weights;
    /// @dev user => token address => amount deposited
    mapping(address => mapping(address => Balance)) public balances;

    event TokenWeightWasChanged(address indexed token, uint256 newWeight);
    error TokenNotSupported();
    error InsufficientAmountDeposited();
    error NullAmount();

    constructor() ERC20("stITHIL", "STAKED ITHIL") ERC20Permit("stITHIL") {}

    function stake(address token, uint256 amount) external {
        if (weights[token] == 0) revert TokenNotSupported();

        uint256 minted = amount * weights[token];
        balances[msg.sender][token] = Balance(amount, minted);
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        _mint(msg.sender, minted);
    }

    function unstake(address token, uint256 amount) external {
        if (amount == 0) revert NullAmount();
        if (balances[msg.sender][token].deposited < amount) revert InsufficientAmountDeposited();

        balances[msg.sender][token].deposited -= amount;
        IERC20(token).safeTransfer(msg.sender, amount);

        uint256 oldWeight = balances[msg.sender][token].minted / amount;
        uint256 toBurn = amount * oldWeight;
        balances[msg.sender][token].minted -= toBurn;
        _burn(msg.sender, toBurn);
    }

    function setTokenWeight(address token, uint256 val) external onlyOwner {
        weights[token] = val;

        emit TokenWeightWasChanged(token, val);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        ERC20Votes._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        ERC20Votes._mint(to, amount);
    }

    function _burn(address account, uint256 amount) internal override(ERC20, ERC20Votes) {
        ERC20Votes._burn(account, amount);
    }
}
