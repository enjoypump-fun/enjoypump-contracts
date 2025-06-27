//SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IEnjoyPumpGenerator {
    function generateProject(bytes calldata tokenPayload, bytes calldata bondingCurvePayload, address liquidityAdder) external returns (address token, address bondingCurve);
}