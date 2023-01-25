// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

abstract contract HarvestableService {
    event HarvestWasTriggered(uint256 indexed poolID);

    /// @dev mapping containing the rewards for each pool ID
    struct HarvestsData {
        uint256[] totalRewards;
        uint256 totalStakedAmount;
    }
    mapping(uint256 => HarvestsData) public harvests;

    function _computeShareOfRewards(uint256 allowance, uint256 poolID) internal view returns (uint256[] memory) {
        HarvestsData memory data = harvests[poolID];
        uint256[] memory amounts = new uint256[](data.totalRewards.length);

        for(uint16 i = 0; i < data.totalRewards.length; i++) {
            //totalRewards * collateral / allowance...
        }
    }

    function collectRewards(bytes memory data) public virtual;
}
