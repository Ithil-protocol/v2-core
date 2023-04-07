// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.17;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ithil } from "../src/Ithil.sol";

contract TokenVestor is ERC20 {
    using SafeERC20 for IERC20;

    struct VestingSchedule {
        uint256 start;
        uint256 duration;
        uint256 amount;
        uint256 totalClaimed;
    }

    mapping(address => VestingSchedule) public vestedAmount;
    IERC20 public immutable ithil;

    error NullAllocation();
    error TransferNotSupported();

    modifier notNull() {
        if (vestedAmount[msg.sender].amount == 0) revert NullAllocation();
        _;
    }

    constructor(address _token) ERC20("magic coin", "MAGIC COIN") {
        ithil = IERC20(_token);
    }

    function addAllocation(uint256 amount, uint256 start, uint256 duration, address to) external {
        ithil.safeTransferFrom(msg.sender, address(this), amount);
        _mint(to, amount);
        vestedAmount[to] = VestingSchedule(start, duration, amount, 0);
    }

    function claim() external notNull {
        uint256 toTransfer = claimable(msg.sender);
        vestedAmount[msg.sender].totalClaimed += toTransfer;

        ithil.safeTransfer(msg.sender, toTransfer);
        _burn(msg.sender, toTransfer);
    }

    function claimable(address user) public view returns (uint256) {
        VestingSchedule memory vesting = vestedAmount[user];

        return _vestingSchedule(vesting) - vesting.totalClaimed;
    }

    function _vestingSchedule(VestingSchedule memory vesting) internal view returns (uint256) {
        if (block.timestamp < vesting.start) {
            return 0;
        } else if (block.timestamp > vesting.start + vesting.duration) {
            return vesting.amount;
        } else {
            return (vesting.amount * (block.timestamp - vesting.start)) / vesting.duration;
        }
    }

    function transfer(address /*recipient*/, uint256 /*amount*/) public virtual override returns (bool) {
        revert TransferNotSupported();
    }

    function transferFrom(address /*sender*/, address /*recipient*/, uint256 /*amount*/)
        public
        virtual
        override
        returns (bool)
    {
        revert TransferNotSupported();
    }

    function approve(address /*spender*/, uint256 /*amount*/) public virtual override returns (bool) {
        revert TransferNotSupported();
    }
}
