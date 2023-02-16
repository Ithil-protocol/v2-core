// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { IVault } from "../../src/interfaces/IVault.sol";
import { IService } from "../../src/interfaces/IService.sol";
import { IManager, Manager } from "../../src/Manager.sol";
import { CurveConvexService } from "../../src/services/debit/CurveConvexService.sol";
import { GeneralMath } from "../../src/libraries/GeneralMath.sol";
import { BaseIntegrationServiceTest } from "./BaseIntegrationServiceTest.sol";
import { Helper } from "./Helper.sol";

contract CurveConvexServiceTestRenBTCWBTC is BaseIntegrationServiceTest {
    CurveConvexService internal immutable service;

    address internal constant convexBooster = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address internal constant cvx = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    address internal constant curvePool = 0x93054188d876f558f4a66B2EF1d97d16eDf0895B;
    uint256 internal constant convexPid = 6;

    string internal constant rpcUrl = "MAINNET_RPC_URL";
    uint256 internal constant blockNumber = 16448665;

    constructor() BaseIntegrationServiceTest(rpcUrl, blockNumber) {
        vm.startPrank(admin);
        service = new CurveConvexService(address(manager), convexBooster, cvx);
        vm.stopPrank();
        loanLength = 2;
        loanTokens = new address[](loanLength);
        collateralTokens = new address[](1);
        loanTokens[0] = 0xEB4C2781e4ebA804CE9a9803C67d0893436bB27D; // renBTC
        loanTokens[1] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // wbtc
        whales[loanTokens[0]] = 0xaAde032DC41DbE499deBf54CFEe86d13358E9aFC;
        whales[loanTokens[1]] = 0x218B95BE3ed99141b0144Dba6cE88807c4AD7C09;
        collateralTokens[0] = 0x49849C98ae39Fff122806C06791Fa73784FB3675;
        serviceAddress = address(service);
    }

    function setUp() public virtual override {
        super.setUp();
        vm.prank(admin);
        service.addPool(curvePool, convexPid, loanTokens);
    }

    function testOpen(uint256 amount0, uint256 loan0, uint256 margin0, uint256 amount1, uint256 loan1, uint256 margin1)
        public
    {
        IService.Order memory order = _openOrder2(
            amount0,
            loan0,
            margin0,
            amount1,
            loan1,
            margin1,
            0,
            block.timestamp,
            ""
        );
        service.open(order);
    }

    function testClose(uint256 amount0, uint256 loan0, uint256 margin0, uint256 amount1, uint256 loan1, uint256 margin1)
        public
    {
        testOpen(amount0, loan0, margin0, amount1, loan1, margin1);
        // Allow for any loss
        // TODO: insert minAmountsOut and use quoter to check for slippage
        uint256[2] memory minAmountsOut = [uint256(0), uint256(0)];
        bytes memory data = abi.encode(minAmountsOut);

        service.close(0, data);
    }

    function testQuote(uint256 amount0, uint256 loan0, uint256 margin0, uint256 amount1, uint256 loan1, uint256 margin1)
        public
    {
        testOpen(amount0, loan0, margin0, amount1, loan1, margin1);
        (
            IService.Loan[] memory loan,
            IService.Collateral[] memory collateral,
            uint256 createdAt,
            IService.Status status
        ) = service.getAgreement(1);

        IService.Agreement memory agreement = IService.Agreement(loan, collateral, createdAt, status);

        (uint256[] memory quoted, ) = service.quote(agreement);
    }
}
