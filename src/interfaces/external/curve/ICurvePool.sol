// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.18;

/// @title    Interface of the Curve contract
interface ICurvePool {
    function coins(uint256 arg0) external view returns (address);

    function coins(int128 arg0) external view returns (address);

    /**
     * @notice The current virtual price of the pool LP token
     *     @dev Useful for calculating profits
     *     @return LP token virtual price normalized to 1e18
     */
    function get_virtual_price() external view returns (uint256);

    function calc_withdraw_one_coin(uint256 token_amount, uint256 i) external view returns (uint256);

    /**
     * @notice Calculate addition or reduction in token supply from a deposit or withdrawal
     *     @dev This calculation accounts for slippage, but not fees.
     *         Needed to prevent front-running, not for precise calculations!
     *     @param amounts Amount of each coin being deposited
     *     @param is_deposit set True for deposits, False for withdrawals
     *     @return Expected amount of LP tokens received
     */
    function calc_token_amount(uint256[2] memory amounts, bool is_deposit) external view returns (uint256);

    function calc_token_amount(uint256[3] memory amounts, bool is_deposit) external view returns (uint256);

    function calc_token_amount(uint256[2] memory amounts) external view returns (uint256);

    function calc_token_amount(uint256[3] memory amounts) external view returns (uint256);

    /**
     * @notice Deposit coins into the pool
     *     @param _amounts List of amounts of coins to deposit
     *     @param _min_mint_amount Minimum amount of LP tokens to mint from the deposit
     */
    function add_liquidity(uint256[2] memory _amounts, uint256 _min_mint_amount) external;

    function add_liquidity(uint256[3] memory _amounts, uint256 _min_mint_amount) external;

    function add_liquidity(uint256[4] memory _amounts, uint256 _min_mint_amount) external;

    /**
     * @notice Withdraw coins from the pool
     *     @dev Withdrawal amounts are based on current deposit ratios
     *     @param _burn_amount Quantity of LP tokens to burn in the withdrawal
     *     @param _min_amounts Minimum amounts of underlying coins to receive
     */
    function remove_liquidity(uint256 _burn_amount, uint256[2] memory _min_amounts) external;

    function remove_liquidity(uint256 _burn_amount, uint256[3] memory _min_amounts) external;

    function remove_liquidity(uint256 _burn_amount, uint256[4] memory _min_amounts) external;

    /**
     * @notice Withdraw a single coin from the pool
     *     @param _burn_amount Amount of LP tokens to burn in the withdrawal
     *     @param i Index value of the coin to withdraw
     *     @param _min_received Minimum amount of coin to receive
     *     @return Amount of coin received
     */
    function remove_liquidity_one_coin(
        uint256 _burn_amount,
        int128 i,
        uint256 _min_received
    ) external returns (uint256);

    function balances(int128 _index) external view returns (uint256);

    function balances(uint256 _index) external view returns (uint256);
}
