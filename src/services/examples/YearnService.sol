// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IYearnRegistry } from "../../interfaces/external/IYearnRegistry.sol";
import { IYearnVault } from "../../interfaces/external/IYearnVault.sol";
import { SecuritisableService } from "../SecuritisableService.sol";
import { Service } from "../Service.sol";

contract YearnService is SecuritisableService {
    IYearnRegistry public immutable registry;

    error YVaultMismatch();

    constructor(address manager, address yearnRegistry) Service("YearnService", "YEARN-SERVICE", manager) {
        registry = IYearnRegistry(yearnRegistry);
    }

    function _open(Agreement memory agreement, bytes calldata /*data*/) internal override {
        address yvault = registry.latestVault(agreement.loans[0].token);
        if (yvault != agreement.collaterals[0].token) revert YVaultMismatch();

        IERC20 token = IERC20(agreement.loans[0].token);
        token.approve(yvault, agreement.loans[0].amount);

        IYearnVault(yvault).deposit(agreement.loans[0].amount, address(this));
    }

    function edit(uint256 tokenID, Agreement calldata agreement, bytes calldata data) public override {}

    function _close(uint256 tokenID, Agreement memory agreement, bytes calldata data) internal override {
        uint256 acceptedLoss = abi.decode(data, (uint256));

        IYearnVault yvault = IYearnVault(agreement.collaterals[0].token);
        uint256 expectedObtained = (yvault.pricePerShare() * agreement.collaterals[0].amount) /
            (10**IERC20Metadata(agreement.loans[0].token).decimals());
        uint256 maxLoss = (expectedObtained - acceptedLoss * 10000) / expectedObtained;
        yvault.withdraw(agreement.collaterals[0].amount, address(this), maxLoss);
    }

    function quote(Agreement memory agreement)
        public
        view
        override
        returns (uint256[] memory results, uint256[] memory)
    {
        // use collateral
        try registry.latestVault(agreement.collaterals[0].token) returns (address vaultAddress) {
            IYearnVault yvault = IYearnVault(vaultAddress);
            uint256 decimals = 10**IERC20Metadata(agreement.collaterals[0].token).decimals();
            results[0] = (agreement.collaterals[0].amount * decimals) / yvault.pricePerShare();
        } catch {
            // use loan
            address vaultAddress = registry.latestVault(agreement.loans[0].token);
            IYearnVault yvault = IYearnVault(vaultAddress);
            uint256 decimals = 10**IERC20Metadata(agreement.loans[0].token).decimals();
            results[0] = (agreement.loans[0].amount * yvault.pricePerShare()) / decimals;
        }
    }
}
