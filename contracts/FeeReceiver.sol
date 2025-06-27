//SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IFeeRecipient {
    function takeBondFee(address token) external payable;
    function takeVolumeFee(address token) external payable;
}

interface IDatabase {
    function getProjectDev(address token) external view returns (address);
}


contract FeeReceiver is IFeeRecipient {

    address public recipient;
    address public database;

    constructor(address _recipient, address _database) {
        database = _database;
        recipient = _recipient;
    }

    function takeBondFee(address token) external payable override {
        (bool s,) = payable(IDatabase(database).getProjectDev(token)).call{value: address(this).balance / 2}("");
        
        (s,) = payable(recipient).call{value: address(this).balance}("");
        require(s, 'Failure To Send Fee');
    }

    function takeVolumeFee(address) external payable override {
        (bool s,) = payable(recipient).call{value: address(this).balance}("");
        require(s, 'Failure To Send Fee');
    }

    receive() external payable {
        (bool s,) = payable(recipient).call{value: address(this).balance}("");
        require(s, 'Failure To Send Fee');
    }
}