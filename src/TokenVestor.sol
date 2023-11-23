// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.18;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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

    uint256 internal immutable _minimumVesting;

    error NullAllocation();
    error UserAlreadyVested();
    error TransferNotSupported();
    error VestingBelowMinimum();

    modifier notNull() {
        if (vestedAmount[msg.sender].amount == 0) revert NullAllocation();
        _;
    }

    constructor(address _token, uint256 _minimum) ERC20("magic coin", "MAGIC COIN") {
        ithil = IERC20(_token);
        _minimumVesting = _minimum;
    }

    function addAllocation(uint256 amount, uint256 start, uint256 duration, address to) external {
        if (amount < _minimumVesting) revert VestingBelowMinimum();
        VestingSchedule memory vesting = vestedAmount[to];
        // user should not be already vested, even in the past: 1 address - 1 vesting
        // an attacker invalidating a given address would need to pay the victim, so it will not occur
        if (vesting.amount >= _minimumVesting) revert UserAlreadyVested();
        // at this point to prevent reentrancy
        vestedAmount[to] = VestingSchedule(start, duration, amount, 0);
        // nothing prevents a caller to vest some ithil to a given address and it's fine
        ithil.safeTransferFrom(msg.sender, address(this), amount);
        _mint(to, amount);
    }

    function claim() external notNull {
        uint256 toTransfer = claimable(msg.sender);
        // at this point to prevent reentrancy
        vestedAmount[msg.sender].totalClaimed += toTransfer;

        ithil.safeTransfer(msg.sender, toTransfer);
        // we are sure the claimer has the correct Magic Token amount
        // because the token is non-transferable
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

    function transfer(address, /*recipient*/ uint256 /*amount*/) public virtual override returns (bool) {
        revert TransferNotSupported();
    }

    function transferFrom(
        address,
        /*sender*/ address,
        /*recipient*/ uint256 /*amount*/
    ) public virtual override returns (bool) {
        revert TransferNotSupported();
    }
}
