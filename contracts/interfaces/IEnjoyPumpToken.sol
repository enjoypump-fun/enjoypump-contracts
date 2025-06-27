//SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./IERC20.sol";

interface IEnjoyPumpToken is IERC20 {

    function bondingCurveTransferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    function __init__(bytes calldata payload, address bondingCurve_) external;
}