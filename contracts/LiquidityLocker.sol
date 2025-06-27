//SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./interfaces/IERC20.sol";

/**
    Contract for Permanently Burning Liquidity
    - should be mostly empty with some read functions
    - no ability to withdraw assets
 */
contract LiquidityLocker {

    function amountLocked(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function percentageLocked(address token) external view returns (uint256) {
        uint256 totalSupply = IERC20(token).totalSupply();
        if (totalSupply == 0) {
            return 0;
        }
        return ( IERC20(token).balanceOf(address(this)) * 1e18 ) / totalSupply;
    }
}