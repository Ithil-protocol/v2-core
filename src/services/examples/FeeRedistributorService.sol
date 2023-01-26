// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { CreditService } from "../CreditService.sol";
import { Service } from "../Service.sol";

contract FeeRedistributorService is CreditService {
    /// @dev tokens with relative weights, if 0 then not supported
    mapping(address => uint256) public weights;
    /// @dev tokenID => token address => amount locked
    mapping(uint256 => mapping(address => uint256)) public lockedTokens;
    uint256 public lockingMultiplier;

    error TokenNotSupported();
    error NonTransferrable();

    constructor(address manager, uint256 initialLockingMultiplier)
        Service("FeeRedistributorService", "FEE-REDISTRIBUTOR-SERVICE", manager)
    {
        assert(initialLockingMultiplier != 0);
        lockingMultiplier = initialLockingMultiplier;
    }

    function _open(Agreement memory agreement, bytes calldata data) internal override {
        if (weights[agreement.collaterals[0].token] == 0) revert TokenNotSupported();

        bool lock = abi.decode(data, (bool));
        if (lock) {
            lockedTokens[id][agreement.collaterals[0].token] = agreement.collaterals[0].amount;
        }

        uint256 toMint = agreement.collaterals[0].amount * weights[agreement.collaterals[0].token] * lockingMultiplier;
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override {
        // non-transferrable or burnable token
        if (from != address(0)) revert NonTransferrable();

        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }
}
