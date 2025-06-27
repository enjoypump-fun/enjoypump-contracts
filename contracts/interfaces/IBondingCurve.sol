//SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IBondingCurve {

    function getVersionNo() external view returns (uint32);

    function isBonded() external view returns (bool);

    /**
        * @dev Check if an account is allowed to transfer tokens before the bonding curve is reached
        * @param account address to check
        * @return bool if the account is allowed to transfer tokens, limited to bonding curve and liquidity adder
     */
    function allowEarlyTransfer(address account) external view returns (bool);

    function __init__(bytes calldata payload, address token, address liquidityAdder) external;

    function getToken() external view returns (address);

    function buyTokens(address recipient, uint256 minOut) external payable returns (uint256 tokensBought);
}