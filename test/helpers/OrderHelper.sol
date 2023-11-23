// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { IService } from "../../src/interfaces/IService.sol";

library OrderHelper {
    function createSimpleERC20Order(
        address token,
        uint256 amount,
        uint256 margin,
        address collateralToken,
        uint256 collateralAmount
    ) public view returns (IService.Order memory) {
        address[] memory tokens = new address[](1);
        tokens[0] = token;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        uint256[] memory margins = new uint256[](1);
        margins[0] = margin;

        address[] memory collateralTokens = new address[](1);
        collateralTokens[0] = collateralToken;
        uint256[] memory collateralAmounts = new uint256[](1);
        collateralAmounts[0] = collateralAmount;
        IService.ItemType[] memory itemTypes = new IService.ItemType[](1);
        itemTypes[0] = IService.ItemType.ERC20;

        return
            createAdvancedOrder(
                tokens,
                amounts,
                margins,
                itemTypes,
                collateralTokens,
                collateralAmounts,
                block.timestamp,
                ""
            );
    }

    // tokens.length = amounts.length = margins.length
    // itemTypes.length = collateralTokens.length = collateralAmounts.length
    // In general the two set of lengths can be different (e.g. Balancer, Uniswap)
    function createAdvancedOrder(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory margins,
        IService.ItemType[] memory itemTypes,
        address[] memory collateralTokens,
        uint256[] memory collateralAmounts,
        uint256 time,
        bytes memory data
    ) public pure returns (IService.Order memory) {
        assert(tokens.length == amounts.length && tokens.length == margins.length);
        IService.Loan[] memory loan = new IService.Loan[](tokens.length);
        IService.Collateral[] memory collateral = new IService.Collateral[](collateralTokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            loan[i].token = tokens[i];
            loan[i].amount = amounts[i];
            loan[i].margin = margins[i];
        }
        for (uint256 i = 0; i < itemTypes.length; i++) {
            collateral[i].itemType = itemTypes[i];
            collateral[i].token = collateralTokens[i];
            collateral[i].amount = collateralAmounts[i];
        }

        IService.Agreement memory agreement = IService.Agreement({
            loans: loan,
            collaterals: collateral,
            createdAt: time,
            status: IService.Status.OPEN
        });
        IService.Order memory order = IService.Order({ agreement: agreement, data: data });

        return order;
    }

    function createERC20Order1Collateral2Tokens(
        address tokenA,
        uint256 loanA,
        uint256 marginA,
        address tokenB,
        uint256 loanB,
        uint256 marginB,
        address collateralToken,
        uint256 collateralAmount,
        uint256 time,
        bytes memory data
    ) public pure returns (IService.Order memory) {
        IService.Loan[] memory loans = new IService.Loan[](2);
        loans[0].token = tokenA;
        loans[0].amount = loanA;
        loans[0].margin = marginA;
        loans[1].token = tokenB;
        loans[1].amount = loanB;
        loans[1].margin = marginB;

        IService.Collateral[] memory collaterals = new IService.Collateral[](2);
        collaterals[0].itemType = IService.ItemType.ERC20;
        collaterals[0].token = collateralToken;
        collaterals[0].amount = collateralAmount;

        IService.Agreement memory agreement = IService.Agreement({
            loans: loans,
            collaterals: collaterals,
            createdAt: time,
            status: IService.Status.OPEN
        });
        return IService.Order({ agreement: agreement, data: data });
    }

    // function createERC20Order1Collateral2Tokens(
    //     address[2] memory tokens,
    //     uint256[2] memory amounts,
    //     uint256[2] memory margins,
    //     address collateralToken,
    //     uint256 collateralAmount,
    //     uint256 time,
    //     bytes memory data
    // ) public view returns (IService.Order memory) {
    //     IService.Loan[] memory loan = new IService.Loan[](tokens.length);
    //     IService.Collateral[] memory collateral = new IService.Collateral[](tokens.length);
    //     for (uint256 i = 0; i < 2; i++) {
    //         loan[i].token = tokens[i];
    //         loan[i].amount = amounts[i];
    //         loan[i].margin = margins[i];
    //     }
    //     collateral[0].itemType = IService.ItemType.ERC20;
    //     collateral[0].token = collateralToken;
    //     collateral[0].amount = collateralAmount;

    //     IService.Agreement memory agreement = IService.Agreement({
    //         loans: loan,
    //         collaterals: collateral,
    //         createdAt: time,
    //         status: IService.Status.OPEN
    //     });
    //     IService.Order memory order = IService.Order({ agreement: agreement, data: data });

    //     return order;
    // }
}
