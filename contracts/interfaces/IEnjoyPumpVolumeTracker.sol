//SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IEnjoyPumpVolumeTracker {
    function addVolume(address user, uint256 volume) external;
}