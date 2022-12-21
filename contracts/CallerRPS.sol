// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface RPS {
    function createPrivate(bytes32 encryptedPick, address payable opponent)
    external
    returns(uint256 gameId);
}

contract CallerRPS{
    RPS rpsAddress;

    constructor(address _rpsAddress){
        rpsAddress = RPS(_rpsAddress);
    }

    function callFunction(bytes32 encryptedPick) public payable returns(uint256 gameId) {
        return rpsAddress.createPrivate(encryptedPick, payable(msg.sender));
    }
}