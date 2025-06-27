//SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IFeeRecipient {

    function takeBondFee(address token) external payable;
    function takeVolumeFee(address token) external payable;

}