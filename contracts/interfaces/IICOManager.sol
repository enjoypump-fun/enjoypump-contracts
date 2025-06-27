//SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IICOManager {
    function remainingTime(address token) external view returns (uint256);
    function isActive(address token) external view returns (bool);
    function isICO(address token) external view returns (bool);
    function launchICO(
        address token,
        bytes calldata payload
    ) external;
}